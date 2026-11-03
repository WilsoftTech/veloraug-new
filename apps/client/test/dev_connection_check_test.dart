import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/widgets/dev_connection_check.dart';

const _baseUrl = 'http://127.0.0.1:8000';
const _serviceInfoBody =
    '{"service":"veloraug-api","api_version":"v1","environment":"development"}';

http.Response _healthyReply(http.Request request) {
  return request.url.path == '/health'
      ? http.Response('{"status":"ok"}', 200)
      : http.Response(_serviceInfoBody, 200);
}

Future<void> _pumpCheck(
  WidgetTester tester,
  http.Client client, {
  String baseUrl = _baseUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DevConnectionCheck(baseUrl: baseUrl, httpClient: client),
        ),
      ),
    ),
  );
}

Future<void> _tapAndFinish(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sends nothing until asked', (tester) async {
    var requests = 0;
    await _pumpCheck(
      tester,
      MockClient((request) async {
        requests++;
        return _healthyReply(request);
      }),
    );
    await tester.pump(const Duration(seconds: 10));

    expect(requests, 0);
    expect(find.text('Development only: API connection check'), findsOneWidget);
    expect(find.text('API address: $_baseUrl'), findsOneWidget);
    expect(find.text('Check connection'), findsOneWidget);
  });

  testWidgets('shows loading, then success with honest scope', (tester) async {
    final gate = Completer<void>();
    await _pumpCheck(
      tester,
      MockClient((request) async {
        await gate.future;
        return _healthyReply(request);
      }),
    );

    await tester.tap(find.text('Check connection'));
    await tester.pump();

    expect(find.text('Checking the API…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('The API answered'), findsOneWidget);
    expect(find.textContaining('Service: veloraug-api'), findsOneWidget);
    expect(find.textContaining('Environment: development'), findsOneWidget);
    expect(
      find.textContaining(
        'It does not check sign-in, payments, a database or production '
        'readiness.',
      ),
      findsOneWidget,
    );
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('calls /health and then /api/v1', (tester) async {
    final paths = <String>[];
    await _pumpCheck(
      tester,
      MockClient((request) async {
        paths.add(request.url.path);
        return _healthyReply(request);
      }),
    );

    await _tapAndFinish(tester, 'Check connection');

    expect(paths, ['/health', '/api/v1']);
  });

  testWidgets('a second tap while loading sends no duplicate requests', (
    tester,
  ) async {
    final gate = Completer<void>();
    var requests = 0;
    await _pumpCheck(
      tester,
      MockClient((request) async {
        requests++;
        await gate.future;
        return _healthyReply(request);
      }),
    );

    await tester.tap(find.text('Check connection'));
    await tester.pump();
    await tester.tap(find.text('Checking…'), warnIfMissed: false);
    await tester.pump();

    expect(requests, 1);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  testWidgets('an unavailable server fails, and retry can then succeed', (
    tester,
  ) async {
    var serverUp = false;
    await _pumpCheck(
      tester,
      MockClient((request) async {
        if (!serverUp) {
          throw http.ClientException('refused');
        }
        return _healthyReply(request);
      }),
    );

    await _tapAndFinish(tester, 'Check connection');

    expect(find.text('The check failed'), findsOneWidget);
    expect(find.textContaining('Could not reach /health'), findsOneWidget);
    expect(find.textContaining('adb reverse tcp:8000'), findsOneWidget);
    expect(find.text('The API answered'), findsNothing);

    serverUp = true;
    await _tapAndFinish(tester, 'Try again');

    expect(find.text('The API answered'), findsOneWidget);
    expect(find.text('The check failed'), findsNothing);
  });

  testWidgets('a server that never answers times out after 5 seconds', (
    tester,
  ) async {
    await _pumpCheck(
      tester,
      MockClient((_) => Completer<http.Response>().future),
    );

    await tester.tap(find.text('Check connection'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Checking the API…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('The check failed'), findsOneWidget);
    expect(find.textContaining('within 5 seconds'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final (name, health, info) in [
    ('malformed health', 'oops', _serviceInfoBody),
    ('a server error', '{"status":"ok"}', null),
    ('malformed service info', '{"status":"ok"}', '{"service":"other"}'),
  ]) {
    testWidgets('$name shows a failure, not a crash', (tester) async {
      await _pumpCheck(
        tester,
        MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response(health, 200);
          }
          return info == null
              ? http.Response('', 500)
              : http.Response(info, 200);
        }),
      );

      await _tapAndFinish(tester, 'Check connection');

      expect(tester.takeException(), isNull);
      expect(find.text('The check failed'), findsOneWidget);
      expect(find.text('The API answered'), findsNothing);
    });
  }

  testWidgets('an invalid address fails without sending a request', (
    tester,
  ) async {
    var requests = 0;
    await _pumpCheck(
      tester,
      MockClient((request) async {
        requests++;
        return _healthyReply(request);
      }),
      baseUrl: 'http://192.168.1.100:8000',
    );

    await _tapAndFinish(tester, 'Check connection');

    expect(requests, 0);
    expect(find.text('The check failed'), findsOneWidget);
    expect(find.textContaining('must use https'), findsOneWidget);
    expect(find.textContaining('adb reverse'), findsNothing);
  });

  testWidgets('a reply after the widget is removed is safely ignored', (
    tester,
  ) async {
    final gate = Completer<void>();
    var requests = 0;
    await _pumpCheck(
      tester,
      MockClient((request) async {
        requests++;
        await gate.future;
        return _healthyReply(request);
      }),
    );

    await tester.tap(find.text('Check connection'));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(requests, 1, reason: 'the /api/v1 request should not be sent');
  });

  testWidgets('every state fits a small screen with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    var serverUp = false;
    await _pumpCheck(
      tester,
      MockClient((request) async {
        if (!serverUp) {
          throw http.ClientException('refused');
        }
        return _healthyReply(request);
      }),
    );

    await _tapAndFinish(tester, 'Check connection');
    expect(tester.takeException(), isNull);

    serverUp = true;
    await _tapAndFinish(tester, 'Try again');
    expect(tester.takeException(), isNull);
  });

  testWidgets('result states meet accessibility guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpCheck(
      tester,
      MockClient((_) => throw http.ClientException('x')),
    );

    await _tapAndFinish(tester, 'Check connection');

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });
}
