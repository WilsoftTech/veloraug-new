import 'package:flutter/material.dart';

import '../../api/account_api.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/edition_cards.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_placeholder.dart';
import '../../widgets/movie_poster.dart';
import '../../widgets/screen_body.dart';
import '../edition_screen.dart' show openPlayer;
import 'account_pages.dart';

AccountPage watchListPage(BuildContext context) => AccountPage(
  title: context.l10n.watchListTitle,
  builder: (_) => const _WatchList(),
);

class _WatchList extends StatefulWidget {
  const _WatchList();

  @override
  State<_WatchList> createState() => _WatchListState();
}

class _WatchListState extends State<_WatchList> {
  List<SavedItem>? _items;
  AccountFailure? _failure;
  final _removing = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final api = accountApiOf(context);
    setState(() {
      _items = null;
      _failure = api == null ? AccountFailure.unreachable : null;
    });
    if (api == null) return;
    try {
      final items = await api.watchList();
      if (mounted) setState(() => _items = items);
    } on AccountException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  Future<void> _remove(SavedItem item) async {
    final api = accountApiOf(context);
    if (api == null || _removing.contains(item.itemId)) return;
    setState(() => _removing.add(item.itemId));
    try {
      await api.setWatchListItem(item.itemId, saved: false);
      if (mounted) setState(() => _items?.remove(item));
    } on AccountException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accountFailureMessage(context.l10n, error.failure)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _removing.remove(item.itemId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ScreenBody(
      heading: l.watchListTitle,
      children: switch ((_items, _failure)) {
        (_, final AccountFailure failure) => [
          ErrorState(
            title: l.watchListLoadFailed,
            message: accountFailureMessage(l, failure),
            onRetry: _load,
          ),
        ],
        (null, _) => [
          VeloraLoadingRegion(
            label: l.loading,
            child: const VeloraSkeleton(height: 72),
          ),
        ],
        (final items?, _) when items.isEmpty => [
          EmptyState(
            icon: Icons.bookmark_border,
            title: l.watchListEmpty,
            message: l.watchListEmptyHelp,
          ),
        ],
        (final items?, _) => [
          for (final item in items)
            Card.outlined(
              key: ValueKey(item.itemId),
              child: ListTile(
                leading: SizedBox(
                  width: VeloraLayout.thumbWidth,
                  child: MoviePoster(url: item.edition.posterUrl),
                ),
                title: Text(item.title(l)),
                subtitle: Text(item.episodeTitle ?? item.edition.label),
                onTap: () async {
                  await openEdition(context, item.edition);
                  if (mounted) await _load();
                },
                trailing: Wrap(
                  spacing: VeloraSpacing.xxs,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline),
                      tooltip: l.watch,
                      onPressed: () => openPlayer(
                        context,
                        itemId: item.itemId,
                        title: item.title(l),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_remove_outlined),
                      tooltip: l.watchListRemove,
                      onPressed: _removing.contains(item.itemId)
                          ? null
                          : () => _remove(item),
                    ),
                  ],
                ),
              ),
            ),
        ],
      },
    );
  }
}
