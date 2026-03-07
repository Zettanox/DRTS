import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/group_service.dart';
import '../../../core/services/discovery_service.dart';
import '../../../core/data/database.dart';
import '../../../app/theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stoa/core/utils/logger.dart';
import 'dart:io';

class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupChatScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupService = ref.watch(groupServiceProvider);
    final myPeerId = ref.read(discoveryServiceProvider).myPeerId;

    return FutureBuilder<Group?>(
      future: ref.read(databaseProvider).getGroup(widget.groupId),
      builder: (context, groupSnapshot) {
        final group = groupSnapshot.data;

        return Scaffold(
          appBar: AppBar(
            title: Text(group?.name ?? 'Group'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _clearChatHistory(context, widget.groupId),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showGroupInfo(context, group),
              ),
            ],
          ),
          body: Column(
            children: [
              // Messages
              Expanded(
                child: StreamBuilder<List<GroupMessage>>(
                  stream: groupService.watchGroupMessages(widget.groupId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data!;

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: Colors.white54),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMe = message.senderId == myPeerId;
                        return _MessageBubble(message: message, isMe: isMe);
                      },
                    );
                  },
                ),
              ),

              // Input area
              _buildInputArea(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black12,
      child: Row(
        children: [
          IconButton(
            onPressed: _pickAndSendFile,
            icon: const Icon(Icons.attach_file),
            color: Colors.white70,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send),
            color: StoaTheme.secondaryColor,
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final groupService = ref.read(groupServiceProvider);

    for (final file in result.files) {
      if (file.path != null) {
        await groupService.sendFile(widget.groupId, File(file.path!));
      }
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    await ref.read(groupServiceProvider).sendGroupMessage(widget.groupId, text);
  }

  void _showGroupInfo(BuildContext context, Group? group) {
    if (group == null) return;

    final groupService = ref.read(groupServiceProvider);
    final myPeerId = ref.read(discoveryServiceProvider).myPeerId;
    final isOwner = group.ownerId == myPeerId;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Members list
            const Text(
              'Members',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<GroupMember>>(
              stream: groupService.watchGroupMembers(widget.groupId),
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                final accepted = members
                    .where((m) => m.status == 'accepted')
                    .toList();

                return Column(
                  children: accepted
                      .map(
                        (m) => ListTile(
                          dense: true,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(m.username),
                          trailing: m.peerId == group.ownerId
                              ? const Chip(label: Text('Owner'))
                              : null,
                        ),
                      )
                      .toList(),
                );
              },
            ),

            const Divider(),

            // Actions
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete Group',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => _deleteGroup(context, group),
              )
            else
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                title: const Text(
                  'Leave Group',
                  style: TextStyle(color: Colors.orange),
                ),
                onTap: () => _leaveGroup(context, group),
              ),
          ],
        ),
      ),
    );
  }

  void _deleteGroup(BuildContext context, Group group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group?'),
        content: const Text('This will delete the group for all members.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(groupServiceProvider).deleteGroup(group.id);
      if (!context.mounted) return;
      Navigator.pop(context); // Close bottom sheet
      context.pop(); // Go back to groups list
    }
  }

  void _leaveGroup(BuildContext context, Group group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text(
          'You will no longer receive messages from this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(groupServiceProvider).leaveGroup(group.id);
      if (!context.mounted) return;
      Navigator.pop(context); // Close bottom sheet
      context.pop(); // Go back to groups list
    }
  }

  void _clearChatHistory(BuildContext context, String groupId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat History?'),
        content: const Text(
          'This will delete all messages and downloaded files in this group from your local device. Other members will still have their copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseProvider);

              // Find and delete all associated files locally
              final messages = await db.getGroupMessages(groupId);
              for (final msg in messages) {
                if (msg.filePath != null) {
                  try {
                    final file = File(msg.filePath!);
                    if (await file.exists()) {
                      await file.delete();
                    }
                  } catch (e) {
                    appLogger.e('Failed to delete file ${msg.filePath}: $e');
                  }
                }
              }

              // Clear from local DB
              await db.clearMessagesForGroup(groupId);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  final GroupMessage message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress: () => _showDeleteMessageDialog(context, ref, message),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: isMe
                ? StoaTheme.primaryColor.withValues(alpha: 0.8)
                : Colors.grey[800]!.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe)
                Text(
                  message.senderName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: StoaTheme.secondaryColor,
                  ),
                ),

              if (message.type == 'file' || message.type == 'folder')
                GestureDetector(
                  onTap: () {
                    if (message.filePath != null) {
                      _openOrShareFile(message.filePath!);
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image Preview
                      if (message.filePath != null &&
                          ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(
                            message.filePath!.split('.').last.toLowerCase(),
                          ))
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(message.filePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),

                      // File Info Row
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              message.type == 'folder'
                                  ? Icons.folder
                                  : Icons.insert_drive_file,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.content,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _formatSize(message.fileSize ?? 0),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                SelectableText(
                  message.content,
                  style: const TextStyle(color: Colors.white),
                ),

              const SizedBox(height: 4),
              Text(
                _formatTime(message.timestamp),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openOrShareFile(String path) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await OpenFilex.open(path);
        if (result.type != ResultType.done) {
          appLogger.w(
            'OpenFilex failed: ${result.message}, falling back to Share',
          );
          await Share.shareXFiles([XFile(path)], text: 'Open or save file');
        }
      } catch (e) {
        await Share.shareXFiles([XFile(path)], text: 'Open or save file');
      }
    } else {
      OpenFilex.open(path);
    }
  }

  void _showDeleteMessageDialog(
    BuildContext context,
    WidgetRef ref,
    GroupMessage message,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text(
          'This will delete the message and any associated files from your device only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);

              // Delete actual file if exists
              if (message.filePath != null) {
                try {
                  final file = File(message.filePath!);
                  if (await file.exists()) {
                    await file.delete();
                    appLogger.i('🗑️ Deleted file: ${message.filePath}');
                  }
                } catch (e) {
                  appLogger.e('❌ Failed to delete file: $e');
                }
              }

              // Delete from DB locally
              await ref.read(databaseProvider).deleteGroupMessage(message.id);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
