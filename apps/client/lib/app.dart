import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_config.dart';
import 'api/catalogue_api.dart';
import 'auth/auth_controller.dart';
import 'auth/browser_step.dart';
import 'auth/oauth_client.dart';
import 'auth/oauth_config.dart';
import 'auth/token_store.dart';
import 'shell/app_shell.dart';
import 'theme/velora_theme.dart';

class VeloraApp extends StatefulWidget {
  const VeloraApp({super.key, this.authController, this.catalogueApi});

  /// Replaces the controller built from this build's settings. The app
  /// restores it but doesn't dispose of it.
  final AuthController? authController;

  /// Replaces the catalogue built from this build's API address, in tests.
  final CatalogueApi? catalogueApi;

  @override
  State<VeloraApp> createState() => _VeloraAppState();
}

class _VeloraAppState extends State<VeloraApp> {
  http.Client? _httpClient;
  AuthController? _ownController;
  http.Client? _catalogueHttpClient;
  CatalogueApi? _ownCatalogue;

  CatalogueApi? get _catalogue => widget.catalogueApi ?? _ownCatalogue;

  AuthController? get _auth => widget.authController ?? _ownController;

  @override
  void initState() {
    super.initState();
    if (widget.authController == null) _ownController = _fromSettings();
    if (widget.catalogueApi == null) _ownCatalogue = _catalogueFromSettings();
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

  CatalogueApi? _catalogueFromSettings() {
    final Uri baseUrl;
    try {
      baseUrl = parseApiBaseUrl(apiBaseUrlSetting);
    } on FormatException catch (error) {
      if (kDebugMode) debugPrint('API address: ${error.message}');
      return null;
    }
    return CatalogueApi(
      baseUrl: baseUrl,
      httpClient: _catalogueHttpClient = http.Client(),
    );
  }

  @override
  void dispose() {
    _ownController?.dispose();
    _httpClient?.close();
    _catalogueHttpClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      controller: _auth,
      // Above MaterialApp, so pushed screens such as a movie's details see
      // the catalogue too.
      child: CatalogueScope(
        api: _catalogue,
        child: MaterialApp(
          title: 'VeloraUG',
          debugShowCheckedModeBanner: false,
          theme: buildVeloraTheme(),
          home: const AppShell(),
        ),
      ),
    );
  }
}
