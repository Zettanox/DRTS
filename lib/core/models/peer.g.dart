// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'peer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PeerImpl _$$PeerImplFromJson(Map<String, dynamic> json) => _$PeerImpl(
  id: json['id'] as String,
  username: json['username'] as String,
  host: json['host'] as String,
  port: (json['port'] as num).toInt(),
  publicKey: json['publicKey'] as String?,
  avatarColor: json['avatarColor'] as String?,
  isConnected: json['isConnected'] as bool? ?? false,
  lastSeen: json['lastSeen'] == null
      ? null
      : DateTime.parse(json['lastSeen'] as String),
);

Map<String, dynamic> _$$PeerImplToJson(_$PeerImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'host': instance.host,
      'port': instance.port,
      'publicKey': instance.publicKey,
      'avatarColor': instance.avatarColor,
      'isConnected': instance.isConnected,
      'lastSeen': instance.lastSeen?.toIso8601String(),
    };
