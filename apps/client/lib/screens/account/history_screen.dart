import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/account_api.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/edition_cards.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_placeholder.dart';
import '../../widgets/movie_poster.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/velora_button.dart';
import '../player_screen.dart';
import 'account_pages.dart';

AccountPage historyPage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.historyTitle,
    builder: (context) => const HistoryBody(),
  );
}

/// "24 Nov 2026, 14:05" in the viewer's locale.
String formatWhen(BuildContext context, DateTime at) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_Hm().format(at.toLocal());
}

/// What the viewer watched on any device, latest first, from their account.
/// Downloads played in the phone's own player aren't included: VeloraUG
/// can't see them.
class HistoryBody extends StatefulWidget {
  const HistoryBody({super.key});

  @override
  State<HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends State<HistoryBody> {
  List<HistoryEntry>? _entries;
  AccountFailure? _failure;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final api = accountApiOf(context);
    setState(() {
      _failure = api == null ? AccountFailure.unreachable : null;
      _entries = null;
    });
    if (api == null) return;
    try {
      final entries = await api.history();
      if (mounted) setState(() => _entries = entries);
    } on AccountException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entries = _entries;
    final failure = _failure;
    return RefreshIndicator(
      onRefresh: _load,
      child: ScreenBody(
        heading: l.historyTitle,
        intro: l.historyIntro,
        children: [
          if (failure != null)
            ErrorState(
              title: l.historyLoadFailed,
              message: accountFailureMessage(l, failure),
              onRetry: _load,
            )
          else if (entries == null)
            VeloraLoadingRegion(
              label: l.loading,
              child: const Column(
                spacing: VeloraSpacing.sm,
                children: [
                  VeloraSkeleton(height: 72),
                  VeloraSkeleton(height: 72),
                  VeloraSkeleton(height: 72),
                ],
              ),
            )
          else if (entries.isEmpty)
            EmptyState(
              icon: Icons.history,
              title: l.historyEmptyTitle,
              message: l.historyEmptyMessage,
            )
          else
            for (final entry in entries)
              _HistoryTile(key: ValueKey(entry.itemId), entry: entry),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final edition = entry.edition;
    final title = entry.isEpisode
        ? l.episodeHeading(edition.title, entry.season!, entry.episode!)
        : edition.title;
    final resume = entry.resumeAt;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openEdition(context, edition),
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.sm),
          child: Row(
            spacing: VeloraSpacing.sm,
            children: [
              SizedBox(
                width: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VeloraRadii.sm),
                  child: MoviePoster(url: edition.posterUrl),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: VeloraSpacing.xxs,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if (entry.episodeTitle case final name?)
                      Text(name, style: muted),
                    Text(edition.label, style: muted),
                    Text(
                      l.watchedAt(formatWhen(context, entry.lastWatchedAt)),
                      style: muted,
                    ),
                  ],
                ),
              ),
              if (resume != null)
                VeloraButton(
                  label: l.resume,
                  icon: Icons.play_arrow,
                  variant: VeloraButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        itemId: entry.itemId,
                        title: edition.title,
                        startAt: resume,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
