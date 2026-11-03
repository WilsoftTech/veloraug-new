import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/api_client.dart';

const _serviceInfoBody =
    '{"service":"veloraug-api","api_version":"v1","environment":"development"}';

ApiClient _clientReturning(
  String body, {
  int status = 200,
  void Function(http.Request request)? onRequest,
}) {
  return ApiClient(
    baseUrl: Uri.parse('http://127.0.0.1:8000'),
    httpClient: MockClient((request) async {
      onRequest?.call(request);
      return http.Response(body, status);
    }),
  );
}

Matcher _failsWith(ApiFailure failure) => throwsA(
  isA<ApiException>().having((error) => error.failure, 'failure', failure),
);

void main() {
  group('fetchHealth', () {
    test('requests /health and parses the reply', () async {
      Uri? requested;
      final client = _clientReturning(
        '{"status":"ok"}',
        onRequest: (request) => requested = request.url,
      );

      final health = await client.fetchHealth();

      expect(requested.toString(), 'http://127.0.0.1:8000/health');
      expect(health.status, 'ok');
    });

    for (final (name, body) in [
      ('a different status', '{"status":"down"}'),
      ('a missing field', '{}'),
      ('a field of the wrong type', '{"status":1}'),
      ('an empty field', '{"status":""}'),
      ('a JSON list', '["ok"]'),
      ('JSON null', 'null'),
      ('text that is not JSON', 'ok'),
      ('an HTML page', '<html></html>'),
      ('an empty body', ''),
    ]) {
      test('rejects $name', () {
        expect(
          _clientReturning(body).fetchHealth(),
          _failsWith(ApiFailure.badResponse),
        );
      });
    }

    for (final status in [204, 301, 404, 500, 503]) {
      test('rejects HTTP $status even with a valid body', () {
        expect(
          _clientReturning('{"status":"ok"}', status: status).fetchHealth(),
          _failsWith(ApiFailure.badResponse),
        );
      });
    }
  });

  group('fetchServiceInfo', () {
    test('requests /api/v1 and parses the reply', () async {
      Uri? requested;
      final client = _clientReturning(
        _serviceInfoBody,
        onRequest: (request) => requested = request.url,
      );

      final info = await client.fetchServiceInfo();

      expect(requested.toString(), 'http://127.0.0.1:8000/api/v1');
      expect(info.service, 'veloraug-api');
      expect(info.apiVersion, 'v1');
      expect(info.environment, 'development');
    });

    for (final (name, body) in [
      (
        'another service',
        '{"service":"other","api_version":"v1","environment":"development"}',
      ),
      (
        'another API version',
        '{"service":"veloraug-api","api_version":"v2","environment":"x"}',
      ),
      (
        'a missing environment',
        '{"service":"veloraug-api","api_version":"v1"}',
      ),
      ('malformed JSON', '{"service":'),
    ]) {
      test('rejects $name', () {
        expect(
          _clientReturning(body).fetchServiceInfo(),
          _failsWith(ApiFailure.badResponse),
        );
      });
    }
  });

  test('a server that never answers becomes a timeout', () async {
    final client = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:8000'),
      httpClient: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(client.fetchHealth(), _failsWith(ApiFailure.timeout));
  });

  test('the default timeout is finite', () {
    final client = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:8000'),
      httpClient: MockClient((_) async => http.Response('', 200)),
    );

    expect(client.timeout, const Duration(seconds: 5));
  });

  test('an unavailable server becomes a clear failure', () {
    final client = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:8000'),
      httpClient: MockClient((_) => throw http.ClientException('refused')),
    );

    expect(client.fetchHealth(), _failsWith(ApiFailure.unavailable));
  });
}
