import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:stoa/app/theme.dart';
import 'package:stoa/core/data/database.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode 
            ? Text('${_selectedIds.length} selected')
            : const Text('Files'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select All',
              onPressed: () {
                // Will be populated after StreamBuilder has data
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Delete Selected',
              onPressed: _selectedIds.isEmpty ? null : () => _deleteSelected(db),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                });
              },
            ),
          ],
        ],
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
              final isSelected = _selectedIds.contains(file.id);
              
              return GestureDetector(
                onLongPress: () {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedIds.add(file.id);
                  });
                },
                onTap: () {
                  if (_isSelectionMode) {
                    setState(() {
                      if (isSelected) {
                        _selectedIds.remove(file.id);
                        if (_selectedIds.isEmpty) {
                          _isSelectionMode = false;
                        }
                      } else {
                        _selectedIds.add(file.id);
                      }
                    });
                  } else if (file.filePath != null) {
                    OpenFilex.open(file.filePath!);
                  }
                },
                child: _buildFileItem(context, file, isSelected),
              );
            },
          );
        },
      ),
    );
  }
  
  Widget _buildFileItem(BuildContext context, Message file, bool isSelected) {
    final isReceived = !file.isMe;
    final date = DateFormat('MMM d, h:mm a').format(file.timestamp);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? StoaTheme.primaryColor.withOpacity(0.3) : null,
      child: ListTile(
        leading: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedIds.add(file.id);
                    } else {
                      _selectedIds.remove(file.id);
                      if (_selectedIds.isEmpty) {
                        _isSelectionMode = false;
                      }
                    }
                  });
                },
              )
            : _buildFileThumbnail(file, isReceived),
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
        trailing: _isSelectionMode
            ? null
            : IconButton(
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
  
  Future<void> _deleteSelected(AppDatabase db) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Files?'),
        content: Text('Delete ${_selectedIds.length} file(s) from storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Delete each selected file
    for (final id in _selectedIds) {
      try {
        // Get file path before deleting from DB
        final files = await db.watchAllFiles().first;
        final file = files.cast<Message?>().firstWhere((f) => f?.id == id, orElse: () => null);
        
        if (file?.filePath != null) {
          final f = File(file!.filePath!);
          if (await f.exists()) {
            await f.delete();
          }
        }
        
        await db.deleteMessage(id);
      } catch (e) {
        debugPrint('Failed to delete file $id: $e');
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${_selectedIds.length} file(s)')),
      );
      
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
    }
  }
  
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
  
  /// Check if the file is an image based on extension
  bool _isImageFile(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'].contains(ext);
  }
  
  /// Check if the file is a video based on extension
  bool _isVideoFile(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv'].contains(ext);
  }
  
  /// Build a thumbnail widget for file preview
  Widget _buildFileThumbnail(Message file, bool isReceived) {
    final filename = file.content;
    final filePath = file.filePath;
    
    // For folders
    if (file.type == 'folder') {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: StoaTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.folder_rounded, color: Colors.amber),
      );
    }
    
    // For images - show thumbnail
    if (_isImageFile(filename) && filePath != null) {
      final imageFile = File(filePath);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: FutureBuilder<bool>(
            future: imageFile.exists(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return Image.file(
                  imageFile,
                  fit: BoxFit.cover,
                  cacheWidth: 96, // 2x for retina
                  errorBuilder: (_, __, ___) => _buildDefaultIcon(isReceived),
                );
              }
              return _buildDefaultIcon(isReceived);
            },
          ),
        ),
      );
    }
    
    // For videos - show play icon
    if (_isVideoFile(filename)) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.deepPurple.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.play_circle_filled_rounded, color: Colors.deepPurple),
      );
    }
    
    // Default icon for other files
    return _buildDefaultIcon(isReceived);
  }
  
  Widget _buildDefaultIcon(bool isReceived) {
    return Container(
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
    );
  }
}
