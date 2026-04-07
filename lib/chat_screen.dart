import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stoa/src/rust/api/chat.dart';
import 'package:stoa/src/rust/api/simple.dart';

// Provides the ChatStore instance (initialized in main.dart)
final chatStoreProvider = Provider<ChatStore>((ref) {
  throw UnimplementedError('chatStoreProvider not initialized');
});

// Provides the local Node ID string
final localNodeIdProvider = Provider<String>((ref) {
  throw UnimplementedError('localNodeIdProvider not initialized');
});

// Provides the TopicHandle for gossip messaging
final topicHandleProvider = Provider<TopicHandle>((ref) {
  throw UnimplementedError('topicHandleProvider not initialized');
});

class ChatScreen extends ConsumerStatefulWidget {
  final String topic;
  const ChatScreen({super.key, required this.topic});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  List<ChatMessage> _messages = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Poll for incoming gossip messages every 500ms
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _pollGossipMessages();
    });
  }

  void _loadMessages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(chatStoreProvider);
      try {
        setState(() {
          _messages = store.getMessages(topic: widget.topic);
        });
      } catch (e) {
        debugPrint('Error loading messages: $e');
      }
    });
  }

  Future<void> _pollGossipMessages() async {
    final topicHandle = ref.read(topicHandleProvider);
    final store = ref.read(chatStoreProvider);

    try {
      while (true) {
        final msg = await topicHandle.recvMessage();
        if (msg == null) break;

        // Create a ChatMessage and store it locally
        final chatMsg = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString() +
              msg.sender.substring(0, 4),
          senderId: msg.sender,
          topic: widget.topic,
          content: msg.content,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        try {
          store.insertMessage(msg: chatMsg);
        } catch (_) {
          // Duplicate ID — already stored
        }

        if (mounted) {
          setState(() {
            _messages.add(chatMsg);
          });
        }
      }
    } catch (e) {
      debugPrint('Gossip poll error: $e');
    }
  }

  Future<void> _sendMessage(String content, String localNodeId) async {
    if (content.trim().isEmpty) return;

    final store = ref.read(chatStoreProvider);
    final topicHandle = ref.read(topicHandleProvider);

    final msg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString() +
          localNodeId.substring(0, 4),
      senderId: localNodeId,
      topic: widget.topic,
      content: content,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      // Store locally
      store.insertMessage(msg: msg);
      setState(() {
        _messages.add(msg);
      });
      // Broadcast over gossip
      await topicHandle.sendMessage(content: content);
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
    _controller.clear();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localNodeId = ref.watch(localNodeIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Chat: ${widget.topic}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg.senderId == localNodeId;

                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.deepPurple[100] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe
                              ? "You"
                              : "${msg.senderId.substring(0, 8)}...",
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(msg.content),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (val) =>
                          _sendMessage(val, localNodeId),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: Colors.deepPurple,
                    onPressed: () =>
                        _sendMessage(_controller.text, localNodeId),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
