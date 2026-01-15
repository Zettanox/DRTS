import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../models/user.dart';
import '../utils/constants.dart';
import 'connection_service.dart';
import 'storage_service.dart';

/// Service for discovering peers on the local network using mDNS
class DiscoveryService {
  static const String _serviceType = '_stoa._tcp';
  
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription? _discoverySubscription;
  Timer? _retryTimer;
  
  final _peersController = StreamController<List<Peer>>.broadcast();
  final _peerResolvedController = StreamController<Peer>.broadcast();
  final Map<String, Peer> _peers = {};
  final Map<String, BonsoirService> _unresolvedServices = {};
  
  bool _isBroadcasting = false;
  bool _isDiscovering = false;
  User? _currentUser;
  
  /// Stream of discovered peers
  Stream<List<Peer>> get peersStream => _peersController.stream;
  
  /// Stream that emits when a peer is resolved (has valid IP)
  /// Used for auto-connect to group members
  Stream<Peer> get peerResolvedStream => _peerResolvedController.stream;
  
  /// Current list of discovered peers
  List<Peer> get peers => _peers.values.toList();
  
  /// Whether we're currently broadcasting our presence
  bool get isBroadcasting => _isBroadcasting;
  
  /// Whether we're currently discovering peers
  bool get isDiscovering => _isDiscovering;
  
  /// Get the current user's peer ID (for group identification)
  String get myPeerId => _currentUser?.id ?? '';
  
  /// Get the current user's username
  String get myUsername => _currentUser?.username ?? 'Unknown';
  
  /// Force retry resolution for all unresolved peers
  void retryUnresolvedPeers() {
    print('🔄 Retrying resolution for ${_unresolvedServices.length} unresolved services...');
    for (final entry in _unresolvedServices.entries) {
      final service = entry.value;
      if (_discovery != null) {
        print('🔄 Retrying: ${service.name}');
        service.resolve(_discovery!.serviceResolver);
      }
    }
  }
  
  /// Start broadcasting our presence on the network
  Future<void> startBroadcast(User user) async {
    if (_isBroadcasting) {
      print('📡 Already broadcasting');
      return;
    }
    
    _currentUser = user;
    
    try {
      // Create service to broadcast
      final service = BonsoirService(
        name: 'Stoa-${user.id.substring(0, 8)}',
        type: _serviceType,
        port: AppConstants.discoveryPort,
        attributes: {
          'id': user.id,
          'username': user.username,
          'avatarColor': user.avatarColor ?? '#6366F1',
          'publicKey': user.publicKey ?? '',
        },
      );
      
      print('📡 Creating broadcast for ${service.name} on port ${service.port}');
      
      _broadcast = BonsoirBroadcast(service: service);
      
      await _broadcast!.ready;
      print('📡 Broadcast ready');
      
      await _broadcast!.start();
      
      _isBroadcasting = true;
      print('📡 ✅ Broadcasting as ${user.username} (${service.name})');
    } catch (e, stack) {
      print('📡 ❌ Broadcast error: $e');
      print(stack);
      rethrow;
    }
  }
  
  /// Stop broadcasting our presence
  Future<void> stopBroadcast() async {
    if (!_isBroadcasting || _broadcast == null) return;
    
    try {
      await _broadcast!.stop();
    } catch (e) {
      print('📡 Stop broadcast error: $e');
    }
    _broadcast = null;
    _isBroadcasting = false;
    
    print('📡 Stopped broadcasting');
  }
  
