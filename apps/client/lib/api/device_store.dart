import 'platform_device_store.dart'
    if (dart.library.js_interop) 'platform_device_store_web.dart'
    as platform;

/// This installation's device credential, Milestone 10: `<id>.<secret>`,
/// made by the API when the device registers and shown to it once. Sent in
/// the `X-Velora-Device` header when playing. Never logged or displayed.
abstract interface class DeviceStore {
  Future<String?> read();
  Future<void> write(String credential);
  Future<void> clear();
}

/// The Android Keystore on Android. On the web, the browser's
/// `localStorage`, so every tab of one browser is one device.
DeviceStore createPlatformDeviceStore() => platform.createDeviceStore();

/// Keeps it in memory only. For tests.
class MemoryDeviceStore implements DeviceStore {
  MemoryDeviceStore([this.credential]);

  String? credential;

  @override
  Future<String?> read() async => credential;

  @override
  Future<void> write(String credential) async => this.credential = credential;

  @override
  Future<void> clear() async => credential = null;
}

/// The credential's shape, checked before it's stored or sent.
final RegExp deviceCredentialPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[A-Za-z0-9_-]{43}$',
);
