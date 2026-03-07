import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import 'package:stoa/core/models/user.dart';
import 'package:stoa/core/services/storage_service.dart';
import 'package:stoa/core/services/discovery_service.dart';
import 'package:stoa/core/services/connection_service.dart';
import 'package:stoa/core/data/database.dart';
import 'package:stoa/app/theme.dart';
import 'package:stoa/features/peers/screens/peers_screen.dart';
import 'package:stoa/features/files/screens/files_screen.dart';
import 'package:stoa/features/groups/screens/groups_screen.dart';
import 'package:stoa/features/shared_spaces/screens/shared_spaces_screen.dart';
import 'package:stoa/features/onboarding/widgets/edit_profile_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  User? _user;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadUser();

    // Initialize connection server
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(connectionServiceProvider).initialize();
    });
  }

  Future<void> _loadUser() async {
    final storage = ref.read(storageServiceProvider);
    final user = await storage.loadUser();
    if (mounted) {
      setState(() {
        _user = user;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _user == null
            ? const Center(child: CircularProgressIndicator())
            : _buildCurrentScreen(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Peers',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_shared_outlined),
            selectedIcon: Icon(Icons.folder_shared),
            label: 'Shared',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Files',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return const PeersScreen();
      case 2:
        return const GroupsScreen();
      case 3:
        return const SharedSpacesScreen(); // New Tab
      case 4:
        return const FilesScreen();
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    final discoveryState = ref.watch(discoveryStateControllerProvider);

    return CustomScrollView(
      slivers: [
        // App Bar
        SliverAppBar(
          floating: true,
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [StoaTheme.primaryColor, StoaTheme.secondaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Stoa'),
            ],
          ),
          actions: const [
            // Settings icon removed as requested
          ],
        ),

        // Content
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Welcome card
              _buildWelcomeCard()
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),

              const SizedBox(height: 24),

              // Quick actions
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge,
              ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

              const SizedBox(height: 12),

              Row(
                    children: [
                      Expanded(
                        child: _buildQuickAction(
                          icon: Icons.person_add_outlined,
                          label: 'Find Peers',
                          color: StoaTheme.primaryColor,
                          onTap: () {
                            setState(() => _selectedIndex = 1);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickAction(
                          icon: Icons.group_add_outlined,
                          label: 'New Group',
                          color: StoaTheme.secondaryColor,
                          onTap: () {
                            context.push('/groups/create');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickAction(
                          icon: Icons.folder_open_outlined,
                          label: 'Open Downloads',
                          color: StoaTheme.accentColor,
                          onTap: () {
                            ref
                                .read(storageServiceProvider)
                                .openDownloadsFolder();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Opening downloads folder...'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),

              const SizedBox(height: 32),

              // Status section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Network Status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  // Discovery toggle
                  TextButton.icon(
                    onPressed: () {
                      if (discoveryState.isDiscovering) {
                        ref
                            .read(discoveryStateControllerProvider.notifier)
                            .stop();
                      } else {
                        ref
                            .read(discoveryStateControllerProvider.notifier)
                            .start();
                      }
                    },
                    icon: Icon(
                      discoveryState.isDiscovering
                          ? Icons.wifi_tethering
                          : Icons.wifi_tethering_off,
                      size: 18,
                    ),
                    label: Text(
                      discoveryState.isDiscovering ? 'Active' : 'Start',
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

              const SizedBox(height: 12),

              _buildStatusCard(discoveryState)
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),

              const SizedBox(height: 32),

              // Recent Activity Section
              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge,
              ).animate().fadeIn(delay: 500.ms, duration: 400.ms),

              const SizedBox(height: 12),

              _buildRecentActivity().animate().fadeIn(
                delay: 600.ms,
                duration: 400.ms,
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    final db = ref.watch(databaseProvider);

    return Column(
      children: [
        // Recent Messages
        StreamBuilder<List<Message>>(
          stream: db.watchRecentMessages(5),
          builder: (context, snapshot) {
            final messages = snapshot.data ?? [];

            if (messages.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Messages',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedIndex = 1),
                      child: const Text('See all'),
                    ),
                  ],
                ),
                ...messages.take(3).map((msg) => _buildRecentMessageItem(msg)),
              ],
            );
          },
        ),

        const SizedBox(height: 16),

        // Recent Downloads
        FutureBuilder<List<FileSystemEntity>>(
          future: _getRecentDownloads(),
          builder: (context, snapshot) {
            final files = snapshot.data ?? [];

            if (files.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Downloads',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedIndex = 2),
                      child: const Text('See all'),
                    ),
                  ],
                ),
                ...files.take(3).map((file) => _buildRecentDownloadItem(file)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecentMessageItem(Message msg) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: StoaTheme.primaryColor.withValues(alpha: 0.2),
          child: Icon(
            msg.isMe ? Icons.arrow_upward : Icons.arrow_downward,
            color: msg.isMe ? Colors.blue : Colors.green,
            size: 20,
          ),
        ),
        title: Text(
          msg.content.length > 40
              ? '${msg.content.substring(0, 40)}...'
              : msg.content,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatTime(msg.timestamp),
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        trailing: msg.type == 'file'
            ? const Icon(Icons.attach_file, size: 16, color: Colors.white38)
            : null,
        onTap: () {
          context.pushNamed('chat', pathParameters: {'peerId': msg.peerId});
        },
      ),
    );
  }

  Widget _buildRecentDownloadItem(FileSystemEntity file) {
    final name = p.basename(file.path);
    final stat = file.statSync();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: StoaTheme.accentColor.withValues(alpha: 0.2),
          child: Icon(
            _getFileIcon(name),
            color: StoaTheme.accentColor,
            size: 20,
          ),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          _formatTime(stat.modified),
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        onTap: () => OpenFilex.open(file.path),
      ),
    );
  }

  Future<List<FileSystemEntity>> _getRecentDownloads() async {
    final basePath = await StorageService.getStoaDownloadsPath();
    final dir = Directory(basePath);

    if (!await dir.exists()) return [];

    final files = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && !p.basename(entity.path).startsWith('.')) {
        files.add(entity);
      }
    }

    // Sort by modification time (newest first)
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );

    return files.take(5).toList();
  }

  IconData _getFileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
      return Icons.image;
    }
    if (['.mp4', '.mov', '.avi', '.mkv'].contains(ext)) {
      return Icons.video_file;
    }
    if (['.mp3', '.wav', '.aac', '.flac'].contains(ext)) {
      return Icons.audio_file;
    }
    if (['.pdf'].contains(ext)) {
      return Icons.picture_as_pdf;
    }
    if (['.txt', '.md', '.json', '.xml'].contains(ext)) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            StoaTheme.primaryColor.withValues(alpha: 0.2),
            StoaTheme.secondaryColor.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: StoaTheme.primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _parseColor(_user?.avatarColor),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                _user?.username.substring(0, 1).toUpperCase() ?? '?',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
                ),
                Text(
                  _user?.username ?? 'User',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              if (_user == null) return;
              final updatedUser = await EditProfileDialog.show(context, _user!);
              if (updatedUser != null && mounted) {
                setState(() {
                  _user = updatedUser;
                });
                // Restart discovery with new user info
                final discoveryNotifier = ref.read(
                  discoveryStateControllerProvider.notifier,
                );
                await discoveryNotifier.stop();
                await discoveryNotifier.start();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profile updated! Discovery restarted.'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(DiscoveryState discoveryState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StoaTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildStatusRow(
            icon: Icons.wifi,
            label: 'Discovery',
            status: discoveryState.isDiscovering ? 'Active' : 'Inactive',
            statusColor: discoveryState.isDiscovering
                ? StoaTheme.success
                : Colors.grey,
          ),
          const Divider(height: 24),
          _buildStatusRow(
            icon: Icons.people_outline,
            label: 'Peers nearby',
            status: '${discoveryState.peers.length} found',
            statusColor: discoveryState.peers.isNotEmpty
                ? StoaTheme.primaryColor
                : Colors.grey,
          ),
          const Divider(height: 24),
          _buildStatusRow(
            icon: Icons.folder_shared_outlined,
            label: 'Shared folders',
            status: '0 active',
            statusColor: Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required String status,
    required Color statusColor,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: statusColor),
          ),
        ),
      ],
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null) return StoaTheme.primaryColor;
    final hexCode = hex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }
}
