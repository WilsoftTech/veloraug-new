/// Picks one image file for upload: the browser's file chooser on the web.
/// The admin screens are on the web only, so elsewhere it picks nothing.
library;

import 'dart:typed_data';

export 'image_picker_stub.dart'
    if (dart.library.js_interop) 'image_picker_web.dart';

/// The only image types the media gateway stores.
const Set<String> uploadImageTypes = {'image/jpeg', 'image/png', 'image/webp'};

/// The media gateway refuses anything larger.
const int maxImageBytes = 2 * 1024 * 1024;

class PickedImage {
  const PickedImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// The type from the browser, or from the file's name when it gives none.
String? imageTypeOf(String browserType, String name) {
  if (uploadImageTypes.contains(browserType)) return browserType;
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}
