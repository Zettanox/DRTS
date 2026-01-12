import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/peer.dart';
import 'connection_service.dart';
import '../data/database.dart';
import 'package:drift/drift.dart' hide Column; // Avoid conflict if any, though likely safe

enum TransferType { sending, receiving }

enum TransferStatus {
  pending,
  inProgress,
  completed,
  failed,
}

class TransferProgress {
  final String id;
  final String filename;
  final int totalBytes;
  final int transferredBytes;
  final TransferType type;
  final TransferStatus status;
  final String? filePath;
  final String peerId;

  double get percentage => totalBytes == 0 ? 0 : transferredBytes / totalBytes;

  TransferProgress({
    required this.id,
    required this.filename,
    required this.totalBytes,
    required this.transferredBytes,
    required this.type,
    required this.status,
    this.filePath,
    required this.peerId,
  });
}

class FileTransferService {
  final Ref _ref;
  final _uuid = const Uuid();
  
  // Track active transfers
  final Map<String, TransferProgress> _transfers = {};
  final _progressController = StreamController<Map<String, TransferProgress>>.broadcast();
  
  // Incoming file buffers
  final Map<String, List<int>> _incomingBuffers = {};
  
  // Constants
  static const int chunkSize = 16 * 1024; // 16KB chunks

  FileTransferService(this._ref) {
    _listenToConnectionService();
  }

  void _listenToConnectionService() {
    final connectionService = _ref.read(connectionServiceProvider);
    connectionService.messageStream.listen((message) {
      if (message.type == ConnectionMessageType.data && message.payload != null) {
        handleMessage(message.peerId, message.payload);
      }
    });
  }

  Stream<Map<String, TransferProgress>> get progressStream => _progressController.stream;

  /// Pick and send a file to a peer
  Future<void> pickAndSendFile(Peer peer) async {
    final result = await FilePicker.platform.pickFiles();
    
    if (result != null && result.files.isNotEmpty) {
      final file = File(result.files.single.path!);
      await _sendFile(peer, file);
    }
  }
  
  /// Send a file to a peer
  Future<void> _sendFile(Peer peer, File file) async {
    final filename = file.uri.pathSegments.last;
    final size = await file.length();
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final fileId = _uuid.v4();
    
    // 1. Register transfer
    _updateProgress(TransferProgress(
      id: fileId,
      filename: filename,
      totalBytes: size,
      transferredBytes: 0,
      type: TransferType.sending,
      status: TransferStatus.pending,
      peerId: peer.id,
      filePath: file.path,
    ));
    
    final connectionService = _ref.read(connectionServiceProvider);
    
    try {
      // 2. Send Offer
      print('📤 Sending file offer: $filename to ${peer.username}');
      await connectionService.send(peer.id, {
        'type': 'file_offer',
        'fileId': fileId,
        'filename': filename,
        'size': size,
        'mime': mimeType,
      });
      
      _updateProgress(_transfers[fileId]!.copyWith(status: TransferStatus.inProgress));
      
      // 3. Send Chunks using Turbo Mode (raw binary) - Maximum Speed
      int sentBytes = 0;
      int chunkIndex = 0;
      
      // 1MB chunks for maximum throughput
      const chunkSize = 1024 * 1024;
      final fileBytes = await file.readAsBytes();
      final totalChunks = (fileBytes.length / chunkSize).ceil();
      
      // Pipeline writes: collect futures, don't await each one
      final List<Future<void>> pendingWrites = [];
      
      for (int i = 0; i < fileBytes.length; i += chunkSize) {
        final end = (i + chunkSize > fileBytes.length) ? fileBytes.length : i + chunkSize;
        final chunk = Uint8List.fromList(fileBytes.sublist(i, end));
        final isLast = (end >= fileBytes.length);
        
        // Don't await - let TCP buffer handle flow control
        pendingWrites.add(connectionService.sendRawFileChunk(peer.id, fileId, chunk, isLast: isLast));
        
        sentBytes += chunk.length;
        chunkIndex++;
        
        // Update progress every 20 chunks (less UI overhead)
        if (chunkIndex % 20 == 0 || isLast) {
          _updateProgress(_transfers[fileId]!.copyWith(
            transferredBytes: sentBytes,
          ));
        }
        
        // Limit pipeline depth to avoid memory bloat on huge files
        if (pendingWrites.length >= 10) {
          await Future.wait(pendingWrites);
          pendingWrites.clear();
        }
      }
      
      // Wait for any remaining writes
      if (pendingWrites.isNotEmpty) {
        await Future.wait(pendingWrites);
      }
      
      _updateProgress(_transfers[fileId]!.copyWith(
        transferredBytes: size,
        status: TransferStatus.completed,
      ));
      
      print('✅ File sent: $filename');
      
      // Log to database
      try {
        final db = _ref.read(databaseProvider);
        await db.insertMessage(MessagesCompanion.insert(
          peerId: peer.id,
          isMe: true,
          content: filename,
          type: 'file',
          status: 'sent',
          timestamp: DateTime.now(),
          filePath: Value(file.path),
          fileSize: Value(size),
        ));
      } catch (e) {
        print('⚠️ Failed to log transfer: $e');
      }
      
    } catch (e) {
      print('❌ Error sending file: $e');
      _updateProgress(_transfers[fileId]!.copyWith(status: TransferStatus.failed));
    }
  }
  
