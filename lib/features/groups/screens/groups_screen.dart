import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/group_service.dart';
import '../../../core/data/database.dart';
import '../../../app/theme.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupService = ref.watch(groupServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: StreamBuilder<List<Group>>(
        stream: groupService.watchAllGroups(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final groups = snapshot.data!;

          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.group_outlined,
                    size: 80,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No groups yet',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to create a group',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return _GroupCard(group: group);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/groups/create'),
        backgroundColor: StoaTheme.primaryColor,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final Group group;

  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupService = ref.watch(groupServiceProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: StoaTheme.primaryColor.withValues(alpha: 0.2),
          child: const Icon(Icons.group, color: Colors.white70),
        ),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: StreamBuilder<List<GroupMember>>(
          stream: groupService.watchGroupMembers(group.id),
          builder: (context, snapshot) {
            final count =
                snapshot.data?.where((m) => m.status == 'accepted').length ?? 0;
            return Text('$count member${count == 1 ? '' : 's'}');
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/groups/${group.id}'),
      ),
    );
  }
}
