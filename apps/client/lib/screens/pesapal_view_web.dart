import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../l10n/l10n.dart';

/// What Pesapal's page may do inside the frame. It can run, keep its
/// session, send its forms, and open a bank's card check in a new window.
/// It can't move VeloraUG itself away: without `allow-top-navigation`,
/// Pesapal's return to the callback address stays blocked, and the app's
/// own checks notice the payment instead.
const frameSandbox =
    'allow-scripts allow-same-origin allow-forms allow-popups '
    'allow-popups-to-escape-sandbox allow-modals';

/// Pesapal's page in an `<iframe>`, inside the app. The web never calls
/// [onReturned]: the frame can't see where Pesapal sends it.
Widget platformPesapalView(
  BuildContext context,
  Uri page,
  VoidCallback onReturned,
) {
  final title = context.l10n.paymentFormLabel;
  return HtmlElementView.fromTagName(
    key: ValueKey(page),
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      frame
        ..src = page.toString()
        ..title = title
        ..allow = 'payment';
      frame.setAttribute('sandbox', frameSandbox);
      frame.style
        ..border = 'none'
        ..width = '100%'
        ..height = '100%'
        ..background = '#FFFFFF';
    },
  );
}
