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
import 'package:archive/archive.dart';

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
  final String? groupId;

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
    this.groupId,
  });
}

/// Represents a queued file transfer
class QueueItem {
  final String id;
  final File file;
  final Peer peer;
  final String displayName;
  final bool isFolder;
  final String? groupId;
  QueueItemStatus status;
  
  QueueItem({
    required this.id,
    required this.file,
    required this.peer,
    required this.displayName,
    this.isFolder = false,
    this.groupId,
    this.status = QueueItemStatus.pending,
  });
}

enum QueueItemStatus { pending, inProgress, completed, failed }

class FileTransferService {
  final Ref _ref;
  final _uuid = const Uuid();
  
  // Track active transfers
  final Map<String, TransferProgress> _transfers = {};
  final _progressController = StreamController<Map<String, TransferProgress>>.broadcast();
  
  // Incoming file buffers
  final Map<String, List<int>> _incomingBuffers = {};
  
  // Transfer Queue
  final List<QueueItem> _sendQueue = [];
  bool _isProcessingQueue = false;
  final _queueController = StreamController<List<QueueItem>>.broadcast();
  
  // Constants
  static const int chunkSize = 16 * 1024; // 16KB chunks

  FileTransferService(this._ref) {
    _listenToConnectionService();
  }
  
  /// Stream of queue updates
  Stream<List<QueueItem>> get queueStream => _queueController.stream;
  
  /// Current queue items
  List<QueueItem> get queue => List.unmodifiable(_sendQueue);

  void _listenToConnectionService() {
    final connectionService = _ref.read(connectionServiceProvider);
    connectionService.messageStream.listen((message) {
      if (message.type == ConnectionMessageType.data && message.payload != null) {
        handleMessage(message.peerId, message.payload);
      }
    });
  }

  Stream<Map<String, TransferProgress>> get progressStream => _progressController.stream;

  /// Pick and send file(s) to a peer - supports multi-select
  Future<void> pickAndSendFile(Peer peer, {bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: allowMultiple);
    
    if (result != null && result.files.isNotEmpty) {
      if (result.files.length == 1) {
        // Single file - send directly
        final file = File(result.files.single.path!);
        await _sendFile(peer, file);
      } else {
        // Multiple files - add to queue
        for (final picked in result.files) {
          if (picked.path != null) {
            final file = File(picked.path!);
            _addToQueue(peer, file, picked.name);
          }
        }
        _processQueue();
      }
    }
  }
  
  /// Add a file to the transfer queue (Public for GroupService)
  void queueFile(Peer peer, File file, {bool isFolder = false, String? groupId}) {
    final filename = file.uri.pathSegments.last;
    _addToQueue(peer, file, filename, isFolder: isFolder, groupId: groupId);
    _processQueue();
  }

  /// Internal add to queue
  void _addToQueue(Peer peer, File file, String displayName, {bool isFolder = false, String? groupId}) {
    final item = QueueItem(
      id: _uuid.v4(),
      file: file,
      peer: peer,
      displayName: displayName,
      isFolder: isFolder,
      groupId: groupId,
    );
    _sendQueue.add(item);
    _notifyQueueChanged();
    print('📥 Added to queue: $displayName (${_sendQueue.length} items)');
  }
  
  /// Remove item from queue
  void removeFromQueue(String itemId) {
    _sendQueue.removeWhere((item) => item.id == itemId && item.status == QueueItemStatus.pending);
    _notifyQueueChanged();
  }
  
  /// Clear completed/failed items from queue
  void clearCompletedFromQueue() {
    _sendQueue.removeWhere((item) => 
      item.status == QueueItemStatus.completed || 
      item.status == QueueItemStatus.failed
    );
    _notifyQueueChanged();
  }
  
  void _notifyQueueChanged() {
    _queueController.add(List.unmodifiable(_sendQueue));
  }
  
  /// Process the transfer queue sequentially
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    
    while (_sendQueue.any((item) => item.status == QueueItemStatus.pending)) {
      final item = _sendQueue.firstWhere((item) => item.status == QueueItemStatus.pending);
      
      item.status = QueueItemStatus.inProgress;
      _notifyQueueChanged();
      
      try {
        await _sendFile(item.peer, item.file, isFolder: item.isFolder, originalName: item.displayName, groupId: item.groupId);
        item.status = QueueItemStatus.completed;
      } catch (e) {
        print('❌ Queue transfer failed: ${item.displayName}: $e');
        item.status = QueueItemStatus.failed;
      }
      _notifyQueueChanged();
    }
    
    _isProcessingQueue = false;
    
