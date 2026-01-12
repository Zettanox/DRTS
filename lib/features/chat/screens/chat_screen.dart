import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/peer.dart';
import '../../../core/services/connection_service.dart';
import '../../../core/services/file_transfer_service.dart';
import '../../../core/services/discovery_service.dart';
import '../../../core/data/database.dart';
import 'package:open_filex/open_filex.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String peerId;

  const ChatScreen({super.key, required this.peerId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

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
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(peer.username),
            Text(
              peer.isConnected ? 'Connected 🔒' : 'Disconnected',
              style: TextStyle(
                fontSize: 12,
                color: peer.isConnected ? Colors.greenAccent : Colors.grey,
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
              stream: db.watchMessagesForPeer(peer!.id),
              builder: (context, dbSnapshot) {
                final dbMessages = dbSnapshot.data ?? [];
                
                return StreamBuilder<Map<String, TransferProgress>>(
                  stream: transfersStream,
                  builder: (context, transferSnapshot) {
                    final transfers = transferSnapshot.data ?? {};
                    
                    // Filter active transfers for this peer (exclude completed/failed as they should be in DB)
                    // Actually, failed might not be in DB if we only log success. 
                    // Let's keep failed in active list for now or until dismissed.
                    // For now, exclude COMPLETED.
                    final activeTransfers = transfers.values
                        .where((t) => t.peerId == peer!.id && t.status != TransferStatus.completed)
                        .toList();
                        
                    // Combine lists. Active transfers are assumed newer (at the bottom/start of reverse list)
                    final allItems = [...activeTransfers.reversed, ...dbMessages];
                    
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
                Icon(
                  message.isMe ? Icons.upload_rounded : Icons.download_rounded,
                  color: Colors.white70, 
                  size: 20
                ),
                const SizedBox(width: 8),
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
                  message.fileSize != null ? _formatBytes(message.fileSize!) : '',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
                if (message.type == 'file' && message.filePath != null)
                  GestureDetector(
                    onTap: () {
                      if (message.filePath != null) {
                         // We don't have openFilex imported specifically here, 
                         // but we can use generic OpenFilex or call via service if we expose helper.
                         // For now let's rely on importing open_filex or just use the service helper if generic.
                         // ConnectionService doesn't have open. FileTransferService does.
                         // But FileTransferService takes 'fileId' (uuid) which we might not have easily in DB message (unless we store it).
                         // We should just use OpenFilex directly here.
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
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Secure Encrypted Channel',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          // Placeholder for text input later
          IconButton(
            onPressed: null, // Disabled for now
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
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
