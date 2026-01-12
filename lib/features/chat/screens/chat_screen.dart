import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/peer.dart';
import '../../../core/services/connection_service.dart';
import '../../../core/services/file_transfer_service.dart';
import '../../../core/services/discovery_service.dart';
import '../../../core/data/database.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:async';

class ChatScreen extends ConsumerStatefulWidget {
  final String peerId;

  const ChatScreen({super.key, required this.peerId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  
  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We need to find the peer object. 
    // Since we navigate by ID, we look it up from discovery service
    // In a real app we'd have a unified PeerRepository
    // final discoveryService = ref.watch(discoveryServiceProvider); // Not needed if we watch state
    final discoveryState = ref.watch(discoveryStateProvider);
    final peers = discoveryState.peers;
    
    // Also check active manually added peers if needed, but the stream should emit them
    // Initial peers list might be empty if we just loaded, so we might need to rely on the current value if stream hasnt emitted
    final peerList = peers; 
    
    Peer? peer;
    try {
      peer = peerList.firstWhere((p) => p.id == widget.peerId);
    } catch (_) {
      // If not found in list (e.g. disconnected or app restart), showing a placeholder or loading
      // For now, let's assume valid navigation
    }

    if (peer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Peer not found or disconnected')),
      );
    }
    
    final fileTransferService = ref.watch(fileTransferServiceProvider);
    final transfersStream = fileTransferService.progressStream;
    final db = ref.watch(databaseProvider);
    
    // Listen for incoming text messages
    return StreamBuilder<ConnectionMessage>(
      stream: ref.watch(connectionServiceProvider).messageStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final msg = snapshot.data!;
          // If message is for this peer and is data (text)
          if (msg.peerId == peer!.id && msg.type == ConnectionMessageType.data && msg.payload['type'] == 'text') {
             // We need to add this to our ephemeral list if it's new
             // But StreamBuilder rebuilds on every event. We should manipulate state in a listener, not builder.
             // Ideally we wrap this in a ConsumerStatefulWidget listener or use a provider.
             // For quick implementation:
             // We can rely on the fact that we can't easily dedup without ID tracking.
             // Let's use a simpler approach: Watch a provider that accumulates messages?
             // Or just use `ref.listen` in `build`?
          }
        }
        
        return _buildScaffold(peer!, transfersStream, db);
      }
    );
  }
  
  Widget _buildScaffold(Peer peer, Stream<Map<String, TransferProgress>> transfersStream, AppDatabase db) {
     // Check actual connection status from service, not discovery state
     final isActuallyConnected = ref.read(connectionServiceProvider).isConnectedTo(peer.id);
     
     return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(peer.username),
            Text(
              isActuallyConnected ? 'Connected 🔒' : 'Disconnected',
              style: TextStyle(
                fontSize: 12,
                color: isActuallyConnected ? Colors.greenAccent : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show peer details
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: db.watchMessagesForPeer(peer.id),
              builder: (context, dbSnapshot) {
                final dbMessages = dbSnapshot.data ?? [];
                
                return StreamBuilder<Map<String, TransferProgress>>(
                  stream: transfersStream,
                  builder: (context, transferSnapshot) {
                    final transfers = transferSnapshot.data ?? {};
                    
                    final activeTransfers = transfers.values
                        .where((t) => t.peerId == peer.id && t.status != TransferStatus.completed)
                        .toList();
                        
                    // Merge everything (DB only now)
                    final allItems = [
                        ...activeTransfers.reversed, 
                        ...dbMessages
                    ];
                    
                    // Retain simple sort order if needed, but active/ephemeral are usually newer.
                    // We might need to sort by timestamp if we want perfect ordering.
                    // dbMessages are likely sorted by time DESC.
                    // _ephemeralMessages should be prepended (newest).
                    
                    if (allItems.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[700]),
                            const SizedBox(height: 16),
                            const Text('No messages yet'),
                            const SizedBox(height: 8),
                            const Text('Tap + to send a file', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      );
                    }
                    
                    return ListView.builder(
                      reverse: true, 
                      padding: const EdgeInsets.all(16),
                      itemCount: allItems.length,
                      itemBuilder: (context, index) {
                        final item = allItems[index];
                        if (item is TransferProgress) {
                          return _buildTransferBubble(item);
                        } else if (item is Message) {
                          return _buildDbMessageBubble(item);
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  },
                );
              },
            ),
          ),
          _buildInputArea(peer),
        ],
      ),
    );
  }
  
  // Initialize listener
  @override
  void initState() {
    super.initState();
    // No need to listen to connection stream for text messages anymore
    // DB watch handles it
  }

  Widget _buildInputArea(Peer peer) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black12,
      child: Row(
        children: [
          IconButton(
            onPressed: () {
               ref.read(fileTransferServiceProvider).pickAndSendFile(peer);
            },
            icon: const Icon(Icons.add_circle, size: 32),
            color: Colors.white70,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey),
              ),
              onSubmitted: (_) => _sendMessage(peer),
            ),
          ),
          IconButton(
            onPressed: () => _sendMessage(peer),
            icon: const Icon(Icons.send),
            color: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }
  
  void _sendMessage(Peer peer) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    // Send via connection service
    await ref.read(connectionServiceProvider).sendText(peer, text);
    
    // Add to DB
    final db = ref.read(databaseProvider);
    await db.insertMessage(MessagesCompanion.insert(
      peerId: peer.id,
      isMe: true,
      content: text,
      type: 'text',
      status: 'sent',
      timestamp: DateTime.now(),
    ));

    _messageController.clear();
  }

  Widget _buildTransferBubble(TransferProgress transfer) {
    final isMe = transfer.type == TransferType.sending;
    final color = isMe ? Theme.of(context).primaryColor : Colors.grey[800];
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24), // Highlight active
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.upload_file, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    transfer.filename,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: transfer.percentage,
              backgroundColor: Colors.black26,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(transfer.percentage * 100).toInt()}% • ${_formatBytes(transfer.totalBytes)}',
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
                if (transfer.status == TransferStatus.failed)
                  const Text('FAILED', style: TextStyle(fontSize: 10, color: Colors.redAccent)),
                if (transfer.status == TransferStatus.inProgress)
                  const Text('Transferring...', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDbMessageBubble(Message message) {
    final isMe = message.isMe;
    final color = isMe ? Theme.of(context).primaryColor.withOpacity(0.8) : Colors.grey[800]!.withOpacity(0.8);
    final isText = message.type == 'text';
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isText) ...[
                  Icon(
                    message.isMe ? Icons.upload_rounded : Icons.download_rounded,
                    color: Colors.white70, 
                    size: 20
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    message.content,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  message.fileSize != null ? _formatBytes(message.fileSize!) : 
                  (isText ? _formatTime(message.timestamp) : ''),
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
                if (message.type == 'file' && message.filePath != null)
                  GestureDetector(
                    onTap: () {
                      if (message.filePath != null) {
                         ref.read(fileTransferServiceProvider).openFileByPath(message.filePath!);
                    }
                    },
                    child: const Text('OPEN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// Extension to help open files by path in FileTransferService
extension FileTransferServiceExtensions on FileTransferService {
  Future<void> openFileByPath(String path) async {
    await OpenFilex.open(path);
  }
}
