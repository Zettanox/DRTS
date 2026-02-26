import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stoa/core/data/database.dart';
import 'package:stoa/core/services/connection_service.dart';
import 'package:uuid/uuid.dart';

final syncServiceProvider = Provider((ref) => SyncService(ref));

class SyncService {
  final Ref _ref;
  StreamSubscription? _subscription;
  
  SyncService(this._ref);
  
  ConnectionService get _connectionService => _ref.read(connectionServiceProvider);
  AppDatabase get _db => _ref.read(databaseProvider);
  
  void initialize() {
    _subscription = _connectionService.messageStream.listen(_handleMessage);
  }
  
  void dispose() {
    _subscription?.cancel();
  }
  
  void _handleMessage(ConnectionMessage message) {
    if (message.type == ConnectionMessageType.connected) {
      debugPrint('🔄 Auto-sync triggered for new connection: ${message.peerId}');
      initiateSync(message.peerId);
      return;
    }

    if (message.type != ConnectionMessageType.data) return;
    
    final payload = message.payload;
    if (payload is! Map<String, dynamic> || payload['type'] != 'sync') return;
    
    final syncType = payload['syncType'];
    final data = payload['data'];
    
    switch (syncType) {
      case 'sync_req':
        _handleSyncReq(message.peerId, data);
        break;
      case 'sync_state':
        _handleSyncState(message.peerId, data);
        break;
      case 'content_req':
        _handleContentReq(message.peerId, data);
        break;
      case 'content_ack':
        _handleContentAck(message.peerId, data);
        break;
    }
  }
  
  // Triggered on connect or manual refresh
  Future<void> initiateSync(String peerId) async {
    // Request state for all folders we know about
    final folders = await _db.select(_db.sharedFolders).get();
    for (final f in folders) {
      _sendSyncMessage(peerId, 'sync_req', {'folderId': f.id});
    }
  }
  
  Future<void> _handleSyncState(String peerId, Map<String, dynamic> data) async {
    final folderId = data['folderId'];
    final name = data['name'];
    final remoteFiles = List<Map<String, dynamic>>.from(data['files']);
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;
    
    // 1. Update Name
    if (folder.name.startsWith('Joined Space') && name != 'Joined Space') {
         await (_db.update(_db.sharedFolders)..where((t) => t.id.equals(folderId))).write(
           SharedFoldersCompanion(name: Value(name)),
         );
         debugPrint('🏷️ Updated folder name to: $name');
    }
    
    // 2. Compare Files
    for (final rf in remoteFiles) {
      final relativePath = rf['relativePath'];
      final hash = rf['hash'];
      
      final localFile = await (_db.select(_db.sharedFiles)
        ..where((t) => t.folderId.equals(folderId) & t.relativePath.equals(relativePath)))
        .getSingleOrNull();
        
      bool needsDownload = false;
      
      if (localFile == null) {
        needsDownload = true; // New file
      } else if (localFile.hash != hash) {
        needsDownload = true; // Changed file (hash mismatch)
      }
      
      if (needsDownload) {
        debugPrint('📥 Requesting file content: $relativePath');
        _sendSyncMessage(peerId, 'content_req', {
          'folderId': folderId,
          'relativePath': relativePath,
        });
      }
    }
  }
  
  Future<void> _handleContentReq(String peerId, Map<String, dynamic> data) async {
    final folderId = data['folderId'];
    final relativePath = data['relativePath'];
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;
    
    final file = File(p.join(folder.path, relativePath));
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      // For small files, base64 is fine. Large files need chunking/streaming.
      // Assuming small files for this MVP phase.
      
      _sendSyncMessage(peerId, 'content_ack', {
        'folderId': folderId,
        'relativePath': relativePath,
        'content': base64Encode(bytes),
        'hash': sha256.convert(bytes).toString(),
      });
      debugPrint('📤 Sent content for $relativePath');
    }
  }

  Future<void> _handleContentAck(String peerId, Map<String, dynamic> data) async {
    final folderId = data['folderId'];
    final relativePath = data['relativePath'];
    final content = data['content'];
    final hash = data['hash'];
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;

    final filePath = p.join(folder.path, relativePath);
    final file = File(filePath);
    
    try {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      
      final bytes = base64Decode(content);
      await file.writeAsBytes(bytes);
      debugPrint('📥 Wrote content for $relativePath');
      
      // Update DB
      final existingFile = await (_db.select(_db.sharedFiles)
        ..where((t) => t.folderId.equals(folderId) & t.relativePath.equals(relativePath)))
        .getSingleOrNull();
        
      final id = existingFile?.id ?? const Uuid().v4();
      
      await _db.into(_db.sharedFiles).insertOnConflictUpdate(SharedFilesCompanion.insert(
        id: id,
        folderId: folderId,
        relativePath: relativePath,
        hash: hash ?? sha256.convert(bytes).toString(),
        hlc: DateTime.now().toIso8601String(),
        isDeleted: const Value(false),
        size: bytes.length,
        updatedAt: DateTime.now(),
      ));
      
    } catch (e) {
      debugPrint('❌ Failed to write file content: $e');
    }
  }

  void _sendSyncMessage(String peerId, String syncType, Map<String, dynamic> data) {
    _connectionService.send(peerId, {
      'type': 'sync',
      'syncType': syncType,
      'data': data,
    });
  }
  
  Future<void> broadcastFolderUpdate(String folderId) async {
    // Notify all connected peers about the update by pushing our state
    final peers = _connectionService.connectedPeers;
    for (final peerId in peers) {
       await _sendFullState(peerId, folderId);
    }
  }

  Future<void> _handleSyncReq(String peerId, Map<String, dynamic> data) async {
    final folderId = data['folderId'];
    await _sendFullState(peerId, folderId);
  }
  
  Future<void> _sendFullState(String peerId, String folderId) async {
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;
    
    final files = await (_db.select(_db.sharedFiles)..where((t) => t.folderId.equals(folderId))).get();
    
    final fileList = files.where((f) => !f.isDeleted).map((f) => {
      'relativePath': f.relativePath,
      'hash': f.hash,
      'size': f.size,
    }).toList();
    
    _sendSyncMessage(peerId, 'sync_state', {
      'folderId': folderId,
      'name': folder.name,
      'files': fileList,
    });
  }
}
