import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/auth/browser_failure.dart';

String _describe(String code, {String? message, Object? details}) =>
    describeBrowserFailure(
      PlatformException(code: code, message: message, details: details),
    ).join('\n');

void main() {
  test('separates a closed tab from the resume clean-up', () {
    final closed = _describe(
      'CANCELED',
      message: 'User canceled authentication',
    );
    final resumed = _describe('CANCELED', message: 'User canceled login');
    expect(closed, contains('closed with no callback'));
    expect(resumed, contains('resume clean-up'));
  });

  test('names launch failures', () {
    expect(
      _describe(
        'NO_BROWSER',
        message: 'No valid browser available for authentication.',
      ),
      contains('no browser could be launched'),
    );
    expect(
      _describe(
        'SECURITY_EXCEPTION',
        message: 'Selected browser cannot be accessed for authentication.',
      ),
      contains('refused the launch'),
    );
  });

  test('names Auth Tab callback verification results', () {
    expect(
      _describe('FAILED', message: 'Authentication failed with code: 2'),
      contains('verification failed'),
    );
    expect(
      _describe('FAILED', message: 'Authentication failed with code: 3'),
      contains('timed out'),
    );
    expect(
      _describe('FAILED', message: 'Authentication failed with code: 99'),
      contains('Auth Tab result 99: not recognised'),
    );
  });

  test('never repeats an unknown message, details or code', () {
    const secret = 'https://pages.test/cb?code=SECRET&state=SECRET';
    final text = _describe(
      'https://x?code=SECRET',
      message: 'Intent failed: $secret',
      details: secret,
    );
    expect(text, isNot(contains('SECRET')));
    expect(text, contains('code: unrecognised'));
    expect(text, contains('message withheld'));
    expect(text, contains('native details present: true'));
  });
}
