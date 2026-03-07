import 'package:flutter/material.dart';
import 'package:stoa/core/models/peer.dart';
import 'package:stoa/app/theme.dart';

/// Card widget displaying a discovered peer
class PeerCard extends StatelessWidget {
  final Peer peer;
  final VoidCallback? onTap;

  const PeerCard({super.key, required this.peer, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              _buildAvatar(),

              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            peer.username,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(context),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      peer.host,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              // Action indicator
              _buildActionIcon(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    switch (peer.connectionStatus) {
      case PeerConnectionStatus.connected:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: StoaTheme.success.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 10, color: StoaTheme.success),
              const SizedBox(width: 4),
              Text(
                'Connected',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StoaTheme.success,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      case PeerConnectionStatus.connecting:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: StoaTheme.secondaryColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: StoaTheme.secondaryColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Connecting...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StoaTheme.secondaryColor,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      case PeerConnectionStatus.failed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: StoaTheme.error.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Failed',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StoaTheme.error,
              fontSize: 10,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildActionIcon() {
    if (peer.connectionStatus == PeerConnectionStatus.connecting) {
      return const SizedBox.shrink();
    }
    return const Icon(Icons.chevron_right, color: Colors.white54);
  }

  Widget _buildAvatar() {
    final color = _parseColor(peer.avatarColor);

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          peer.username.isNotEmpty ? peer.username[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null) return StoaTheme.primaryColor;
    final hexCode = hex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }
}
