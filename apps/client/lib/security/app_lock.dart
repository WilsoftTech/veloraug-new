import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/startup_gate.dart';
import '../widgets/velora_button.dart';

/// How the phone's own prompt ended.
enum LockCheck {
  /// The person proved it's them: fingerprint, face, PIN, pattern or
  /// password.
  passed,

  /// They closed the prompt, or Android closed it.
  cancelled,

  /// Too many tries: Android has locked the prompt for a while.
  lockedOut,

  /// The phone has no screen lock or biometrics set up any more.
  unavailable,

  /// Anything else.
  failed,
}

/// The phone's own authentication prompt. Tests replace it.
abstract interface class LockAuthenticator {
  /// Whether this phone can show the prompt: biometrics, or its PIN,
  /// pattern or password.
  Future<bool> isSupported();

  Future<LockCheck> check(String reason);
}

/// Android's prompt, through local_auth. Biometrics, with the phone's PIN,
/// pattern or password as the fallback. VeloraUG never sees any of them:
/// Android only answers whether the person passed.
class SystemLockAuthenticator implements LockAuthenticator {
  SystemLockAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<LockCheck> check(String reason) async {
    try {
      final passed = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return passed ? LockCheck.passed : LockCheck.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback => LockCheck.cancelled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => LockCheck.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware => LockCheck.unavailable,
        _ => LockCheck.failed,
      };
    } on Object {
      return LockCheck.failed;
    }
  }
}

/// Where App lock's on or off is kept: on this installation only, never
/// synced or backed up.
abstract interface class LockSettingStore {
  Future<bool> read();
  Future<void> write(bool enabled);
}

class SecureLockSettingStore implements LockSettingStore {
  const SecureLockSettingStore();

  static const _key = 'veloraug.app_lock';
  static const _storage = FlutterSecureStorage();

  @override
  Future<bool> read() async => await _storage.read(key: _key) == 'on';

  @override
  Future<void> write(bool enabled) => enabled
      ? _storage.write(key: _key, value: 'on')
      : _storage.delete(key: _key);
}

class MemoryLockSettingStore implements LockSettingStore {
  MemoryLockSettingStore([this.enabled = false]);

  bool enabled;

  @override
  Future<bool> read() async => enabled;

  @override
  Future<void> write(bool enabled) async => this.enabled = enabled;
}

