import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/constants.dart';
import '../../../app/theme.dart';

/// Dialog for editing user profile
class EditProfileDialog extends ConsumerStatefulWidget {
  final User user;

  const EditProfileDialog({super.key, required this.user});

  /// Show the dialog and return the updated user (or null if cancelled)
  static Future<User?> show(BuildContext context, User user) {
    return showDialog<User>(
      context: context,
      builder: (context) => EditProfileDialog(user: user),
    );
  }

  @override
  ConsumerState<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<EditProfileDialog> {
  late TextEditingController _usernameController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _selectedColor;

  final List<String> _colors = [
    '#6366F1',
    '#8B5CF6',
    '#06B6D4',
    '#10B981',
    '#F59E0B',
    '#EF4444',
    '#EC4899',
    '#3B82F6',
  ];

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _selectedColor = widget.user.avatarColor ?? _colors[0];
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updatedUser = User(
        id: widget.user.id,
        username: _usernameController.text.trim(),
        createdAt: widget.user.createdAt,
        publicKey: widget.user.publicKey,
        avatarColor: _selectedColor,
      );

      final storage = ref.read(storageServiceProvider);
      await storage.saveUser(updatedUser);

      if (mounted) {
        Navigator.of(context).pop(updatedUser);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: StoaTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit Profile',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Avatar preview
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _parseColor(_selectedColor),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _parseColor(
                          _selectedColor,
                        ).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _usernameController.text.isNotEmpty
                          ? _usernameController.text[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Color picker
              Text(
                'Avatar Color',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colors.map((color) {
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _parseColor(color),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Username field
              Text(
                'Display Name',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _usernameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Enter your name...',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  if (value.trim().length < AppConstants.minUsernameLength) {
                    return 'Name must be at least ${AppConstants.minUsernameLength} characters';
                  }
                  if (value.trim().length > AppConstants.maxUsernameLength) {
                    return 'Name must be less than ${AppConstants.maxUsernameLength} characters';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _save,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Note
              Text(
                'Note: Restart discovery for changes to be visible to others',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null) return StoaTheme.primaryColor;
    final hexCode = hex.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }
}
