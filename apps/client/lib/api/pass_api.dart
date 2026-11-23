import 'dart:async';

import 'playback_api.dart';

/// A plan for sale, Milestone 10: one of VeloraUG's six tiers. Every value
/// comes from the API; the app never decides a price or an allowance.
class PassPlan {
  const PassPlan({
    required this.id,
    required this.days,
    required this.priceUgx,
    String? displayName,
    this.description,
    this.maxDevices = 1,
    this.maxStreams = 1,
    this.featured = false,
  }) : displayName = displayName ?? id;

  /// Such as velora_prime.
  final String id;
  final int days;

  /// Whole Uganda shillings.
  final int priceUgx;
  final String displayName;
  final String? description;
  final int maxDevices;
  final int maxStreams;

  /// The plan to highlight: Velora Prime, unless an admin chose another.
  final bool featured;
}

/// One pass: what it allows, from when, until when.
class Entitlement {
  const Entitlement({
    required this.planId,
    required this.planName,
    required this.startsAt,
    required this.endsAt,
    required this.maxDevices,
    required this.maxStreams,
  });

  final String planId;
  final String planName;
  final DateTime startsAt;
  final DateTime endsAt;
  final int maxDevices;
  final int maxStreams;
}

/// The viewer's membership, Step 10C and Milestone 10.
class PassStatus {
  const PassStatus({
    required this.active,
    this.currentEndsAt,
    this.endsAt,
    this.checking = false,
    this.current,
    this.queued = const [],
  });

  /// A pass is running now.
  final bool active;

  /// When the running pass ends.
  final DateTime? currentEndsAt;

  /// When the last pass bought ends: later than [currentEndsAt] when one was
  /// bought early.
  final DateTime? endsAt;

  /// A payment is still being checked with Pesapal.
  final bool checking;

  /// The pass running now, which decides devices and streams.
  final Entitlement? current;

  /// Passes bought early, each starting when the one before ends.
  final List<Entitlement> queued;
}

/// A payment started: where the viewer pays.
class Checkout {
  const Checkout({required this.paymentId, required this.paymentPage});

  final String paymentId;

  /// Pesapal's page, already checked to be https on pesapal.com.
  final Uri paymentPage;
}

enum PaymentState {
  started,
  pending,
  completed,
  failed,
  reversed,
  abandoned,

  /// Refunded in full: an admin marked it so, and its pass has ended.
  refunded,
}

class PaymentCheck {
  const PaymentCheck({required this.state, this.passEndsAt});

  final PaymentState state;

  /// Once completed: when the viewer's passes end.
  final DateTime? passEndsAt;
}

/// One of the viewer's payments, for Account, Payments.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.planName,
    required this.amountUgx,
    required this.state,
    required this.createdAt,
    this.providerReference,
  });

  final String id;
  final String planName;
  final int amountUgx;
  final PaymentState state;
  final DateTime createdAt;

  /// Pesapal's confirmation code, once paid.
  final String? providerReference;
}

/// One of the viewer's registered devices.
class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.label,
    required this.platform,
    required this.lastActiveAt,
    this.current = false,
  });

  final String id;
  final String label;

  /// web, android, ios or other.
  final String platform;
  final DateTime lastActiveAt;

  /// The device asking: this one.
  final bool current;
}

class DeviceList {
  const DeviceList({
    required this.devices,
    required this.allowed,
    required this.streamsAllowed,
    required this.overLimit,
  });

  final List<RegisteredDevice> devices;
  final int allowed;
  final int streamsAllowed;

  /// More devices than the plan running now allows: some must go.
  final bool overLimit;
}

enum PassFailure {
  /// Not signed in, or the token was refused.
  signedOut,

  /// 404: no such device or session, or it's someone else's.
  notFound,

  /// 409: the pass isn't for sale any more.
  notForSale,

  /// 422: no email or phone, or one that isn't valid.
  needsContact,

  /// 429: too many attempts.
  tooMany,

  /// 502 or 503: Pesapal, the API or payments aren't available.
  unavailable,

  /// No answer at all.
  unreachable,

  /// Anything else, including a payment page that isn't Pesapal's.
  unexpected,
}

class PassException implements Exception {
  const PassException(this.failure);

  final PassFailure failure;

  @override
  String toString() => 'PassException(${failure.name})';
}

/// Pesapal's page: https on pesapal.com, or one of its subdomains.
bool isPesapalPage(Uri url) =>
    url.scheme == 'https' &&
    url.userInfo.isEmpty &&
    (url.host == 'pesapal.com' || url.host.endsWith('.pesapal.com'));

/// Membership, payments and devices go with playback: the same API, token,
/// device and client.
extension PassRequests on PlaybackApi {
  Future<List<PassPlan>> passPlans() async {
    final json = await _passJson('GET', '/api/v1/passes/plans', signIn: false);
    if (json is! List) throw const PassException(PassFailure.unexpected);
    return [
      for (final plan in json)
        if (plan case {
          'id': final String id,
          'days': final int days,
          'price_ugx': final int price,
        })
          PassPlan(
            id: id,
            days: days,
            priceUgx: price,
            displayName: _string(plan['display_name']),
            description: _string(plan['description']),
            maxDevices: _int(plan['max_devices']) ?? 1,
            maxStreams: _int(plan['max_streams']) ?? 1,
            featured: plan['featured'] == true,
          ),
    ];
  }

  Future<PassStatus> myPass() async {
    final json = await _passJson('GET', '/api/v1/me/pass');
    if (json case {'active': final bool active}) {
      return PassStatus(
        active: active,
        currentEndsAt: _time(json['current_ends_at']),
        endsAt: _time(json['ends_at']),
        checking: json['checking'] == true,
        current: _entitlement(json['current']),
        queued: [
          if (json['queued'] case final List<Object?> rows)
            for (final row in rows) ?_entitlement(row),
        ],
      );
    }
    throw const PassException(PassFailure.unexpected);
  }

