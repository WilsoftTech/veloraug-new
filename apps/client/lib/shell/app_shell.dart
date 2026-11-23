import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../admin/admin_screen.dart';
import '../api/admin_api.dart';
import '../auth/auth_controller.dart';
import '../downloads/download_manager.dart';
import '../l10n/l10n.dart';
import '../screens/account_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';

/// Screens at least this wide use a side rail. Narrower ones use a bottom bar.
const double wideLayoutBreakpoint = VeloraLayout.mediumBreakpoint;

/// The admin screens are on the web only in the first release.
const bool adminScreensAvailable = kIsWeb;

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.showAdmin = adminScreensAvailable});

  /// Whether this build may show the Admin entry at all. Tests set it.
  final bool showAdmin;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  AuthController? _auth;
  AdminApi? _adminApi;

  /// True once the API has said this person is an admin.
  bool _isAdmin = false;

  /// Whether this phone keeps downloads: Android only.
  bool _hasDownloads = false;

  /// Home, Search, Downloads where kept, and Account. Admin comes after.
  int get _viewerTabs => _hasDownloads ? 4 : 3;

  /// Who [_isAdmin] was checked for, so a change of person checks again.
  String? _checkedFor;
  int _check = 0;

  /// Opening the app at /admin starts on the admin screens, once they show.
  bool _wantsAdmin = WidgetsBinding.instance.platformDispatcher.defaultRouteName
      .startsWith('/admin');

  /// AuthScope notifies its dependents, so this runs on every sign-in or
  /// sign-out too.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.of(context);
    final admin = AdminScope.of(context);
    _syncDownloads();
    if (!identical(admin, _adminApi) || !identical(auth, _auth)) {
      _adminApi = admin;
      _auth = auth;
      _checkedFor = null;
    }
    _checkAdmin();
  }

  void _checkAdmin() {
    final auth = _auth;
    final admin = _adminApi;
    final signedIn = auth != null && auth.status == AuthStatus.signedIn;
    if (!widget.showAdmin || admin == null || !signedIn) {
      // No setState: this runs before a build, which shows the change.
      _checkedFor = null;
      _check++;
      _isAdmin = false;
      if (_selectedIndex >= _viewerTabs) _selectedIndex = 0;
      return;
    }
    final who = auth.email ?? '';
    if (_checkedFor == who) return;
    _checkedFor = who;
    final check = ++_check;
    admin.isAdmin().then(
      (isAdmin) {
        if (mounted && check == _check) _setAdmin(isAdmin);
      },
      onError: (Object _) {
        // Unknown: keep the menu as it was, and check again next time.
        if (check == _check) _checkedFor = null;
      },
    );
  }

  void _setAdmin(bool isAdmin) {
    setState(() {
      _isAdmin = isAdmin;
      if (isAdmin && _wantsAdmin) {
        _wantsAdmin = false;
        _selectedIndex = _viewerTabs;
      }
      if (!isAdmin && _selectedIndex >= _viewerTabs) _selectedIndex = 0;
    });
  }

  /// Downloads are found a moment after launch, on Android. The tab is
  /// added before Account, so whatever was chosen stays chosen.
  void _syncDownloads() {
    final has = DownloadsScope.peek(context) != null;
    if (has == _hasDownloads) return;
    if (_selectedIndex >= 2) _selectedIndex += has ? 1 : -1;
    _hasDownloads = has;
  }

  void _select(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    _syncDownloads();
    final isWide = MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint;
    final destinations = [
      _Destination(l.home, Icons.home_outlined, Icons.home, const HomeScreen()),
      _Destination(
        l.search,
        Icons.search_outlined,
        Icons.search,
        const SearchScreen(),
      ),
      if (_hasDownloads)
        _Destination(
          l.downloads,
          Icons.download_for_offline_outlined,
          Icons.download_for_offline,
          const DownloadsScreen(),
        ),
      _Destination(
        l.account,
        Icons.person_outline,
        Icons.person,
        const AccountScreen(),
      ),
      if (_isAdmin)
        _Destination(
          l.admin,
          Icons.admin_panel_settings_outlined,
          Icons.admin_panel_settings,
          const AdminScreen(),
        ),
    ];
    final selected = _selectedIndex.clamp(0, destinations.length - 1);

    return Scaffold(
      appBar: AppBar(title: const VeloraWordmark()),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isWide) ...[
              NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                scrollable: true,
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
            ],
            // IndexedStack keeps hidden screens alive, so search text survives
            // changing screen, and it keeps them out of the Tab order.
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  for (final destination in destinations) destination.screen,
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              animationDuration: VeloraMotion.of(context, VeloraMotion.slow),
              selectedIndex: selected,
              onDestinationSelected: _select,
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
    );
  }
}
