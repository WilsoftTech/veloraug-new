import 'dart:js_interop';

import 'device_store.dart';

DeviceStore createDeviceStore() => _LocalStorageDeviceStore();

@JS('localStorage')
external _Storage get _localStorage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// Shared by every tab of this browser profile, so they count as one
/// device. Like the session, scripts on the page could read it, which is
/// why the web app loads no third-party scripts.
class _LocalStorageDeviceStore implements DeviceStore {
  static const String _key = 'veloraug.device';

  @override
  Future<String?> read() async => _localStorage.getItem(_key);

  @override
  Future<void> write(String credential) async =>
      _localStorage.setItem(_key, credential);

  @override
  Future<void> clear() async => _localStorage.removeItem(_key);
}
