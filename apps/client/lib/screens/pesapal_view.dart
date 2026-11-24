/// Pesapal's payment page, shown inside VeloraUG so the viewer never leaves
/// the app to pay: an in-app web view on Android, and a sandboxed `<iframe>`
/// on the web.
///
/// The page is Pesapal's own. The viewer types their mobile money number or
/// card on it, so VeloraUG still never sees a PIN or a card number. Neither
/// view decides whether a payment went through: only the API's check does.
library;

import 'package:flutter/widgets.dart';

export 'pesapal_view_io.dart' if (dart.library.js_interop) 'pesapal_view_web.dart';

/// Builds the payment page for [page]. [onReturned] is called once Pesapal
/// sends the viewer back to VeloraUG's return address, where the view can
/// see that: on Android. On the web the app's own checks notice instead.
typedef PesapalViewBuilder = Widget Function(
  BuildContext context,
  Uri page,
  VoidCallback onReturned,
);

/// The API's return address, `/api/v1/passes/return`, where Pesapal sends
/// the viewer after paying. Never a page on Pesapal's own site.
bool isReturnAddress(Uri url) {
  final host = url.host.toLowerCase();
  final onPesapal = host == 'pesapal.com' || host.endsWith('.pesapal.com');
  return !onPesapal && url.path.endsWith('/api/v1/passes/return');
}
