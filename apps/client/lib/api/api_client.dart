import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ApiFailure { timeout, unavailable, badResponse }

class ApiException implements Exception {
  const ApiException(this.failure, this.message);

  final ApiFailure failure;
  final String message;

  @override
  String toString() => 'ApiException(${failure.name}): $message';
}

/// The reply from GET /health. It only means the API process answered.
class HealthStatus {
  const HealthStatus({required this.status});

  final String status;
}

/// The reply from GET /api/v1.
class ServiceInfo {
  const ServiceInfo({
    required this.service,
    required this.apiVersion,
    required this.environment,
  });

  final String service;
  final String apiVersion;
  final String environment;
}

class ApiClient {
  ApiClient({
    required this._baseUrl,
    required this._httpClient,
    this.timeout = const Duration(seconds: 5),
  });

  final Uri _baseUrl;
  final http.Client _httpClient;
  final Duration timeout;

  Future<HealthStatus> fetchHealth() async {
    const path = '/health';
    final json = await _getJsonObject(path);
    final status = _requireString(json, 'status', path);
    if (status != 'ok') {
      throw ApiException(
        ApiFailure.badResponse,
        '$path reported an unexpected status: "$status".',
      );
    }
    return HealthStatus(status: status);
  }

  Future<ServiceInfo> fetchServiceInfo() async {
    const path = '/api/v1';
    final json = await _getJsonObject(path);
    final service = _requireString(json, 'service', path);
    final apiVersion = _requireString(json, 'api_version', path);
    // Another program using the same port would otherwise look like success.
    if (service != 'veloraug-api' || apiVersion != 'v1') {
      throw ApiException(
        ApiFailure.badResponse,
        '$path did not identify the VeloraUG API v1.',
      );
    }
    return ServiceInfo(
      service: service,
      apiVersion: apiVersion,
      environment: _requireString(json, 'environment', path),
    );
  }

  Future<Map<String, Object?>> _getJsonObject(String path) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(_baseUrl.replace(path: path))
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        ApiFailure.timeout,
        '$path did not answer within ${timeout.inSeconds} seconds.',
      );
    } on Exception {
      throw ApiException(
        ApiFailure.unavailable,
        'Could not reach $path. The API may be stopped, or the browser may '
        'have blocked the request.',
      );
    }

    if (response.statusCode != 200) {
      throw ApiException(
        ApiFailure.badResponse,
        '$path answered with HTTP ${response.statusCode}.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(ApiFailure.badResponse, '$path did not return JSON.');
    }
    if (decoded is! Map<String, Object?>) {
      throw ApiException(
        ApiFailure.badResponse,
        '$path did not return a JSON object.',
      );
    }
    return decoded;
  }

  String _requireString(Map<String, Object?> json, String field, String path) {
    final value = json[field];
    if (value is! String || value.isEmpty) {
      throw ApiException(
        ApiFailure.badResponse,
        '$path is missing the text field "$field".',
      );
    }
    return value;
  }
}
