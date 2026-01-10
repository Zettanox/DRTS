import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'router.dart';
import 'theme.dart';

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
      themeMode: ThemeMode.dark, // Default to dark theme
      routerConfig: router,
    );
  }
}
