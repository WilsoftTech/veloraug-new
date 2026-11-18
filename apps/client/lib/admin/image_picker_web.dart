import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'image_picker.dart';

/// The browser's file chooser, for one JPEG, PNG or WebP image. Null if the
/// admin cancels, or picks a file of another type.
Future<PickedImage?> pickImage() {
  final done = Completer<PickedImage?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = uploadImageTypes.join(',');
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS,
  );
  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      final type = file == null ? null : imageTypeOf(file.type, file.name);
      if (file == null || type == null) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      file.arrayBuffer().toDart.then(
        (buffer) {
          if (!done.isCompleted) {
            done.complete(
              PickedImage(
                bytes: buffer.toDart.asUint8List(),
                contentType: type,
              ),
            );
          }
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete(null);
        },
      );
    }).toJS,
  );
  input.click();
  return done.future;
}
