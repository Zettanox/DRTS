import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'database.g.dart';

// Tables
class LocalPeers extends Table {
  TextColumn get id => text()();
  TextColumn get username => text()();
  TextColumn get avatarColor => text().nullable()();
  TextColumn get publicKey => text().nullable()();
  DateTimeColumn get lastSeen => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get peerId => text().references(LocalPeers, #id)();
  BoolColumn get isMe => boolean()();
  TextColumn get content => text()(); // Text message or filename
  TextColumn get type => text()(); // 'text', 'file', 'system'
  TextColumn get filePath => text().nullable()(); // Local path for files
  IntColumn get fileSize => integer().nullable()();
  TextColumn get status => text()(); // 'sending', 'sent', 'received', 'failed'
  DateTimeColumn get timestamp => dateTime()();
}

// Group Tables
class Groups extends Table {
  TextColumn get id => text()();              // UUID
  TextColumn get name => text()();
  TextColumn get ownerId => text()();         // Creator/owner peer ID
  BoolColumn get showHistoryToNew => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

class GroupMembers extends Table {
  TextColumn get groupId => text().references(Groups, #id)();
  TextColumn get peerId => text()();          // Peer ID (can be self or remote)
  TextColumn get username => text()();        // Cached username
  TextColumn get status => text()();          // 'pending', 'accepted', 'rejected'
  DateTimeColumn get joinedAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {groupId, peerId};
}

class GroupMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get groupId => text().references(Groups, #id)();
  TextColumn get senderId => text()();        // Who sent it
  TextColumn get senderName => text()();      // Cached sender name
  TextColumn get content => text()();
  TextColumn get type => text()();            // 'text', 'file', 'system'
  TextColumn get filePath => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  DateTimeColumn get timestamp => dateTime()();
}

// Shared Spaces (CRDT) Tables
class SharedFolders extends Table {
  TextColumn get id => text()();              // UUID
  TextColumn get key => text()();             // Share Key (for joining)
  TextColumn get name => text()();
  TextColumn get ownerId => text()();         // Peer ID of owner ('me' if local)
  TextColumn get path => text()();            // Local path (only for owner)
  TextColumn get permission => text().withDefault(const Constant('read-write'))(); // 'read-only' or 'read-write'
  DateTimeColumn get createdAt => dateTime()(); 
  DateTimeColumn get lastSync => dateTime().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

class SharedFiles extends Table {
  TextColumn get id => text()();              // UUID (Used for CRDT tracking)
  TextColumn get folderId => text().references(SharedFolders, #id)();
  TextColumn get relativePath => text()();    // Path relative to folder root
  TextColumn get hash => text()();            // SHA-256 for loop prevention
  TextColumn get hlc => text()();             // Hybrid Logical Clock
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get size => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// Collaborators for Shared Spaces
class SpaceCollaborators extends Table {
  TextColumn get spaceId => text().references(SharedFolders, #id)();
  TextColumn get peerId => text()();          // Peer ID of collaborator
  TextColumn get peerName => text()();        // Cached peer name
  TextColumn get permission => text().withDefault(const Constant('read-write'))(); // 'read-only' or 'read-write'
  TextColumn get status => text().withDefault(const Constant('pending'))(); // 'pending', 'accepted', 'rejected'
  DateTimeColumn get addedAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {spaceId, peerId};
}

@DriftDatabase(tables: [LocalPeers, Messages, Groups, GroupMembers, GroupMessages, SharedFolders, SharedFiles, SpaceCollaborators])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;
  
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
         // Migration from v1 to v2 (Groups)
         await m.createTable(groups);
         await m.createTable(groupMembers);
         await m.createTable(groupMessages);
      }
      if (from < 3) {
         // Migration from v2 to v3 (Shared Spaces)
         await m.createTable(sharedFolders);
         await m.createTable(sharedFiles);
      }
      if (from < 4) {
         // Migration from v3 to v4 (Collaborators + Permission)
         await m.createTable(spaceCollaborators);
         await m.addColumn(sharedFolders, sharedFolders.permission);
      }
    }
  );
  
  // Peer Queries
  Future<List<LocalPeer>> getAllPeers() => select(localPeers).get();
  
  Stream<List<LocalPeer>> watchAllPeers() => select(localPeers).watch();
  
  Future<int> insertPeer(LocalPeer peer) {
    return into(localPeers).insert(peer, mode: InsertMode.insertOrReplace);
  }
  
