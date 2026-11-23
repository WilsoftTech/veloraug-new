import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'download_storage_io.dart'
    if (dart.library.js_interop) 'download_storage_web.dart'
    as platform;

/// Where downloads are kept: one folder per item, named by its ID, laid out
/// as on the media gateway, plus one index of every download.
///
/// On Android, the app's private storage: other apps can't read it, it
/// isn't backed up (backup is off in the manifest), and uninstalling the
/// app removes it. Downloads aren't kept on the web.
abstract interface class DownloadStorage {
  /// The index, as last written, or null.
  Future<String?> readIndex();
  Future<void> writeIndex(String text);

  /// The size of a file in an item's folder, or null if it isn't there.
  /// A file is only there once wholly written.
  Future<int?> sizeOf(String itemId, String path);

  /// Writes a whole file, replacing any before.
  Future<void> write(String itemId, String path, Uint8List bytes);

  /// Removes an item's folder and everything in it.
  Future<void> delete(String itemId);

  /// The address the player opens: the item's local master playlist.
  Uri playUri(String itemId);

  /// A picture kept with a download, such as its poster, or null.
  ImageProvider? image(String itemId, String path);
}

/// The app's private storage on Android; null on the web.
Future<DownloadStorage?> createPlatformDownloadStorage() =>
    platform.createDownloadStorage();

/// A file name inside an item's folder: one folder down at most, as the
/// media gateway's are. Anything else is refused before it touches a disk.
final RegExp safeDownloadPath = RegExp(
  r'^(?:[A-Za-z0-9_-]{1,32}/)?[A-Za-z0-9_-]{1,40}(?:\.[a-z0-9]{1,5})?$',
);

final RegExp _itemId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Throws unless [itemId] and [path] are safe to use on disk.
void checkDownloadPath(String itemId, [String path = 'master.m3u8']) {
  if (!_itemId.hasMatch(itemId) || !safeDownloadPath.hasMatch(path)) {
    throw ArgumentError('Not a download path');
  }
}

/// Keeps everything in memory. For tests.
class MemoryDownloadStorage implements DownloadStorage {
  String? index;
  final Map<String, Map<String, Uint8List>> files = {};

  /// Makes writes fail, as a full disk does.
  bool full = false;

  @override
  Future<String?> readIndex() async => index;

  @override
  Future<void> writeIndex(String text) async => index = text;

  @override
  Future<int?> sizeOf(String itemId, String path) async =>
      files[itemId]?[path]?.length;

  @override
  Future<void> write(String itemId, String path, Uint8List bytes) async {
    checkDownloadPath(itemId, path);
    if (full) throw const DownloadStorageFull();
    (files[itemId] ??= {})[path] = bytes;
  }

  @override
  Future<void> delete(String itemId) async => files.remove(itemId);

  @override
  Uri playUri(String itemId) =>
      Uri.parse('file:///downloads/$itemId/master.m3u8');

  @override
  ImageProvider? image(String itemId, String path) {
    final bytes = files[itemId]?[path];
    return bytes == null ? null : MemoryImage(bytes);
  }
}

/// The phone has no room left for the download.
class DownloadStorageFull implements Exception {
  const DownloadStorageFull();
}
