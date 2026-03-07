import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/onboarding/screens/welcome_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/peers/screens/peers_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/groups/screens/groups_screen.dart';
import '../features/groups/screens/create_group_screen.dart';
import '../features/groups/screens/group_chat_screen.dart';
import '../core/services/storage_service.dart';

// Global navigator key for showing dialogs from anywhere
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

final routerProvider = Provider<GoRouter>((ref) {
  final navigatorKey = ref.watch(navigatorKeyProvider);

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    redirect: (context, state) async {
      // Check if user has completed onboarding
      final storage = ref.read(storageServiceProvider);
      final hasUser = await storage.hasUser();

      final isOnboarding =
          state.matchedLocation == '/' || state.matchedLocation == '/welcome';

      if (!hasUser && !isOnboarding) {
        return '/welcome';
      }

      if (hasUser && isOnboarding) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/welcome'),
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
      GoRoute(
        path: '/peers',
        name: 'peers',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PeersScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/chat/:peerId',
        name: 'chat',
        builder: (context, state) =>
            ChatScreen(peerId: state.pathParameters['peerId']!),
      ),
      // Groups routes
      GoRoute(
        path: '/groups',
        name: 'groups',
        builder: (context, state) => const GroupsScreen(),
      ),
      GoRoute(
        path: '/groups/create',
        name: 'createGroup',
        builder: (context, state) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '/groups/:groupId',
        name: 'groupChat',
        builder: (context, state) =>
            GroupChatScreen(groupId: state.pathParameters['groupId']!),
      ),
    ],
  );
});
