import 'package:web/web.dart' as web;

import 'downloads.dart';

Future<(DownloadTarget, DownloadRecords?)?> createDownloadTarget() async =>
    (const BrowserDownloadTarget(), null);

/// The browser's own downloader. The media gateway sends the file as an
/// attachment, so following its address saves it rather than playing it,
/// and the page stays where it is. The browser shows its progress.
class BrowserDownloadTarget implements DownloadTarget {
  const BrowserDownloadTarget();

  @override
  bool get followed => false;

  @override
  Future<String?> start(DownloadFile file, String title) async {
    final link = web.HTMLAnchorElement()
      ..href = file.url.toString()
      ..download = file.fileName
      ..rel = 'noopener';
    web.document.body?.append(link);
    link.click();
    link.remove();
    return null;
  }

  @override
  Future<Map<String, FileStatus>> status(List<String> ids) async => const {};

  @override
  Future<bool> open(String id) async => false;

  @override
  Future<void> remove(String id) async {}
}
