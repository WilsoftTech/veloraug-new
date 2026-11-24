import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Push notifications, as far as they go in this build.
///
/// No push service is set up for VeloraUG yet: there is no Firebase Cloud
/// Messaging project, no google-services.json, and no server key or token
/// store on the API. So nothing can be delivered to a phone, and Settings
/// shows the switch off and says so. The in-app inbox, Account >
/// Notifications, works without push. docs/viewer-app-upgrade.md lists what
/// push needs.
const bool pushServiceConfigured = false;

enum PushAvailability {
  /// The web app: push isn't offered there.
  notOnThisPlatform,

  /// Android, with no push service set up yet.
  notSetUp,
}

class PushStatus {
  const PushStatus({required this.availability, this.osAllowed});

  final PushAvailability availability;

  /// Whether Android lets VeloraUG show notifications now, or null when it
  /// can't be read.
  final bool? osAllowed;
}

const MethodChannel _channel = MethodChannel('veloraug/notifications');

/// Reads what Android allows. Never asks for permission: there is nothing
/// to deliver yet.
Future<PushStatus> readPushStatus({
  bool? isAndroid,
  Future<bool?> Function()? readOsAllowed,
}) async {
  final android =
      isAndroid ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  if (!android) {
    return const PushStatus(availability: PushAvailability.notOnThisPlatform);
  }
  bool? allowed;
  try {
    allowed = await (readOsAllowed ?? _readOsAllowed)();
  } on Object {
    allowed = null;
  }
  return PushStatus(
    availability: PushAvailability.notSetUp,
    osAllowed: allowed,
  );
}

Future<bool?> _readOsAllowed() => _channel.invokeMethod<bool>('allowed');
