import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:stoa/app/theme.dart';
import 'package:stoa/core/data/database.dart';
import 'package:stoa/core/services/remote_folder_service.dart';
import 'package:stoa/features/shared_spaces/screens/text_editor_screen.dart';
import 'package:path/path.dart' as p;

class FolderViewScreen extends ConsumerStatefulWidget {
  final SharedFolder folder;
  
  const FolderViewScreen({super.key, required this.folder});

  @override
  ConsumerState<FolderViewScreen> createState() => _FolderViewScreenState();
}

class _FolderViewScreenState extends ConsumerState<FolderViewScreen> {
  @override
  void initState() {
    super.initState();
    // If peer, request file list on open
    if (widget.folder.ownerId != 'me') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(remoteFolderServiceProvider).requestFileList(widget.folder.id, widget.folder.ownerId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.folder.ownerId == 'me';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.name),
        actions: [
          if (!isOwner)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.read(remoteFolderServiceProvider).requestFileList(widget.folder.id, widget.folder.ownerId);
              },
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
               showDialog(context: context, builder: (_) => AlertDialog(
                 title: const Text('Space Info'),
                 content: SelectableText(
                   'ID: ${widget.folder.id}\n'
                   'Owner: ${isOwner ? "You" : widget.folder.ownerId}\n'
                   'Permission: ${widget.folder.permission}\n'
                   '${isOwner ? "Path: ${widget.folder.path}" : ""}'
                 ),
               ));
            },
          ),
        ],
      ),
      body: isOwner ? _buildOwnerView() : _buildPeerView(),
      floatingActionButton: (isOwner || widget.folder.permission == 'read-write')
        ? FloatingActionButton(
            onPressed: () => _pickAndUploadFile(context),
            child: const Icon(Icons.upload_file),
          )
        : null,
    );
  }
  
  /// Owner sees local files directly from disk
  Widget _buildOwnerView() {
    return FutureBuilder<List<FileSystemEntity>>(
      future: _listLocalFiles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
           return _buildEmptyState();
        }
        
        final files = snapshot.data!;
        
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {}); // Trigger rebuild
          },
          child: ListView.builder(
            itemCount: files.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final entity = files[index];
              final isDir = entity is Directory;
              final stat = entity.statSync();
              
              return _buildFileCard(
                name: p.basename(entity.path),
                size: isDir ? 0 : stat.size,
                isDirectory: isDir,
                onTap: () {
                  if (!isDir) {
                     OpenFilex.open(entity.path);
                  }
                },
                onDelete: () => _confirmDeleteOwnerFile(entity.path),
              );
            },
          ),
        );
      },
    );
  }
  
  Future<List<FileSystemEntity>> _listLocalFiles() async {
    final dir = Directory(widget.folder.path);
    if (!await dir.exists()) return [];
    
    final entities = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: false)) {
      // Skip hidden files
      if (p.basename(entity.path).startsWith('.')) continue;
      entities.add(entity);
    }
    entities.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return entities;
  }
  
  void _confirmDeleteOwnerFile(String filePath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File?'),
        content: Text('Delete "${p.basename(filePath)}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final entity = FileSystemEntity.typeSync(filePath) == FileSystemEntityType.directory
                ? Directory(filePath)
                : File(filePath);
              await entity.delete(recursive: true);
              setState(() {}); // Refresh
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  /// Peer sees remote files via stream
  Widget _buildPeerView() {
    return StreamBuilder<List<RemoteFile>>(
      stream: ref.read(remoteFolderServiceProvider).watchRemoteFiles(widget.folder.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Connecting to owner...', style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }
        
        final files = snapshot.data!;
        
        if (files.isEmpty) {
           return _buildEmptyState();
        }
        
        return ListView.builder(
          itemCount: files.length,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, index) {
            final file = files[index];
            final isTextFile = _isTextFile(file.name);
            
            return _buildFileCard(
              name: file.name,
              size: file.size,
              isDirectory: file.isDirectory,
              onTap: () {
                if (!file.isDirectory && isTextFile) {
                  _openInEditor(file.relativePath);
                } else if (!file.isDirectory) {
                  _downloadFile(file.relativePath);
                }
              },
              onEdit: isTextFile && !file.isDirectory && widget.folder.permission == 'read-write'
                ? () => _openInEditor(file.relativePath)
                : null,
              onDownload: !file.isDirectory ? () => _downloadFile(file.relativePath) : null,
              onDelete: widget.folder.permission == 'read-write' && !file.isDirectory
                ? () => _confirmDeleteRemote(file.relativePath)
                : null,
            );
          },
        );
      },
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           const Icon(Icons.folder_open, size: 64, color: Colors.white24),
           const SizedBox(height: 16),
           const Text('Empty Space', style: TextStyle(fontSize: 18, color: Colors.white60)),
           const SizedBox(height: 8),
           if (widget.folder.ownerId == 'me' || widget.folder.permission == 'read-write')
             TextButton.icon(
               onPressed: () => _pickAndUploadFile(context),
               icon: const Icon(Icons.add),
               label: const Text('Add File'),
             )
        ],
      ),
    );
  }
  
  Widget _buildFileCard({
    required String name,
    required int size,
    required bool isDirectory,
    required VoidCallback onTap,
    VoidCallback? onEdit,
    VoidCallback? onDownload,
    VoidCallback? onDelete,
  }) {
    final isText = _isTextFile(name);
    
    return Card(
      child: ListTile(
        leading: Icon(
          isDirectory ? Icons.folder : (isText ? Icons.description : Icons.insert_drive_file_outlined),
          color: isDirectory ? StoaTheme.accentColor : (isText ? Colors.amber : null),
        ),
        title: Text(name),
        subtitle: Text(isDirectory ? 'Folder' : _formatBytes(size)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.amber),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
            if (onDownload != null)
              IconButton(
                icon: const Icon(Icons.download, color: Colors.blue),
                onPressed: onDownload,
                tooltip: 'Download',
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
  
  bool _isTextFile(String name) {
    final ext = p.extension(name).toLowerCase();
    const textExtensions = ['.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.csv', '.log', '.ini', '.conf', '.sh', '.py', '.js', '.dart', '.html', '.css'];
    return textExtensions.contains(ext);
  }
  
  Future<void> _openInEditor(String relativePath) async {
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextEditorScreen(
            spaceId: widget.folder.id,
            spaceName: widget.folder.name,
            ownerId: widget.folder.ownerId,
            relativePath: relativePath,
          ),
        ),
      );
    }
  }
  
  void _downloadFile(String relativePath) {
    ref.read(remoteFolderServiceProvider).requestDownload(
      widget.folder.id, 
      widget.folder.ownerId, 
      relativePath,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading $relativePath...')),
    );
  }
  
  void _confirmDeleteLocal(SharedFile file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File?'),
        content: Text('Delete "${p.basename(file.relativePath)}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final path = p.join(widget.folder.path, file.relativePath);
              final f = File(path);
              if (await f.exists()) {
                await f.delete();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  void _confirmDeleteRemote(String relativePath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File?'),
        content: Text('Delete "$relativePath" from owner\'s device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(remoteFolderServiceProvider).requestDelete(
                widget.folder.id, 
                widget.folder.ownerId, 
                relativePath,
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _pickAndUploadFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final source = File(result.files.single.path!);
      final bytes = await source.readAsBytes();
      final fileName = result.files.single.name;
      
      if (widget.folder.ownerId == 'me') {
        // Owner: Copy to local folder
        final destPath = p.join(widget.folder.path, fileName);
        await source.copy(destPath);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File added!')));
        }
      } else {
        // Peer: Upload to owner
        ref.read(remoteFolderServiceProvider).uploadFile(
          widget.folder.id,
          widget.folder.ownerId,
          fileName,
          bytes,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading...')));
        }
      }
    }
  }
  
  String _formatBytes(int bytes) {
     if (bytes <= 0) return '0 B';
     const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
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