    // Auto-clear completed items after a delay
    Future.delayed(const Duration(seconds: 3), () {
      clearCompletedFromQueue();
    });
  }
  
  /// Pick and send a folder as ZIP to a peer
  Future<void> pickAndSendFolder(Peer peer) async {
    final directoryPath = await FilePicker.platform.getDirectoryPath();
    
    if (directoryPath == null) return;
    
    final directory = Directory(directoryPath);
    final folderName = directory.path.split(Platform.pathSeparator).last;
    
    print('📁 Zipping folder: $folderName...');
    
    // Create ZIP archive
    final archive = Archive();
    
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(directory.path.length + 1);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      }
    }
    
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      print('❌ Failed to create ZIP archive');
      return;
    }
    
    // Save ZIP to temp directory
    final tempDir = await getTemporaryDirectory();
    final zipPath = '${tempDir.path}/$folderName.zip';
    final zipFile = File(zipPath);
    await zipFile.writeAsBytes(zipBytes);
    
    print('✅ Created ZIP: ${zipFile.path} (${(zipBytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
    
    // Send the ZIP file (with .zip extension so receiver can open it)
    await _sendFile(peer, zipFile, isFolder: true, originalName: '$folderName.zip');
  }
  
  /// Send a file to a peer
  Future<void> _sendFile(Peer peer, File file, {bool isFolder = false, String? originalName, String? groupId}) async {
    final filename = originalName ?? file.uri.pathSegments.last;
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
      groupId: groupId,
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
        'groupId': groupId,
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
    final groupId = message['groupId'];
    
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
      groupId: groupId,
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
      // Use Downloads folder on Android, Documents on other platforms
      Directory baseDir;
      if (Platform.isAndroid) {
        baseDir = Directory('/storage/emulated/0/Download/Stoa');
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        baseDir = Directory('${docDir.path}/Stoa');
      }
      
      // Ensure Stoa folder exists
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      
      // Check if it's a ZIP file (folder transfer)
      final isZip = transfer.filename.toLowerCase().endsWith('.zip');
      String savePath;
      String displayPath;
      
      if (isZip) {
        // Auto-extract ZIP to folder
        final folderName = transfer.filename.substring(0, transfer.filename.length - 4);
        var extractDir = Directory('${baseDir.path}/$folderName');
        
        // Ensure unique folder name
        int counter = 1;
        while (await extractDir.exists()) {
          extractDir = Directory('${baseDir.path}/${folderName}_$counter');
          counter++;
        }
        savePath = extractDir.path;
        
        // Create extraction directory
        await extractDir.create(recursive: true);
        
        // Extract ZIP contents
        try {
          final archive = ZipDecoder().decodeBytes(buffer);
          for (final file in archive) {
            final filename = file.name;
            if (file.isFile) {
              final outputFile = File('${extractDir.path}/$filename');
              await outputFile.create(recursive: true);
              await outputFile.writeAsBytes(file.content as List<int>);
            } else {
              await Directory('${extractDir.path}/$filename').create(recursive: true);
            }
          }
          print('📦 Extracted ${archive.length} files to: ${extractDir.path}');
        } catch (e) {
          print('⚠️ Failed to extract ZIP, saving as-is: $e');
          // Fallback: save as ZIP file
          savePath = '${baseDir.path}/${transfer.filename}';
          final file = File(savePath);
          await file.writeAsBytes(buffer);
        }
        
        displayPath = savePath;
      } else {
        // Regular file - save normally
        savePath = '${baseDir.path}/${transfer.filename}';
        int counter = 1;
        while (await File(savePath).exists()) {
          final name = transfer.filename.split('.').first;
          final ext = transfer.filename.split('.').last;
          savePath = '${baseDir.path}/${name}_$counter.$ext';
          counter++;
        }
        
        final file = File(savePath);
        await file.writeAsBytes(buffer);
        displayPath = savePath;
      }
      
      _updateProgress(transfer.copyWith(
        status: TransferStatus.completed,
        filePath: displayPath,
        transferredBytes: transfer.totalBytes,
      ));
      
      // Clear buffer to free memory
      _incomingBuffers.remove(fileId);
      
      print('💾 File saved to: $displayPath');
      
      // Log to database
      try {
        final db = _ref.read(databaseProvider);
        
        if (transfer.groupId != null) {
          // Group Transfer: Update existing group message
          await db.updateGroupMessageFile(
            transfer.groupId!, 
            transfer.peerId, 
            transfer.filename, // Use original filename for lookup
            displayPath
          );
          print('✅ Updated group message file path');
        } else {
          // Direct Transfer: Insert into Messages (DM)
          await db.insertMessage(MessagesCompanion.insert(
            peerId: transfer.peerId,
            isMe: false,
            content: isZip ? transfer.filename.substring(0, transfer.filename.length - 4) : transfer.filename,
            type: isZip ? 'folder' : 'file',
            status: 'received',
            timestamp: DateTime.now(),
            filePath: Value(displayPath),
            fileSize: Value(transfer.totalBytes),
          ));
        }
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
    String? groupId,
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
      groupId: groupId ?? this.groupId,
    );
  }
}

final fileTransferServiceProvider = Provider<FileTransferService>((ref) {
  return FileTransferService(ref);
});
