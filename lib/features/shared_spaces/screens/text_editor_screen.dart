import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stoa/core/services/remote_folder_service.dart';
import 'package:path/path.dart' as p;

/// Simple text editor for editing text files in shared spaces
/// Supports real-time sync with collaborators
class TextEditorScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final String spaceName;
  final String ownerId;
  final String relativePath;
  
  const TextEditorScreen({
    super.key,
    required this.spaceId,
    required this.spaceName,
    required this.ownerId,
    required this.relativePath,
  });

  @override
  ConsumerState<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends ConsumerState<TextEditorScreen> {
  late TextEditingController _controller;
  bool _hasChanges = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  StreamSubscription? _editSubscription;
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadContent();
    _listenForEdits();
  }
  
  Future<void> _loadContent() async {
    try {
      final content = await ref.read(remoteFolderServiceProvider).fetchContent(
        widget.spaceId,
        widget.ownerId,
        widget.relativePath,
      );
      
      if (mounted) {
        setState(() {
          _controller.text = content;
          _isLoading = false;
        });
        _controller.addListener(_onTextChanged);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }
  
  void _listenForEdits() {
    _editSubscription = ref.read(remoteFolderServiceProvider).textEditStream.listen((event) {
      // Only update if it's for our file and not from us
      if (event.spaceId == widget.spaceId && event.relativePath == widget.relativePath) {
        // Preserve cursor position
        final cursorPos = _controller.selection.baseOffset;
        
        setState(() {
          _controller.removeListener(_onTextChanged);
          _controller.text = event.content;
          
          // Restore cursor position (clamped to valid range)
          final newPos = cursorPos.clamp(0, event.content.length);
          _controller.selection = TextSelection.fromPosition(TextPosition(offset: newPos));
          _controller.addListener(_onTextChanged);
        });
      }
    });
  }
  
  void _onTextChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    
    // Debounce: Send updates after 500ms of no typing
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _syncContent();
    });
  }
  
  void _syncContent() {
    ref.read(remoteFolderServiceProvider).sendTextEdit(
      widget.spaceId,
      widget.ownerId,
      widget.relativePath,
      _controller.text,
    );
    setState(() => _hasChanges = false);
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _editSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }
  
  Future<void> _saveFile() async {
    setState(() => _isSaving = true);
    
    try {
      final bytes = utf8.encode(_controller.text);
      
      // Upload to owner
      await ref.read(remoteFolderServiceProvider).uploadFile(
        widget.spaceId,
        widget.ownerId,
        widget.relativePath,
        bytes,
      );
      
      setState(() {
        _hasChanges = false;
        _isSaving = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved!')),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.relativePath)),
        actions: [
          // Sync indicator
          if (_hasChanges)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: _isSaving 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
            onPressed: !_isSaving ? _saveFile : null,
            tooltip: 'Save (force sync)',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading content...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadContent();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    return TextField(
      controller: _controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.all(16),
        border: InputBorder.none,
        hintText: 'Start typing...',
      ),
    );
  }
}
