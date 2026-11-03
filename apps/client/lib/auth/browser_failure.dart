import 'package:flutter/services.dart';

final RegExp _safeCode = RegExp(r'^[A-Za-z0-9_.-]{1,40}$');

// Fixed text in flutter_web_auth_2 5.1.0. Anything else may quote an address or
// intent, so it is withheld rather than filtered.
const Map<String, String> _knownMessages = {
  'User canceled authentication':
      'the browser tab closed with no callback (Auth Tab RESULT_CANCELED)',
  'User canceled login':
      'the app resumed while no result had arrived (resume clean-up)',
  'Authentication returned no URI':
      'the browser reported success without an address',
  'No valid browser available for authentication.':
      'no browser could be launched',
  'Selected browser cannot be accessed for authentication.':
      'the selected browser refused the launch',
  'Authentication session was lost, likely because the app was killed in the '
          'background. Please try again.':
      'the app process died during the browser step',
};

final RegExp _authTabResult = RegExp(
  r'^Authentication failed with code: (-?\d+)$',
);

// androidx.browser AuthTabIntent result codes.
const Map<int, String> _authTabResults = {
  2: 'Digital Asset Links verification failed',
  3: 'Digital Asset Links verification timed out',
  -2: 'Auth Tab reported an unknown error',
};

/// Describes a failed browser step for recording, using only the plugin's code
/// and fixed messages. It never includes an address, query, details or stack.
List<String> describeBrowserFailure(PlatformException error) {
  final code = _safeCode.hasMatch(error.code) ? error.code : 'unrecognised';
  final message = error.message;
  final meaning = _knownMessages[message];
  final authTabResult = _authTabResult.firstMatch(message ?? '')?.group(1);

  final String explanation;
  if (meaning != null) {
    explanation = meaning;
  } else if (authTabResult != null) {
    final known = _authTabResults[int.parse(authTabResult)];
    explanation =
        'Auth Tab result $authTabResult: ${known ?? 'not recognised'}';
  } else {
    explanation = message == null ? 'no message' : 'message withheld';
  }
  return [
    'PlatformException code: $code',
    'meaning: $explanation',
    'native details present: ${error.details != null}',
  ];
}
