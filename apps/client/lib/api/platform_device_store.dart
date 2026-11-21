import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_store.dart';

DeviceStore createDeviceStore() => _SecureDeviceStore();

/// Encrypted with a key held in the Android Keystore. Backup is off in the
/// manifest, so a restored phone registers as a new device.
class _SecureDeviceStore implements DeviceStore {
  static const String _key = 'veloraug.device';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String credential) =>
      _storage.write(key: _key, value: credential);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
