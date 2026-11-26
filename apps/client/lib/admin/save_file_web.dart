import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [text] as a file called [name], of MIME [type], through a
/// link the browser clicks. Answers true once handed to the browser.
Future<bool> saveTextFile(String name, String text, String type) async {
  final bytes = utf8.encode(text);
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body?.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
