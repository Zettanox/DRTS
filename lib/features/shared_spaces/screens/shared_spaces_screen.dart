import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:stoa/app/theme.dart';
import 'package:stoa/core/data/database.dart';
import 'package:stoa/core/services/shared_folder_service.dart';
import 'package:stoa/core/services/connection_service.dart';
import 'package:stoa/core/services/sync_service.dart';
import 'package:stoa/features/shared_spaces/screens/folder_view_screen.dart';

class SharedSpacesScreen extends ConsumerWidget {
  const SharedSpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Spaces'),
      ),
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
                   Icon(Icons.folder_open, size: 64, color: Colors.white24),
                   const SizedBox(height: 16),
                   Text('No shared spaces yet', style: Theme.of(context).textTheme.titleMedium),
                   const SizedBox(height: 8),
                   Text('Create a space to sync files with peers', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54)),
                ],
              ),
            );
          }
          
          return ListView.builder(
            itemCount: folders.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.folder_shared, color: StoaTheme.accentColor, size: 32),
                  title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folder.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      SelectableText('ID: ${folder.id}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'sync') {
                         final peers = ref.read(connectionServiceProvider).connectedPeers;
                         int count = 0;
                         for (final peerId in peers) {
                           await ref.read(syncServiceProvider).initiateSync(peerId);
                           count++;
                         }
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Triggered sync with $count peers')));
                      } else if (value == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Shared Space?'),
                            content: const Text('This will remove the folder from your shared spaces list. The files on disk will NOT be deleted.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          await ref.read(databaseProvider).deleteSharedFolder(folder.id);
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'sync',
                        child: Row(
                          children: [
                            Icon(Icons.sync, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Force Sync'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete Space'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                     Navigator.of(context).push(
                       MaterialPageRoute(builder: (_) => FolderViewScreen(folder: folder))
                     );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join',
            onPressed: () => _showJoinDialog(context, ref),
            icon: const Icon(Icons.link),
            label: const Text('Join Space'),
            backgroundColor: StoaTheme.secondaryColor,
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: 'create',
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New Space'),
          ),
        ],
      ),
    );
  }
  
  void _showJoinDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Shared Space'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the Space ID shared by your peer.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Space ID',
                hintText: 'e.g. 123e4567-e89b...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
               // Logic to "join" - for now just add to DB with unknown path or ask for path
               // Ideally: Ask where to save it locally
               Navigator.pop(ctx);
               _showPathSelectionDialog(context, ref, controller.text.trim());
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _showPathSelectionDialog(BuildContext context, WidgetRef ref, String spaceId) async {
    if (spaceId.isEmpty) return;
    
    // For simplicity in this iteration, we auto-create a folder in Documents/Stoa/Shared/<SpaceId>
    // In a real app, use FilePicker to pick directory.
    
    // We don't verify validity yet (P2P handshake handles that).
    // We just create the local record so SyncService can start talking about it.
    
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, 'Stoa', 'Shared', 'Joined_Space_${spaceId.substring(0, 8)}');
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    // Insert into DB
    final folder = SharedFoldersCompanion.insert(
      id: spaceId,
      key: 'unknown', // We don't have the key yet, maybe protocol exchanges it? Or ID comes with key?
      name: 'Joined Space',
      ownerId: 'remote',
      path: path,
      createdAt: DateTime.now(),
    );
    
    try {
      await ref.read(databaseProvider).insertSharedFolder(folder);
      
      // Initialize watcher for it
      // Re-init service or expose manual start
      await ref.read(sharedFolderServiceProvider).initialize(); // Lazy reload
      
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined space! syncing to: $path')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error joining space: $e')));
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
               if (controller.text.trim().isNotEmpty) {
                 Navigator.pop(ctx);
                 await ref.read(sharedFolderServiceProvider).createSharedSpace(controller.text.trim());
               }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
