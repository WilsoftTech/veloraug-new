import 'package:flutter/material.dart';

import 'shell/app_shell.dart';

const Color _seedColor = Color(0xFFF2B33D);
const Color _backgroundColor = Color(0xFF0E1014);

class VeloraApp extends StatelessWidget {
  const VeloraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeloraUG',
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      home: const AppShell(),
    );
  }
}

ThemeData _buildDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.dark,
    surface: _backgroundColor,
  );
  return ThemeData(colorScheme: colorScheme, useMaterial3: true);
}