  /// Start discovering peers on the network
  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      print('🔍 Already discovering');
      return;
    }
    
    try {
      print('🔍 Creating discovery for $_serviceType');
      _discovery = BonsoirDiscovery(type: _serviceType);
      
      await _discovery!.ready;
      print('🔍 Discovery ready');
      
      // Cancel any existing subscription
      _discoverySubscription?.cancel();
      
      // Listen for discovery events
      _discoverySubscription = _discovery!.eventStream!.listen(
        (event) {
          print('🔍 Event: ${event.type} - ${event.service?.name ?? "no service"}');
          
          switch (event.type) {
            case BonsoirDiscoveryEventType.discoveryServiceFound:
              // When a service is found, try to handle it even if not resolved yet
              // Some platforms like Android may have attributes already
              if (event.service != null) {
                _handleServiceFound(event.service!);
              }
              break;
            case BonsoirDiscoveryEventType.discoveryServiceResolved:
              _handleServiceResolved(event.service as ResolvedBonsoirService);
              break;
            case BonsoirDiscoveryEventType.discoveryServiceLost:
              if (event.service != null) {
                _handleServiceLost(event.service!);
              }
              break;
            case BonsoirDiscoveryEventType.discoveryStarted:
              print('🔍 Discovery started successfully');
              break;
            case BonsoirDiscoveryEventType.discoveryStopped:
              print('🔍 Discovery stopped');
              break;
            default:
              break;
          }
        },
        onError: (error) {
          print('🔍 ❌ Discovery stream error: $error');
        },
        onDone: () {
          print('🔍 Discovery stream closed');
        },
      );
      
      await _discovery!.start();
      _isDiscovering = true;
      
      // Start periodic retry for unresolved services
      _retryTimer?.cancel();
      _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_unresolvedServices.isNotEmpty) {
          retryUnresolvedPeers();
        }
      });
      
      print('🔍 ✅ Peer discovery started');
    } catch (e, stack) {
      print('🔍 ❌ Discovery error: $e');
      print(stack);
      rethrow;
    }
  }
  
  /// Stop discovering peers
  Future<void> stopDiscovery() async {
    if (!_isDiscovering || _discovery == null) return;
    
    try {
      _discoverySubscription?.cancel();
      _discoverySubscription = null;
      await _discovery!.stop();
    } catch (e) {
      print('🔍 Stop discovery error: $e');
    }
    _discovery = null;
    _isDiscovering = false;
    
    print('🔍 Stopped peer discovery');
  }
  
  /// Handle when a service is found (may not be fully resolved yet)
  void _handleServiceFound(BonsoirService service) {
    print('🔍 Service found: ${service.name}');
    print('   Type: ${service.type}');
    print('   Port: ${service.port}');
    print('   Attributes: ${service.attributes}');
    
    final attributes = service.attributes;
    
    // Check if we have the required attributes
    final peerId = attributes['id'];
    final username = attributes['username'];
    
    if (peerId == null || username == null) {
      print('🔍 Service missing required attributes, waiting for resolution...');
      return;
    }
    
    // Skip ourselves
    if (peerId == _currentUser?.id) {
      print('🔍 Skipping self');
      return;
    }
    
    // Try to get host info from resolved service
    String host = 'unknown';
    int port = AppConstants.discoveryPort;
    
    if (service is ResolvedBonsoirService) {
      host = service.host ?? 'unknown';
      port = service.port;
    } else if (service.port > 0) {
      port = service.port;
    }
    
    // Preserve existing peer state
    bool isConnected = false;
    PeerConnectionStatus connectionStatus = PeerConnectionStatus.disconnected;
    
    if (_peers.containsKey(peerId)) {
      final existing = _peers[peerId]!;
      isConnected = existing.isConnected;
      connectionStatus = existing.connectionStatus;
      
      // IMPORTANT: Don't overwrite a valid host with 'unknown'
      if (host == 'unknown' && existing.host != 'unknown') {
        host = existing.host;
        print('🔍 Preserving known host for $username: $host');
      }
      
      // If we already have a valid host, just update last seen
      if (existing.host != 'unknown' && host == existing.host) {
        final updatedPeer = existing.copyWith(lastSeen: DateTime.now());
        _peers[peerId] = updatedPeer;
        return; // No need to do anything else
      }
    }

    // Create peer with available info
    final peer = Peer(
      id: peerId,
      username: username,
      host: host,
      port: port,
      avatarColor: attributes['avatarColor'],
      publicKey: attributes['publicKey'],
      lastSeen: DateTime.now(),
      isConnected: isConnected,
      connectionStatus: connectionStatus,
    );
    
    _peers[peer.id] = peer;
    _notifyPeersChanged();
    
    // If not resolved (unknown host), track for retry and force resolution now
    if (host == 'unknown' && _discovery != null) {
      print('🔍 Attempting to resolve ${service.name}...');
      _unresolvedServices[peerId] = service;
      service.resolve(_discovery!.serviceResolver);
    }

    print('✅ Added peer: ${peer.username} (host: $host, port: $port)');
  }
  
  /// Handle when a service is resolved (we have full details)
  void _handleServiceResolved(ResolvedBonsoirService service) {
    print('🔍 Resolving service: ${service.name}');
    print('   Host: ${service.host}');
    print('   Port: ${service.port}');
    print('   Attributes: ${service.attributes}');
    
    final attributes = service.attributes;
    final peerId = attributes['id'];
    
    // Skip ourselves
    if (peerId == _currentUser?.id) {
      print('🔍 Skipping self');
      return;
    }
    
    // Get the IP address
    String? host = service.host;
    if (host == null || host.isEmpty) {
      print('⚠️ Service ${service.name} has no host');
      return;
    }
    
    // Remove zone ID if present (link-local IPv6)
    if (host.contains('%')) {
      host = host.split('%').first;
    }
    
    // Skip IPv6 link-local addresses (fe80::) - prefer IPv4
    if (host.startsWith('fe80:') || host.startsWith('Fe80:')) {
      print('⚠️ Skipping link-local IPv6 address: $host');
      return;
    }
    
    // If it's an IPv6 address and we already have an IPv4 for this peer, keep IPv4
    if (host.contains(':') && _peers.containsKey(peerId)) {
      final existing = _peers[peerId]!;
      if (existing.host != 'unknown' && !existing.host.contains(':')) {
        print('🔍 Keeping existing IPv4 address for peer: ${existing.host}');
        host = existing.host;
      }
    }
    
    // Preserve local state (connection status) if peer already exists
    bool isConnected = false;
    PeerConnectionStatus connectionStatus = PeerConnectionStatus.disconnected;
    
    if (_peers.containsKey(peerId)) {
      final existing = _peers[peerId]!;
      isConnected = existing.isConnected;
      connectionStatus = existing.connectionStatus;
    }

    final peer = Peer.fromServiceAttributes(
      host: host,
      port: service.port,
      attributes: attributes,
    ).copyWith(
      isConnected: isConnected,
      connectionStatus: connectionStatus,
    );
    
    _peers[peer.id] = peer;
    _notifyPeersChanged();
    
    // Remove from unresolved tracking since we now have a valid host
    _unresolvedServices.remove(peerId);
    
    print('✅ Resolved peer: ${peer.username} at $host:${service.port}');
    
    // Emit resolved peer event for auto-connect handling
    if (!isConnected && connectionStatus != PeerConnectionStatus.connecting) {
      _peerResolvedController.add(peer);
    }
  }
  
  /// Handle when a service is lost
  void _handleServiceLost(BonsoirService service) {
    final peerId = service.attributes['id'];
    
    if (peerId != null && _peers.containsKey(peerId)) {
      final peer = _peers[peerId]!;
      
      // Don't remove peers that are actively connected
      if (peer.isConnected || peer.connectionStatus == PeerConnectionStatus.connected) {
        print('🔍 Keeping connected peer: ${peer.username} (mDNS lost but still connected)');
        return;
      }
      
      _peers.remove(peerId);
      _notifyPeersChanged();
      print('❌ Lost peer: ${peer.username}');
    }
  }
  
  /// Notify listeners that peers have changed
  void _notifyPeersChanged() {
    _peersController.add(peers);
    print('📋 Total peers: ${peers.length}');
  }
  
  /// Manually add a peer (e.g. when connected via socket but not found via mDNS)
  void addConnectedPeer(Peer peer) {
    // If we already know this peer, ensure we update the connection status and host info
    if (_peers.containsKey(peer.id)) {
      final existing = _peers[peer.id]!;
      
      // Update if:
      // 1. Connection status changed (we are now connected)
      // 2. Host info improved (unknown -> valid IP)
      // 3. Other details changed
      if (!existing.isConnected || (existing.host == 'unknown' && peer.host != 'unknown')) {
         _peers[peer.id] = existing.copyWith(
           isConnected: true, // We are adding a *connected* peer
           connectionStatus: PeerConnectionStatus.connected,
           host: peer.host != 'unknown' ? peer.host : existing.host,
           port: peer.port > 0 ? peer.port : existing.port,
         );
         _notifyPeersChanged();
      }
      return;
    }
    
    print('✅ Added connected peer manually: ${peer.username}');
    _peers[peer.id] = peer;
    _notifyPeersChanged();
  }

  /// Update just the connection status of a peer
  void updatePeerStatus(String peerId, bool isConnected) {
    if (_peers.containsKey(peerId)) {
      final existing = _peers[peerId]!;
      // Only update if changed
      if (existing.isConnected != isConnected) {
        _peers[peerId] = existing.copyWith(
          isConnected: isConnected,
          connectionStatus: isConnected ? PeerConnectionStatus.connected : PeerConnectionStatus.disconnected,
        );
        _notifyPeersChanged();
      }
    }
  }
  
  /// Cleanup resources
  Future<void> dispose() async {
    await stopBroadcast();
    await stopDiscovery();
    await _peersController.close();
  }
}

