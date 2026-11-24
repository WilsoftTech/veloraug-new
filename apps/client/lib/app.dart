import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'admin/uploads/tus.dart';
import 'admin/uploads/upload_platform.dart' as uploads;
import 'admin/uploads/upload_queue.dart';
import 'admin/uploads/uploads_view.dart';
import 'api/admin_api.dart';
import 'api/api_config.dart';
import 'api/catalogue_api.dart';
import 'api/device_store.dart';
import 'api/playback_api.dart';
import 'auth/auth_controller.dart';
import 'auth/browser_step.dart';
import 'auth/oauth_client.dart';
import 'auth/oauth_config.dart';
import 'auth/token_store.dart';
import 'downloads/download_target.dart';
import 'downloads/downloads.dart';
import 'l10n/l10n.dart';
import 'security/app_lock.dart';
import 'shell/app_shell.dart';
import 'theme/velora_theme.dart';
import 'widgets/startup_gate.dart';

class VeloraApp extends StatefulWidget {
  const VeloraApp({
    super.key,
    this.authController,
    this.catalogueApi,
    this.playbackApi,
    this.adminApi,
    this.uploadQueue,
    this.downloads,
    this.appLock,
    this.pickVideos = uploads.pickVideos,
    this.showAdmin = adminScreensAvailable,
  });

  /// Replaces the controller built from this build's settings. The app
  /// restores it but doesn't dispose of it.
  final AuthController? authController;

  /// Replaces the catalogue built from this build's API address, in tests.
  final CatalogueApi? catalogueApi;

  /// Replaces the playback client built from this build's settings, in
  /// tests.
  final PlaybackApi? playbackApi;

  /// Replaces the admin client built from this build's settings, in tests.
  final AdminApi? adminApi;

  /// Replaces the browser upload queue built from this build's settings, in
  /// tests. The app doesn't dispose of it.
  final UploadQueue? uploadQueue;

  /// Replaces the downloads built for this platform, in tests. The app
  /// doesn't dispose of it.
  final Downloads? downloads;

  /// Replaces App lock for this platform, in tests. The app loads it but
  /// doesn't dispose of it.
  final AppLockController? appLock;

  /// The file chooser for uploads. Tests replace it.
  final Future<List<PickedVideo>> Function() pickVideos;

  /// Whether the Admin entry may show, to admins. The web only, except in
  /// tests.
  final bool showAdmin;

  @override
  State<VeloraApp> createState() => _VeloraAppState();
}

class _VeloraAppState extends State<VeloraApp> {
  http.Client? _httpClient;
  AuthController? _ownController;
  http.Client? _catalogueHttpClient;
  CatalogueApi? _ownCatalogue;
  http.Client? _playbackHttpClient;
  PlaybackApi? _ownPlayback;
  http.Client? _adminHttpClient;
  AdminApi? _ownAdmin;
  UploadQueue? _ownUploads;
  Downloads? _ownDownloads;
  AppLockController? _ownLock;

  AppLockController? get _lock => widget.appLock ?? _ownLock;

  Downloads? get _downloads => widget.downloads ?? _ownDownloads;

  UploadQueue? get _uploads => widget.uploadQueue ?? _ownUploads;

  AdminApi? get _admin => widget.adminApi ?? _ownAdmin;

  PlaybackApi? get _playback => widget.playbackApi ?? _ownPlayback;

  CatalogueApi? get _catalogue => widget.catalogueApi ?? _ownCatalogue;

  AuthController? get _auth => widget.authController ?? _ownController;

  @override
  void initState() {
    super.initState();
    if (widget.authController == null) _ownController = _fromSettings();
    if (widget.catalogueApi == null) _ownCatalogue = _catalogueFromSettings();
    if (widget.playbackApi == null) _ownPlayback = _playbackFromSettings();
    if (widget.adminApi == null) _ownAdmin = _adminFromSettings();
    if (widget.uploadQueue == null) _ownUploads = _uploadsFromSettings();
    _auth?.restore();
    if (widget.appLock == null) _ownLock = createPlatformAppLock();
    _lock?.load();
    if (widget.downloads == null) {
      _downloadsForPlatform();
    } else {
      widget.downloads!.load();
    }
  }

