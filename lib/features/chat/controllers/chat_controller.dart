import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/data/database.dart';
import '../../../core/services/connection_service.dart';
import '../../../core/models/peer.dart';

part 'chat_controller.g.dart';

@riverpod
class ChatController extends _$ChatController {
  @override
  FutureOr<void> build() {}

  Future<void> sendMessage(Peer peer, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final connectionService = ref.read(connectionServiceProvider);
    final db = ref.read(databaseProvider);

    await connectionService.sendText(peer, trimmed);

    await db.insertMessage(
      MessagesCompanion.insert(
        peerId: peer.id,
        isMe: true,
        content: trimmed,
        type: 'text',
        status: 'sent',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> clearChat(String peerId) async {
    final db = ref.read(databaseProvider);
    await db.clearMessagesForPeer(peerId);
  }
}
