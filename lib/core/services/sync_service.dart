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
import 'package:stoa/core/services/storage_service.dart';

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
      case 'handshake':
        _handleHandshake(message.peerId, data);
        break;
      case 'delta_req':
        _handleDeltaReq(message.peerId, data);
        break;
      case 'delta_ack':
        _handleDeltaAck(message.peerId, data);
        break;
      case 'content_req':
        _handleContentReq(message.peerId, data);
        break;
      case 'content_ack':
        _handleContentAck(message.peerId, data);
        break;
    }
  }
  
  // 1. Handshake: Triggered when we want to sync (e.g. on connect)
  Future<void> initiateSync(String peerId) async {
    // Get latest HLC for all folders provided by this peer?
    // Or just send OUR latest HLC for all folders we know.
    
    // For simplicity, let's just sync ALL shared folders we have in common.
    // In a real app, we'd filter by what the peer has access to.
    // Here we assume if you have the Key, you have access.
    
    final folders = await _db.select(_db.sharedFolders).get();
    final Map<String, String> folderHlcs = {};
    
    for (final f in folders) {
      // Get max HLC for this folder
      final latest = await _getLatestHlc(f.id);
      folderHlcs[f.id] = latest;
    }

    // Map of FolderID -> Name
    final Map<String, String> folderNames = {
      for (var f in folders) f.id: f.name
    };
    
    _sendSyncMessage(peerId, 'handshake', {
      'folders': folderHlcs,
      'names': folderNames,
    });
  }
  
  Future<void> _handleHandshake(String peerId, Map<String, dynamic> data) async {
    final remoteFolders = Map<String, String>.from(data['folders']);
    final remoteNames = data['names'] != null ? Map<String, String>.from(data['names']) : <String, String>{};
    
    for (final entry in remoteFolders.entries) {
      final folderId = entry.key;
      final remoteHlc = entry.value;
      
      // Do we have this folder?
      final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
      if (folder == null) continue; 
      
      // Metadata Update: Fix "Joined Space" name if remote has real name
      if (folder.name.startsWith('Joined Space') && remoteNames.containsKey(folderId)) {
        final realName = remoteNames[folderId]!;
        if (realName != 'Joined Space') {
           await (_db.update(_db.sharedFolders)..where((t) => t.id.equals(folderId))).write(
             SharedFoldersCompanion(name: Value(realName)),
           );
           debugPrint('🏷️ Updated folder name to: $realName');
        }
      }
      
      final localHlc = await _getLatestHlc(folderId);
      
      // Compare HLCs
      if (remoteHlc.compareTo(localHlc) > 0) {
        // Peer is ahead, request deltas from our Local HLC to Remote HLC
        _sendSyncMessage(peerId, 'delta_req', {
          'folderId': folderId,
          'sinceHlc': localHlc,
        });
      } else if (localHlc.compareTo(remoteHlc) > 0) {
        // We are ahead, we could push, or wait for them to pull.
        // Let's wait for them to pull (they will see our handshake and request).
        // But we should also reply with our HLC if this was an initial handshake?
        // Protocol: A sends Handshake. B replies Handshake.
        // To avoid loops, we can check if we already checked recently?
        // Or just Request Deltas if we are behind.
      }
    }
  }
  
  Future<void> _handleDeltaReq(String peerId, Map<String, dynamic> data) async {
    final folderId = data['folderId'];
    final sinceHlc = data['sinceHlc'];
    
    // Get all files updated since 'sinceHlc'
    final changes = await (_db.select(_db.sharedFiles)
      ..where((t) => t.folderId.equals(folderId) & t.hlc.isBiggerThan(Variable(sinceHlc)))
    ).get();
    
    final List<Map<String, dynamic>> deltaPayload = changes.map((f) => {
      'id': f.id,
      'relativePath': f.relativePath,
      'hash': f.hash,
      'hlc': f.hlc,
      'isDeleted': f.isDeleted,
      'size': f.size,
    }).toList();
    
    _sendSyncMessage(peerId, 'delta_ack', {
      'folderId': folderId,
      'deltas': deltaPayload,
    });
  }
  
  Future<void> _handleDeltaAck(String peerId, Map<String, dynamic> data) async {
    final folderId = data['folderId'];
    final deltas = List<Map<String, dynamic>>.from(data['deltas']);
    
    for (final delta in deltas) {
      final id = delta['id'];
      final hlc = delta['hlc'];
      
      // Last-Write-Wins: Check if we have a newer version locally
      final local = await (_db.select(_db.sharedFiles)..where((t) => t.id.equals(id))).getSingleOrNull();
      
      if (local != null && local.hlc.compareTo(hlc) >= 0) {
        continue; // We have newer or same (LWW)
      }
      
      // Apply Update (Metadata)
      await _db.into(_db.sharedFiles).insertOnConflictUpdate(SharedFilesCompanion.insert(
        id: id,
        folderId: folderId,
        relativePath: delta['relativePath'],
        hash: delta['hash'],
        hlc: hlc,
        isDeleted: delta['isDeleted'],
        size: delta['size'],
        updatedAt: DateTime.now(),
      ));
      
      debugPrint('🔄 Applied sync delta: ${delta['relativePath']}');
      
      // If not deleted, we might need the content
      if (!delta['isDeleted']) {
        // Check if we have file content matching hash
        final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(folderId))).getSingle();
        final filePath = p.join(folder.path, delta['relativePath']);
        final file = File(filePath);
        
        bool needsDownload = true;
        if (await file.exists()) {
           final bytes = await file.readAsBytes();
           final hash = sha256.convert(bytes).toString();
           if (hash == delta['hash']) {
             needsDownload = false;
           }
        }
        
        if (needsDownload) {
           debugPrint('📥 Requesting file content: ${delta['relativePath']}');
           // Request content from peer
           _sendSyncMessage(peerId, 'content_req', {
             'folderId': folderId,
             'relativePath': delta['relativePath'],
           });
        }
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
      });
      debugPrint('📤 Sent content for $relativePath');
    }
  }

  Future<void> _handleContentAck(String peerId, Map<String, dynamic> data) async {
    final folderId = data['folderId'];
    final relativePath = data['relativePath'];
    final content = data['content'];
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;

    final filePath = p.join(folder.path, relativePath);
    final file = File(filePath);
    
    try {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      
      await file.writeAsBytes(base64Decode(content));
      debugPrint('📥 Wrote content for $relativePath');
      
      // Update database hash to avoid loop?
      // Watcher will pick this up as MODIFY/ADD.
      // The Watcher calculates new hash. If it matches DB hash (which came from delta), it won't broadcast a new delta.
      // So ensuring the file content matches the delta hash is key.
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
    // Notify all connected peers about the update
    // In a real app, only notify peers who are in the space
    final peers = _connectionService.connectedPeers;
    for (final peerId in peers) {
      await initiateSync(peerId);
    }
  }

  Future<String> _getLatestHlc(String folderId) async {
    final query = _db.select(_db.sharedFiles)
      ..where((t) => t.folderId.equals(folderId))
      ..orderBy([(t) => OrderingTerm(expression: t.hlc, mode: OrderingMode.desc)])
      ..limit(1);
      
    final latest = await query.getSingleOrNull();
    return latest?.hlc ?? ''; // Empty string < any timestamp
  }
}
