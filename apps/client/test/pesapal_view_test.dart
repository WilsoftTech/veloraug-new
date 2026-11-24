import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/screens/pesapal_view.dart';

void main() {
  test('only the API\'s return address counts as coming back', () {
    for (final url in [
      'https://api.veloraug.test/api/v1/passes/return?OrderTrackingId=abc',
      'http://10.0.2.2:8000/api/v1/passes/return',
    ]) {
      expect(isReturnAddress(Uri.parse(url)), isTrue, reason: url);
    }
    for (final url in [
      'https://pay.pesapal.com/iframe/PesapalIframe3/Index?OrderTrackingId=abc',
      'https://pay.pesapal.com/api/v1/passes/return',
      'https://pesapal.com/api/v1/passes/return',
      'https://api.veloraug.test/api/v1/passes/ipn',
      'https://bank.example/3ds/challenge',
    ]) {
      expect(isReturnAddress(Uri.parse(url)), isFalse, reason: url);
    }
  });
}
