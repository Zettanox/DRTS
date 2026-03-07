import 'package:stoa/core/utils/logger.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../data/database.dart';
import '../models/peer.dart';
import 'connection_service.dart';
import 'discovery_service.dart';
import 'file_transfer_service.dart';

/// Group message types for the protocol
enum GroupMessageType {
  invite, // Invite a peer to join group
  inviteResponse, // Accept/reject invitation
  memberAdded, // Notify members of new member
  memberRemoved, // Notify members of removed member
  message, // Regular group message
  fileOffer, // File being sent to group
  deleted, // Group was deleted
  syncRequest, // Request group state (for offline sync)
  syncResponse, // Respond with group state
}

/// Represents a pending group invitation
class GroupInvitation {
  final String groupId;
  final String groupName;
  final String ownerId;
  final String ownerName;
  final DateTime receivedAt;

  GroupInvitation({
    required this.groupId,
    required this.groupName,
    required this.ownerId,
    required this.ownerName,
    required this.receivedAt,
  });
}

class GroupService {
  final Ref _ref;
  final _uuid = const Uuid();

  // Pending invitations received
  final Map<String, GroupInvitation> _pendingInvitations = {};
  final _invitationController = StreamController<GroupInvitation>.broadcast();

  GroupService(this._ref) {
    _listenToConnectionService();
  }

  AppDatabase get _db => _ref.read(databaseProvider);
  ConnectionService get _connectionService =>
      _ref.read(connectionServiceProvider);
  DiscoveryService get _discoveryService => _ref.read(discoveryServiceProvider);

  Stream<GroupInvitation> get invitationStream => _invitationController.stream;

  /// Get my peer ID and username from discovery service
  String get _myPeerId => _discoveryService.myPeerId;
  String get _myUsername => _discoveryService.myUsername;

  /// Send to a connected peer by ID
  Future<void> _sendToPeer(String peerId, Map<String, dynamic> payload) async {
    if (_connectionService.isConnectedTo(peerId)) {
      await _connectionService.send(peerId, payload);
    }
  }

  /// Listen for group-related messages from ConnectionService
  void _listenToConnectionService() {
    _connectionService.messageStream.listen((message) {
      if (message.type == ConnectionMessageType.data &&
          message.payload != null) {
        final payload = message.payload;
        if (payload['groupType'] != null) {
          _handleGroupMessage(message.peerId, payload);
        }
      }
    });
  }

  /// Handle incoming group protocol messages
  void _handleGroupMessage(String senderId, Map<String, dynamic> payload) {
    final type = payload['groupType'] as String;

    switch (type) {
      case 'invite':
        _handleInvite(senderId, payload);
        break;
      case 'inviteResponse':
        _handleInviteResponse(senderId, payload);
        break;
      case 'memberAdded':
        _handleMemberAdded(payload);
        break;
      case 'memberRemoved':
        _handleMemberRemoved(payload);
        break;
      case 'message':
        _handleGroupTextMessage(senderId, payload);
        break;
      case 'deleted':
        _handleGroupDeleted(payload);
        break;
    }
  }

  // ==================== GROUP CREATION ====================

  /// Create a new group and invite members
  Future<Group> createGroup(
    String name,
    List<Peer> members, {
    bool showHistoryToNew = false,
  }) async {
    final groupId = _uuid.v4();
    final now = DateTime.now();

    // Create the group in DB
    await _db.insertGroup(
      GroupsCompanion.insert(
        id: groupId,
        name: name,
        ownerId: _myPeerId,
        createdAt: now,
        showHistoryToNew: Value(showHistoryToNew),
      ),
    );

    // Add self as member (accepted)
    await _db.insertGroupMember(
      GroupMembersCompanion.insert(
        groupId: groupId,
        peerId: _myPeerId,
        username: _myUsername,
        status: 'accepted',
        joinedAt: now,
      ),
    );

    // Invite all selected peers
    for (final peer in members) {
      await inviteToGroup(groupId, peer);
    }

    appLogger.i(
      '👥 Created group: $name with ${members.length} invited members',
    );

    return (await _db.getGroup(groupId))!;
  }

  /// Invite a peer to join a group
  Future<void> inviteToGroup(String groupId, Peer peer) async {
    final group = await _db.getGroup(groupId);
    if (group == null) return;

    // Add as pending member
    await _db.insertGroupMember(
      GroupMembersCompanion.insert(
        groupId: groupId,
        peerId: peer.id,
        username: peer.username,
        status: 'pending',
        joinedAt: DateTime.now(),
      ),
    );

    // Send invite message
    await _sendToPeer(peer.id, {
      'groupType': 'invite',
      'groupId': groupId,
      'groupName': group.name,
      'ownerId': _myPeerId,
      'ownerName': _myUsername,
    });

    appLogger.i('📨 Sent group invite to ${peer.username} for ${group.name}');
  }

  // ==================== INVITATION HANDLING ====================

