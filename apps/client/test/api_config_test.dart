import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/api/api_config.dart';

void main() {
  test('the default address is the local API', () {
    expect(apiBaseUrlSetting, 'http://127.0.0.1:8000');
  });

  for (final value in [
    'http://127.0.0.1:8000',
    'http://127.0.0.1:8000/',
    'http://localhost:8000',
    'https://api.example.com',
    'https://api.example.com:8443',
  ]) {
    test('accepts $value', () {
      expect(parseApiBaseUrl(value).host, isNotEmpty);
    });
  }

  for (final value in [
    '',
    'not a url',
    '127.0.0.1:8000',
    'ftp://127.0.0.1:8000',
    'http://',
    'http://127.0.0.1:8000/api',
    'http://127.0.0.1:8000?x=1',
    'http://127.0.0.1:8000#top',
    'https://user:secret@api.example.com',
    'http://api.example.com',
    'http://192.168.1.100:8000',
  ]) {
    test('rejects "$value"', () {
      expect(() => parseApiBaseUrl(value), throwsFormatException);
    });
  }

  test('the default media gateway is the local Worker', () {
    expect(mediaBaseUrlSetting, 'http://127.0.0.1:8787');
    expect(parseMediaBaseUrl(mediaBaseUrlSetting).port, 8787);
  });

  test('the media gateway follows the same rules, and names itself', () {
    expect(
      () => parseMediaBaseUrl('http://media.example.com'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          startsWith('MEDIA_BASE_URL must use https'),
        ),
      ),
    );
    expect(
      parseMediaBaseUrl('https://veloraug-media-dev.example.workers.dev').host,
      'veloraug-media-dev.example.workers.dev',
    );
  });
}
