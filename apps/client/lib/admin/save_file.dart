/// Saves text as a file the person downloads: the browser's download on
/// the web. The admin screens are on the web only, so elsewhere it saves
/// nothing and answers false.
library;

export 'save_file_stub.dart' if (dart.library.js_interop) 'save_file_web.dart';