/// Provider for the DiscoveryService
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the current list of peers
final peersProvider = StreamProvider<List<Peer>>((ref) {
  final discovery = ref.watch(discoveryServiceProvider);
  return discovery.peersStream;
});

/// Provider for discovery state
final discoveryStateProvider = StateNotifierProvider<DiscoveryStateNotifier, DiscoveryState>((ref) {
  return DiscoveryStateNotifier(ref);
});

/// State for discovery
class DiscoveryState {
  final bool isBroadcasting;
  final bool isDiscovering;
  final List<Peer> peers;
  final String? error;
  
  const DiscoveryState({
    this.isBroadcasting = false,
    this.isDiscovering = false,
    this.peers = const [],
    this.error,
  });
  
  DiscoveryState copyWith({
    bool? isBroadcasting,
    bool? isDiscovering,
    List<Peer>? peers,
    String? error,
  }) {
    return DiscoveryState(
      isBroadcasting: isBroadcasting ?? this.isBroadcasting,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      peers: peers ?? this.peers,
      error: error,
    );
  }
}

/// State notifier for managing discovery
class DiscoveryStateNotifier extends StateNotifier<DiscoveryState> {
  final Ref _ref;
  StreamSubscription<List<Peer>>? _peersSubscription;
  StreamSubscription? _connectionSubscription;
  
