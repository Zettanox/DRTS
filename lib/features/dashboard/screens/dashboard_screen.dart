import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import 'package:stoa/core/models/user.dart';
import 'package:stoa/core/services/storage_service.dart';
import 'package:stoa/core/services/discovery_service.dart';
import 'package:stoa/app/theme.dart';
import 'package:stoa/features/peers/screens/peers_screen.dart';
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
        return _buildPlaceholder('Groups', Icons.forum_outlined, 'Coming in Phase 5');
      case 3:
        return _buildPlaceholder('Files', Icons.folder_outlined, 'Coming in Phase 3');
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildPlaceholder(String title, IconData icon, String message) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    final discoveryState = ref.watch(discoveryStateProvider);
    
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
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                // TODO: Open settings
              },
            ),
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
              )
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms),
              
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Groups coming in Phase 5!')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickAction(
                      icon: Icons.upload_file_outlined,
                      label: 'Share File',
                      color: StoaTheme.accentColor,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('File sharing coming in Phase 3!')),
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
                        ref.read(discoveryStateProvider.notifier).stop();
                      } else {
                        ref.read(discoveryStateProvider.notifier).start();
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
              )
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 400.ms),
              
              const SizedBox(height: 12),
              
              _buildStatusCard(discoveryState)
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
              
              const SizedBox(height: 32),
              
              // Recent activity placeholder
              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge,
              )
                  .animate()
                  .fadeIn(delay: 500.ms, duration: 400.ms),
              
              const SizedBox(height: 12),
              
              _buildEmptyState(
                icon: Icons.history_outlined,
                title: 'No recent activity',
                subtitle: 'Your recent files, messages, and collaborations will appear here',
              )
                  .animate()
                  .fadeIn(delay: 600.ms, duration: 400.ms),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            StoaTheme.primaryColor.withOpacity(0.2),
            StoaTheme.secondaryColor.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: StoaTheme.primaryColor.withOpacity(0.2),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white60,
                  ),
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
                final discoveryNotifier = ref.read(discoveryStateProvider.notifier);
                await discoveryNotifier.stop();
                await discoveryNotifier.start();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated! Discovery restarted.')),
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
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
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
            statusColor: discoveryState.isDiscovering ? StoaTheme.success : Colors.grey,
          ),
          const Divider(height: 24),
          _buildStatusRow(
            icon: Icons.people_outline,
            label: 'Peers nearby',
            status: '${discoveryState.peers.length} found',
            statusColor: discoveryState.peers.isNotEmpty ? StoaTheme.primaryColor : Colors.grey,
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
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: StoaTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null) return StoaTheme.primaryColor;
    final hexCode = hex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }
}
