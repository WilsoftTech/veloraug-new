import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'drafts_view.dart';
import 'library_view.dart';
import 'settings_view.dart';
import 'subscriptions_view.dart';
import 'uploads/uploads_view.dart';
import 'vjs_view.dart';

/// The admin screens: drafts and editions, uploads, the library of
/// published titles, VJs, subscriptions
/// and settings. Shown only to
/// admins, on the web. Every route they call checks again on the server.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            // The theme aligns tabs to the start, which needs this.
            isScrollable: true,
            tabs: [
              Tab(text: l.adminDrafts),
              Tab(text: l.adminUploads),
              Tab(text: l.adminLibrary),
              Tab(text: l.adminVjs),
              Tab(text: l.adminSubscriptions),
              Tab(text: l.adminSettings),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                DraftsView(),
                UploadsView(),
                LibraryView(),
                VjsView(),
                SubscriptionsView(),
                SettingsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