  // Message Queries
  Future<List<Message>> getMessagesForPeer(String peerId) {
    return (select(messages)..where((t) => t.peerId.equals(peerId))
           ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
           .get();
  }
  
  Stream<List<Message>> watchMessagesForPeer(String peerId) {
    return (select(messages)..where((t) => t.peerId.equals(peerId))
           ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
           .watch();
  }
  
  Future<int> insertMessage(MessagesCompanion message) {
    return into(messages).insert(message);
  }
  
  // File Queries (for "Files" section)
  Stream<List<Message>> watchAllFiles() {
    return (select(messages)..where((t) => t.type.equals('file'))
           ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
           .watch();
  }
  
  // Delete a message by ID
  Future<int> deleteMessage(int id) {
    return (delete(messages)..where((t) => t.id.equals(id))).go();
  }
  
  // Clear all messages for a specific peer
  Future<int> clearMessagesForPeer(String peerId) {
    return (delete(messages)..where((t) => t.peerId.equals(peerId))).go();
  }
  
  // Watch recent messages (all types, for home screen)
  Stream<List<Message>> watchRecentMessages(int limit) {
    return (select(messages)
           ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)])
           ..limit(limit))
           .watch();
  }
  
  // ==================== GROUP QUERIES ====================
  
  // Create a new group
  Future<int> insertGroup(GroupsCompanion group) {
    return into(groups).insert(group);
  }
  
  // Get all groups the user is a member of
  Future<List<Group>> getAllGroups() => select(groups).get();
  
  Stream<List<Group>> watchAllGroups() => select(groups).watch();
  
  // Get a specific group
  Future<Group?> getGroup(String groupId) {
    return (select(groups)..where((t) => t.id.equals(groupId))).getSingleOrNull();
  }
  
  // Delete a group and all its data
  Future<void> deleteGroup(String groupId) async {
    await (delete(groupMessages)..where((t) => t.groupId.equals(groupId))).go();
    await (delete(groupMembers)..where((t) => t.groupId.equals(groupId))).go();
    await (delete(groups)..where((t) => t.id.equals(groupId))).go();
  }
  
  // ==================== GROUP MEMBER QUERIES ====================
  
  Future<int> insertGroupMember(GroupMembersCompanion member) {
    return into(groupMembers).insert(member, mode: InsertMode.insertOrReplace);
  }
  
  Future<List<GroupMember>> getGroupMembers(String groupId) {
    return (select(groupMembers)..where((t) => t.groupId.equals(groupId))).get();
  }
  
  Stream<List<GroupMember>> watchGroupMembers(String groupId) {
    return (select(groupMembers)..where((t) => t.groupId.equals(groupId))).watch();
  }
  
  Future<void> removeGroupMember(String groupId, String peerId) {
    return (delete(groupMembers)
      ..where((t) => t.groupId.equals(groupId) & t.peerId.equals(peerId)))
      .go();
  }
  
  // Get all peer IDs that share a group with the user (for auto-connect)
  Future<Set<String>> getAllGroupMemberIds() async {
    final members = await select(groupMembers).get();
    return members.map((m) => m.peerId).toSet();
  }
  
  // Check if a peer is in any group with accepted status
  Future<bool> isPeerInAnyGroup(String peerId) async {
    final member = await (select(groupMembers)
      ..where((t) => t.peerId.equals(peerId) & t.status.equals('accepted')))
      .getSingleOrNull();
    return member != null;
  }
  
  // ==================== GROUP MESSAGE QUERIES ====================
  
  Future<int> insertGroupMessage(GroupMessagesCompanion message) {
    return into(groupMessages).insert(message);
  }
  
  Future<List<GroupMessage>> getGroupMessages(String groupId) {
    return (select(groupMessages)
      ..where((t) => t.groupId.equals(groupId))
      ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
      .get();
  }
  
  Future<int> deleteGroupMessage(int id) {
    return (delete(groupMessages)..where((t) => t.id.equals(id))).go();
  }
  
  Stream<List<GroupMessage>> watchAllGroupFiles() {
    return (select(groupMessages)
      ..where((t) => t.type.isIn(['file', 'folder']))
      ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
      .watch();
  }
  
  Stream<List<GroupMessage>> watchGroupMessages(String groupId) {
    return (select(groupMessages)
      ..where((t) => t.groupId.equals(groupId))
      ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
      .watch();
  }
  
  // Update file path for a group message after download
  Future<void> updateGroupMessageFile(String groupId, String senderId, String filename, String path) async {
    print('🔍 Attempting to update group message: groupId=$groupId, sender=$senderId, file=$filename');
    
    // Retry logic to handle race conditions where message insertion might lag behind file transfer
    for (int i = 0; i < 3; i++) {
        // Find the most recent message matching criteria
        final query = select(groupMessages)
          ..where((t) => t.groupId.equals(groupId) & 
                         t.senderId.equals(senderId) & 
                         t.content.equals(filename)) // Removed loose type check
          ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)])
          ..limit(1);
          
        final message = await query.getSingleOrNull();
        
        if (message != null) {
          print('✅ Found message ${message.id}, updating path to $path');
          await (update(groupMessages)..where((t) => t.id.equals(message.id))).write(
            GroupMessagesCompanion(
                filePath: Value(path),
                type: Value(path.endsWith('.zip') || Directory(path).existsSync() ? 'folder' : 'file') // Auto-detect folder type
            )
          );
          return;
        }
        
        print('⚠️ Message not found (attempt ${i + 1}/3), retrying in 500ms...');
        await Future.delayed(const Duration(milliseconds: 500));
    }
    
    print('❌ Failed to find matching group message for file update after retries.');
  }