/// App lock: off by default, Android only. When on, the app asks for the
/// phone's own authentication at a cold start and when it comes back after
/// [relockAfter] away. Turning it on or off needs the same.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController({
    required this.authenticator,
    required this.store,
    this.relockAfter = const Duration(seconds: 60),
    this.loadTimeout = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final LockAuthenticator authenticator;
  final LockSettingStore store;

  /// Away for less than this, such as for a sign-in page, doesn't lock.
  final Duration relockAfter;

  /// The longest [load] waits for the setting and the phone's answer.
  final Duration loadTimeout;
  final DateTime Function() _now;

  bool _loaded = false;
  bool _supported = false;
  bool _enabled = false;
  bool _locked = false;
  bool _checking = false;
  DateTime? _leftAt;
  bool _settingUnknown = false;

  bool get loaded => _loaded;

  /// Whether this phone can use App lock.
  bool get supported => _supported;
  bool get enabled => _enabled;
  bool get locked => _locked;

  /// The prompt is showing.
  bool get checking => _checking;

  /// Reads the setting and whether the phone supports it. Locks at once if
  /// it is on.
  Future<void> load() async {
    WidgetsBinding.instance.addObserver(this);
    final capability = authenticator
        .isSupported()
        .timeout(loadTimeout)
        .catchError((Object _) => false);
    try {
      _enabled = await store.read().timeout(loadTimeout);
    } on Object {
      // Unknown storage must not expose a possibly locked installation.
      _settingUnknown = true;
      _enabled = true;
    }
    _supported = await capability;
    _locked = _enabled;
    _loaded = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        // The prompt itself sends the app to the background briefly.
        if (!_checking) _leftAt ??= _now();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left != null && _now().difference(left) >= relockAfter) {
          _locked = true;
          notifyListeners();
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  Future<LockCheck> _check(String reason) async {
    if (_checking) return LockCheck.cancelled;
    _checking = true;
    notifyListeners();
    try {
      return await authenticator.check(reason);
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Asks for the phone's authentication, and unlocks if it passes.
  Future<LockCheck> unlock(String reason) async {
    if (_settingUnknown) {
      try {
        _enabled = await store.read().timeout(loadTimeout);
        _settingUnknown = false;
        if (!_enabled) {
          _locked = false;
          notifyListeners();
          return LockCheck.passed;
        }
      } on Object {
        // System authentication still permits this session to open.
      }
    }
    final result = await _check(reason);
    if (result == LockCheck.passed) {
      _locked = false;
      _supported = true;
    }
    notifyListeners();
    return result;
  }

  /// Turns App lock on or off, once the phone's authentication passes.
  Future<LockCheck> setEnabled(bool enabled, String reason) async {
    if (enabled == _enabled) return LockCheck.passed;
    if (enabled && !_supported) return LockCheck.unavailable;
    final result = await _check(reason);
    if (result != LockCheck.passed) return result;
    try {
      await store.write(enabled);
    } on Object {
      return LockCheck.failed;
    }
    _enabled = enabled;
    _locked = false;
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({
    super.key,
    required AppLockController? controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLockController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}

/// Covers the whole app while it is locked. What is underneath stays
/// alive, so a sign-in or a download carries on, but nothing of it is shown,
/// read out or tappable.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  /// The app's own focus, which keyboard focus returns to once unlocked:
  /// while covered, nothing underneath can take it.
  final _appFocus = FocusScopeNode(debugLabel: 'App under App lock');
  bool _wasLocked = false;

  @override
  void dispose() {
    _appFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLockScope.of(context);
    // Until the setting is read, nothing shows: a locked app must never
    // flash its screens at launch.
    final locked =
        lock != null && (!lock.loaded || (lock.enabled && lock.locked));
    if (_wasLocked && !locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_appFocus.hasFocus) _appFocus.requestFocus();
      });
    }
    _wasLocked = locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !locked,
          child: ExcludeSemantics(
            excluding: locked,
            child: IgnorePointer(
              ignoring: locked,
              child: Visibility(
                visible: !locked,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: FocusScope(node: _appFocus, child: widget.child),
              ),
            ),
          ),
        ),
        if (locked && !lock.loaded) const StartupScreen(),
        if (locked && lock.loaded) _LockScreen(lock: lock),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.lock});

  final AppLockController lock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  LockCheck? _last;

  @override
  void initState() {
    super.initState();
    // Ask straight away, once the screen is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _unlock();
    });
  }

  Future<void> _unlock() async {
    final result = await widget.lock.unlock(context.l10n.appLockReasonUnlock);
    if (mounted) setState(() => _last = result);
  }

  Future<void> _signOut() async {
    final auth = AuthScope.of(context);
    await auth?.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = VeloraPalette.of(context);
    final message = switch (_last) {
      LockCheck.cancelled => l.appLockCancelled,
      LockCheck.lockedOut => l.appLockLockedOut,
      LockCheck.failed => l.appLockFailed,
      LockCheck.unavailable => l.appLockUnavailable,
      LockCheck.passed || null => null,
    };
    return Material(
      color: VeloraColors.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(VeloraSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: VeloraLayout.formWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: VeloraSpacing.md,
                children: [
                  const VeloraMark(size: 72),
                  Semantics(
                    header: true,
                    child: Text(
                      l.appLockLockedTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    l.appLockLockedMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (message != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _last == LockCheck.cancelled
                              ? null
                              : palette.danger,
                        ),
                      ),
                    ),
                  VeloraButton(
                    label: l.appLockUnlock,
                    icon: Icons.lock_open,
                    expand: true,
                    isLoading: widget.lock.checking,
                    loadingLabel: l.appLockChecking,
                    onPressed: _unlock,
                  ),
                  if (AuthScope.of(context)?.status == AuthStatus.signedIn)
                    VeloraButton(
                      label: l.appLockSignOutInstead,
                      icon: Icons.logout,
                      variant: VeloraButtonVariant.tertiary,
                      onPressed: _signOut,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// App lock for this build: Android only.
AppLockController? createPlatformAppLock() {
  if (kIsWeb || !Platform.isAndroid) return null;
  return AppLockController(
    authenticator: SystemLockAuthenticator(),
    store: const SecureLockSettingStore(),
  );
}
