import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/oauth_client.dart';
import 'playback_api.dart';

/// A pass for sale: a day, a week or a month, in whole Uganda shillings.
class PassPlan {
  const PassPlan({
    required this.id,
    required this.days,
    required this.priceUgx,
  });

  /// day, week or month.
  final String id;
  final int days;
  final int priceUgx;
}

/// Whether the viewer has a pass, Step 10C.
class PassStatus {
  const PassStatus({
    required this.active,
    this.currentEndsAt,
    this.endsAt,
    this.checking = false,
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
}

/// A payment started: where the viewer pays.
class Checkout {
  const Checkout({required this.paymentId, required this.paymentPage});

  final String paymentId;

  /// Pesapal's page, already checked to be https on pesapal.com.
  final Uri paymentPage;
}

enum PaymentState { started, pending, completed, failed, reversed, abandoned }

class PaymentCheck {
  const PaymentCheck({required this.state, this.passEndsAt});

  final PaymentState state;

  /// Once completed: when the viewer's passes end.
  final DateTime? passEndsAt;
}

enum PassFailure {
  /// Not signed in, or the token was refused.
  signedOut,

  /// 409: the pass isn't for sale any more.
  notForSale,

  /// 422: no email or phone, or one that isn't valid.
  needsContact,

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

/// Passes go with playback: the same API, token and client.
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
          PassPlan(id: id, days: days, priceUgx: price),
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
      );
    }
    throw const PassException(PassFailure.unexpected);
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
      final state = PaymentState.values
          .where((s) => s.name == name)
          .firstOrNull;
      if (state != null) {
        return PaymentCheck(
          state: state,
          passEndsAt: _time(json['pass_ends_at']),
        );
      }
    }
    throw const PassException(PassFailure.unexpected);
  }

  Future<Object?> _passJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool signIn = true,
  }) async {
    final headers = <String, String>{};
    if (signIn) {
      final String? token;
      try {
        token = await accessToken();
      } on OAuthException {
        throw const PassException(PassFailure.unreachable);
      }
      if (token == null) throw const PassException(PassFailure.signedOut);
      headers['Authorization'] = 'Bearer $token';
    }
    final request = http.Request(method, baseUrl.replace(path: path))
      ..headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await httpClient.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const PassException(PassFailure.unreachable);
    } on Exception {
      throw const PassException(PassFailure.unreachable);
    }
    final failure = switch (response.statusCode) {
      200 || 201 => null,
      401 => PassFailure.signedOut,
      409 => PassFailure.notForSale,
      422 => PassFailure.needsContact,
      502 || 503 => PassFailure.unavailable,
      _ => PassFailure.unexpected,
    };
    if (failure != null) throw PassException(failure);
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PassException(PassFailure.unexpected);
    }
  }
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
