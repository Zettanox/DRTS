import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:stoa/app/theme.dart';
import 'package:stoa/core/data/database.dart';
import 'package:stoa/core/services/storage_service.dart';
import 'package:path/path.dart' as p;

// Wrapper for unified file display
class UnifiedFile {
  final dynamic originalObject; // Message or GroupMessage
  final String id;
  final String name;
  final String? path;
  final int size;
  final DateTime timestamp;
  final bool isFolder;
  final String? groupId;
  final bool isReceived;

  UnifiedFile({
    required this.originalObject,
    required this.id,
    required this.name,
    this.path,
    required this.size,
    required this.timestamp,
    this.isFolder = false,
    this.groupId,
    required this.isReceived,
  });
}

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen>
    with SingleTickerProviderStateMixin {
  String?
  _currentGroupId; // If null, we are at Root (showing Groups + DM Files)
  final Set<String> _selectedIds =
      {}; // Use String ID now (prefix with 'm-' or 'g-')
  bool _isSelectionMode = false;
  late TabController _tabController;
  String _downloadsPath = ''; // Current path in downloads browser

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        leading: _currentGroupId != null || _downloadsPath.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_tabController.index == 0 && _currentGroupId != null) {
                    setState(() => _currentGroupId = null);
                  } else if (_tabController.index == 1 &&
                      _downloadsPath.isNotEmpty) {
                    setState(() => _downloadsPath = p.dirname(_downloadsPath));
                  }
                },
              )
            : null,
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected')
            : Text(_getTitle(db)),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Delete Selected',
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _deleteSelected(db),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                });
              },
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Messages', icon: Icon(Icons.chat_bubble_outline)),
            Tab(text: 'Downloads', icon: Icon(Icons.download)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildMessagesTab(db), _buildDownloadsTab()],
      ),
    );
  }

  String _getTitle(AppDatabase db) {
    if (_tabController.index == 0) {
      return _currentGroupId == null
          ? 'Files'
          : _getGroupName(db, _currentGroupId!);
    } else {
      if (_downloadsPath.isEmpty) return 'Downloads';
      return p.basename(_downloadsPath);
    }
  }

  Widget _buildMessagesTab(AppDatabase db) {
    return StreamBuilder<List<Message>>(
      stream: db.watchAllFiles(),
      builder: (context, dmSnapshot) {
        return StreamBuilder<List<GroupMessage>>(
          stream: db.watchAllGroupFiles(),
          builder: (context, groupSnapshot) {
            // Loading states
            if (!dmSnapshot.hasData || !groupSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final dmFiles = dmSnapshot.data!;
            final groupFiles = groupSnapshot.data!;

            // Combine and Filter based on view
            final items = _processFiles(db, dmFiles, groupFiles);

            if (items.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = _selectedIds.contains(item.id);

                return GestureDetector(
                  onLongPress: () {
                    // Only allow selecting files, not folders (for now)
                    if (!item.isFolder || item.groupId == null) {
                      // Allow selecting file-folders but not group-folders
                      // Actually, navigating folders shouldn't be selectable in this mode usually
                      // But user might want to delete a whole group folder? Let's keep it simple: no folder selection
                    }
                    if (!item.isFolder ||
                        (item.isFolder &&
                            item.groupId != null &&
                            _currentGroupId != null)) {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedIds.add(item.id);
                      });
                    }
                  },
                  onTap: () {
                    if (_isSelectionMode) {
                      if (!(_isFolderNavigation(item))) {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(item.id);
                          } else {
                            _selectedIds.add(item.id);
                          }
                          if (_selectedIds.isEmpty) _isSelectionMode = false;
                        });
                      }
                    } else {
                      if (_isFolderNavigation(item)) {
                        // Enter folder
                        setState(() => _currentGroupId = item.groupId);
                      } else {
                        // Open File
                        if (item.path != null) {
                          OpenFilex.open(item.path!);
                        }
                      }
                    }
                  },
                  child: _buildFileItem(context, item, isSelected),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDownloadsTab() {
    return FutureBuilder<String>(
      future: StorageService.getStoaDownloadsPath(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final basePath = snapshot.data!;
        final currentPath = _downloadsPath.isEmpty ? basePath : _downloadsPath;
        final dir = Directory(currentPath);

        return FutureBuilder<List<FileSystemEntity>>(
          future: _listDownloadsDir(dir),
          builder: (context, dirSnapshot) {
            if (!dirSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final entities = dirSnapshot.data!;

            if (entities.isEmpty) {
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
                      _downloadsPath.isEmpty
                          ? 'No downloads yet'
                          : 'Empty folder',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Files from DMs, Groups, and Shared Spaces appear here',
                      style: TextStyle(color: Colors.white38),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async => setState(() {}),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: entities.length,
                itemBuilder: (context, index) {
                  final entity = entities[index];
                  final isDir = entity is Directory;
                  final name = p.basename(entity.path);
                  final stat = entity.statSync();

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        isDir ? Icons.folder : _getFileIcon(name),
                        color: isDir ? StoaTheme.accentColor : null,
                        size: 40,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        isDir ? 'Folder' : _formatBytes(stat.size),
                      ),
                      trailing: isDir
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  _confirmDeleteDownload(entity.path),
                            ),
                      onTap: () {
                        if (isDir) {
                          setState(() => _downloadsPath = entity.path);
                        } else {
                          OpenFilex.open(entity.path);
                        }
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<List<FileSystemEntity>> _listDownloadsDir(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return [];
    }

    final entities = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: false)) {
      if (p.basename(entity.path).startsWith('.')) continue;
      entities.add(entity);
    }

    // Sort: folders first, then alphabetically
    entities.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });

    return entities;
  }

  IconData _getFileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
      return Icons.image;
    }
    if (['.mp4', '.mov', '.avi', '.mkv'].contains(ext)) return Icons.video_file;
    if (['.mp3', '.wav', '.aac', '.flac'].contains(ext)) {
      return Icons.audio_file;
    }
    if (['.pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['.txt', '.md', '.json', '.xml'].contains(ext)) {
      return Icons.description;
    }
    if (['.zip', '.tar', '.gz', '.7z'].contains(ext)) return Icons.archive;
    return Icons.insert_drive_file;
  }

  void _confirmDeleteDownload(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete "${p.basename(path)}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final entity =
                  FileSystemEntity.typeSync(path) ==
                      FileSystemEntityType.directory
                  ? Directory(path)
                  : File(path);
              await entity.delete(recursive: true);
              setState(() {});
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  bool _isFolderNavigation(UnifiedFile item) {
    return item.isFolder && item.groupId != null && _currentGroupId == null;
  }

  List<UnifiedFile> _processFiles(
    AppDatabase db,
    List<Message> dmFiles,
    List<GroupMessage> groupFiles,
  ) {
    final List<UnifiedFile> results = [];

    // 1. Process Group Files
    if (_currentGroupId == null) {
      // ROOT VIEW: Show consolidated Groups and DM files

      // Identify unique groups
      final uniqueGroups = <String>{};
      for (var gf in groupFiles) {
        uniqueGroups.add(gf.groupId);
      }

      // Add Group Folders
      // We need group names. This is async in build...
      // Ideally we'd have a Stream of Groups.
      // For now, we will use a "Group Folder" placeholder and let FutureBuilder resolve generic name if needed?
      // Or better, we can assume we can fetch names or just display "Group (ID)" if needed, but names are better.
      // NOTE: We will fetch actual names via a separate helper or provider in a real app,
      // but here let's try to get names from a cached map or just iterate.
      // A better way is to use `groupFiles` which might not have group name.
      // `Group` table has names.
      // Let's defer group name lookup to the Item builder (using FutureBuilder or similar).

      for (var groupId in uniqueGroups) {
        results.add(
          UnifiedFile(
            originalObject: null, // Virtual folder
            id: 'folder-$groupId',
            name: 'Loading...', // Will solve in UI
            size: 0,
            timestamp: DateTime.now(), // Sort by latest?
            isFolder: true,
            groupId: groupId,
            isReceived: true,
          ),
        );
      }

      // Add DM Files
      for (var f in dmFiles) {
        results.add(
          UnifiedFile(
            originalObject: f,
            id: 'm-${f.id}',
            name: f.content,
            path: f.filePath,
            size: f.fileSize ?? 0,
            timestamp: f.timestamp,
            isFolder: f.type == 'folder',
            isReceived: !f.isMe,
          ),
        );
      }
    } else {
      // GROUP VIEW: Show only files for this group
      final files = groupFiles
          .where((f) => f.groupId == _currentGroupId)
          .toList();
      for (var f in files) {
        results.add(
          UnifiedFile(
            originalObject: f,
            id: 'g-${f.id}',
            name: f.content,
            path: f.filePath,
            size: f.fileSize ?? 0,
            timestamp: f.timestamp,
            isFolder: f.type == 'folder',
            isReceived:
                f.senderId !=
                'me', // simplistic check, ideally check against myId
            groupId: _currentGroupId,
          ),
        );
      }
    }

    // Sort: Folders first, then Newest first
    results.sort((a, b) {
      if (_isFolderNavigation(a) && !_isFolderNavigation(b)) return -1;
      if (!_isFolderNavigation(a) && _isFolderNavigation(b)) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });

    return results;
  }

  String _getGroupName(AppDatabase db, String groupId) {
    // This is sync, but getGroup is async.
    // We will handle title asynchronously in the Widget tree if possible or return 'Group'
    return 'Group'; // Placeholder for title bar
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 80,
            color: Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            'No files shared yet',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(
    BuildContext context,
    UnifiedFile item,
    bool isSelected,
  ) {
    if (_isFolderNavigation(item)) {
      // Group Folder Item with async name fetching
      return FutureBuilder<Group?>(
        future: ref.read(databaseProvider).getGroup(item.groupId!),
        builder: (context, snapshot) {
          final groupName = snapshot.data?.name ?? 'Unknown Group';
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: StoaTheme.secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder,
                  color: StoaTheme.secondaryColor,
                ),
              ),
              title: Text(
                groupName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Group Folder'),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      );
    }

    // Regular File/Folder Item
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? StoaTheme.primaryColor.withValues(alpha: 0.3) : null,
      child: ListTile(
        leading: _buildThumbnail(item),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatBytes(item.size)} • ${DateFormat('MMM d').format(item.timestamp)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (v) {
                  // Handle via parent tap usually, but for checkbox specificity:
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(item.id);
                    } else {
                      _selectedIds.remove(item.id);
                    }
                    if (_selectedIds.isEmpty) _isSelectionMode = false;
                  });
                },
              )
            : null,
      ),
    );
  }

  Widget _buildThumbnail(UnifiedFile item) {
    if (item.isFolder) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.folder_zip, color: Colors.amber),
      );
    }

    // Image Preview
    if (item.path != null && _isImage(item.path!)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(item.path!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultIcon(item),
        ),
      );
    }

    return _defaultIcon(item);
  }

  Widget _defaultIcon(UnifiedFile item) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: StoaTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        item.isReceived ? Icons.download_rounded : Icons.upload_rounded,
        color: StoaTheme.primaryColor,
      ),
    );
  }

  bool _isImage(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
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
    for (final fullId in _selectedIds) {
      try {
        final isGroup = fullId.startsWith('g-');
        final id = int.parse(fullId.substring(2));
        String? filePath;

        if (isGroup) {
          final msg = await (db.select(
            db.groupMessages,
          )..where((t) => t.id.equals(id))).getSingleOrNull();
          filePath = msg?.filePath;
          if (msg != null) await db.deleteGroupMessage(id);
        } else {
          final msg = await (db.select(
            db.messages,
          )..where((t) => t.id.equals(id))).getSingleOrNull();
          filePath = msg?.filePath;
          if (msg != null) await db.deleteMessage(id);
        }

        if (filePath != null) {
          final f = File(filePath);
          if (await f.exists()) {
            await f.delete();
          }
        }
      } catch (e) {
        debugPrint('Failed to delete file $fullId: $e');
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
}
