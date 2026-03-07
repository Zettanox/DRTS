import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// Represents a Stoa user identity
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String username,
    required DateTime createdAt,
    String? publicKey,
    String? avatarColor,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  /// Create a new user with a generated ID
  factory User.create({required String username}) {
    final colors = [
      '#6366F1',
      '#8B5CF6',
      '#06B6D4',
      '#10B981',
      '#F59E0B',
      '#EF4444',
      '#EC4899',
      '#3B82F6',
    ];

    return User(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      username: username,
      createdAt: DateTime.now(),
      avatarColor: colors[username.hashCode % colors.length],
    );
  }
}
