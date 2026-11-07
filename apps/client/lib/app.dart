import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/auth_controller.dart';
import 'auth/browser_step.dart';
import 'auth/oauth_client.dart';
import 'auth/oauth_config.dart';
import 'auth/token_store.dart';
import 'shell/app_shell.dart';
import 'theme/velora_theme.dart';

class VeloraApp extends StatefulWidget {
  const VeloraApp({super.key, this.authController});

  /// Replaces the controller built from this build's settings. The app
  /// restores it but doesn't dispose of it.
  final AuthController? authController;

  @override
  State<VeloraApp> createState() => _VeloraAppState();
}

class _VeloraAppState extends State<VeloraApp> {
  http.Client? _httpClient;
  AuthController? _ownController;

  AuthController? get _auth => widget.authController ?? _ownController;

  @override
  void initState() {
    super.initState();
    if (widget.authController == null) _ownController = _fromSettings();
    _auth?.restore();
  }

  AuthController? _fromSettings() {
    final OAuthConfig? config;
    try {
      config = OAuthConfig.fromSettings();
    } on FormatException catch (error) {
      if (kDebugMode) debugPrint('auth settings: ${error.message}');
      return null;
    }
    if (config == null) return null;
    final httpClient = _httpClient = http.Client();
    return AuthController(
      client: OAuthClient(
        config: config,
        httpClient: httpClient,
        browserStep: openBrowserStep,
      ),
      store: createPlatformTokenStore(),
    );
  }

  @override
  void dispose() {
    _ownController?.dispose();
    _httpClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      controller: _auth,
      child: MaterialApp(
        title: 'VeloraUG',
        debugShowCheckedModeBanner: false,
        theme: buildVeloraTheme(),
        home: const AppShell(),
      ),
    );
  }
}
