import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/peer.dart';
import '../models/user.dart';
import '../utils/constants.dart';
import 'encryption_service.dart';
import 'storage_service.dart';
import 'discovery_service.dart';
import '../data/database.dart';

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
  final _uuid = const Uuid();
  
  ConnectionService(this._ref, this._encryptionService);
  
  /// Check if we have an active connection to a peer
  bool isConnectedTo(String peerId) => _connections.containsKey(peerId);
  
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
  
  // Buffer for incoming data
  final Map<Socket, List<int>> _buffers = {};

  /// Handle incoming data with length-prefix framing
  void _handleData(Socket socket, Uint8List data) async {
    try {
      // Get or create buffer for this socket
      final buffer = _buffers.putIfAbsent(socket, () => []);
      buffer.addAll(data);
      
      // Process all complete messages in the buffer
      while (true) {
        // We need at least 4 bytes for the length prefix
        if (buffer.length < 4) break;
        
        // Read length prefix (big endian)
        final lengthBytes = Uint8List.fromList(buffer.take(4).toList());
        final length = ByteData.sublistView(lengthBytes).getUint32(0);
        
        // Check if we have the full message
        if (buffer.length < 4 + length) break;
        
        // Extract message payload
        final payload = Uint8List.fromList(buffer.sublist(4, 4 + length));
        
        // Remove processed bytes from buffer
        buffer.removeRange(0, 4 + length);
        
        // Check message type: 0x02 = binary file chunk, otherwise JSON
        if (payload.isNotEmpty && payload[0] == 0x02) {
          await _processBinaryFileChunk(socket, payload);
        } else {
          // Process JSON message
          final message = utf8.decode(payload);
          final json = jsonDecode(message);
          
          if (json['type'] == 'handshake') {
            await _processHandshake(socket, json);
          } else if (json['type'] == 'encrypted') {
            await _processEncryptedMessage(socket, json);
          }
        }
      }
    } catch (e) {
      print('❌ Error handling data: $e');
    }
  }
  
  /// Process binary file chunk (Turbo Mode)
  Future<void> _processBinaryFileChunk(Socket socket, Uint8List payload) async {
    // Frame format: [1-byte type=0x02][1-byte isLast][36-byte fileId][encrypted data]
    final isLast = payload[1] == 1;
    final fileId = utf8.decode(payload.sublist(2, 38)).trim();
    final encryptedData = payload.sublist(38);
    
    // Find sender by socket
    String? senderId;
    for (final entry in _connections.entries) {
      if (entry.value == socket) {
        senderId = entry.key;
        break;
      }
    }
    
    if (senderId == null) return;
    
    final secretKey = _sessionKeys[senderId];
    if (secretKey == null) return;
    
    try {
      // Decrypt raw bytes
      final decryptedBytes = await _encryptionService.decryptBytes(encryptedData, secretKey);
      
      // Emit as file chunk message for FileTransferService
      _messageController.add(ConnectionMessage(
        peerId: senderId,
        type: ConnectionMessageType.data,
        payload: {
          'type': 'file_chunk_binary',
          'fileId': fileId,
          'data': Uint8List.fromList(decryptedBytes),
          'isLast': isLast,
        },
      ));
    } catch (e) {
      print('❌ Failed to decrypt binary chunk: $e');
    }
  }
  
  /// Process handshake from peer
  Future<void> _processHandshake(Socket socket, Map<String, dynamic> json) async {
    final peerId = json['id'];
    final peerUsername = json['username'];
    final peerPublicKey = base64Decode(json['publicKey']);
    
    print('🤝 Handshake received from $peerUsername ($peerId)');
    
    // 2. If we are the server (incoming socket), we need approval first
    if (_incomingSockets.contains(socket)) {
      // Check if we already have a session (reconnection) or if it's new
      // For now, always require approval for simplicity, or check DB if trusted?
      // User asked for "connection establishment process to be two directional", implying interactive.
      // So we emit a request.
      
      print('🤝 Handshake request from $peerUsername. Waiting for approval...');
      
      // Store pending info
      _pendingRequests[peerId] = {
        'socket': socket,
        'username': peerUsername,
        'publicKey': peerPublicKey,
        'id': peerId,
      };
      
      // Notify app to show dialog
      _messageController.add(ConnectionMessage(
        peerId: peerId,
        type: ConnectionMessageType.connectionRequest,
        payload: {'username': peerUsername},
      ));
      
      return; // Stop here. Do not auto-reply.
    }
    
    // If we are here, it means WE initiated the connection and they replied (Accept),
    // OR we just accepted their request and this logic is running (wait, no).
    // If we accepted, we called _sendHandshake manually.
    // The peer sending a handshake means we are establishing the session logic.
    
    // ... Proceed to Derive Secret ...
    _finalizeConnection(socket, peerId, peerUsername, peerPublicKey);
  }
  
  // Pending requests: Map<PeerId, Data>
  final Map<String, Map<String, dynamic>> _pendingRequests = {};
  
  Future<void> acceptConnection(String peerId) async {
    final data = _pendingRequests[peerId];
    if (data == null) {
      print('⚠️ No pending request for $peerId');
      return;
    }
    
    final socket = data['socket'] as Socket;
    final username = data['username'] as String;
    final publicKey = data['publicKey'] as List<int>;
    
    print('✅ Accepting connection from $username...');
    
    // Reply with our handshake
    await _sendHandshake(socket);
    
    // Finalize
    await _finalizeConnection(socket, peerId, username, publicKey);
    
    // Cleanup
    _pendingRequests.remove(peerId);
     // Remove from incoming set since it's now a full connection?
    // actually _incomingSockets just tracks source. 
  }
  
  Future<void> denyConnection(String peerId) async {
    final data = _pendingRequests[peerId];
    if (data == null) return;
    
    final socket = data['socket'] as Socket;
    print('⛔ Denying connection from ${data['username']}');
    
    socket.destroy();
    _pendingRequests.remove(peerId);
  }

  Future<void> _finalizeConnection(Socket socket, String peerId, String peerUsername, List<int> peerPublicKey) async {
    print('🔐 Finalizing connection with $peerUsername...');
    
    // Derive shared secret
    final sharedSecret = await _encryptionService.deriveSharedSecret(
      ownKeyPair: _keyPair!,
      peerPublicKeyBytes: peerPublicKey,
    );
    
    _sessionKeys[peerId] = sharedSecret;
    _connections[peerId] = socket;
    
    // Remove from incoming tracking to avoid treating future re-handshakes as requests (if that happens)
    // _incomingSockets.remove(socket); 
    
    // Notify app that we are connected
    _messageController.add(ConnectionMessage(
      peerId: peerId,
      type: ConnectionMessageType.connected,
      payload: null,
    ));
    
    // Ensure the peer is known to the discovery service so it appears in the UI
    // This handles cases where mDNS failed but connection succeeded
    final discoveryService = _ref.read(discoveryServiceProvider);
    
    final peer = Peer(
      id: peerId,
      username: peerUsername,
      host: socket.remoteAddress.address, 
      port: AppConstants.discoveryPort, 
      avatarColor: null, 
      publicKey: base64Encode(peerPublicKey),
      isConnected: true,
      lastSeen: DateTime.now(),
    );
    
    discoveryService.addConnectedPeer(peer);
    
    // Persist peer to database
    try {
      final db = _ref.read(databaseProvider);
      await db.insertPeer(LocalPeer(
        id: peerId,
        username: peerUsername,
        publicKey: base64Encode(peerPublicKey),
        lastSeen: DateTime.now(),
        avatarColor: null,
      ));
    } catch (e) {
      print('⚠️ Failed to persist peer: $e');
    }
    
    print('✅ Secure connection finalized with $peerUsername');
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
      
      // Persist text messages
      if (payload['type'] == 'text') {
        final db = _ref.read(databaseProvider);
        await db.insertMessage(MessagesCompanion.insert(
          peerId: senderId,
          isMe: false,
          content: payload['content'],
          type: 'text',
          status: 'received',
          timestamp: DateTime.parse(payload['timestamp']),
        ));
      }
      
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
    // Length-prefix framing: [4 bytes length][payload]
    final bytes = utf8.encode(string);
    final length = bytes.length;
    
    final header = ByteData(4)..setUint32(0, length);
    
    socket.add(header.buffer.asUint8List());
    socket.add(bytes);
  }
  
  /// Send raw binary file chunk - Turbo Mode (no Base64, no JSON wrapping for data)
  /// Frame format: [4 bytes total len][1 byte type=0x02][36 bytes fileId][encrypted bytes]
  Future<void> sendRawFileChunk(String peerId, String fileId, Uint8List rawBytes, {bool isLast = false}) async {
    final socket = _connections[peerId];
    final secretKey = _sessionKeys[peerId];
    
    if (socket == null || secretKey == null) {
      throw Exception('Not connected to peer $peerId');
    }
    
    // Encrypt raw bytes directly
    final encryptedBytes = await _encryptionService.encryptBytes(rawBytes, secretKey);
    
    // Frame: [4-byte length][1-byte type][1-byte isLast][36-byte fileId][encrypted data]
    final fileIdBytes = utf8.encode(fileId.padRight(36).substring(0, 36)); // Ensure 36 bytes
    final totalLength = 1 + 1 + 36 + encryptedBytes.length;
    
    final header = ByteData(4)..setUint32(0, totalLength);
    
    socket.add(header.buffer.asUint8List());
    socket.add([0x02]); // Type marker for binary file chunk
    socket.add([isLast ? 1 : 0]); // isLast flag
    socket.add(fileIdBytes);
    socket.add(encryptedBytes);
  }

  Future<void> sendMap(Peer peer, Map<String, dynamic> data) async {
    await send(peer.id, data);
  }

  Future<void> sendText(Peer peer, String text) async {
    await sendMap(peer, {
      'type': 'text',
      'id': _uuid.v4(),
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
    });
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
  connectionRequest
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
