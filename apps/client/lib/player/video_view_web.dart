import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'video_view.dart';

/// hls.js, kept in web/vendor/ so no outside script is ever loaded. The
/// light build plays everything VeloraUG publishes: fMP4 HLS, H.264, AAC.
const _hlsScript = 'vendor/hls.js-1.7.4/hls.light.min.js';

/// A `<video>` element with the browser's own controls, fed by hls.js.
Widget platformVideoView(BuildContext context, VideoViewRequest request) =>
    _WebVideoView(key: ValueKey(request.url), request: request);

@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external factory _Hls(JSObject config);
  external static bool isSupported();
  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement media);
  external void on(String event, JSFunction listener);
  external void destroy();
}

extension type _HlsError._(JSObject _) implements JSObject {
  external bool get fatal;
}

Future<void>? _loading;

/// Loads hls.js once, on first use.
Future<void> _loadHls() {
  if (globalContext.has('Hls')) return Future.value();
  return _loading ??= () {
    final done = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = _hlsScript
      ..async = true;
    script.onload = ((web.Event _) => done.complete()).toJS;
    script.onerror = ((web.Event _) {
      _loading = null;
      script.remove();
      done.completeError(StateError("hls.js didn't load"));
    }).toJS;
    web.document.head!.append(script);
    return done.future;
  }();
}

class _WebVideoView extends StatefulWidget {
  const _WebVideoView({super.key, required this.request});

  final VideoViewRequest request;

  @override
  State<_WebVideoView> createState() => _WebVideoViewState();
}

class _WebVideoViewState extends State<_WebVideoView> {
  static int _views = 0;

  final String _viewType = 'veloraug-video-${_views++}';
  final web.HTMLVideoElement _video = web.HTMLVideoElement();
  _Hls? _hls;
  bool _reported = false;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _video
      ..controls = true
      ..autoplay = true
      ..playsInline = true
      ..setAttribute('controlslist', 'nodownload')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'black'
      ..addEventListener(
        'ended',
        ((web.Event _) {
          if (_ended || !mounted) return;
          _ended = true;
          widget.request.onEnded?.call();
        }).toJS,
      );
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _video,
    );
    _attach();
  }

  double get _startSeconds => widget.request.startAt.inMilliseconds / 1000;

  Future<void> _attach() async {
    try {
      await _loadHls();
    } on Object {
      // Without hls.js, a browser that plays HLS itself still can.
    }
    if (!mounted) return;
    final url = widget.request.url.toString();
    if (globalContext.has('Hls') && _Hls.isSupported()) {
      final hls = _hls = _Hls(
        {
              'startPosition': _startSeconds > 0 ? _startSeconds : -1,
              // Never send cookies or credentials to the gateway.
              'withCredentials': false,
            }.jsify()!
            as JSObject,
      );
      hls.on(
        'hlsError',
        ((JSString _, _HlsError data) {
          if (data.fatal) _fail();
        }).toJS,
      );
      hls.loadSource(url);
      hls.attachMedia(_video);
    } else if (_video.canPlayType('application/vnd.apple.mpegurl') != '') {
      _video
        ..addEventListener(
          'loadedmetadata',
          ((web.Event _) {
            if (_startSeconds > 0) _video.currentTime = _startSeconds;
          }).toJS,
        )
        ..addEventListener('error', ((web.Event _) => _fail()).toJS)
        ..src = url;
    } else {
      _fail();
    }
  }

  void _fail() {
    if (_reported || !mounted) return;
    _reported = true;
    final at = _video.currentTime;
    widget.request.onFailed(
      at > 0
          ? Duration(milliseconds: (at * 1000).round())
          : widget.request.startAt,
    );
  }

  @override
  void dispose() {
    _hls?.destroy();
    _video
      ..pause()
      ..removeAttribute('src')
      ..load();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
