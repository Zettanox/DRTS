import 'package:flutter/material.dart';
import 'package:stoa/app/theme.dart';

class SharedSpacesScreen extends StatelessWidget {
  const SharedSpacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Spaces'),
        centerTitle: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: StoaTheme.accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.folder_shared_outlined,
                  size: 64,
                  color: StoaTheme.accentColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Collaborative Folders',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Real-time folder synchronization with CRDTs is coming in Phase 7. Create a shared space to keep files in sync automatically across devices.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white60,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () {
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Coming soon!')),
                   );
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Notify Me'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
