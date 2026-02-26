import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'theme.dart';
import 'global_connection_handler.dart';

class StoaApp extends ConsumerWidget {
  const StoaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Stoa',
      debugShowCheckedModeBanner: false,
      theme: StoaTheme.light,
      darkTheme: StoaTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      // Wrap the entire app content with GlobalConnectionHandler
      // so it has access to MaterialLocalizations for showing dialogs
      builder: (context, child) {
        return GlobalConnectionHandler(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
