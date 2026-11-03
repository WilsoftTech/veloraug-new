import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/theme/tokens.dart';
import 'package:veloraug/theme/velora_theme.dart';
import 'package:veloraug/widgets/empty_state.dart';
import 'package:veloraug/widgets/loading_placeholder.dart';
import 'package:veloraug/widgets/movie_card.dart';
import 'package:veloraug/widgets/status_badge.dart';
import 'package:veloraug/widgets/velora_button.dart';
import 'package:veloraug/widgets/velora_search_field.dart';
import 'package:veloraug/widgets/velora_text_field.dart';

Widget _app(Widget child, {double textScale = 1, bool reducedMotion = false}) {
  return MaterialApp(
    theme: buildVeloraTheme(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: app!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: child,
      ),
    ),
  );
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

List<Widget> _cards({VoidCallback? onTap}) => [
  MovieCard(title: 'Demo One', subtitle: 'Demo, 2026', onTap: onTap),
  MovieCard(
    title: 'A very long demonstration title that goes well past two lines',
    subtitle: 'Demo, 2025',
    status: const StatusBadge(label: 'Processing', tone: StatusTone.warning),
    onTap: onTap,
  ),
  MovieCard(title: 'Demo Three', onTap: onTap),
];

final _skeletonFade = find.descendant(
  of: find.byType(VeloraSkeleton),
  matching: find.byType(FadeTransition),
);

