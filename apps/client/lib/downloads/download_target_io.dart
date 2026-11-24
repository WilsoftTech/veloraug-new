import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'downloads.dart';

/// Android only: other platforms this code compiles for save nothing.
Future<(DownloadTarget, DownloadRecords?)?> createDownloadTarget() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  DownloadRecords? records;
  try {
    final support = await getApplicationSupportDirectory();
    records = FileDownloadRecords(File('${support.path}/downloads.json'));
  } on Object {
    records = null;
  }
  return (const AndroidDownloadTarget(), records);
}

/// Android's own download manager, through MainActivity.kt. It saves to the
/// phone's Downloads/VeloraUG folder, shows a notification, carries on in
/// the background and after a dropped connection, and keeps the file when
/// the app is uninstalled.
class AndroidDownloadTarget implements DownloadTarget {
  const AndroidDownloadTarget();

  static const MethodChannel _channel = MethodChannel('veloraug/downloads');

  @override
  bool get followed => true;

  @override
  Future<String?> start(DownloadFile file, String title) async {
    try {
      final id = await _channel.invokeMethod<String>('start', {
        'url': file.url.toString(),
        'fileName': file.fileName,
        'title': title,
      });
      if (id == null) throw const DownloadRefused(DownloadRefusal.failed);
      return id;
    } on PlatformException catch (error) {
      throw DownloadRefused(
        error.code == 'permission'
            ? DownloadRefusal.noPermission
            : DownloadRefusal.failed,
      );
    }
  }

  @override
  Future<Map<String, FileStatus>> status(List<String> ids) async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('status', {
          'ids': ids,
        }) ??
        const [];
    return {
      for (final row in rows)
        if (row case {'id': final String id, 'state': final String state})
          id: FileStatus(
            state: FileState.values.asNameMap()[state] ?? FileState.failed,
            bytes: row['bytes'] is int ? row['bytes'] as int : 0,
            total: row['total'] is int && (row['total'] as int) > 0
                ? row['total'] as int
                : null,
            noRoom: row['noRoom'] == true,
          ),
    };
  }

  @override
  Future<bool> open(String id) async =>
      await _channel.invokeMethod<bool>('open', {'id': id}) ?? false;

  @override
  Future<void> remove(String id) =>
      _channel.invokeMethod<void>('remove', {'id': id});
}

/// The list of followed downloads, in the app's private storage.
class FileDownloadRecords implements DownloadRecords {
  FileDownloadRecords(this.file);

  final File file;

  @override
  Future<String?> read() async {
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String text) async {
    final part = File('${file.path}.part');
    await part.writeAsString(text, flush: true);
    await part.rename(file.path);
  }
}