  void _handleInvite(String senderId, Map<String, dynamic> payload) {
    final invitation = GroupInvitation(
      groupId: payload['groupId'],
      groupName: payload['groupName'],
      ownerId: payload['ownerId'],
      ownerName: payload['ownerName'],
      receivedAt: DateTime.now(),
    );

    _pendingInvitations[invitation.groupId] = invitation;
    _invitationController.add(invitation);

    appLogger.i(
      '📬 Received group invite: ${invitation.groupName} from ${invitation.ownerName}',
    );
  }

  /// Accept a group invitation
  Future<void> acceptInvitation(String groupId) async {
    final invitation = _pendingInvitations.remove(groupId);
    if (invitation == null) return;

    final now = DateTime.now();

    // Create group locally
    await _db.insertGroup(
      GroupsCompanion.insert(
        id: groupId,
        name: invitation.groupName,
        ownerId: invitation.ownerId,
        createdAt: now,
      ),
    );

    // Add self as accepted member
    await _db.insertGroupMember(
      GroupMembersCompanion.insert(
        groupId: groupId,
        peerId: _myPeerId,
        username: _myUsername,
        status: 'accepted',
        joinedAt: now,
      ),
    );

    // Add owner as member (so we know they're in the group)
    await _db.insertGroupMember(
      GroupMembersCompanion.insert(
        groupId: groupId,
        peerId: invitation.ownerId,
        username: invitation.ownerName,
        status: 'accepted',
        joinedAt: now,
      ),
    );

    // Send acceptance to owner
    await _sendToPeer(invitation.ownerId, {
      'groupType': 'inviteResponse',
      'groupId': groupId,
      'accepted': true,
      'peerId': _myPeerId,
      'username': _myUsername,
    });

    appLogger.i('✅ Accepted group invitation: ${invitation.groupName}');
  }

  /// Reject a group invitation
  Future<void> rejectInvitation(String groupId) async {
    final invitation = _pendingInvitations.remove(groupId);
    if (invitation == null) return;

    // Send rejection to owner
    await _sendToPeer(invitation.ownerId, {
      'groupType': 'inviteResponse',
      'groupId': groupId,
      'accepted': false,
      'peerId': _myPeerId,
    });

    appLogger.i('❌ Rejected group invitation: ${invitation.groupName}');
  }

  void _handleInviteResponse(
    String senderId,
    Map<String, dynamic> payload,
  ) async {
    final groupId = payload['groupId'];
    final accepted = payload['accepted'] as bool;
    final peerId = payload['peerId'];

    if (accepted) {
      final username = payload['username'] ?? 'Unknown';

      // Update member status
      await _db.insertGroupMember(
        GroupMembersCompanion.insert(
          groupId: groupId,
          peerId: peerId,
          username: username,
          status: 'accepted',
          joinedAt: DateTime.now(),
        ),
      );

      // Notify other members about new member
      await _broadcastToGroup(groupId, {
        'groupType': 'memberAdded',
        'groupId': groupId,
        'peerId': peerId,
        'username': username,
      }, excludePeerId: peerId);

      appLogger.i('✅ $username accepted group invitation');
    } else {
      // Remove from pending members
      await _db.removeGroupMember(groupId, peerId);
      appLogger.i('❌ $peerId rejected group invitation');
    }
  }

  // ==================== MEMBER MANAGEMENT ====================

  void _handleMemberAdded(Map<String, dynamic> payload) async {
    final groupId = payload['groupId'];
    final peerId = payload['peerId'];
    final username = payload['username'];

    await _db.insertGroupMember(
      GroupMembersCompanion.insert(
        groupId: groupId,
        peerId: peerId,
        username: username,
        status: 'accepted',
        joinedAt: DateTime.now(),
      ),
    );

    appLogger.i('👤 New member added to group: $username');
  }

  void _handleMemberRemoved(Map<String, dynamic> payload) async {
    final groupId = payload['groupId'];
    final peerId = payload['peerId'];

    await _db.removeGroupMember(groupId, peerId);
    appLogger.i('👤 Member removed from group: $peerId');
  }

  /// Remove a member from a group (owner only)
  Future<void> removeMember(String groupId, String peerId) async {
    final group = await _db.getGroup(groupId);
    if (group == null || group.ownerId != _myPeerId) return;

    await _db.removeGroupMember(groupId, peerId);

    // Notify all members
    await _broadcastToGroup(groupId, {
      'groupType': 'memberRemoved',
      'groupId': groupId,
      'peerId': peerId,
    });
  }

  /// Leave a group
  Future<void> leaveGroup(String groupId) async {
    final group = await _db.getGroup(groupId);
    if (group == null) return;

    // Notify others
    await _broadcastToGroup(groupId, {
      'groupType': 'memberRemoved',
      'groupId': groupId,
      'peerId': _myPeerId,
    });

    // Remove self and local data
    await _db.deleteGroup(groupId);

    appLogger.i('👋 Left group: ${group.name}');
  }

  // ==================== MESSAGING ====================

  /// Send a message to a group
  Future<void> sendGroupMessage(String groupId, String content) async {
    final now = DateTime.now();

    // Save message locally
    await _db.insertGroupMessage(
      GroupMessagesCompanion.insert(
        groupId: groupId,
        senderId: _myPeerId,
        senderName: _myUsername,
        content: content,
        type: 'text',
        timestamp: now,
      ),
    );

    // Broadcast to all members
    await _broadcastToGroup(groupId, {
      'groupType': 'message',
      'groupId': groupId,
      'senderId': _myPeerId,
      'senderName': _myUsername,
      'content': content,
      'type': 'text',
      'timestamp': now.toIso8601String(),
    });
  }

