import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../admin/admin_screen.dart';
import '../api/admin_api.dart';
import '../auth/auth_controller.dart';
import '../downloads/downloads.dart';
import '../l10n/l10n.dart';
import '../screens/account_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/filter_screen.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';

/// Screens at least this wide use a side rail. Narrower ones use a bottom bar.
const double wideLayoutBreakpoint = VeloraLayout.mediumBreakpoint;

/// The admin screens are on the web only in the first release.
const bool adminScreensAvailable = kIsWeb;

/// Each place in the main menu, by a stable identity: entries that come and
/// go, such as Downloads and Admin, never shift which one is chosen.
enum AppDestination { home, search, filter, downloads, account, admin }

class _Destination {
  const _Destination(
    this.id,
    this.label,
    this.icon,
    this.selectedIcon,
    this.screen,
  );

  final AppDestination id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

/// Lets screens inside the shell move to another of its destinations, such
/// as Home's shortcuts to Search and Downloads.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.available,
    required this.select,
    required super.child,
  });

  /// The destinations showing now.
  final Set<AppDestination> available;

  /// Shows a destination if it is available. Answers whether it was.
  final bool Function(AppDestination destination) select;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) =>
      !setEquals(available, oldWidget.available);
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.showAdmin = adminScreensAvailable});

  /// Whether this build may show the Admin entry at all. Tests set it.
  final bool showAdmin;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _selected = AppDestination.home;
  bool _openedFilter = false;

  AuthController? _auth;
  AdminApi? _adminApi;

  /// True once the API has said this person is an admin.
  bool _isAdmin = false;

  /// Whether downloads are listed in the menu: on Android only. Browsers
  /// list their own.
  bool _hasDownloads = false;

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
      return;
    }
    final who = auth.accountKey ?? '';
    if (_checkedFor == who) return;
    _checkedFor = who;
    // A different person: not an admin until the API says so.
    _isAdmin = false;
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
        _selected = AppDestination.admin;
      }
    });
  }

  Set<AppDestination> get _available => {
    AppDestination.home,
    AppDestination.search,
    AppDestination.filter,
    if (_hasDownloads) AppDestination.downloads,
    AppDestination.account,
    if (_isAdmin) AppDestination.admin,
  };

  bool _selectIfAvailable(AppDestination destination) {
    if (!_available.contains(destination)) return false;
    setState(() => _selected = destination);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Downloads are set up a moment after launch, without a sign-in.
    _hasDownloads = DownloadsScope.peek(context)?.followed ?? false;
    final isWide = MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint;
    final destinations = [
      _Destination(
        AppDestination.home,
        l.home,
        Icons.home_outlined,
        Icons.home,
        const HomeScreen(),
      ),
      _Destination(
        AppDestination.search,
        l.search,
        Icons.search_outlined,
        Icons.search,
        const SearchScreen(),
      ),
      _Destination(
        AppDestination.filter,
        l.filter,
        Icons.tune_outlined,
        Icons.tune,
        const FilterScreen(),
      ),
      if (_hasDownloads)
        _Destination(
          AppDestination.downloads,
          l.downloads,
          Icons.download_for_offline_outlined,
          Icons.download_for_offline,
          const DownloadsScreen(),
        ),
      _Destination(
        AppDestination.account,
        l.account,
        Icons.person_outline,
        Icons.person,
        const AccountScreen(),
      ),
      if (_isAdmin)
        _Destination(
          AppDestination.admin,
          l.admin,
          Icons.admin_panel_settings_outlined,
          Icons.admin_panel_settings,
          const AdminScreen(),
        ),
    ];
    var selected = destinations.indexWhere((d) => d.id == _selected);
    if (selected < 0) {
      // The chosen entry has gone, such as Admin after signing out.
      _selected = AppDestination.home;
      selected = 0;
    }
    if (_selected == AppDestination.filter) _openedFilter = true;
    void select(int index) =>
        setState(() => _selected = destinations[index].id);

    return ShellScope(
      available: _available,
      select: _selectIfAvailable,
      child: Scaffold(
        appBar: AppBar(title: const VeloraWordmark()),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide) ...[
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: select,
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
                const VerticalDivider(width: VeloraStroke.hairline),
              ],
              // IndexedStack keeps hidden screens alive, so search text and
              // filter choices survive changing screen, and it keeps them out
              // of the Tab order. Each screen is keyed by its destination, so
              // one added or removed beside it never replaces its state.
              Expanded(
                child: IndexedStack(
                  index: selected,
                  children: [
                    for (final destination in destinations)
                      KeyedSubtree(
                        key: ValueKey(destination.id),
                        child:
                            destination.id == AppDestination.filter &&
                                !_openedFilter
                            ? const SizedBox.shrink()
                            : destination.screen,
                      ),
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
                onDestinationSelected: select,
                destinations: [
                  for (final destination in destinations)
                    NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: destination.label,
                    ),
                ],
              ),
      ),
    );
  }
}
