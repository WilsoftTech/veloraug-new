import 'package:flutter/material.dart';

import '../screens/account_screen.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';

/// Screens at least this wide use a side rail. Narrower ones use a bottom bar.
const double wideLayoutBreakpoint = 600;

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

const List<_Destination> _destinations = [
  _Destination('Home', Icons.home_outlined, Icons.home, HomeScreen()),
  _Destination('Search', Icons.search_outlined, Icons.search, SearchScreen()),
  _Destination('Account', Icons.person_outline, Icons.person, AccountScreen()),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  void _select(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint;

    return Scaffold(
      appBar: AppBar(title: const Text('VeloraUG')),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isWide) ...[
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                scrollable: true,
                destinations: [
                  for (final destination in _destinations)
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
                index: _selectedIndex,
                children: [
                  for (final destination in _destinations) destination.screen,
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _select,
              destinations: [
                for (final destination in _destinations)
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
