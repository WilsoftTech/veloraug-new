/// The browser's part of uploading: sending, storage, drops, the file
/// chooser, online status and the warning before leaving the page. The
/// admin screens are on the web only, so elsewhere these do nothing.
library;

export 'upload_platform_stub.dart'
    if (dart.library.js_interop) 'upload_platform_web.dart';
