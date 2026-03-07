import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stoa/app/theme.dart';
import 'package:stoa/core/data/database.dart';
import 'package:stoa/core/services/remote_folder_service.dart';
import 'package:stoa/core/services/connection_service.dart';
import 'package:stoa/features/shared_spaces/screens/folder_view_screen.dart';

class SharedSpacesScreen extends ConsumerWidget {
  const SharedSpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shared Spaces')),
      body: StreamBuilder<List<SharedFolder>>(
        stream: db.watchAllSharedFolders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final folders = snapshot.data!;

          if (folders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.folder_open,
                    size: 64,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No shared spaces yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a space to share files with peers',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: folders.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final folder = folders[index];
              final isOwner = folder.ownerId == 'me';

              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(
                    isOwner ? Icons.folder_shared : Icons.cloud_outlined,
                    color: isOwner ? StoaTheme.accentColor : Colors.blueGrey,
                    size: 32,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          folder.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isOwner)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: StoaTheme.accentColor.withAlpha(50),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Owner',
                            style: TextStyle(
                              fontSize: 11,
                              color: StoaTheme.accentColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isOwner) ...[
                        Text(
                          folder.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ] else ...[
                        Text(
                          'Remote • ${folder.permission}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 4),
                      SelectableText(
                        'ID: ${folder.id}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'refresh') {
                        // For peers, request file list from owner
                        if (!isOwner) {
                          ref
                              .read(remoteFolderServiceProvider)
                              .requestFileList(folder.id, folder.ownerId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Refreshing...')),
                          );
                        }
                      } else if (value == 'collaborators') {
                        _showCollaboratorsDialog(context, ref, folder);
                      } else if (value == 'delete') {
                        _confirmDelete(context, ref, folder, isOwner);
                      }
                    },
                    itemBuilder: (context) => [
                      if (!isOwner)
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, size: 20, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Refresh'),
                            ],
                          ),
                        ),
                      if (isOwner)
                        const PopupMenuItem(
                          value: 'collaborators',
                          child: Row(
                            children: [
                              Icon(Icons.people, size: 20, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Manage Collaborators'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(isOwner ? 'Delete Space' : 'Leave Space'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FolderViewScreen(folder: folder),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create',
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Space'),
      ),
    );
  }

  void _showCollaboratorsDialog(
    BuildContext context,
    WidgetRef ref,
    SharedFolder folder,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Collaborators',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<SpaceCollaborator>>(
                stream: ref
                    .read(databaseProvider)
                    .watchCollaborators(folder.id),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final collaborators = snapshot.data!;

                  if (collaborators.isEmpty) {
                    return const Center(
                      child: Text(
                        'No collaborators yet',
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: controller,
                    itemCount: collaborators.length,
                    itemBuilder: (context, index) {
                      final c = collaborators[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(c.peerName[0].toUpperCase()),
                        ),
                        title: Text(c.peerName),
                        subtitle: Text(c.permission),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            ref
                                .read(remoteFolderServiceProvider)
                                .removeCollaborator(folder.id, c.peerId);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => _showInviteDialog(context, ref, folder.id),
                icon: const Icon(Icons.person_add),
                label: const Text('Invite Peer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref, String spaceId) {
    final connectedPeers = ref.read(connectionServiceProvider).connectedPeers;

    if (connectedPeers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No connected peers to invite')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Peer'),
        content: FutureBuilder<List<LocalPeer>>(
          future: ref.read(databaseProvider).getAllPeers(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const CircularProgressIndicator();

            final peers = snapshot.data!
                .where((p) => connectedPeers.contains(p.id))
                .toList();

            return SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: peers.length,
                itemBuilder: (context, index) {
                  final peer = peers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: peer.avatarColor != null
                          ? Color(
                              int.parse(
                                peer.avatarColor!.replaceFirst('#', '0xFF'),
                              ),
                            )
                          : Colors.grey,
                      child: Text(peer.username[0].toUpperCase()),
                    ),
                    title: Text(peer.username),
                    onTap: () {
                      Navigator.pop(ctx);
                      ref
                          .read(remoteFolderServiceProvider)
                          .inviteCollaborator(
                            spaceId,
                            peer.id,
                            peer.username,
                            'read-write',
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Invited ${peer.username}')),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SharedFolder folder,
    bool isOwner,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isOwner ? 'Delete Shared Space?' : 'Leave Shared Space?'),
        content: Text(
          isOwner
              ? 'This will remove the space and notify all collaborators. Files on disk will NOT be deleted.'
              : 'You will no longer have access to this space.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isOwner ? 'Delete' : 'Leave'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (isOwner) {
        await ref.read(remoteFolderServiceProvider).deleteSpace(folder.id);
      } else {
        await ref.read(databaseProvider).deleteSharedFolder(folder.id);
      }
    }
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Shared Space'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Space Name',
            hintText: 'e.g. Project Docs',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                await ref
                    .read(remoteFolderServiceProvider)
                    .createSharedSpace(controller.text.trim());
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Space created! Invite collaborators from the menu.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