  /// Downloads: the browser's downloader on the web, Android's download
  /// manager on Android. Only with playback, which grants them.
  Future<void> _downloadsForPlatform() async {
    if (_playback == null) return;
    final found = await createPlatformDownloadTarget();
    if (found == null || !mounted) return;
    final (target, records) = found;
    final downloads = Downloads(
      target: target,
      api: _playback,
      records: records,
    );
    setState(() => _ownDownloads = downloads);
    await downloads.load();
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
    Uri? mediaBaseUrl;
    try {
      mediaBaseUrl = parseMediaBaseUrl(mediaBaseUrlSetting);
    } on FormatException {
      // Only TMDB's images are shown without it.
    }
    return CatalogueApi(
      baseUrl: baseUrl,
      mediaBaseUrl: mediaBaseUrl,
      httpClient: _catalogueHttpClient = http.Client(),
    );
  }

  /// Like playback: the API's address, the media gateway's, and sign-in.
  AdminApi? _adminFromSettings() {
    final auth = _auth;
    if (auth == null) return null;
    try {
      return AdminApi(
        baseUrl: parseApiBaseUrl(apiBaseUrlSetting),
        mediaBaseUrl: parseMediaBaseUrl(mediaBaseUrlSetting),
        httpClient: _adminHttpClient = http.Client(),
        accessToken: auth.accessToken,
      );
    } on FormatException {
      return null;
    }
  }

  /// Uploads from the admin screens: the web only, with the admin routes
  /// and tusd's address.
  UploadQueue? _uploadsFromSettings() {
    final admin = _admin;
    if (!kIsWeb || !widget.showAdmin || admin == null) return null;
    final Uri endpoint;
    try {
      endpoint = parseUploadBaseUrl(uploadBaseUrlSetting);
    } on FormatException catch (error) {
      if (kDebugMode) debugPrint('upload address: ${error.message}');
      return null;
    }
    // A file dropped outside the upload area must never replace the app.
    uploads.guardAgainstFileDrops();
    return UploadQueue(
      api: admin,
      tus: TusClient(uploads.createTusTransport()),
      endpoint: endpoint,
      store: uploads.createUploadStore(),
      network: uploads.createNetworkStatus(),
      onBusyChanged: uploads.warnBeforeLeaving,
    );
  }

  /// Needs the API's address, the media gateway's, and sign-in.
  PlaybackApi? _playbackFromSettings() {
    final auth = _auth;
    if (auth == null) return null;
    final Uri baseUrl;
    final Uri mediaBaseUrl;
    try {
      baseUrl = parseApiBaseUrl(apiBaseUrlSetting);
      mediaBaseUrl = parseMediaBaseUrl(mediaBaseUrlSetting);
    } on FormatException catch (error) {
      if (kDebugMode) debugPrint('playback settings: ${error.message}');
      return null;
    }
    return PlaybackApi(
      baseUrl: baseUrl,
      mediaBaseUrl: mediaBaseUrl,
      httpClient: _playbackHttpClient = http.Client(),
      accessToken: auth.accessToken,
      // Milestone 10: this installation's device credential.
      deviceStore: createPlatformDeviceStore(),
    );
  }

  @override
  void dispose() {
    _ownUploads?.dispose();
    _ownDownloads?.dispose();
    _ownLock?.dispose();
    _ownController?.dispose();
    _httpClient?.close();
    _catalogueHttpClient?.close();
    _playbackHttpClient?.close();
    _adminHttpClient?.close();
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
        child: PlaybackScope(
          api: _playback,
          child: DownloadsScope(
            downloads: _downloads,
            child: AdminScope(
              api: _admin,
              child: UploadsScope(
                queue: _uploads,
                pick: widget.pickVideos,
                child: AppLockScope(
                  controller: _lock,
                  child: MaterialApp(
                    onGenerateTitle: (context) => context.l10n.appName,
                    debugShowCheckedModeBanner: false,
                    theme: buildVeloraTheme(),
                    // English only for now. A Luganda app_lg.arb adds itself here.
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    // App lock covers every screen, pushed ones included.
                    builder: (context, child) =>
                        AppLockGate(child: child ?? const SizedBox.shrink()),
                    home: StartupGate(
                      child: AppShell(showAdmin: widget.showAdmin),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
