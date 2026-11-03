import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A URL-safe random value holding [byteCount] random bytes.
String randomUrlSafe([int byteCount = 32]) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The S256 PKCE challenge for [verifier] (RFC 7636).
String pkceS256Challenge(String verifier) {
  final digest = sha256.convert(ascii.encode(verifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}
