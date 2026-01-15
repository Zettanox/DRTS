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
import 'package:watcher/watcher.dart';
import 'package:path_provider/path_provider.dart';

final remoteFolderServiceProvider = Provider((ref) => RemoteFolderService(ref));

/// Remote Folder Service - Handles Shared Spaces with Remote Browsing model
/// 
/// Owner Mode: Hosts files locally, responds to peer requests
/// Peer Mode: Browses owner's files remotely, downloads on-demand
class RemoteFolderService {
  final Ref _ref;
  final Map<String, StreamSubscription> _watchers = {};
  final Map<String, StreamController<List<RemoteFile>>> _remoteFileControllers = {};
  
  RemoteFolderService(this._ref);
  
  ConnectionService get _connectionService => _ref.read(connectionServiceProvider);
  AppDatabase get _db => _ref.read(databaseProvider);
  
  void initialize() {
    // Listen for incoming messages
    _connectionService.messageStream.listen(_handleMessage);
    
    // Start watchers for owned folders
    _startWatchersForOwnedFolders();
  }
  
  Future<void> _startWatchersForOwnedFolders() async {
    final folders = await _db.select(_db.sharedFolders).get();
    for (final folder in folders) {
      if (folder.ownerId == 'me') {
        _startWatcher(folder);
      }
    }
  }
  
  void _handleMessage(ConnectionMessage message) {
    if (message.type != ConnectionMessageType.data) return;
    
    final payload = message.payload;
    if (payload is! Map<String, dynamic> || payload['type'] != 'space') return;
    
    final spaceType = payload['spaceType'];
    final data = payload['data'];
    
    switch (spaceType) {
      case 'list_req':
        _handleListReq(message.peerId, data);
        break;
      case 'list_ack':
        _handleListAck(message.peerId, data);
        break;
      case 'download_req':
        _handleDownloadReq(message.peerId, data);
        break;
      case 'download_ack':
        _handleDownloadAck(message.peerId, data);
        break;
      case 'upload_req':
        _handleUploadReq(message.peerId, data);
        break;
      case 'upload_ack':
        _handleUploadAck(message.peerId, data);
        break;
      case 'delete_req':
        _handleDeleteReq(message.peerId, data);
        break;
      case 'delete_ack':
        _handleDeleteAck(message.peerId, data);
        break;
      case 'change_notify':
        _handleChangeNotify(message.peerId, data);
        break;
      case 'space_invite':
        _handleSpaceInvite(message.peerId, data);
        break;
      case 'space_invite_ack':
        _handleSpaceInviteAck(message.peerId, data);
        break;
      case 'space_revoke':
        _handleSpaceRevoke(message.peerId, data);
        break;
    }
  }
  
  // ==================== OWNER CREATES SPACE ====================
  
