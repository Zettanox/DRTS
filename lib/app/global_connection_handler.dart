import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/connection_service.dart';
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
  StreamSubscription<ConnectionMessage>? _subscription;
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
    }
  }

  Future<void> _initializeConnectionService() async {
    try {
      debugPrint('🌐 GlobalConnectionHandler: Initializing connection service');
      await ref.read(connectionServiceProvider).initialize();
    } catch (e) {
      debugPrint('❌ GlobalConnectionHandler: Failed to initialize connection service: $e');
    }
  }

  void _listenToConnections() {
    debugPrint('🌐 GlobalConnectionHandler: Subscribing to message stream');
    _subscription?.cancel(); // Cancel any existing subscription
    
    _subscription = ref.read(connectionServiceProvider).messageStream.listen((message) {
      debugPrint('🌐 GlobalConnectionHandler: Received message type: ${message.type}');
      
      if (!mounted) {
        debugPrint('🌐 GlobalConnectionHandler: Not mounted, ignoring');
        return;
      }

      if (message.type == ConnectionMessageType.connectionRequest) {
        debugPrint('🌐 GlobalConnectionHandler: Showing connection request dialog');
        _showConnectionRequestDialog(message);
      }
    }, onError: (e) {
      debugPrint('🌐 GlobalConnectionHandler: Stream error: $e');
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

  @override
  void dispose() {
    debugPrint('🌐 GlobalConnectionHandler: dispose');
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
