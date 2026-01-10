import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/onboarding/screens/welcome_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../core/services/storage_service.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      // Check if user has completed onboarding
      final storage = ref.read(storageServiceProvider);
      final hasUser = await storage.hasUser();
      
      final isOnboarding = state.matchedLocation == '/' || 
                           state.matchedLocation == '/welcome';
      
      if (!hasUser && !isOnboarding) {
        return '/welcome';
      }
      
      if (hasUser && isOnboarding) {
        return '/dashboard';
      }
      
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/welcome',
      ),
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const WelcomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const DashboardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      // More routes will be added in later phases
      // GoRoute(path: '/peers', ...),
      // GoRoute(path: '/groups', ...),
      // GoRoute(path: '/chat/:groupId', ...),
      // GoRoute(path: '/files', ...),
      // GoRoute(path: '/editor', ...),
    ],
  );
});
