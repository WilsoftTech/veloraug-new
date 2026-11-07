import 'package:flutter/services.dart';

import 'oauth_client.dart';

const String _tryAgain = "The sign-in didn't finish. Please try again.";

/// Words a failed sign-in for the person using the app. It never includes a
/// code, token, address or the server's own text.
String signInFailureMessage(Object error) {
  if (error is PlatformException) {
    // flutter_web_auth_2 uses CANCELED when the tab or popup closes without a
    // result, including when the person goes back.
    if (error.code == 'CANCELED') {
      return "Sign-in was cancelled, so you're still signed out.";
    }
    return "The sign-in page couldn't open. Check that a browser is "
        'available, and on the web that pop-ups are allowed, then try again.';
  }
  if (error is OAuthException) {
    return switch (error.kind) {
      OAuthFailure.denied =>
        "You didn't allow VeloraUG to use your account, so you're still "
            'signed out.',
      OAuthFailure.loginRequired =>
        'The sign-in timed out. Press Sign in to start again.',
      OAuthFailure.network =>
        "VeloraUG couldn't reach the sign-in service. Check your connection "
            'and try again.',
      OAuthFailure.wrongCallback ||
      OAuthFailure.stateMismatch ||
      OAuthFailure.wrongIssuer ||
      OAuthFailure.nonceMismatch =>
        "The sign-in couldn't be verified, so it was stopped. Please try "
            'again.',
      OAuthFailure.refused ||
      OAuthFailure.grantRefused ||
      OAuthFailure.badReply => _tryAgain,
    };
  }
  return _tryAgain;
}

const String sessionEndedMessage =
    'Your sign-in has ended. Sign in again to continue.';

const String signedOutMessage = "You're signed out.";

const String signedOutOfflineMessage =
    "You're signed out on this device. VeloraUG couldn't reach the sign-in "
    'service, so the browser may still remember you. On a shared device, sign '
    'in and out again when you are online.';

const String signedOutBrowserKeptMessage =
    "You're signed out on this device, but the browser sign-out didn't "
    'finish, so the browser may still remember you. On a shared device, sign '
    'in and out again.';