  DiscoveryStateNotifier(this._ref) : super(const DiscoveryState());
  
  /// Start both broadcasting and discovery
  Future<void> start() async {
    try {
      final storage = _ref.read(storageServiceProvider);
      final user = await storage.loadUser();
      
      if (user == null) {
        state = state.copyWith(error: 'No user found. Please set your name first.');
        return;
      }
      
      print('🚀 Starting discovery for user: ${user.username} (${user.id})');
      
      final discovery = _ref.read(discoveryServiceProvider);
      
      // Subscribe to peer updates
      _peersSubscription?.cancel();
      _peersSubscription = discovery.peersStream.listen((peers) {
        state = state.copyWith(peers: peers);
      });
      
      // Subscribe to connection updates to sync status
      final connectionService = _ref.read(connectionServiceProvider);
      _connectionSubscription?.cancel();
      _connectionSubscription = connectionService.messageStream.listen((message) {
        if (message.type == ConnectionMessageType.connected) {
          discovery.updatePeerStatus(message.peerId, true);
        } else if (message.type == ConnectionMessageType.disconnected) {
          discovery.updatePeerStatus(message.peerId, false);
        }
      });
      
      // Start broadcasting and discovery
      await discovery.startBroadcast(user);
      await discovery.startDiscovery();
      
      state = state.copyWith(
        isBroadcasting: true,
        isDiscovering: true,
        error: null,
      );
      
      print('🚀 ✅ Discovery fully started');
    } catch (e, stack) {
      state = state.copyWith(error: 'Failed to start discovery: $e');
      print('❌ Discovery error: $e');
      print(stack);
    }
  }
  
  /// Stop both broadcasting and discovery
  Future<void> stop() async {
    final discovery = _ref.read(discoveryServiceProvider);
    
    await discovery.stopBroadcast();
    await discovery.stopDiscovery();
    
    _peersSubscription?.cancel();
    _peersSubscription = null;
    
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    state = state.copyWith(
      isBroadcasting: false,
      isDiscovering: false,
    );
  }
  
  @override
  void dispose() {
    _peersSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }
}
