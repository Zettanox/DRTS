import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../models/user.dart';
import '../utils/constants.dart';
import 'encryption_service.dart';
import 'encryption_service.dart';
import 'storage_service.dart';
import 'discovery_service.dart';

/// Manages TCP connections to peers
class ConnectionService {
  ServerSocket? _serverSocket;
  final Map<String, Socket> _connections = {};
  final Set<Socket> _incomingSockets = {}; // Track sockets that initiated connection to us
  final Map<String, SecretKey> _sessionKeys = {};
  
  final EncryptionService _encryptionService;
  final Ref _ref;
  
  // Stream for incoming messages
  final _messageController = StreamController<ConnectionMessage>.broadcast();
  Stream<ConnectionMessage> get messageStream => _messageController.stream;
  
  // Ephemeral key pair for this session
  SimpleKeyPair? _keyPair;
  
  ConnectionService(this._ref, this._encryptionService);
  
  /// Initialize server and keys
  Future<void> initialize() async {
    _keyPair = await _encryptionService.generateKeyPair();
    await _startServer();
  }
  
  /// Start TCP server to listen for incoming connections
  Future<void> _startServer() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, AppConstants.transferPort);
      _serverSocket!.listen(_handleIncomingConnection);
      print('🚀 Connection service listening on port ${AppConstants.transferPort}');
    } catch (e) {
      print('❌ Failed to start connection server: $e');
    }
  }
  
  /// Handle incoming TCP connection
  void _handleIncomingConnection(Socket socket) {
    print('🔌 New incoming connection from ${socket.remoteAddress.address}');
    _incomingSockets.add(socket);
    
    // We don't know who this is yet, wait for handshake
    socket.listen(
      (data) => _handleData(socket, data),
      onError: (e) => _handleError(socket, e),
      onDone: () => _handleDone(socket),
    );
  }
  
  /// Connect to a peer
  Future<void> connectTo(Peer peer) async {
    if (_connections.containsKey(peer.id)) {
      print('🔌 Already connected to ${peer.username}');
      return;
    }
    
    try {
      print('🔌 Connecting to ${peer.host}:${AppConstants.transferPort}...');
      final socket = await Socket.connect(peer.host, AppConstants.transferPort, timeout: AppConstants.peerTimeout);
      
      // Store temporary connection until handshake completes
      
      // Initiate handshake
      print('🤝 Sending handshake to ${peer.username}...');
      await _sendHandshake(socket);
      
      // Set a timeout for the handshake response
      // If we don't get a valid handshake back within 10 seconds, close the socket
      Timer(const Duration(seconds: 10), () {
        if (!_connections.containsKey(peer.id)) {
          print('⏰ Handshake timed out for ${peer.username}');
          socket.destroy();
        }
      });
      
      socket.listen(
        (data) => _handleData(socket, data),
        onError: (e) => _handleError(socket, e),
        onDone: () => _handleDone(socket),
      );
      
    } catch (e) {
      print('❌ Failed to connect to ${peer.username}: $e');
      rethrow;
    }
  }
  
  /// Send handshake with our identity and public key
  Future<void> _sendHandshake(Socket socket) async {
    final user = await _ref.read(storageServiceProvider).loadUser();
    if (user == null || _keyPair == null) return;
    
    final publicKey = await _encryptionService.getPublicKeyBytes(_keyPair!);
    
    final handshake = {
      'type': 'handshake',
      'id': user.id,
      'username': user.username,
      'publicKey': base64Encode(publicKey),
    };
    
    _sendRaw(socket, jsonEncode(handshake));
  }
  
  /// Handle incoming data
  void _handleData(Socket socket, Uint8List data) async {
    try {
      // In a real implementation, we'd need a framing protocol (length-prefix)
      // For now we assume messages arrive in complete chunks (which is fragile but okay for PoC)
      final message = utf8.decode(data);
      final json = jsonDecode(message);
      
      if (json['type'] == 'handshake') {
        await _processHandshake(socket, json);
      } else if (json['type'] == 'encrypted') {
        await _processEncryptedMessage(socket, json);
      }
    } catch (e) {
      print('❌ Error handling data: $e');
    }
  }
  
  /// Process handshake from peer
  Future<void> _processHandshake(Socket socket, Map<String, dynamic> json) async {
    final peerId = json['id'];
    final peerUsername = json['username'];
    final peerPublicKey = base64Decode(json['publicKey']);
    
    print('🤝 Handshake received from $peerUsername ($peerId)');
    
    // 1. Derive shared secret
    final sharedSecret = await _encryptionService.deriveSharedSecret(
      ownKeyPair: _keyPair!,
      peerPublicKeyBytes: peerPublicKey,
    );
    
    _sessionKeys[peerId] = sharedSecret;
    _connections[peerId] = socket;
    
    // 2. If we are the server (incoming socket), reply with our handshake
    if (_incomingSockets.contains(socket)) {
      print('🤝 Replying to handshake from $peerUsername...');
      await _sendHandshake(socket);
      // We've verified distinctness, remove from incoming tracking so we don't reply again loops
      // Actually we don't need to remove it, just checking contains is enough
      // But clearing it is cleaner
      _incomingSockets.remove(socket);
    }
    
    // Notify app that we are connected
    _messageController.add(ConnectionMessage(
      peerId: peerId,
      type: ConnectionMessageType.connected,
      payload: null,
    ));
    
    // Ensure the peer is known to the discovery service so it appears in the UI
    // This handles cases where mDNS failed but connection succeeded
    final discoveryService = _ref.read(discoveryServiceProvider);
    
    // Construct peer object from available info
    // We might not have the host/port if this was an incoming connection
    // But we can infer or use defaults, the main thing is having the ID and Username
    final peer = Peer(
      id: peerId,
      username: peerUsername,
      host: socket.remoteAddress.address, // We know the IP connect via socket
      port: AppConstants.discoveryPort, // Assume default port
      // We don't have avatarColor in handshake yet, use default or random
      avatarColor: null, 
      publicKey: base64Encode(peerPublicKey),
      isConnected: true,
      lastSeen: DateTime.now(),
    );
    
    discoveryService.addConnectedPeer(peer);
    
    print('✅ Secure connection established with $peerUsername');
  }
  
  /// Process encrypted message
  Future<void> _processEncryptedMessage(Socket socket, Map<String, dynamic> json) async {
    final senderId = json['senderId'];
    final encryptedPayload = json['payload'];
    
    final secretKey = _sessionKeys[senderId];
    if (secretKey == null) {
      print('⚠️ Received encrypted message from unknown/unauthenticated peer $senderId');
      return;
    }
    
    try {
      final decryptedBytes = await _encryptionService.decrypt(encryptedPayload, secretKey);
      final decryptedString = utf8.decode(decryptedBytes);
      final payload = jsonDecode(decryptedString);
      
      _messageController.add(ConnectionMessage(
        peerId: senderId,
        type: ConnectionMessageType.data,
        payload: payload,
      ));
    } catch (e) {
      print('❌ Failed to decrypt message: $e');
    }
  }
  
  /// Send encrypted data to a peer
  Future<void> send(String peerId, dynamic payload) async {
    final socket = _connections[peerId];
    final secretKey = _sessionKeys[peerId];
    final user = await _ref.read(storageServiceProvider).loadUser();
    
    if (socket == null || secretKey == null || user == null) {
      throw Exception('Not connected to peer $peerId');
    }
    
    final encrypted = await _encryptionService.encrypt(payload, secretKey);
    
    final message = {
      'type': 'encrypted',
      'senderId': user.id,
      'payload': encrypted,
    };
    
    _sendRaw(socket, jsonEncode(message));
  }
  
  void _sendRaw(Socket socket, String string) {
    socket.write(string);
  }
  
  void _handleError(Socket socket, dynamic error) {
    print('❌ Socket error: $error');
    _cleanupSocket(socket);
  }
  
  void _handleDone(Socket socket) {
    print('🔌 Socket closed');
    _cleanupSocket(socket);
  }
  
  void _cleanupSocket(Socket socket) {
    String? peerIdToRemove;
    _connections.forEach((id, s) {
      if (s == socket) peerIdToRemove = id;
    });
    
    if (peerIdToRemove != null) {
      _connections.remove(peerIdToRemove);
      _sessionKeys.remove(peerIdToRemove);
      
      // Notify app
      _messageController.add(ConnectionMessage(
        peerId: peerIdToRemove!,
        type: ConnectionMessageType.disconnected,
        payload: null,
      ));
      
      // Update discovery service to reflect disconnection
      try {
        final discoveryService = _ref.read(discoveryServiceProvider);
        // We can't easily get the full peer object here without looking it up, 
        // but addConnectedPeer will handle updates if we pass what we know.
        // Actually, better to just expose a 'setDisconnected' method or similar.
        // For now, we'll just check if it exists in discovery and update it manually
        // But since we can't access _peers directly, we need a method.
        // Let's rely on the fact that next discovery update will overwrite it,
        // OR we should ideally add a 'disconnectPeer(id)' to DiscoveryService.
        // For quick fix:
        discoveryService.updatePeerStatus(peerIdToRemove!, false);
      } catch (e) {
        print('⚠️ Failed to update discovery service on disconnect: $e');
      }
    }
    
    socket.destroy();
  }
  
  void dispose() {
    _serverSocket?.close();
    for (var socket in _connections.values) {
      socket.destroy();
    }
  }
}

enum ConnectionMessageType {
  connected,
  disconnected,
  data,
}

class ConnectionMessage {
  final String peerId;
  final ConnectionMessageType type;
  final dynamic payload;
  
  ConnectionMessage({required this.peerId, required this.type, this.payload});
}

final connectionServiceProvider = Provider<ConnectionService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return ConnectionService(ref, encryption);
});
