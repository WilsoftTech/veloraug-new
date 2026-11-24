import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/velora_button.dart';
import 'pesapal_view.dart';

/// Pesapal's page in an Android web view, inside the app.
Widget platformPesapalView(
  BuildContext context,
  Uri page,
  VoidCallback onReturned,
) => _AppPesapalView(key: ValueKey(page), page: page, onReturned: onReturned);

class _AppPesapalView extends StatefulWidget {
  const _AppPesapalView({
    super.key,
    required this.page,
    required this.onReturned,
  });

  final Uri page;
  final VoidCallback onReturned;

  @override
  State<_AppPesapalView> createState() => _AppPesapalViewState();
}

class _AppPesapalViewState extends State<_AppPesapalView> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _failed = false;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(VeloraColors.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onNavigationRequest: _allow,
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              if (mounted) setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadRequest(widget.page);
  }

  /// Pesapal's page and the bank's card checks load here. The return
  /// address never does: the app takes over there. Anything that isn't a
  /// secure web page, such as `intent:` or `tel:`, is refused.
  NavigationDecision _allow(NavigationRequest request) {
    final url = Uri.tryParse(request.url);
    if (url == null) return NavigationDecision.prevent;
    if (isReturnAddress(url)) {
      if (!_returned) {
        _returned = true;
        widget.onReturned();
      }
      return NavigationDecision.prevent;
    }
    if (!request.isMainFrame) return NavigationDecision.navigate;
    return url.scheme == 'https'
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  void _reload() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller.loadRequest(widget.page);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: VeloraSpacing.md,
            children: [
              Text(l.paymentFormCouldNotLoad, textAlign: TextAlign.center),
              VeloraButton(
                label: l.tryAgain,
                icon: Icons.refresh,
                onPressed: _reload,
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label: l.paymentFormLabel,
      child: Stack(
        children: [
          WebViewWidget(
            controller: _controller,
            // The page scrolls itself, inside the screen's own scrolling.
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                EagerGestureRecognizer.new,
              ),
            },
          ),
          if (_progress < 100)
            Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 3,
              ),
            ),
        ],
      ),
    );
  }
}
