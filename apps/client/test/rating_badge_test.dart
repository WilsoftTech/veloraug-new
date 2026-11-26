import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/theme/tokens.dart';
import 'package:veloraug/theme/velora_theme.dart';
import 'package:veloraug/widgets/movie_card.dart';
import 'package:veloraug/widgets/rating_badge.dart';

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  theme: buildVeloraTheme(),
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: app!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(VeloraSpacing.md),
      child: child,
    ),
  ),
);

void main() {
  group('RatingBadge', () {
    testWidgets('shows the score to one decimal and the votes, no logo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const RatingBadge(rating: 7, voteCount: 1234)),
      );

      expect(find.text('7.0'), findsOneWidget);
      expect(find.text('1.23K votes'), findsOneWidget);
      final star = tester.widget<Icon>(find.byIcon(Icons.star_rounded));
      expect(star.color, VeloraColors.rating);
      expect(find.byType(Image), findsNothing);
      expect(
        find.bySemanticsLabel('Rated 7.0 out of 10 on TMDB, from 1,234 votes'),
        findsOneWidget,
      );
    });

    testWidgets('without votes, it reads the score alone', (tester) async {
      await tester.pumpWidget(_app(const RatingBadge(rating: 8.25)));

      expect(find.textContaining('votes'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Rated 8\.[23] out of 10 on TMDB$')),
        findsOneWidget,
      );
    });

    testWidgets('without a rating, it shows nothing at all', (tester) async {
      await tester.pumpWidget(
        _app(const RatingBadge(rating: null, voteCount: 50)),
      );

      expect(find.byType(Icon), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(find.byType(RatingBadge)), Size.zero);
    });
  });

  group('a poster', () {
    testWidgets('shows the rating bottom-right and reads it with the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 160,
            child: MovieCard(
              title: 'Demo One',
              cornerLabel: 'VJ Demo',
              bottomCorner: PosterRating(7.4),
              bottomCornerLabel: 'Rated 7.4 out of 10 on TMDB',
              subtitle: '2023',
            ),
          ),
        ),
      );

      expect(find.text('7.4'), findsOneWidget);
      final poster = tester.getRect(find.byType(PosterPlaceholder));
      final rating = tester.getRect(find.byType(PosterRating));
      final vj = tester.getRect(find.byType(CornerLabel));
      expect(rating.right, closeTo(poster.right - VeloraSpacing.xs, 0.5));
      expect(rating.bottom, closeTo(poster.bottom - VeloraSpacing.xs, 0.5));
      expect(vj.left, closeTo(poster.left + VeloraSpacing.xs, 0.5));
      expect(vj.top, closeTo(poster.top + VeloraSpacing.xs, 0.5));
      expect(
        find.bySemanticsLabel(
          'Demo One, VJ Demo, Rated 7.4 out of 10 on TMDB, 2023',
        ),
        findsOneWidget,
      );
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('a narrow card fits the VJ and the rating at $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            const SizedBox(
              width: 96,
              child: MovieCard(
                title: 'Demo',
                cornerLabel: 'VJ A Very Long Translator Name',
                bottomCorner: PosterRating(9.9),
                dense: true,
              ),
            ),
            textScale: scale,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('9.9'), findsOneWidget);
        // Each keeps its own corner, so neither covers the other.
        final vj = tester.getRect(find.byType(CornerLabel));
        final rating = tester.getRect(find.byType(PosterRating));
        expect(vj.overlaps(rating), isFalse);
      });
    }

    testWidgets('a rating with no VJ sits bottom-right alone', (tester) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 160,
            child: MovieCard(title: 'Demo', bottomCorner: PosterRating(6.5)),
          ),
        ),
      );

      final poster = tester.getRect(find.byType(PosterPlaceholder));
      final rating = tester.getRect(find.byType(PosterRating));
      expect(rating.right, closeTo(poster.right - VeloraSpacing.xs, 0.5));
      expect(rating.bottom, closeTo(poster.bottom - VeloraSpacing.xs, 0.5));
      expect(find.byType(CornerLabel), findsNothing);
    });
  });
}
