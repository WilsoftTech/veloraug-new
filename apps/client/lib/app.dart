import 'package:flutter/material.dart';

import 'shell/app_shell.dart';
import 'theme/velora_theme.dart';

class VeloraApp extends StatelessWidget {
  const VeloraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeloraUG',
      debugShowCheckedModeBanner: false,
      theme: buildVeloraTheme(),
      home: const AppShell(),
    );
  }
}
