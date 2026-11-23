import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'download_storage.dart';

/// Android only: other platforms this code compiles for keep nothing.
Future<DownloadStorage?> createDownloadStorage() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/downloads');
    await root.create(recursive: true);
    return _FileDownloadStorage(root);
  } on Object {
    return null;
  }
}

/// Files in the app's private storage. Each file is written beside its
/// place as `.part`, then renamed, so a file there is always whole.
class _FileDownloadStorage implements DownloadStorage {
  _FileDownloadStorage(this.root);

  final Directory root;

  File get _index => File('${root.path}/index.json');

  File _file(String itemId, String path) {
    checkDownloadPath(itemId, path);
    return File('${root.path}/$itemId/$path');
  }

  @override
  Future<String?> readIndex() async {
    try {
      return await _index.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> writeIndex(String text) => _replace(_index, utf8.encode(text));

  @override
  Future<int?> sizeOf(String itemId, String path) async {
    final file = _file(itemId, path);
    try {
      return await file.length();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String itemId, String path, Uint8List bytes) =>
      _replace(_file(itemId, path), bytes);

  Future<void> _replace(File file, Uint8List bytes) async {
    final part = File('${file.path}.part');
    try {
      await part.parent.create(recursive: true);
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    } on FileSystemException catch (error) {
      try {
        await part.delete();
      } on FileSystemException {
        // Nothing was written.
      }
      // ENOSPC on Linux, so on Android.
      if (error.osError?.errorCode == 28) throw const DownloadStorageFull();
      rethrow;
    }
  }

  @override
  Future<void> delete(String itemId) async {
    checkDownloadPath(itemId);
    final folder = Directory('${root.path}/$itemId');
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  @override
  Uri playUri(String itemId) => _file(itemId, 'master.m3u8').uri;

  @override
  ImageProvider? image(String itemId, String path) {
    final file = _file(itemId, path);
    return file.existsSync() ? FileImage(file) : null;
  }
}