  Future<List<PaymentRecord>> myPayments() async {
    final json = await _passJson('GET', '/api/v1/me/payments');
    if (json is! List) throw const PassException(PassFailure.unexpected);
    return [
      for (final row in json)
        if (row case {
          'id': final String id,
          'plan_name': final String plan,
          'amount_ugx': final int amount,
          'state': final String state,
          'created_at': final String created,
        })
          if (_state(state) case final known?)
            PaymentRecord(
              id: id,
              planName: plan,
              amountUgx: amount,
              state: known,
              createdAt: DateTime.tryParse(created)?.toUtc() ?? DateTime.now(),
              providerReference: _string(row['provider_reference']),
            ),
    ];
  }

  Future<Checkout> checkout(
    String planId, {
    String? email,
    String? phone,
  }) async {
    final json = await _passJson(
      'POST',
      '/api/v1/passes/checkout',
      body: {'plan_id': planId, 'email': ?email, 'phone': ?phone},
    );
    if (json case {
      'payment_id': final String id,
      'redirect_url': final String page,
    }) {
      final url = Uri.tryParse(page);
      if (url != null && isPesapalPage(url)) {
        return Checkout(paymentId: id, paymentPage: url);
      }
    }
    throw const PassException(PassFailure.unexpected);
  }

  Future<PaymentCheck> payment(String paymentId) async {
    final json = await _passJson(
      'GET',
      '/api/v1/passes/payments/${Uri.encodeComponent(paymentId)}',
    );
    if (json case {'state': final String name}) {
      if (_state(name) case final state?) {
        return PaymentCheck(
          state: state,
          passEndsAt: _time(json['pass_ends_at']),
        );
      }
    }
    throw const PassException(PassFailure.unexpected);
  }

  // --- Devices and sessions -------------------------------------------------

  Future<DeviceList> myDevices() async {
    final json = await _passJson('GET', '/api/v1/me/devices');
    if (json case {
      'devices': final List<Object?> rows,
      'allowed': final int allowed,
    }) {
      return DeviceList(
        devices: [
          for (final row in rows)
            if (row case {
              'id': final String id,
              'label': final String label,
              'platform': final String platform,
              'last_active_at': final String active,
            })
              RegisteredDevice(
                id: id,
                label: label,
                platform: platform,
                lastActiveAt:
                    DateTime.tryParse(active)?.toUtc() ?? DateTime.now(),
                current: row['current'] == true,
              ),
        ],
        allowed: allowed,
        streamsAllowed: _int(json['streams_allowed']) ?? 0,
        overLimit: json['over_limit'] == true,
      );
    }
    throw const PassException(PassFailure.unexpected);
  }

  Future<void> renameDevice(String deviceId, String label) async {
    await _passJson(
      'PATCH',
      '/api/v1/me/devices/${Uri.encodeComponent(deviceId)}',
      body: {'label': label},
    );
  }

  /// Removes a device. Removing this one forgets its credential too, so it
  /// registers again, as a new device, next time it plays.
  Future<void> removeDevice(String deviceId, {bool current = false}) async {
    await _passJson(
      'DELETE',
      '/api/v1/me/devices/${Uri.encodeComponent(deviceId)}',
    );
    if (current) await deviceStore.clear();
  }

  Future<List<LiveSession>> playingNow() async {
    final json = await _passJson('GET', '/api/v1/me/playback-sessions');
    if (json is! List) throw const PassException(PassFailure.unexpected);
    return [
      for (final row in json)
        if (row case {
          'id': final String id,
          'device_label': final String label,
          'started_at': final String started,
        })
          LiveSession(
            id: id,
            deviceLabel: label,
            startedAt: DateTime.tryParse(started)?.toUtc() ?? DateTime.now(),
            currentDevice: row['current_device'] == true,
          ),
    ];
  }

  Future<void> stopSession(String sessionId) async {
    await _passJson(
      'DELETE',
      '/api/v1/me/playback-sessions/${Uri.encodeComponent(sessionId)}',
    );
  }

  Future<Object?> _passJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool signIn = true,
  }) async {
    final ApiAnswer answer;
    try {
      answer = await send(method, path, body: body, signIn: signIn);
    } on Exception catch (error) {
      throw PassException(
        isSignedOut(error) ? PassFailure.signedOut : PassFailure.unreachable,
      );
    }
    final failure = switch (answer.status) {
      200 || 201 || 204 => null,
      401 => PassFailure.signedOut,
      404 => PassFailure.notFound,
      409 => PassFailure.notForSale,
      422 => PassFailure.needsContact,
      429 => PassFailure.tooMany,
      502 || 503 => PassFailure.unavailable,
      _ => PassFailure.unexpected,
    };
    if (failure != null) throw PassException(failure);
    return answer.json;
  }
}

Entitlement? _entitlement(Object? value) => switch (value) {
  {
    'plan_id': final String planId,
    'plan_name': final String planName,
    'starts_at': final String starts,
    'ends_at': final String ends,
    'max_devices': final int devices,
    'max_streams': final int streams,
  } =>
    switch ((DateTime.tryParse(starts), DateTime.tryParse(ends))) {
      (final s?, final e?) => Entitlement(
        planId: planId,
        planName: planName,
        startsAt: s.toUtc(),
        endsAt: e.toUtc(),
        maxDevices: devices,
        maxStreams: streams,
      ),
      _ => null,
    },
  _ => null,
};

PaymentState? _state(String name) =>
    PaymentState.values.where((s) => s.name == name).firstOrNull;

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
