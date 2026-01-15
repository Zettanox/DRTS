import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/connection_service.dart';
import '../core/services/discovery_service.dart';
import '../core/services/group_service.dart';
import '../core/services/remote_folder_service.dart';
import '../core/data/database.dart';
import 'router.dart';

/// Global handler for connection events that works regardless of which screen is active.
/// This widget should be placed inside MaterialApp.builder to ensure connection
/// request dialogs appear even when the user is not on the Peers screen.
class GlobalConnectionHandler extends ConsumerStatefulWidget {
  final Widget child;
  
  const GlobalConnectionHandler({super.key, required this.child});

  @override
  ConsumerState<GlobalConnectionHandler> createState() => _GlobalConnectionHandlerState();
}

class _GlobalConnectionHandlerState extends ConsumerState<GlobalConnectionHandler> {
  StreamSubscription<ConnectionMessage>? _connectionSubscription;
  StreamSubscription<GroupInvitation>? _groupInviteSubscription;
  StreamSubscription? _peerResolvedSubscription;
  bool _isDialogShowing = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🌐 GlobalConnectionHandler: initState');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set up subscription after dependencies are available
    if (!_isInitialized) {
      _isInitialized = true;
      debugPrint('🌐 GlobalConnectionHandler: Setting up in didChangeDependencies');
      _initializeConnectionService();
      _listenToConnections();
      _listenToGroupInvitations();
      _listenToPeerResolution();
    }
  }

  Future<void> _initializeConnectionService() async {
    try {
      debugPrint('🌐 GlobalConnectionHandler: Initializing connection service');
      await ref.read(connectionServiceProvider).initialize();
      
      // Initialize Remote Folder Service for Shared Spaces
      debugPrint('📂 GlobalConnectionHandler: Initializing Shared Spaces');
      ref.read(remoteFolderServiceProvider).initialize();
      
    } catch (e) {
      debugPrint('❌ GlobalConnectionHandler: Failed to initialize services: $e');
    }
  }

  void _listenToConnections() {
    debugPrint('🌐 GlobalConnectionHandler: Subscribing to message stream');
    _connectionSubscription?.cancel(); // Cancel any existing subscription
    
    _connectionSubscription = ref.read(connectionServiceProvider).messageStream.listen((message) async {
      debugPrint('🌐 GlobalConnectionHandler: Received message type: ${message.type}');
      
      if (!mounted) {
        debugPrint('🌐 GlobalConnectionHandler: Not mounted, ignoring');
        return;
      }

      if (message.type == ConnectionMessageType.connectionRequest) {
        // Check if this peer is in a shared group (auto-connect)
        final isGroupMember = await ref.read(databaseProvider).isPeerInAnyGroup(message.peerId);
        
        if (isGroupMember) {
          debugPrint('🌐 Auto-accepting connection from group member: ${message.peerId}');
          ref.read(connectionServiceProvider).acceptConnection(message.peerId);
        } else {
          debugPrint('🌐 GlobalConnectionHandler: Showing connection request dialog');
          _showConnectionRequestDialog(message);
        }
      }
    }, onError: (e) {
      debugPrint('🌐 GlobalConnectionHandler: Stream error: $e');
    });
  }

  void _listenToGroupInvitations() {
    debugPrint('🌐 GlobalConnectionHandler: Subscribing to group invitations');
    _groupInviteSubscription?.cancel();
    
    _groupInviteSubscription = ref.read(groupServiceProvider).invitationStream.listen((invitation) {
      if (!mounted) return;
      _showGroupInvitationDialog(invitation);
    });
  }

  void _listenToPeerResolution() {
    debugPrint('🌐 GlobalConnectionHandler: Subscribing to peer resolution for auto-connect');
    _peerResolvedSubscription?.cancel();
    
    _peerResolvedSubscription = ref.read(discoveryServiceProvider).peerResolvedStream.listen((peer) async {
      if (!mounted) return;
      
      // Check if this peer is a group member
      final isGroupMember = await ref.read(databaseProvider).isPeerInAnyGroup(peer.id);
      
      if (isGroupMember && peer.host != 'unknown') {
        final connectionService = ref.read(connectionServiceProvider);
        
        // Only initiate if not already connected
        if (!connectionService.isConnectedTo(peer.id)) {
          debugPrint('🔄 Auto-initiating connection to group member: ${peer.username}');
          try {
            await connectionService.connectTo(peer);
          } catch (e) {
            debugPrint('⚠️ Auto-connect failed: $e');
          }
        }
      }
    });
  }

  void _showConnectionRequestDialog(ConnectionMessage message) {
    if (_isDialogShowing) {
      debugPrint('🌐 GlobalConnectionHandler: Dialog already showing, skipping');
      return;
    }
    
    final username = message.payload['username'] as String?;
    final peerId = message.peerId;

    debugPrint('🌐 GlobalConnectionHandler: Showing dialog for $username');
    
    // Get the navigator key from the router provider
    final navigatorKey = ref.read(navigatorKeyProvider);
    final navigatorContext = navigatorKey.currentContext;
    
    if (navigatorContext == null) {
      debugPrint('❌ GlobalConnectionHandler: Navigator context not available');
      return;
    }
    
    _isDialogShowing = true;
    
    showDialog(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection Request'),
        content: Text('${username ?? 'Unknown user'} wants to connect with you.'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(connectionServiceProvider).denyConnection(peerId);
              Navigator.pop(ctx);
              _isDialogShowing = false;
            },
            child: const Text('Deny', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              ref.read(connectionServiceProvider).acceptConnection(peerId);
              Navigator.pop(ctx);
              _isDialogShowing = false;
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  void _showGroupInvitationDialog(GroupInvitation invitation) {
    if (_isDialogShowing) return;
    
    final navigatorKey = ref.read(navigatorKeyProvider);
    final navigatorContext = navigatorKey.currentContext;
    
    if (navigatorContext == null) return;
    
    _isDialogShowing = true;
    
    showDialog(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Group Invitation'),
        content: Text('${invitation.ownerName} invites you to join "${invitation.groupName}"'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(groupServiceProvider).rejectInvitation(invitation.groupId);
              Navigator.pop(ctx);
              _isDialogShowing = false;
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              ref.read(groupServiceProvider).acceptInvitation(invitation.groupId);
              Navigator.pop(ctx);
              _isDialogShowing = false;
            },
            child: const Text('Join'),
          ),
        ],
      ),
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  @override
  void dispose() {
    debugPrint('🌐 GlobalConnectionHandler: dispose');
    _connectionSubscription?.cancel();
    _groupInviteSubscription?.cancel();
    _peerResolvedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

