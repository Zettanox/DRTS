import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart'; // Import open_filex
import 'package:stoa/app/theme.dart';
import 'package:stoa/core/data/database.dart'; // Import database
import 'package:stoa/core/services/file_transfer_service.dart'; // Import file transfer service

class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
      ),
      body: StreamBuilder<List<Message>>(
        stream: db.watchAllFiles(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final files = snapshot.data!;
          
          if (files.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_open_outlined, size: 80, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text(
                    'No files shared yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            );
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return _buildFileItem(context, file);
            },
          );
        },
      ),
    );
  }
  
  Widget _buildFileItem(BuildContext context, Message file) {
    final isReceived = !file.isMe;
    final date = DateFormat('MMM d, h:mm a').format(file.timestamp);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: (isReceived ? StoaTheme.secondaryColor : StoaTheme.primaryColor).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isReceived ? Icons.download_rounded : Icons.upload_rounded,
            color: isReceived ? StoaTheme.secondaryColor : StoaTheme.primaryColor,
          ),
        ),
        title: Text(
          file.content,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              _formatBytes(file.fileSize ?? 0),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            const Text('•'),
            const SizedBox(width: 8),
            Text(
              date,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () {
            if (file.filePath != null) {
              OpenFilex.open(file.filePath!);
            }
          },
        ),
      ),
    );
  }
  
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}
