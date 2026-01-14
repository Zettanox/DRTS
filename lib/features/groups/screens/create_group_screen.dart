import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/group_service.dart';
import '../../../core/services/discovery_service.dart';
import '../../../core/models/peer.dart';
import '../../../app/theme.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedPeerIds = {};
  bool _showHistoryToNew = false;
  bool _isCreating = false;
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryStateProvider);
    // Show all discovered peers (they may not be "online" but are visible)
    final availablePeers = discoveryState.peers;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group'),
        actions: [
          TextButton(
            onPressed: _canCreate() ? _createGroup : null,
            child: _isCreating
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Group name
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Group Name',
              hintText: 'Enter group name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          
          const SizedBox(height: 24),
          
          // Settings
          SwitchListTile(
            title: const Text('Show history to new members'),
            subtitle: const Text('New members can see old messages'),
            value: _showHistoryToNew,
            onChanged: (val) => setState(() => _showHistoryToNew = val),
          ),
          
          const SizedBox(height: 24),
          
          // Peer selection
          Text(
            'Select Members (${_selectedPeerIds.length} selected)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          
          if (availablePeers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No peers found. Members must be discovered to be invited.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...availablePeers.map((peer) => _PeerCheckbox(
              peer: peer,
              isSelected: _selectedPeerIds.contains(peer.id),
              onToggle: (selected) {
                setState(() {
                  if (selected) {
                    _selectedPeerIds.add(peer.id);
                  } else {
                    _selectedPeerIds.remove(peer.id);
                  }
                });
              },
            )),
        ],
      ),
    );
  }
  
  bool _canCreate() {
    return _nameController.text.trim().isNotEmpty && 
           _selectedPeerIds.isNotEmpty &&
           !_isCreating;
  }
  
  Future<void> _createGroup() async {
    setState(() => _isCreating = true);
    
    try {
      final discoveryState = ref.read(discoveryStateProvider);
      final selectedPeers = discoveryState.peers
          .where((p) => _selectedPeerIds.contains(p.id))
          .toList();
      
      await ref.read(groupServiceProvider).createGroup(
        _nameController.text.trim(),
        selectedPeers,
        showHistoryToNew: _showHistoryToNew,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created! Invites sent.')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}

class _PeerCheckbox extends StatelessWidget {
  final Peer peer;
  final bool isSelected;
  final ValueChanged<bool> onToggle;
  
  const _PeerCheckbox({
    required this.peer,
    required this.isSelected,
    required this.onToggle,
  });
  
  static Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return StoaTheme.primaryColor;
    try {
      return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
    } catch (_) {
      return StoaTheme.primaryColor;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (val) => onToggle(val ?? false),
        title: Text(peer.username),
        subtitle: Text(peer.isConnected ? 'Connected' : 'Discovered'),
        secondary: CircleAvatar(
          backgroundColor: _parseColor(peer.avatarColor),
          child: Text(
            peer.username[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

