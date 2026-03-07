import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/user.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/constants.dart';
import '../../../app/theme.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final username = _usernameController.text.trim();
      final user = User.create(username: username);

      final storage = ref.read(storageServiceProvider);
      await storage.saveUser(user);

      if (mounted) {
        context.go('/dashboard');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo/Icon
                    Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                StoaTheme.primaryColor,
                                StoaTheme.secondaryColor,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: StoaTheme.primaryColor.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.hub_rounded,
                            size: 50,
                            color: Colors.white,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          duration: 600.ms,
                          curve: Curves.easeOutBack,
                        ),

                    const SizedBox(height: 32),

                    // Title
                    Text(
                          'Welcome to Stoa',
                          style: Theme.of(context).textTheme.displaySmall,
                          textAlign: TextAlign.center,
                        )
                        .animate()
                        .fadeIn(delay: 200.ms, duration: 500.ms)
                        .slideY(begin: 0.2, end: 0),

                    const SizedBox(height: 12),

                    // Subtitle
                    Text(
                          'Your collaborative workspace for sharing files, messages, and ideas with people nearby.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: Colors.white60),
                          textAlign: TextAlign.center,
                        )
                        .animate()
                        .fadeIn(delay: 300.ms, duration: 500.ms)
                        .slideY(begin: 0.2, end: 0),

                    const SizedBox(height: 48),

                    // Username input
                    Text(
                      'Choose your display name',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                    ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

                    const SizedBox(height: 12),

                    TextFormField(
                          controller: _usernameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleContinue(),
                          decoration: InputDecoration(
                            hintText: 'Enter your name...',
                            prefixIcon: const Icon(Icons.person_outline),
                            suffixIcon: _usernameController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _usernameController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a name';
                            }
                            if (value.trim().length <
                                AppConstants.minUsernameLength) {
                              return 'Name must be at least ${AppConstants.minUsernameLength} characters';
                            }
                            if (value.trim().length >
                                AppConstants.maxUsernameLength) {
                              return 'Name must be less than ${AppConstants.maxUsernameLength} characters';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        )
                        .animate()
                        .fadeIn(delay: 500.ms, duration: 500.ms)
                        .slideY(begin: 0.1, end: 0),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: StoaTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: StoaTheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: StoaTheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: StoaTheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Continue button
                    SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleContinue,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Get Started'),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 20),
                                    ],
                                  ),
                          ),
                        )
                        .animate()
                        .fadeIn(delay: 600.ms, duration: 500.ms)
                        .slideY(begin: 0.1, end: 0),

                    const SizedBox(height: 24),

                    // Info text
                    Text(
                      'This name will be visible to others on your network',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 700.ms, duration: 500.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