void main() {
  group('VeloraButton', () {
    testWidgets('runs its action when pressed', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _app(VeloraButton(label: 'Play', onPressed: () => presses++)),
      );
      await tester.tap(find.text('Play'));
      expect(presses, 1);
    });

    for (final variant in VeloraButtonVariant.values) {
      testWidgets('${variant.name}: loading blocks presses and says so', (
        tester,
      ) async {
        var presses = 0;
        await tester.pumpWidget(
          _app(
            VeloraButton(
              label: 'Play',
              loadingLabel: 'Starting…',
              variant: variant,
              isLoading: true,
              onPressed: () => presses++,
            ),
          ),
        );
        expect(find.text('Starting…'), findsOneWidget);
        expect(find.text('Play'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(find.text('Starting…'), warnIfMissed: false);
        expect(presses, 0);
      });

      testWidgets('${variant.name}: disabled and at least 48 pixels', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            Center(
              child: VeloraButton(
                label: 'Play',
                variant: variant,
                onPressed: null,
              ),
            ),
          ),
        );
        final button = find.byWidgetPredicate((w) => w is ButtonStyleButton);
        expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('expands when asked', (tester) async {
      _setSize(tester, const Size(400, 800));
      await tester.pumpWidget(
        _app(VeloraButton(label: 'Play', expand: true, onPressed: () {})),
      );
      expect(tester.getSize(find.byType(FilledButton)).width, 400 - 32);
    });

    testWidgets('shows a focus border when focused by keyboard', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _app(
          Focus(
            focusNode: focus,
            child: VeloraButton(label: 'Play', onPressed: () {}),
          ),
        ),
      );
      final style = Theme.of(tester.element(find.text('Play')))
          .filledButtonTheme
          .style!;
      expect(
        style.side!.resolve({WidgetState.focused})!.color,
        VeloraColors.focusRing,
      );
      expect(style.side!.resolve({}), isNull);
    });
  });

  group('VeloraTextField', () {
    testWidgets('has a label for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(const VeloraTextField(label: 'Email')));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Email')),
        isSemantics(label: 'Email', isTextField: true),
      );
      semantics.dispose();
    });

    testWidgets('shows a validation error with an icon, then clears it', (
      tester,
    ) async {
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        _app(
          Form(
            key: form,
            child: VeloraTextField(
              label: 'Email',
              validator: (value) =>
                  (value ?? '').contains('@') ? null : 'Include an @.',
            ),
          ),
        ),
      );
      expect(find.text('Include an @.'), findsNothing);

      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Include an @.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a@b');
      await tester.pump();
      expect(find.text('Include an @.'), findsNothing);
      expect(form.currentState!.validate(), isTrue);
    });

    test('a disabled field looks different from an enabled one', () {
      final input = buildVeloraTheme().inputDecorationTheme;
      final fill = input.fillColor! as WidgetStateColor;
      expect(fill.resolve({}), VeloraColors.surface);
      expect(fill.resolve({WidgetState.disabled}), VeloraColors.canvas);
      expect(
        (input.labelStyle! as WidgetStateTextStyle).resolve({
          WidgetState.disabled,
        }).color,
        VeloraColors.textDisabled,
      );
      expect(
        input.disabledBorder!.borderSide.color,
        VeloraColors.outlineSubtle,
      );
    });

    testWidgets('a disabled field cannot be edited', (tester) async {
      await tester.pumpWidget(
        _app(const VeloraTextField(label: 'Email', enabled: false)),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });

  group('VeloraPasswordField', () {
    testWidgets('hides text until asked, with labelled controls', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const VeloraPasswordField()));
      bool obscured() =>
          tester.widget<TextField>(find.byType(TextField)).obscureText;

      expect(obscured(), isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(obscured(), isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(obscured(), isTrue);
    });

    testWidgets('turns off suggestions and correction', (tester) async {
      await tester.pumpWidget(_app(const VeloraPasswordField()));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('a disabled field cannot be revealed', (tester) async {
      await tester.pumpWidget(_app(const VeloraPasswordField(enabled: false)));
      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
    });
  });

  group('VeloraSearchField', () {
    testWidgets('offers Clear only when there is text', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(_app(VeloraSearchField(onChanged: changes.add)));
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'kampala');
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('kampala'), findsNothing);
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(changes, ['kampala', '']);
    });

    testWidgets('submits with the search action', (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        _app(VeloraSearchField(onSubmitted: submitted.add)),
      );
      await tester.enterText(find.byType(TextField), 'kampala');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(submitted, ['kampala']);
    });

    testWidgets('keeps text in a controller the caller supplies', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'kept');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(VeloraSearchField(controller: controller)));
      expect(find.text('kept'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsOneWidget);
    });
  });

  group('MovieCard', () {
    testWidgets('runs its action, and has one spoken description', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 200,
            child: MovieCard(
              title: 'Demo One',
              subtitle: 'Demo, 2026',
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Demo One'));
      expect(taps, 1);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Demo One, Demo, 2026')),
        isSemantics(
          label: 'Demo One, Demo, 2026',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('with no action, it is not offered as a button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const SizedBox(width: 200, child: MovieCard(title: 'Demo One'))),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Demo One'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    });

    testWidgets('uses local artwork at 2:3 and loads no image', (tester) async {
      await tester.pumpWidget(
        _app(const SizedBox(width: 200, child: MovieCard(title: 'Demo One'))),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byType(PosterPlaceholder), findsOneWidget);
      final size = tester.getSize(find.byType(PosterPlaceholder));
      expect(size.width / size.height, closeTo(2 / 3, 0.01));
    });

    testWidgets('keyboard focus changes the border', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 200,
            child: MovieCard(title: 'D', onTap: () {}),
          ),
        ),
      );
      BorderSide border() {
        final box = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        final decoration = box.foregroundDecoration! as BoxDecoration;
        return (decoration.border! as Border).top;
      }

      expect(border().color, VeloraColors.outlineSubtle);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(border().color, VeloraColors.focusRing);
      expect(border().width, VeloraStroke.focus);
    });

    testWidgets('reduced motion removes its animation time', (tester) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(width: 200, child: MovieCard(title: 'D')),
          reducedMotion: true,
        ),
      );
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
    });
  });

  group('MovieCardGrid', () {
    testWidgets('cards in a row share one height', (tester) async {
      _setSize(tester, const Size(1000, 1200));
      await tester.pumpWidget(_app(MovieCardGrid(children: _cards())));
      final heights = tester
          .widgetList<MovieCard>(find.byType(MovieCard))
          .map((card) => tester.getSize(find.byWidget(card)).height)
          .toSet();
      expect(heights, hasLength(1));
    });

    test('fits columns to the width, and at least two', () {
      expect(MovieCardGrid.columnsFor(100, 320), 2);
      expect(MovieCardGrid.columnsFor(288, 320), 2);
      expect(MovieCardGrid.columnsFor(600, 1024), 3);
      expect(MovieCardGrid.columnsFor(1184, 1280), 6);
    });

    for (final (name, size) in const [
      ('small phone', Size(320, 568)),
      ('tablet', Size(768, 1024)),
      ('desktop', Size(1440, 900)),
    ]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('does not overflow on a $name at $scale× text', (
          tester,
        ) async {
          _setSize(tester, size);
          await tester.pumpWidget(
            _app(MovieCardGrid(children: _cards()), textScale: scale),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('loading placeholders', () {
    testWidgets('fade when motion is allowed', (tester) async {
      await tester.pumpWidget(_app(const VeloraSkeleton(height: 20)));
      FadeTransition fade() => tester.widget<FadeTransition>(_skeletonFade);
      final start = fade().opacity.value;
      await tester.pump(const Duration(milliseconds: 300));
      expect(fade().opacity.value, isNot(start));
      // Stays well inside three changes a second, and never fully disappears.
      expect(fade().opacity.value, greaterThanOrEqualTo(0.55));
      expect(VeloraMotion.pulse.inMilliseconds, greaterThanOrEqualTo(1000));
    });

    testWidgets('hold still with reduced motion', (tester) async {
      await tester.pumpWidget(
        _app(const VeloraSkeleton(height: 20), reducedMotion: true),
      );
      final fade = tester.widget<FadeTransition>(_skeletonFade);
      await tester.pump(const Duration(milliseconds: 300));
      expect(fade.opacity.value, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('are named once for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 200,
            child: VeloraLoadingRegion(
              label: 'Loading movies',
              child: MovieCardSkeleton(),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Loading movies'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the spinner holds still with reduced motion', (tester) async {
      await tester.pumpWidget(_app(const VeloraSpinner(), reducedMotion: true));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('empty and error states', () {
    testWidgets('an empty state shows its action', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _app(
          EmptyState(
            icon: Icons.movie_outlined,
            title: 'Nothing',
            message: 'Why.',
            action: VeloraButton(label: 'Next', onPressed: () => presses++),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      expect(presses, 1);
    });

    testWidgets('an error state retries only if it can', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _app(
          ErrorState(
            title: 'Failed',
            message: 'Why.',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(retries, 1);

      await tester.pumpWidget(
        _app(const ErrorState(title: 'Failed', message: 'Why.')),
      );
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('StatusBadge', () {
    for (final tone in StatusTone.values) {
      testWidgets('${tone.name} has words and an icon, not just colour', (
        tester,
      ) async {
        await tester.pumpWidget(_app(StatusBadge(label: 'Status', tone: tone)));
        expect(find.text('Status'), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
      });
    }
  });

  group('guidelines and text size', () {
    Widget everything() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.md,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final variant in VeloraButtonVariant.values)
              VeloraButton(
                label: variant.name,
                variant: variant,
                onPressed: () {},
              ),
            VeloraButton(label: 'Busy', isLoading: true, onPressed: () {}),
          ],
        ),
        const VeloraTextField(label: 'Email', helperText: 'Helper text.'),
        const VeloraPasswordField(),
        const VeloraSearchField(),
        MovieCardGrid(children: _cards(onTap: () {})),
        for (final tone in StatusTone.values)
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(label: 'A status: ${tone.name}', tone: tone),
          ),
        const EmptyState(
          icon: Icons.movie_outlined,
          title: 'Nothing here',
          message: 'A longer explanation of why nothing is here yet.',
        ),
        ErrorState(title: 'That failed', message: 'Why.', onRetry: () {}),
      ],
    );

    for (final (name, size) in const [
      ('narrow', Size(360, 800)),
      ('wide', Size(1200, 800)),
    ]) {
      testWidgets('meets guidelines on a $name screen', (tester) async {
        final semantics = tester.ensureSemantics();
        _setSize(tester, size);
        // Holds the loading button's spinner and placeholders still.
        await tester.pumpWidget(_app(everything(), reducedMotion: true));
        await tester.pump();

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }

    for (final (name, size) in const [
      ('320 pixels', Size(320, 568)),
      ('768 pixels', Size(768, 1024)),
      ('1440 pixels', Size(1440, 900)),
    ]) {
      for (final scale in const [1.0, 1.3, 2.0, 3.0]) {
        testWidgets('all components fit $name at $scale× text', (tester) async {
          _setSize(tester, size);
          await tester.pumpWidget(
            _app(everything(), textScale: scale, reducedMotion: true),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('text grows with the setting instead of being capped', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Align(
            alignment: Alignment.topLeft,
            child: StatusBadge(label: 'Status'),
          ),
        ),
      );
      final normal = tester.getSize(find.text('Status')).height;

      await tester.pumpWidget(
        _app(
          const Align(
            alignment: Alignment.topLeft,
            child: StatusBadge(label: 'Status'),
          ),
          textScale: 2,
        ),
      );
      expect(tester.getSize(find.text('Status')).height, normal * 2);
    });
  });
}
