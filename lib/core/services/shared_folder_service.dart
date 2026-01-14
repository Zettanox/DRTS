import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:stoa/core/data/database.dart';
import 'package:stoa/core/services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'package:watcher/watcher.dart';
import 'package:path_provider/path_provider.dart';

final sharedFolderServiceProvider = Provider((ref) => SharedFolderService(ref));

class SharedFolderService {
  final Ref _ref;
  final Map<String, StreamSubscription> _watchers = {};
  
  SharedFolderService(this._ref);
  
  AppDatabase get _db => _ref.read(databaseProvider);
  SyncService get _syncService => _ref.read(syncServiceProvider);
  
  Future<void> initialize() async {
    // Cleanup any existing junk
    await _db.purgeIgnoredFiles();
    
    final folders = await _db.select(_db.sharedFolders).get();
    for (final folder in folders) {
      _startWatcher(folder);
    }
  }
  
  Future<void> createSharedSpace(String name) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, 'Stoa', 'Shared', name);
    final dir = Directory(path);
    
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    final id = const Uuid().v4();
    final key = const Uuid().v4(); // Simple key for now
    
    final folder = SharedFoldersCompanion.insert(
      id: id,
      key: key,
      name: name,
      ownerId: 'me', // TODO: Get actual peer ID
      path: path,
      createdAt: DateTime.now(),
    );
    
    await _db.into(_db.sharedFolders).insert(folder);
    
    // Fetch inserted row to start watcher
    final inserted = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(id))).getSingle();
    _startWatcher(inserted);
  }
  
  void _startWatcher(SharedFolder folder) {
    if (_watchers.containsKey(folder.id)) return;
    
    // Create watcher
    final watcher = DirectoryWatcher(folder.path);
    
    debugPrint('👀 Started watching shared folder: ${folder.path}');
    
    final sub = watcher.events.listen((event) async {
       await _handleFileEvent(folder, event);
    });
    
    _watchers[folder.id] = sub;
  }
  
  Future<void> _handleFileEvent(SharedFolder folder, WatchEvent event) async {
    final filename = p.basename(event.path);
    
    // Ignore common temporary/hidden files
    if (filename.startsWith('.') || 
        filename.endsWith('~') || 
        filename.endsWith('.tmp') ||
        filename.endsWith('.swp') ||
        filename == 'Thumbs.db' ||
        Directory(event.path).existsSync()) {
      return;
    }
    
    final relativePath = p.relative(event.path, from: folder.path);
    debugPrint('📁 File Event: ${event.type} at $relativePath');
    
    try {
      if (event.type == ChangeType.ADD || event.type == ChangeType.MODIFY) {
         final file = File(event.path);
         if (!file.existsSync()) return;
         
         final bytes = await file.readAsBytes();
         final hash = sha256.convert(bytes).toString();
         final size = bytes.length;
         
         // Check if we already have this state (loop prevention)
         final existing = await (_db.select(_db.sharedFiles)
           ..where((t) => t.folderId.equals(folder.id) & t.relativePath.equals(relativePath)))
           .getSingleOrNull();

         if (existing != null && existing.hash == hash && !existing.isDeleted) {
           debugPrint('Build-in loop prevention: Hash identical, ignoring.');
           return;
         }
         
         // Insert or Update CRDT
         // HLC generation would happen here (using local timestamp for now)
         final hlc = DateTime.now().toIso8601String(); 
         
         if (existing == null) {
           await _db.into(_db.sharedFiles).insert(SharedFilesCompanion.insert(
             id: const Uuid().v4(),
             folderId: folder.id,
             relativePath: relativePath,
             hash: hash,
             hlc: hlc,
             size: size,
             updatedAt: DateTime.now(),
           ));
         } else {
           await (_db.update(_db.sharedFiles)..where((t) => t.id.equals(existing.id))).write(
             SharedFilesCompanion(
               hash: Value(hash),
               hlc: Value(hlc),
               size: Value(size),
               updatedAt: Value(DateTime.now()),
               isDeleted: const Value(false),
             ),
           );
         }
         
         // Broadcast Sync Message
         _syncService.broadcastFolderUpdate(folder.id);
      } else if (event.type == ChangeType.REMOVE) {
         final existing = await (_db.select(_db.sharedFiles)
           ..where((t) => t.folderId.equals(folder.id) & t.relativePath.equals(relativePath)))
           .getSingleOrNull();
           
         if (existing != null && !existing.isDeleted) {
            final hlc = DateTime.now().toIso8601String();
            await (_db.update(_db.sharedFiles)..where((t) => t.id.equals(existing.id))).write(
             SharedFilesCompanion(
               hlc: Value(hlc),
               updatedAt: Value(DateTime.now()),
               isDeleted: const Value(true),
             ),
           );
           // Broadcast Sync Message
           _syncService.broadcastFolderUpdate(folder.id);
         }
      }
    } catch (e) {
      debugPrint('Error handling file event: $e');
    }
  }
  Future<void> deleteFile(SharedFile file) async {
    final folder = await (_db.select(_db.sharedFolders)..where((t) => t.id.equals(file.folderId))).getSingle();
    final fullPath = p.join(folder.path, file.relativePath);
    
    try {
      final f = File(fullPath);
      if (await f.exists()) {
        await f.delete();
        debugPrint('🗑️ Deleted physical file: $fullPath');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to delete physical file: $e');
    }

    // Mark as deleted in CRDT (Watcher handles this too, but for immediate UI reponse + explicit action)
    final hlc = DateTime.now().toIso8601String();
    await (_db.update(_db.sharedFiles)..where((t) => t.id.equals(file.id))).write(
      SharedFilesCompanion(
        hlc: Value(hlc),
        updatedAt: Value(DateTime.now()),
        isDeleted: const Value(true),
      ),
    );
  }
}
