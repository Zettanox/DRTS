import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:stoa/app/theme.dart';
import 'package:stoa/core/data/database.dart';
import 'package:stoa/core/services/shared_folder_service.dart';
import 'package:path/path.dart' as p;


class FolderViewScreen extends ConsumerWidget {
  final SharedFolder folder;
  
  const FolderViewScreen({super.key, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(folder.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
               // Show folder info / key in future
               showDialog(context: context, builder: (_) => AlertDialog(
                 title: const Text('Space Info'),
                 content: SelectableText('Path: ${folder.path}\nID: ${folder.id}\nKey: ${folder.key}'),
               ));
            },
          ),
        ],
      ),
      body: StreamBuilder<List<SharedFile>>(
        stream: db.watchSharedFiles(folder.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final files = snapshot.data!;
          
          if (files.isEmpty) {
             return Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                    const Icon(Icons.copy_all, size: 64, color: Colors.white24),
                    const SizedBox(height: 16),
                    const Text('Empty Space', style: TextStyle(fontSize: 18, color: Colors.white60)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _pickAndAddFile(context, folder),
                      icon: const Icon(Icons.add),
                      label: const Text('Add File'),
                    )
                 ],
               ),
             );
          }
          
          return ListView.builder(
            itemCount: files.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final file = files[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined), // TODO: differentiate types
                  title: Text(p.basename(file.relativePath)),
                  subtitle: Text('${_formatBytes(file.size)} • ${file.updatedAt.toLocal().toString().split('.')[0]}'),
                  trailing: file.isDeleted 
                      ? const Icon(Icons.delete, color: Colors.grey) 
                      : IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                             showDialog(
                               context: context,
                               builder: (ctx) => AlertDialog(
                                 title: const Text('Delete File?'),
                                 content: Text('Are you sure you want to delete "${p.basename(file.relativePath)}"? This will sync to all peers.'),
                                 actions: [
                                   TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                   FilledButton(
                                     onPressed: () {
                                       Navigator.pop(ctx);
                                       ref.read(sharedFolderServiceProvider).deleteFile(file);
                                     },
                                     child: const Text('Delete'),
                                   ),
                                 ],
                               ),
                             );
                          },
                        ),
                  onTap: () {
                     if (file.isDeleted) return;
                     final path = p.join(folder.path, file.relativePath);
                     if (File(path).existsSync()) {
                        OpenFilex.open(path);
                     } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File not found locally (may be syncing)')));
                     }
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAndAddFile(context, folder),
        child: const Icon(Icons.upload_file),
      ),
    );
  }
  
  Future<void> _pickAndAddFile(BuildContext context, SharedFolder folder) async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final source = File(result.files.single.path!);
      final destPath = p.join(folder.path, result.files.single.name);
      
      // Copy to shared folder (Watcher will handle the rest!)
      await source.copy(destPath);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File added! Syncing...')));
      }
    }
  }
  
  String _formatBytes(int bytes) {
     if (bytes <= 0) return '0 B';
     const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
     var i = (bytes > 0) ? (bytes / 1024).floor() : 0; // simplified logic
     // Proper logic:
     if (bytes < 1024) return '$bytes B';
     double num = bytes.toDouble();
     int index = 0;
     while (num >= 1024 && index < suffixes.length - 1) {
       num /= 1024;
       index++;
     }
     return '${num.toStringAsFixed(1)} ${suffixes[index]}';
  }
}
