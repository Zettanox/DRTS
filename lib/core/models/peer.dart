import 'package:freezed_annotation/freezed_annotation.dart';

part 'peer.freezed.dart';
part 'peer.g.dart';

/// Represents a discovered peer on the network
@freezed
class Peer with _$Peer {
  const factory Peer({
    required String id,
    required String username,
    required String host,
    required int port,
    String? publicKey,
    String? avatarColor,
    @Default(false) bool isConnected,
    @Default(false) bool isVerified,
    @Default(PeerConnectionStatus.disconnected) PeerConnectionStatus connectionStatus,
    DateTime? lastSeen,
  }) = _Peer;
  
  factory Peer.fromJson(Map<String, dynamic> json) => _$PeerFromJson(json);
  
  /// Create from Bonsoir service attributes
  factory Peer.fromServiceAttributes({
    required String host,
    required int port,
    required Map<String, String> attributes,
  }) {
    return Peer(
      id: attributes['id'] ?? host,
      username: attributes['username'] ?? 'Unknown',
      host: host,
      port: port,
      publicKey: attributes['publicKey'],
      avatarColor: attributes['avatarColor'],
      lastSeen: DateTime.now(),
    );
  }
}

enum PeerConnectionStatus {
  disconnected,
  connecting,
  connected,
  failed,
}

/// Connection state for a peer
enum PeerConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}
