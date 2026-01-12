// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LocalPeersTable extends LocalPeers
    with TableInfo<$LocalPeersTable, LocalPeer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPeersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarColorMeta = const VerificationMeta(
    'avatarColor',
  );
  @override
  late final GeneratedColumn<String> avatarColor = GeneratedColumn<String>(
    'avatar_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    username,
    avatarColor,
    publicKey,
    lastSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_peers';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPeer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('avatar_color')) {
      context.handle(
        _avatarColorMeta,
        avatarColor.isAcceptableOrUnknown(
          data['avatar_color']!,
          _avatarColorMeta,
        ),
      );
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPeer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPeer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      avatarColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_color'],
      ),
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      ),
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      )!,
    );
  }

  @override
  $LocalPeersTable createAlias(String alias) {
    return $LocalPeersTable(attachedDatabase, alias);
  }
}

class LocalPeer extends DataClass implements Insertable<LocalPeer> {
  final String id;
  final String username;
  final String? avatarColor;
  final String? publicKey;
  final DateTime lastSeen;
  const LocalPeer({
    required this.id,
    required this.username,
    this.avatarColor,
    this.publicKey,
    required this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['username'] = Variable<String>(username);
    if (!nullToAbsent || avatarColor != null) {
      map['avatar_color'] = Variable<String>(avatarColor);
    }
    if (!nullToAbsent || publicKey != null) {
      map['public_key'] = Variable<String>(publicKey);
    }
    map['last_seen'] = Variable<DateTime>(lastSeen);
    return map;
  }

  LocalPeersCompanion toCompanion(bool nullToAbsent) {
    return LocalPeersCompanion(
      id: Value(id),
      username: Value(username),
      avatarColor: avatarColor == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarColor),
      publicKey: publicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKey),
      lastSeen: Value(lastSeen),
    );
  }

  factory LocalPeer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPeer(
      id: serializer.fromJson<String>(json['id']),
      username: serializer.fromJson<String>(json['username']),
      avatarColor: serializer.fromJson<String?>(json['avatarColor']),
      publicKey: serializer.fromJson<String?>(json['publicKey']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'username': serializer.toJson<String>(username),
      'avatarColor': serializer.toJson<String?>(avatarColor),
      'publicKey': serializer.toJson<String?>(publicKey),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
    };
  }

  LocalPeer copyWith({
    String? id,
    String? username,
    Value<String?> avatarColor = const Value.absent(),
    Value<String?> publicKey = const Value.absent(),
    DateTime? lastSeen,
  }) => LocalPeer(
    id: id ?? this.id,
    username: username ?? this.username,
    avatarColor: avatarColor.present ? avatarColor.value : this.avatarColor,
    publicKey: publicKey.present ? publicKey.value : this.publicKey,
    lastSeen: lastSeen ?? this.lastSeen,
  );
  LocalPeer copyWithCompanion(LocalPeersCompanion data) {
    return LocalPeer(
      id: data.id.present ? data.id.value : this.id,
      username: data.username.present ? data.username.value : this.username,
      avatarColor: data.avatarColor.present
          ? data.avatarColor.value
          : this.avatarColor,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPeer(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('publicKey: $publicKey, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, username, avatarColor, publicKey, lastSeen);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPeer &&
          other.id == this.id &&
          other.username == this.username &&
          other.avatarColor == this.avatarColor &&
          other.publicKey == this.publicKey &&
          other.lastSeen == this.lastSeen);
}

class LocalPeersCompanion extends UpdateCompanion<LocalPeer> {
  final Value<String> id;
  final Value<String> username;
  final Value<String?> avatarColor;
  final Value<String?> publicKey;
  final Value<DateTime> lastSeen;
  final Value<int> rowid;
  const LocalPeersCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPeersCompanion.insert({
    required String id,
    required String username,
    this.avatarColor = const Value.absent(),
    this.publicKey = const Value.absent(),
    required DateTime lastSeen,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       username = Value(username),
       lastSeen = Value(lastSeen);
  static Insertable<LocalPeer> custom({
    Expression<String>? id,
    Expression<String>? username,
    Expression<String>? avatarColor,
    Expression<String>? publicKey,
    Expression<DateTime>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (publicKey != null) 'public_key': publicKey,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPeersCompanion copyWith({
    Value<String>? id,
    Value<String>? username,
    Value<String?>? avatarColor,
    Value<String?>? publicKey,
    Value<DateTime>? lastSeen,
    Value<int>? rowid,
  }) {
    return LocalPeersCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarColor: avatarColor ?? this.avatarColor,
      publicKey: publicKey ?? this.publicKey,
      lastSeen: lastSeen ?? this.lastSeen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (avatarColor.present) {
      map['avatar_color'] = Variable<String>(avatarColor.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPeersCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('publicKey: $publicKey, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_peers (id)',
    ),
  );
  static const VerificationMeta _isMeMeta = const VerificationMeta('isMe');
  @override
  late final GeneratedColumn<bool> isMe = GeneratedColumn<bool>(
    'is_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_me" IN (0, 1))',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    peerId,
    isMe,
    content,
    type,
    filePath,
    fileSize,
    status,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('is_me')) {
      context.handle(
        _isMeMeta,
        isMe.isAcceptableOrUnknown(data['is_me']!, _isMeMeta),
      );
    } else if (isInserting) {
      context.missing(_isMeMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      isMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_me'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final int id;
  final String peerId;
  final bool isMe;
  final String content;
  final String type;
  final String? filePath;
  final int? fileSize;
  final String status;
  final DateTime timestamp;
  const Message({
    required this.id,
    required this.peerId,
    required this.isMe,
    required this.content,
    required this.type,
    this.filePath,
    this.fileSize,
    required this.status,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['peer_id'] = Variable<String>(peerId);
    map['is_me'] = Variable<bool>(isMe);
    map['content'] = Variable<String>(content);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    map['status'] = Variable<String>(status);
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      peerId: Value(peerId),
      isMe: Value(isMe),
      content: Value(content),
      type: Value(type),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      status: Value(status),
      timestamp: Value(timestamp),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      peerId: serializer.fromJson<String>(json['peerId']),
      isMe: serializer.fromJson<bool>(json['isMe']),
      content: serializer.fromJson<String>(json['content']),
      type: serializer.fromJson<String>(json['type']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      status: serializer.fromJson<String>(json['status']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'peerId': serializer.toJson<String>(peerId),
      'isMe': serializer.toJson<bool>(isMe),
      'content': serializer.toJson<String>(content),
      'type': serializer.toJson<String>(type),
      'filePath': serializer.toJson<String?>(filePath),
      'fileSize': serializer.toJson<int?>(fileSize),
      'status': serializer.toJson<String>(status),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  Message copyWith({
    int? id,
    String? peerId,
    bool? isMe,
    String? content,
    String? type,
    Value<String?> filePath = const Value.absent(),
    Value<int?> fileSize = const Value.absent(),
    String? status,
    DateTime? timestamp,
  }) => Message(
    id: id ?? this.id,
    peerId: peerId ?? this.peerId,
    isMe: isMe ?? this.isMe,
    content: content ?? this.content,
    type: type ?? this.type,
    filePath: filePath.present ? filePath.value : this.filePath,
    fileSize: fileSize.present ? fileSize.value : this.fileSize,
    status: status ?? this.status,
    timestamp: timestamp ?? this.timestamp,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      isMe: data.isMe.present ? data.isMe.value : this.isMe,
      content: data.content.present ? data.content.value : this.content,
      type: data.type.present ? data.type.value : this.type,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      status: data.status.present ? data.status.value : this.status,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('isMe: $isMe, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('filePath: $filePath, ')
          ..write('fileSize: $fileSize, ')
          ..write('status: $status, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    peerId,
    isMe,
    content,
    type,
    filePath,
    fileSize,
    status,
    timestamp,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.peerId == this.peerId &&
          other.isMe == this.isMe &&
          other.content == this.content &&
          other.type == this.type &&
          other.filePath == this.filePath &&
          other.fileSize == this.fileSize &&
          other.status == this.status &&
          other.timestamp == this.timestamp);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<String> peerId;
  final Value<bool> isMe;
  final Value<String> content;
  final Value<String> type;
  final Value<String?> filePath;
  final Value<int?> fileSize;
  final Value<String> status;
  final Value<DateTime> timestamp;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.peerId = const Value.absent(),
    this.isMe = const Value.absent(),
    this.content = const Value.absent(),
    this.type = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.status = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required String peerId,
    required bool isMe,
    required String content,
    required String type,
    this.filePath = const Value.absent(),
    this.fileSize = const Value.absent(),
    required String status,
    required DateTime timestamp,
  }) : peerId = Value(peerId),
       isMe = Value(isMe),
       content = Value(content),
       type = Value(type),
       status = Value(status),
       timestamp = Value(timestamp);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<String>? peerId,
    Expression<bool>? isMe,
    Expression<String>? content,
    Expression<String>? type,
    Expression<String>? filePath,
    Expression<int>? fileSize,
    Expression<String>? status,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (peerId != null) 'peer_id': peerId,
      if (isMe != null) 'is_me': isMe,
      if (content != null) 'content': content,
      if (type != null) 'type': type,
      if (filePath != null) 'file_path': filePath,
      if (fileSize != null) 'file_size': fileSize,
      if (status != null) 'status': status,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? peerId,
    Value<bool>? isMe,
    Value<String>? content,
    Value<String>? type,
    Value<String?>? filePath,
    Value<int?>? fileSize,
    Value<String>? status,
    Value<DateTime>? timestamp,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      isMe: isMe ?? this.isMe,
      content: content ?? this.content,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (isMe.present) {
      map['is_me'] = Variable<bool>(isMe.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('isMe: $isMe, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('filePath: $filePath, ')
          ..write('fileSize: $fileSize, ')
          ..write('status: $status, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalPeersTable localPeers = $LocalPeersTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [localPeers, messages];
}

typedef $$LocalPeersTableCreateCompanionBuilder =
    LocalPeersCompanion Function({
      required String id,
      required String username,
      Value<String?> avatarColor,
      Value<String?> publicKey,
      required DateTime lastSeen,
      Value<int> rowid,
    });
typedef $$LocalPeersTableUpdateCompanionBuilder =
    LocalPeersCompanion Function({
      Value<String> id,
      Value<String> username,
      Value<String?> avatarColor,
      Value<String?> publicKey,
      Value<DateTime> lastSeen,
      Value<int> rowid,
    });

final class $$LocalPeersTableReferences
    extends BaseReferences<_$AppDatabase, $LocalPeersTable, LocalPeer> {
  $$LocalPeersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: $_aliasNameGenerator(db.localPeers.id, db.messages.peerId),
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.peerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalPeersTableFilterComposer
    extends Composer<_$AppDatabase, $LocalPeersTable> {
  $$LocalPeersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.peerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalPeersTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalPeersTable> {
  $$LocalPeersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPeersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalPeersTable> {
  $$LocalPeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.peerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalPeersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalPeersTable,
          LocalPeer,
          $$LocalPeersTableFilterComposer,
          $$LocalPeersTableOrderingComposer,
          $$LocalPeersTableAnnotationComposer,
          $$LocalPeersTableCreateCompanionBuilder,
          $$LocalPeersTableUpdateCompanionBuilder,
          (LocalPeer, $$LocalPeersTableReferences),
          LocalPeer,
          PrefetchHooks Function({bool messagesRefs})
        > {
  $$LocalPeersTableTableManager(_$AppDatabase db, $LocalPeersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPeersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPeersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPeersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String?> avatarColor = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<DateTime> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPeersCompanion(
                id: id,
                username: username,
                avatarColor: avatarColor,
                publicKey: publicKey,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String username,
                Value<String?> avatarColor = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                required DateTime lastSeen,
                Value<int> rowid = const Value.absent(),
              }) => LocalPeersCompanion.insert(
                id: id,
                username: username,
                avatarColor: avatarColor,
                publicKey: publicKey,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalPeersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (messagesRefs) db.messages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedData<
                      LocalPeer,
                      $LocalPeersTable,
                      Message
                    >(
                      currentTable: table,
                      referencedTable: $$LocalPeersTableReferences
                          ._messagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LocalPeersTableReferences(
                            db,
                            table,
                            p0,
                          ).messagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.peerId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LocalPeersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalPeersTable,
      LocalPeer,
      $$LocalPeersTableFilterComposer,
      $$LocalPeersTableOrderingComposer,
      $$LocalPeersTableAnnotationComposer,
      $$LocalPeersTableCreateCompanionBuilder,
      $$LocalPeersTableUpdateCompanionBuilder,
      (LocalPeer, $$LocalPeersTableReferences),
      LocalPeer,
      PrefetchHooks Function({bool messagesRefs})
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> id,
      required String peerId,
      required bool isMe,
      required String content,
      required String type,
      Value<String?> filePath,
      Value<int?> fileSize,
      required String status,
      required DateTime timestamp,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> id,
      Value<String> peerId,
      Value<bool> isMe,
      Value<String> content,
      Value<String> type,
      Value<String?> filePath,
      Value<int?> fileSize,
      Value<String> status,
      Value<DateTime> timestamp,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LocalPeersTable _peerIdTable(_$AppDatabase db) => db.localPeers
      .createAlias($_aliasNameGenerator(db.messages.peerId, db.localPeers.id));

  $$LocalPeersTableProcessedTableManager get peerId {
    final $_column = $_itemColumn<String>('peer_id')!;

    final manager = $$LocalPeersTableTableManager(
      $_db,
      $_db.localPeers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_peerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMe => $composableBuilder(
    column: $table.isMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalPeersTableFilterComposer get peerId {
    final $$LocalPeersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerId,
      referencedTable: $db.localPeers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalPeersTableFilterComposer(
            $db: $db,
            $table: $db.localPeers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMe => $composableBuilder(
    column: $table.isMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalPeersTableOrderingComposer get peerId {
    final $$LocalPeersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerId,
      referencedTable: $db.localPeers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalPeersTableOrderingComposer(
            $db: $db,
            $table: $db.localPeers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get isMe =>
      $composableBuilder(column: $table.isMe, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  $$LocalPeersTableAnnotationComposer get peerId {
    final $$LocalPeersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerId,
      referencedTable: $db.localPeers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalPeersTableAnnotationComposer(
            $db: $db,
            $table: $db.localPeers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({bool peerId})
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<bool> isMe = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                peerId: peerId,
                isMe: isMe,
                content: content,
                type: type,
                filePath: filePath,
                fileSize: fileSize,
                status: status,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String peerId,
                required bool isMe,
                required String content,
                required String type,
                Value<String?> filePath = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                required String status,
                required DateTime timestamp,
              }) => MessagesCompanion.insert(
                id: id,
                peerId: peerId,
                isMe: isMe,
                content: content,
                type: type,
                filePath: filePath,
                fileSize: fileSize,
                status: status,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({peerId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (peerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.peerId,
                                referencedTable: $$MessagesTableReferences
                                    ._peerIdTable(db),
                                referencedColumn: $$MessagesTableReferences
                                    ._peerIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({bool peerId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalPeersTableTableManager get localPeers =>
      $$LocalPeersTableTableManager(_db, _db.localPeers);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
}