  void _handleGroupTextMessage(
    String senderId,
    Map<String, dynamic> payload,
  ) async {
    final type = payload['type'] ?? 'text';
    final fileSize = payload['fileSizeBytes'];

    await _db.insertGroupMessage(
      GroupMessagesCompanion.insert(
        groupId: payload['groupId'],
        senderId: payload['senderId'],
        senderName: payload['senderName'],
        content: payload['content'],
        type: type,
        fileSize: fileSize != null
            ? Value(fileSize as int)
            : const Value.absent(),
        timestamp: DateTime.parse(payload['timestamp']),
      ),
    );
  }

  // ==================== GROUP DELETION ====================

  /// Delete a group (owner only)
  Future<void> deleteGroup(String groupId) async {
    final group = await _db.getGroup(groupId);
    if (group == null || group.ownerId != _myPeerId) return;

    // Notify all members
    await _broadcastToGroup(groupId, {
      'groupType': 'deleted',
      'groupId': groupId,
    });

    // Delete locally
    await _db.deleteGroup(groupId);

    appLogger.i('🗑️ Deleted group: ${group.name}');
  }

  void _handleGroupDeleted(Map<String, dynamic> payload) async {
    final groupId = payload['groupId'];
    await _db.deleteGroup(groupId);
    appLogger.i('🗑️ Group was deleted by owner');
  }

  // ==================== AUTO-CONNECT HELPER ====================

  /// Check if a peer is in any shared group (for auto-connect)
  Future<bool> isInAnySharedGroup(String peerId) async {
    return await _db.isPeerInAnyGroup(peerId);
  }

  // ==================== UTILITIES ====================

  /// Broadcast a message to all group members
  Future<void> _broadcastToGroup(
    String groupId,
    Map<String, dynamic> payload, {
    String? excludePeerId,
  }) async {
    final members = await _db.getGroupMembers(groupId);

    for (final member in members) {
      // Skip self and excluded peer
      if (member.peerId == _myPeerId) continue;
      if (excludePeerId != null && member.peerId == excludePeerId) continue;
      if (member.status != 'accepted') continue;

      if (_connectionService.isConnectedTo(member.peerId)) {
        await _sendToPeer(member.peerId, payload);
      }
    }
  }

  /// Find a peer by ID from discovery service
  Peer? _findPeerById(String peerId) {
    try {
      final discoveryService = _ref.read(discoveryServiceProvider);
      return discoveryService.peers.firstWhere((p) => p.id == peerId);
    } catch (_) {
      return null;
    }
  }

  // Watch methods for UI
  Stream<List<Group>> watchAllGroups() => _db.watchAllGroups();
  Stream<List<GroupMember>> watchGroupMembers(String groupId) =>
      _db.watchGroupMembers(groupId);
  Stream<List<GroupMessage>> watchGroupMessages(String groupId) =>
      _db.watchGroupMessages(groupId);

  // ==================== FILE SHARING ====================

  /// Send a file to the group
  Future<void> sendFile(String groupId, File file) async {
    final group = await _db.getGroup(groupId);
    if (group == null) return;

    final filename = file.uri.pathSegments.last;
    final size = await file.length();

    // 1. Insert into database
    await _db.insertGroupMessage(
      GroupMessagesCompanion.insert(
        groupId: groupId,
        senderId: _myPeerId,
        senderName: _myUsername,
        content: filename,
        type: 'file',
        timestamp: DateTime.now(),
        filePath: Value(file.path),
        fileSize: Value(size),
      ),
    );

    // 2. Broadcast file message to group members (so they see it in chat)
    final payload = {
      'groupType': 'message',
      'groupId': groupId,
      'groupName': group.name,
      'senderId': _myPeerId,
      'senderName': _myUsername,
      'content': filename,
      'type': 'file',
      'fileSizeBytes': size,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final members = await _db.getGroupMembers(groupId);
    final fts = _ref.read(fileTransferServiceProvider);

    for (final member in members) {
      if (member.peerId == _myPeerId) continue;

      // Send chat notification
      if (_connectionService.isConnectedTo(member.peerId)) {
        await _sendToPeer(member.peerId, payload);

        // 3. Initiate actual file transfer
        // Construct peer object for FTS
        final peer =
            _findPeerById(member.peerId) ??
            Peer(
              id: member.peerId,
              username: member.username,
              host:
                  'unknown', // FTS/ConnectionService handles lookup by ID usually, but FTS needs Peer object
              port: 0,
              isConnected: true,
            );

        // Queue the file transfer
        appLogger.i('📂 Queuing group file "$filename" for ${member.username}');
        fts.queueFile(peer, file, groupId: groupId);
      }
    }
  }

  Future<List<Group>> getAllGroups() => _db.getAllGroups();
}

// Provider
final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService(ref);
});
