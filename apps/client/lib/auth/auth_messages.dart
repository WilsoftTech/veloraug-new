import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'oauth_client.dart';

/// The last sign-in or sign-out outcome. The Account screen words it, so
/// the controller holds no text and the words can be translated.
enum AuthNotice {
  cancelled(isError: true),
  browserFailed(isError: true),
  denied(isError: true),
  timedOut(isError: true),
  network(isError: true),
  unverified(isError: true),
  tryAgain(isError: true),
  sessionEnded(isError: false),
  signedOut(isError: false),
  signedOutOffline(isError: true),
  signedOutBrowserKept(isError: true);

  const AuthNotice({required this.isError});

  final bool isError;
}

/// What a failed sign-in means for the person using the app. It never
/// carries a code, token, address or the server's own text.
AuthNotice signInFailureNotice(Object error) {
  if (error is PlatformException) {
    // flutter_web_auth_2 uses CANCELED when the tab or popup closes without a
    // result, including when the person goes back.
    return error.code == 'CANCELED'
        ? AuthNotice.cancelled
        : AuthNotice.browserFailed;
  }
  if (error is OAuthException) {
    return switch (error.kind) {
      OAuthFailure.denied => AuthNotice.denied,
      OAuthFailure.loginRequired => AuthNotice.timedOut,
      OAuthFailure.network => AuthNotice.network,
      OAuthFailure.wrongCallback ||
      OAuthFailure.stateMismatch ||
      OAuthFailure.wrongIssuer ||
      OAuthFailure.nonceMismatch => AuthNotice.unverified,
      OAuthFailure.refused ||
      OAuthFailure.grantRefused ||
      OAuthFailure.badReply => AuthNotice.tryAgain,
    };
  }
  return AuthNotice.tryAgain;
}

String authNoticeMessage(AppLocalizations l, AuthNotice notice) =>
    switch (notice) {
      AuthNotice.cancelled => l.signInCancelled,
      AuthNotice.browserFailed => l.signInBrowserFailed,
      AuthNotice.denied => l.signInDenied,
      AuthNotice.timedOut => l.signInTimedOut,
      AuthNotice.network => l.signInNetwork,
      AuthNotice.unverified => l.signInUnverified,
      AuthNotice.tryAgain => l.signInTryAgain,
      AuthNotice.sessionEnded => l.sessionEnded,
      AuthNotice.signedOut => l.signedOutNotice,
      AuthNotice.signedOutOffline => l.signedOutOffline,
      AuthNotice.signedOutBrowserKept => l.signedOutBrowserKept,
    };
