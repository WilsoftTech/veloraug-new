import 'download_target_io.dart'
    if (dart.library.js_interop) 'download_target_web.dart'
    as platform;
import 'downloads.dart';

/// Where this build saves downloads, and where it keeps their list: the
/// browser's downloader on the web, Android's download manager on Android,
/// and nothing elsewhere.
Future<(DownloadTarget, DownloadRecords?)?> createPlatformDownloadTarget() =>
    platform.createDownloadTarget();
