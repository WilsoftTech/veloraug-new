import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/admin/category_input.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/theme/velora_theme.dart';

import 'admin_screens_test.dart' show adminApi, body, edition, openDraft;
import 'support.dart';

const known = ['Indian', 'Nollywood', 'Korean', 'Kids', 'Action Classics'];

/// The input alone, keeping what it saves, as the draft screen does.
class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.saved});

  final List<String> initial;
  final List<List<String>> saved;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String> _categories = widget.initial;

  @override
  Widget build(BuildContext context) => CategoryInput(
    categories: _categories,
    suggestions: known,
    onChanged: (names) {
      widget.saved.add(names);
      setState(() => _categories = names);
    },
  );
}

Future<List<List<String>>> pumpInput(
  WidgetTester tester, {
  List<String> initial = const [],
  double textScale = 1,
  double width = 600,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  final saved = <List<String>>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildVeloraTheme(),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _Host(initial: initial, saved: saved),
        ),
      ),
    ),
  );
  return saved;
}

final field = find.byKey(const ValueKey('category-field'));

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> enter(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

List<String> chips(WidgetTester tester) => [
  for (final chip in tester.widgetList<InputChip>(find.byType(InputChip)))
    (chip.label as Text).data!,
];

void main() {
  group('the chip input', () {
    testWidgets('Enter adds what was typed', (tester) async {
      final saved = await pumpInput(tester);
      expect(find.text('No categories yet.'), findsOneWidget);

      await type(tester, '  Bollywood   Hits ');
      await enter(tester);

      expect(saved, [
        ['Bollywood Hits'],
      ]);
      expect(chips(tester), ['Bollywood Hits']);
      expect(find.text('1 of 10'), findsOneWidget);
      // Ready for the next one.
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '',
      );
    });

    testWidgets('a comma adds each name before it', (tester) async {
      final saved = await pumpInput(tester);

      await type(tester, 'kids, Korean,Bolly');

      expect(saved.last, ['Kids', 'Korean']);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Bolly',
      );
    });

    testWidgets("a known name takes the catalogue's spelling", (tester) async {
      final saved = await pumpInput(tester);

      await type(tester, 'INDIAN');
      await enter(tester);

      expect(saved.last, ['Indian']);
    });

    testWidgets('a repeat is ignored, whatever its case', (tester) async {
      final saved = await pumpInput(tester, initial: ['Indian']);

      await type(tester, 'indian');
      await enter(tester);

      expect(saved, isEmpty);
      expect(chips(tester), ['Indian']);
    });

    testWidgets('suggestions match as you type, and a tap adds one', (
      tester,
    ) async {
      final saved = await pumpInput(tester, initial: ['Kids']);

      await type(tester, 'o');
      await tester.pumpAndSettle();

      // Matching, without the ones already chosen.
      expect(find.byKey(const ValueKey('category-option-Nollywood')), findsOne);
      expect(find.byKey(const ValueKey('category-option-Korean')), findsOne);
      expect(find.byKey(const ValueKey('category-option-Kids')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('category-option-Korean')));
      await tester.pumpAndSettle();
      expect(saved.last, ['Kids', 'Korean']);
    });

    testWidgets('× removes a chip', (tester) async {
      final saved = await pumpInput(tester, initial: ['Indian', 'Kids']);

      await tester.tap(find.byTooltip('Remove Indian'));
      await tester.pumpAndSettle();

      expect(saved.last, ['Kids']);
    });

    testWidgets('Backspace in the empty field removes the last chip', (
      tester,
    ) async {
      final saved = await pumpInput(tester, initial: ['Indian', 'Kids']);
      await tester.tap(field);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(saved.last, ['Indian']);
    });

    testWidgets('a name over 40 characters is refused, with why', (
      tester,
    ) async {
      final saved = await pumpInput(tester);

      await type(tester, 'x' * 41);
      await enter(tester);

      expect(saved, isEmpty);
      expect(find.text('A category is at most 40 characters'), findsOneWidget);
      // Corrected, the message goes.
      await type(tester, 'x' * 40);
      expect(find.text('A category is at most 40 characters'), findsNothing);
    });

    testWidgets('at 10 the field is off, and says why', (tester) async {
      await pumpInput(tester, initial: [for (var n = 0; n < 10; n++) 'Tag $n']);

      expect(find.text('10 of 10'), findsOneWidget);
      expect(
        find.text(
          'A title has at most 10 categories. Remove one to add another.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('a comma list past 10 stops with why', (tester) async {
      final saved = await pumpInput(
        tester,
        initial: [for (var n = 0; n < 9; n++) 'Tag $n'],
      );

      await type(tester, 'A, B,');

      expect(saved, isEmpty);
      expect(
        find.text(
          'A title has at most 10 categories. Remove one to add another.',
        ),
        findsOneWidget,
      );
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits 320 pixels at text size $scale', (tester) async {
        await pumpInput(
          tester,
          initial: ['Action Classics', 'Indian', 'Nollywood'],
          textScale: scale,
          width: 320,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('on the draft screen', () {
    FakeApi categoryApi({List<String> categories = const []}) {
      final api = adminApi(
        drafts: [edition('d1')..['categories'] = categories],
      );
      api.admin.addAll({
        'GET /categories': (_) => json([
          for (final (i, name) in known.indexed)
            {
              'id': 'c$i',
              'name': name,
              'slug': name.toLowerCase(),
              'editions': 0,
            },
        ]),
        'PUT /editions/d1/categories': (request) {
          final names = (jsonDecode(request.body) as Map)['names'] as List;
          return json(edition('d1')..['categories'] = names);
        },
      });
      return api;
    }

    testWidgets('shows the categories and saves each change', (tester) async {
      final api = categoryApi(categories: ['Kids']);
      await openDraft(tester, api, 'Fast X');

      expect(find.text('Categories'), findsOneWidget);
      expect(chips(tester), ['Kids']);

      await tester.ensureVisible(field);
      await type(tester, 'indian');
      await enter(tester);

      expect(body(api, '/editions/d1/categories'), {
        'names': ['Kids', 'Indian'],
      });
      expect(chips(tester), ['Kids', 'Indian']);
      expect(find.text('Categories saved'), findsOneWidget);
    });

    testWidgets('without suggestions, names can still be typed', (
      tester,
    ) async {
      final api = categoryApi()..admin.remove('GET /categories');
      await openDraft(tester, api, 'Fast X');

      await tester.ensureVisible(field);
      await type(tester, 'Kids');
      await enter(tester);

      expect(body(api, '/editions/d1/categories'), {
        'names': ['Kids'],
      });
    });

    testWidgets("a refusal is shown and the chips don't change", (
      tester,
    ) async {
      final api = categoryApi(categories: ['Kids']);
      api.admin['PUT /editions/d1/categories'] = (_) =>
          json({'detail': 'A title has at most 10 categories'}, 400);
      await openDraft(tester, api, 'Fast X');

      await tester.ensureVisible(field);
      await type(tester, 'Korean');
      await enter(tester);

      expect(
        find.textContaining('A title has at most 10 categories'),
        findsOneWidget,
      );
      expect(chips(tester), ['Kids']);
    });
  });
}
