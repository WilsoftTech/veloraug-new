import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../l10n/l10n.dart';

/// What Pesapal's page may do inside the frame. It can run, keep its
/// session, send its forms, and open a bank's card check in a new window.
/// It can't move VeloraUG itself away: without `allow-top-navigation`, a
/// return that targets the whole window stays blocked.
const frameSandbox =
    'allow-scripts allow-same-origin allow-forms allow-popups '
    'allow-popups-to-escape-sandbox allow-modals';

/// What the API's return page posts when it loads inside the frame.
const returnedMessage = 'veloraug:pesapal-returned';

/// Pesapal's page in an `<iframe>`, inside the app.
Widget platformPesapalView(
  BuildContext context,
  Uri page,
  VoidCallback onReturned,
) => _FramePesapalView(key: ValueKey(page), page: page, onReturned: onReturned);

class _FramePesapalView extends StatefulWidget {
  const _FramePesapalView({
    super.key,
    required this.page,
    required this.onReturned,
  });

  final Uri page;
  final VoidCallback onReturned;

  @override
  State<_FramePesapalView> createState() => _FramePesapalViewState();
}

class _FramePesapalViewState extends State<_FramePesapalView> {
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener = _onMessage.toJS;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  /// When Pesapal sends its frame to the API's return page, that page says
  /// so. Only a message from this frame counts, and it only makes the app
  /// check the payment sooner.
  void _onMessage(web.MessageEvent event) {
    final frame = _frame;
    if (_returned || frame == null || !mounted) return;
    final from = event.source;
    if (from == null || from != frame.contentWindow) return;
    final data = event.data;
    if (data.isA<JSString>() && (data as JSString).toDart == returnedMessage) {
      _returned = true;
      widget.onReturned();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = context.l10n.paymentFormLabel;
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        _frame = frame;
        frame
          ..src = widget.page.toString()
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
}