  // ==================== SHARED SPACES QUERIES ====================
  
  Stream<List<SharedFolder>> watchAllSharedFolders() {
    return (select(sharedFolders)
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
      .watch();
  }
  
  Future<int> insertSharedFolder(SharedFoldersCompanion folder) {
    return into(sharedFolders).insert(folder);
  }
  
  Future<SharedFolder?> getSharedFolder(String id) {
    return (select(sharedFolders)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  Stream<List<SharedFile>> watchSharedFiles(String folderId) {
    return (select(sharedFiles)
      ..where((t) => t.folderId.equals(folderId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.relativePath)]))
      .watch();
  }
  
  Future<int> insertSharedFile(SharedFilesCompanion file) {
    return into(sharedFiles).insert(file, mode: InsertMode.insertOrReplace);
  }

  Future<void> deleteSharedFolder(String id) async {
    await (delete(sharedFiles)..where((t) => t.folderId.equals(id))).go();
    await (delete(sharedFolders)..where((t) => t.id.equals(id))).go();
  }

  Future<void> purgeIgnoredFiles() async {
     // Delete files that match ignored patterns
     // SQLite GLOB or LIKE can be used, or just fetch all and filter in Dart if complex regex needed.
     // For simplicity and power, let's fetch all and filter in Dart, then delete by ID.
     final all = await select(sharedFiles).get();
     final toDelete = <String>[];
     
     for (final f in all) {
       final name = p.basename(f.relativePath);
       if (name.startsWith('.') || 
           name.endsWith('~') || 
           name.endsWith('.tmp') ||
           name.endsWith('.swp') ||
           name == 'Thumbs.db') {
         toDelete.add(f.id);
       }
     }
     
     if (toDelete.isNotEmpty) {
       await (delete(sharedFiles)..where((t) => t.id.isIn(toDelete))).go();
       print('🧹 Purged ${toDelete.length} ignored files from database.');
     }
  }
  
  // ==================== SPACE COLLABORATOR QUERIES ====================
  
  Future<int> addCollaborator(SpaceCollaboratorsCompanion collaborator) {
    return into(spaceCollaborators).insert(collaborator, mode: InsertMode.insertOrReplace);
  }
  
  Future<void> removeCollaborator(String spaceId, String peerId) {
    return (delete(spaceCollaborators)
      ..where((t) => t.spaceId.equals(spaceId) & t.peerId.equals(peerId)))
      .go();
  }
  
  Stream<List<SpaceCollaborator>> watchCollaborators(String spaceId) {
    return (select(spaceCollaborators)
      ..where((t) => t.spaceId.equals(spaceId) & t.status.equals('accepted')))
      .watch();
  }
  
  Future<List<SpaceCollaborator>> getCollaborators(String spaceId) {
    return (select(spaceCollaborators)
      ..where((t) => t.spaceId.equals(spaceId) & t.status.equals('accepted')))
      .get();
  }
  
  Future<void> updateCollaboratorStatus(String spaceId, String peerId, String status) {
    return (update(spaceCollaborators)
      ..where((t) => t.spaceId.equals(spaceId) & t.peerId.equals(peerId)))
      .write(SpaceCollaboratorsCompanion(status: Value(status)));
  }
  
  Stream<List<SharedFolder>> watchSpacesAsCollaborator(String myPeerId) {
    // Return spaces where I'm accepted as a collaborator (not owner)
    final collaboratorSpaceIds = selectOnly(spaceCollaborators)
      ..addColumns([spaceCollaborators.spaceId])
      ..where(spaceCollaborators.peerId.equals(myPeerId) & spaceCollaborators.status.equals('accepted'));
      
    return (select(sharedFolders)
      ..where((t) => t.id.isInQuery(collaboratorSpaceIds)))
      .watch();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'stoa.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

// Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