  Future<String> createSharedSpace(String name) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, 'Stoa', 'SharedSpaces', name);
    final dir = Directory(path);
    
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    final id = const Uuid().v4();
    final key = const Uuid().v4();
    
    final folder = SharedFoldersCompanion.insert(
      id: id,
      key: key,
      name: name,
      ownerId: 'me',
      path: path,
      createdAt: DateTime.now(),
    );
    
    await _db.into(_db.sharedFolders).insert(folder);
    
    // Start watcher
    final inserted = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(id))).getSingle();
    _startWatcher(inserted);
    
    return id;
  }
  
  // ==================== LIST FILES ====================
  
  /// Request file list from owner (Peer -> Owner)
  Future<void> requestFileList(String spaceId, String ownerId) async {
    _sendSpaceMessage(ownerId, 'list_req', {'spaceId': spaceId});
  }
  
  /// Handle list request (Owner)
  Future<void> _handleListReq(String peerId, Map<String, dynamic> data) async {
    final spaceId = data['spaceId'];
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(spaceId))).getSingleOrNull();
    
    if (folder == null || folder.ownerId != 'me') return;
    
    // Check if peer is a collaborator
    final collaborator = await (_db.select(_db.spaceCollaborators)
      ..where((t) => t.spaceId.equals(spaceId) & t.peerId.equals(peerId) & t.status.equals('accepted')))
      .getSingleOrNull();
      
    if (collaborator == null) {
      debugPrint('⚠️ Peer $peerId is not a collaborator for space $spaceId');
      return;
    }
    
    // List files
    final files = await _listFilesRecursive(folder.path);
    
    _sendSpaceMessage(peerId, 'list_ack', {
      'spaceId': spaceId,
      'spaceName': folder.name,
      'permission': collaborator.permission,
      'files': files,
    });
  }
  
  /// Handle list acknowledgment (Peer)
  void _handleListAck(String peerId, Map<String, dynamic> data) {
    final spaceId = data['spaceId'];
    final files = List<Map<String, dynamic>>.from(data['files']);
    final spaceName = data['spaceName'];
    final permission = data['permission'];
    
    // Update local space name if needed
    _updateSpaceMetadata(spaceId, spaceName, permission);
    
    // Notify UI via stream
    final remoteFiles = files.map((f) => RemoteFile(
      relativePath: f['path'],
      size: f['size'],
      isDirectory: f['isDir'],
    )).toList();
    
    _getFileController(spaceId).add(remoteFiles);
  }
  
  StreamController<List<RemoteFile>> _getFileController(String spaceId) {
    if (!_remoteFileControllers.containsKey(spaceId)) {
      _remoteFileControllers[spaceId] = StreamController<List<RemoteFile>>.broadcast();
    }
    return _remoteFileControllers[spaceId]!;
  }
  
  Stream<List<RemoteFile>> watchRemoteFiles(String spaceId) {
    return _getFileController(spaceId).stream;
  }
  
  Future<void> _updateSpaceMetadata(String spaceId, String name, String permission) async {
    await (_db.update(_db.sharedFolders)..where((t) => t.id.equals(spaceId))).write(
      SharedFoldersCompanion(
        name: Value(name),
        permission: Value(permission),
      ),
    );
  }
  
  // ==================== DOWNLOAD FILE ====================
  
  Future<void> requestDownload(String spaceId, String ownerId, String relativePath) async {
    _sendSpaceMessage(ownerId, 'download_req', {
      'spaceId': spaceId,
      'path': relativePath,
    });
  }
  
  Future<void> _handleDownloadReq(String peerId, Map<String, dynamic> data) async {
    final spaceId = data['spaceId'];
    final relativePath = data['path'];
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(spaceId))).getSingleOrNull();
    if (folder == null || folder.ownerId != 'me') return;
    
    final file = File(p.join(folder.path, relativePath));
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _sendSpaceMessage(peerId, 'download_ack', {
        'spaceId': spaceId,
        'path': relativePath,
        'content': base64Encode(bytes),
        'hash': sha256.convert(bytes).toString(),
      });
    }
  }
  
  Future<void> _handleDownloadAck(String peerId, Map<String, dynamic> data) async {
    final spaceId = data['spaceId'];
    final relativePath = data['path'];
    final content = data['content'];
    
    // Save to Downloads/Stoa/<spaceName>/<relativePath>
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(spaceId))).getSingleOrNull();
    if (folder == null) return;
    
    final docsDir = await getApplicationDocumentsDirectory();
    final savePath = p.join(docsDir.path, 'Downloads', 'Stoa', folder.name, relativePath);
    final file = File(savePath);
    
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    
    await file.writeAsBytes(base64Decode(content));
    debugPrint('📥 Downloaded: $savePath');
    
    // Notify via callback (if set)
    _onDownloadComplete?.call(savePath);
  }
  
  // Download completion callback
  void Function(String path)? _onDownloadComplete;
  
  void setDownloadCallback(void Function(String path)? callback) {
    _onDownloadComplete = callback;
  }
  
  // ==================== UPLOAD FILE ====================
  
  Future<void> uploadFile(String spaceId, String ownerId, String relativePath, List<int> bytes) async {
    _sendSpaceMessage(ownerId, 'upload_req', {
      'spaceId': spaceId,
      'path': relativePath,
      'content': base64Encode(bytes),
      'hash': sha256.convert(bytes).toString(),
    });
  }
  
  Future<void> _handleUploadReq(String peerId, Map<String, dynamic> data) async {
    final spaceId = data['spaceId'];
    final relativePath = data['path'];
    final content = data['content'];
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(spaceId))).getSingleOrNull();
    if (folder == null || folder.ownerId != 'me') return;
    
    // Check permission
    final collaborator = await (_db.select(_db.spaceCollaborators)
      ..where((t) => t.spaceId.equals(spaceId) & t.peerId.equals(peerId) & t.status.equals('accepted')))
      .getSingleOrNull();
      
    if (collaborator == null || collaborator.permission == 'read-only') {
      _sendSpaceMessage(peerId, 'upload_ack', {
        'spaceId': spaceId,
        'path': relativePath,
        'success': false,
        'error': 'Permission denied',
      });
      return;
    }
    
    final file = File(p.join(folder.path, relativePath));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    
    await file.writeAsBytes(base64Decode(content));
    debugPrint('📤 Received upload: ${file.path}');
    
    _sendSpaceMessage(peerId, 'upload_ack', {
      'spaceId': spaceId,
      'path': relativePath,
      'success': true,
    });
    
    // Notify all collaborators
    _broadcastChange(spaceId, 'add', relativePath);
  }
  
  void _handleUploadAck(String peerId, Map<String, dynamic> data) {
    final success = data['success'] as bool;
    final path = data['path'];
    if (success) {
      debugPrint('✅ Upload confirmed: $path');
    } else {
      debugPrint('❌ Upload failed: ${data['error']}');
    }
  }
  
  // ==================== DELETE FILE ====================
  
  Future<void> requestDelete(String spaceId, String ownerId, String relativePath) async {
    _sendSpaceMessage(ownerId, 'delete_req', {
      'spaceId': spaceId,
      'path': relativePath,
    });
  }
  
  Future<void> _handleDeleteReq(String peerId, Map<String, dynamic> data) async {
    final spaceId = data['spaceId'];
    final relativePath = data['path'];
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(spaceId))).getSingleOrNull();
    if (folder == null || folder.ownerId != 'me') return;
    
    // Check permission
    final collaborator = await (_db.select(_db.spaceCollaborators)
      ..where((t) => t.spaceId.equals(spaceId) & t.peerId.equals(peerId) & t.status.equals('accepted')))
      .getSingleOrNull();
      
    if (collaborator == null || collaborator.permission == 'read-only') {
      _sendSpaceMessage(peerId, 'delete_ack', {
        'spaceId': spaceId,
        'path': relativePath,
        'success': false,
        'error': 'Permission denied',
      });
      return;
    }
    
    final file = File(p.join(folder.path, relativePath));
    if (await file.exists()) {
      await file.delete();
      debugPrint('🗑️ Deleted: ${file.path}');
    }
    
    _sendSpaceMessage(peerId, 'delete_ack', {
      'spaceId': spaceId,
      'path': relativePath,
      'success': true,
    });
    
    _broadcastChange(spaceId, 'delete', relativePath);
  }
  
  void _handleDeleteAck(String peerId, Map<String, dynamic> data) {
    final success = data['success'] as bool;
    if (success) {
      debugPrint('✅ Delete confirmed');
    } else {
      debugPrint('❌ Delete failed: ${data['error']}');
    }
  }
  
  // ==================== CHANGE NOTIFICATIONS ====================
  
  Future<void> _broadcastChange(String spaceId, String action, String path) async {
    final collaborators = await _db.getCollaborators(spaceId);
    for (final c in collaborators) {
      _sendSpaceMessage(c.peerId, 'change_notify', {
        'spaceId': spaceId,
        'action': action,
        'path': path,
      });
    }
  }
  
  void _handleChangeNotify(String peerId, Map<String, dynamic> data) {
    final spaceId = data['spaceId'];
    debugPrint('🔔 Change notification for space $spaceId: ${data['action']} ${data['path']}');
    
    // Trigger refresh
    requestFileList(spaceId, peerId);
  }
  
  // ==================== COLLABORATOR MANAGEMENT ====================
  
  Future<void> inviteCollaborator(String spaceId, String peerId, String peerName, String permission) async {
    await _db.addCollaborator(SpaceCollaboratorsCompanion.insert(
      spaceId: spaceId,
      peerId: peerId,
      peerName: peerName,
      addedAt: DateTime.now(),
    ));
    
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(spaceId))).getSingle();
    
    _sendSpaceMessage(peerId, 'space_invite', {
      'spaceId': spaceId,
      'spaceName': folder.name,
      'permission': permission,
    });
  }
  
  void _handleSpaceInvite(String peerId, Map<String, dynamic> data) {
    final spaceId = data['spaceId'];
    final spaceName = data['spaceName'];
    final permission = data['permission'];
    
    // Store invitation for UI to show
    // For now, auto-accept
    _acceptInvitation(spaceId, spaceName, peerId, permission);
  }
  
  Future<void> _acceptInvitation(String spaceId, String spaceName, String ownerId, String permission) async {
    // Create local record (no path since we don't store files)
    await _db.into(_db.sharedFolders).insert(
      SharedFoldersCompanion.insert(
        id: spaceId,
        key: 'remote',
        name: spaceName,
        ownerId: ownerId,
        path: '', // No local path for remote spaces
        createdAt: DateTime.now(),
      ),
      mode: InsertMode.insertOrReplace,
    );
    
    _sendSpaceMessage(ownerId, 'space_invite_ack', {
      'spaceId': spaceId,
      'accepted': true,
    });
    
    // Immediately request file list
    requestFileList(spaceId, ownerId);
  }
  
  void _handleSpaceInviteAck(String peerId, Map<String, dynamic> data) {
    final spaceId = data['spaceId'];
    final accepted = data['accepted'] as bool;
    
    if (accepted) {
      _db.updateCollaboratorStatus(spaceId, peerId, 'accepted');
      debugPrint('✅ $peerId accepted invitation to $spaceId');
    } else {
      _db.removeCollaborator(spaceId, peerId);
      debugPrint('❌ $peerId rejected invitation to $spaceId');
    }
  }
  
  Future<void> removeCollaborator(String spaceId, String peerId) async {
    await _db.removeCollaborator(spaceId, peerId);
    _sendSpaceMessage(peerId, 'space_revoke', {
      'spaceId': spaceId,
      'reason': 'removed',
    });
  }
  
  Future<void> deleteSpace(String spaceId) async {
    // Notify all collaborators
    final collaborators = await _db.getCollaborators(spaceId);
    for (final c in collaborators) {
      _sendSpaceMessage(c.peerId, 'space_revoke', {
        'spaceId': spaceId,
        'reason': 'deleted',
      });
    }
    
    // Delete local records
    await _db.deleteSharedFolder(spaceId);
  }
  
  void _handleSpaceRevoke(String peerId, Map<String, dynamic> data) {
    final spaceId = data['spaceId'];
    final reason = data['reason'];
    
    debugPrint('🚫 Space $spaceId revoked: $reason');
    
    // Remove local record
    _db.deleteSharedFolder(spaceId);
    _remoteFileControllers[spaceId]?.close();
    _remoteFileControllers.remove(spaceId);
  }
  
  // ==================== FILE WATCHER (Owner) ====================
  
  void _startWatcher(SharedFolder folder) {
    if (_watchers.containsKey(folder.id)) return;
    
    final watcher = DirectoryWatcher(folder.path);
    debugPrint('👀 Started watching: ${folder.path}');
    
    final sub = watcher.events.listen((event) {
      final relativePath = p.relative(event.path, from: folder.path);
      final action = event.type == ChangeType.REMOVE ? 'delete' : 'add';
      _broadcastChange(folder.id, action, relativePath);
    });
    
    _watchers[folder.id] = sub;
  }
  
  // ==================== HELPERS ====================
  
  Future<List<Map<String, dynamic>>> _listFilesRecursive(String dirPath) async {
    final result = <Map<String, dynamic>>[];
    final dir = Directory(dirPath);
    
    if (!await dir.exists()) return result;
    
    await for (final entity in dir.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: dirPath);
      
      // Skip hidden files
      if (p.basename(relativePath).startsWith('.')) continue;
      
      if (entity is File) {
        final stat = await entity.stat();
        result.add({
          'path': relativePath,
          'size': stat.size,
          'isDir': false,
        });
      } else if (entity is Directory) {
        result.add({
          'path': relativePath,
          'size': 0,
          'isDir': true,
        });
      }
    }
    
    return result;
  }
  
  void _sendSpaceMessage(String peerId, String spaceType, Map<String, dynamic> data) {
    _connectionService.send(peerId, {
      'type': 'space',
      'spaceType': spaceType,
      'data': data,
    });
  }
}

/// Represents a file on a remote owner's device
class RemoteFile {
  final String relativePath;
  final int size;
  final bool isDirectory;
  
  RemoteFile({
    required this.relativePath,
    required this.size,
    required this.isDirectory,
  });
  
  String get name => p.basename(relativePath);
}