  /// Handle incoming file message
  Future<void> handleMessage(String senderId, Map<String, dynamic> message) async {
    final type = message['type'];
    
    if (type == 'file_offer') {
      await _handleOffer(senderId, message);
    } else if (type == 'file_chunk') {
      await _handleChunk(senderId, message);
    } else if (type == 'file_chunk_binary') {
      await _handleBinaryChunk(senderId, message);
    }
  }
  
  /// Handle binary chunk (Turbo Mode)
  Future<void> _handleBinaryChunk(String senderId, Map<String, dynamic> message) async {
    final fileId = message['fileId'];
    final data = message['data'] as Uint8List;
    final isLast = message['isLast'] as bool;
    
    if (!_transfers.containsKey(fileId)) return;
    
    final buffer = _incomingBuffers[fileId];
    if (buffer == null) return;
    
    buffer.addAll(data);
    
    final current = _transfers[fileId]!;
    _updateProgress(current.copyWith(
      transferredBytes: current.transferredBytes + data.length,
    ));
    
    if (isLast) {
      await _saveFile(fileId);
    }
  }
  
  Future<void> _handleOffer(String senderId, Map<String, dynamic> message) async {
    final fileId = message['fileId'];
    final filename = message['filename'];
    final size = message['size'];
    
    print('📥 Receiving file offer: $filename from $senderId');
    
    _incomingBuffers[fileId] = [];
    
    _updateProgress(TransferProgress(
      id: fileId,
      filename: filename,
      totalBytes: size,
      transferredBytes: 0,
      type: TransferType.receiving,
      status: TransferStatus.inProgress,
      peerId: senderId,
    ));
    
    // Auto-accepting for now (Phase 3b)
  }
  
  Future<void> _handleChunk(String senderId, Map<String, dynamic> message) async {
    final fileId = message['fileId'];
    final data = message['data'] as String;
    final isLast = message['isLast'] as bool;
    
    if (!_transfers.containsKey(fileId)) return;
    
    final buffer = _incomingBuffers[fileId];
    if (buffer == null) return; // Should not happen if offer handled
    
    if (data.isNotEmpty) {
      final bytes = base64Decode(data);
      buffer.addAll(bytes);
      
      final current = _transfers[fileId]!;
      _updateProgress(current.copyWith(
        transferredBytes: current.transferredBytes + bytes.length,
      ));
    }
    
    if (isLast) {
      await _saveFile(fileId);
    }
  }
  
  Future<void> _saveFile(String fileId) async {
    final transfer = _transfers[fileId];
    final buffer = _incomingBuffers[fileId];
    
    if (transfer == null || buffer == null) return;
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Ensure unique name
      String savePath = '${dir.path}/${transfer.filename}';
      int counter = 1;
      while (File(savePath).existsSync()) {
        final name = transfer.filename.split('.').first;
        final ext = transfer.filename.split('.').last;
        savePath = '${dir.path}/${name}_$counter.$ext';
        counter++;
      }
      
      final file = File(savePath);
      await file.writeAsBytes(buffer);
      
      _updateProgress(transfer.copyWith(
        status: TransferStatus.completed,
        filePath: savePath,
        transferredBytes: transfer.totalBytes, // Ensure 100%
      ));
      
      // Clear buffer to free memory
      _incomingBuffers.remove(fileId);
      
      print('💾 File saved to: $savePath');
      
      // Log to database
      try {
        final db = _ref.read(databaseProvider);
        await db.insertMessage(MessagesCompanion.insert(
          peerId: transfer.peerId,
          isMe: false,
          content: transfer.filename,
          type: 'file',
          status: 'received',
          timestamp: DateTime.now(),
          filePath: Value(savePath),
          fileSize: Value(transfer.totalBytes),
        ));
      } catch (e) {
        print('⚠️ Failed to log transfer: $e');
      }
      
    } catch (e) {
      print('❌ Error saving file: $e');
      _updateProgress(transfer.copyWith(status: TransferStatus.failed));
    }
  }
  
  /// Open a completed file
  Future<void> openFile(String fileId) async {
    final transfer = _transfers[fileId];
    if (transfer != null && transfer.status == TransferStatus.completed && transfer.filePath != null) {
      await OpenFilex.open(transfer.filePath!);
    }
  }
  
  void _updateProgress(TransferProgress progress) {
    _transfers[progress.id] = progress;
    _progressController.add(_transfers);
  }
}

// Helpers for copyWith
extension TransferProgressCopy on TransferProgress {
  TransferProgress copyWith({
    int? transferredBytes,
    TransferStatus? status,
    String? filePath,
  }) {
    return TransferProgress(
      id: id,
      filename: filename,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      type: type,
      status: status ?? this.status,
      peerId: peerId,
      filePath: filePath ?? this.filePath,
    );
  }
}

final fileTransferServiceProvider = Provider<FileTransferService>((ref) {
  return FileTransferService(ref);
});
