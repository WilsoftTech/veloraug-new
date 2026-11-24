import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Debug-only tools, left out of release builds, keep their English.
const _debugOnly = {
  'lib/showcase/design_system_showcase.dart',
  'lib/showcase/showcase_gate.dart',
  'lib/widgets/dev_connection_check.dart',
  'lib/widgets/dev_token_checks.dart',
};

/// The development tools heading on the Account screen, shown in debug
/// builds only.
const _allowed = {"label: 'Debug builds only'", "'Development tools'"};

/// Visible text given as a literal: Text('Watch'), label: 'Watch', and so on.
final _visibleLiteral = RegExp(
  r'''(Text|label|title|message|tooltip|semanticsLabel|semanticLabel|helperText|labelText|hintText|loadingLabel|retryLabel)(:\s*|\(\s*)'[A-Z][^']*' ''',
);

void main() {
  test('every visible string comes from app_en.arb', () {
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      final path = file.path.replaceAll(r'\', '/');
      if (file is! File ||
          !path.endsWith('.dart') ||
          path.startsWith('lib/l10n/') ||
          _debugOnly.contains(path)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        final match = _visibleLiteral.firstMatch('$line ');
        if (match == null) continue;
        if (_allowed.any(line.contains)) continue;
        found.add('$path:${i + 1}: ${line.trim()}');
      }
    }
    expect(found, isEmpty);
  });

  test('every message has a description or placeholders checked', () {
    final arb = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, Object?>;
    for (final MapEntry(:key, :value) in arb.entries) {
      if (key.startsWith('@')) continue;
      final text = value as String;
      // gen-l10n checks plural messages itself.
      if (text.contains(', plural,')) continue;
      final meta = arb['@$key'] as Map<String, Object?>?;
      final placeholders = (meta?['placeholders'] as Map?)?.keys ?? const [];
      for (final name in RegExp(r'\{(\w+)').allMatches(text).map((m) => m[1])) {
        expect(placeholders, contains(name), reason: '$key uses {$name}');
      }
    }
  });
}
