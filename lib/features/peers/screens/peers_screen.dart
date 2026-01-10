import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:stoa/core/models/peer.dart';
import 'package:stoa/core/services/discovery_service.dart';
import 'package:stoa/app/theme.dart';
import '../widgets/peer_card.dart';

class PeersScreen extends ConsumerStatefulWidget {
  const PeersScreen({super.key});

  @override
  ConsumerState<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends ConsumerState<PeersScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-start discovery when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryStateProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryStateProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Peers'),
        actions: [
          // Toggle discovery button
          IconButton(
            icon: Icon(
              discoveryState.isDiscovering 
                  ? Icons.wifi_tethering 
                  : Icons.wifi_tethering_off,
              color: discoveryState.isDiscovering 
                  ? StoaTheme.success 
                  : Colors.grey,
            ),
            onPressed: () {
              if (discoveryState.isDiscovering) {
                ref.read(discoveryStateProvider.notifier).stop();
              } else {
                ref.read(discoveryStateProvider.notifier).start();
              }
            },
            tooltip: discoveryState.isDiscovering 
                ? 'Stop discovery' 
                : 'Start discovery',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(discoveryState),
          
          // Error message
          if (discoveryState.error != null)
            _buildErrorBanner(discoveryState.error!),
          
          // Peers list
          Expanded(
            child: discoveryState.peers.isEmpty
                ? _buildEmptyState(discoveryState)
                : _buildPeersList(discoveryState.peers),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusBar(DiscoveryState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: StoaTheme.darkSurface,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Discovery status indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.isDiscovering ? StoaTheme.success : Colors.grey,
              boxShadow: state.isDiscovering
                  ? [
                      BoxShadow(
                        color: StoaTheme.success.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          )
              .animate(
                onPlay: (controller) => state.isDiscovering 
                    ? controller.repeat(reverse: true) 
                    : controller.stop(),
              )
              .scaleXY(
                begin: 1.0,
                end: 1.3,
                duration: 1.seconds,
              ),
          
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.isDiscovering 
                      ? 'Searching for peers...' 
                      : 'Discovery paused',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '${state.peers.length} peer(s) found',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          
          // Broadcast status
          if (state.isBroadcasting)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: StoaTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broadcast_on_personal,
                    size: 14,
                    color: StoaTheme.primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Visible',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StoaTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildErrorBanner(String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: StoaTheme.error.withOpacity(0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: StoaTheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: StoaTheme.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            color: StoaTheme.error,
            onPressed: () {
              ref.read(discoveryStateProvider.notifier).start();
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState(DiscoveryState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.isDiscovering 
                  ? Icons.radar 
                  : Icons.wifi_off,
              size: 80,
              color: Colors.white24,
            )
                .animate(
                  onPlay: (controller) => state.isDiscovering 
                      ? controller.repeat() 
                      : controller.stop(),
                )
                .rotate(
                  duration: 3.seconds,
                  curve: Curves.linear,
                ),
            
            const SizedBox(height: 24),
            
            Text(
              state.isDiscovering 
                  ? 'Looking for peers...' 
                  : 'Discovery is paused',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              state.isDiscovering
                  ? 'Make sure other Stoa users are on the same network'
                  : 'Tap the antenna icon to start searching',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
            
            if (!state.isDiscovering) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(discoveryStateProvider.notifier).start();
                },
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Start Discovery'),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildPeersList(List<Peer> peers) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: peers.length,
      itemBuilder: (context, index) {
        final peer = peers[index];
        return PeerCard(
          peer: peer,
          onTap: () => _showPeerOptions(peer),
        )
            .animate()
            .fadeIn(delay: (index * 100).ms)
            .slideX(begin: 0.1, end: 0);
      },
    );
  }
  
  void _showPeerOptions(Peer peer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: StoaTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PeerOptionsSheet(peer: peer),
    );
  }
}

class _PeerOptionsSheet extends StatelessWidget {
  final Peer peer;
  
  const _PeerOptionsSheet({required this.peer});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Peer info
          Row(
            children: [
              _buildAvatar(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.username,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${peer.host}:${peer.port}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Actions
          _buildAction(
            context,
            icon: Icons.send_rounded,
            label: 'Send File',
            color: StoaTheme.primaryColor,
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement file sending
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File sharing coming in Phase 3!')),
              );
            },
          ),
          
          _buildAction(
            context,
            icon: Icons.message_outlined,
            label: 'Send Message',
            color: StoaTheme.secondaryColor,
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement messaging
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Messaging coming in Phase 5!')),
              );
            },
          ),
          
          _buildAction(
            context,
            icon: Icons.folder_shared_outlined,
            label: 'Create Shared Folder',
            color: StoaTheme.accentColor,
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement shared folders
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Shared folders coming in Phase 6!')),
              );
            },
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  Widget _buildAvatar() {
    final color = _parseColor(peer.avatarColor);
    
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          peer.username.isNotEmpty 
              ? peer.username[0].toUpperCase() 
              : '?',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
  
  Widget _buildAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }
  
  Color _parseColor(String? hex) {
    if (hex == null) return StoaTheme.primaryColor;
    final hexCode = hex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }
}
