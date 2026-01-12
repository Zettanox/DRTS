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

@DriftDatabase(tables: [LocalPeers, Messages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
  
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
