import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../utils/result.dart';
import '../utils/secure_storage.dart';

/// Central HTTP client. Every service (auth, recipe, ingredient, timer)
/// calls through here so auth headers, timeouts, and error parsing are
/// handled in exactly one place.
class ApiClient {
  ApiClient._({http.Client? client}) : _client = client ?? http.Client();
  static final ApiClient instance = ApiClient._();

  /// Builds a client backed by a caller-supplied [http.Client]. Used by
  /// tests to plug in `package:http/testing.dart`'s `MockClient`.
  @visibleForTesting
  factory ApiClient.withClient(http.Client client) => ApiClient._(client: client);

  final http.Client _client;

  Future<Map<String, String>> _headers({bool withAuth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (withAuth) {
      final token = await SecureStorage.instance.accessToken;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(ApiConstants.baseUrl + path);
    if (query == null || query.isEmpty) return base;
    return base.replace(
      queryParameters: query.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Future<Result<dynamic>> get(String path, {Map<String, dynamic>? query, bool auth = true}) async {
    try {
      final res = await _client
          .get(_uri(path, query), headers: await _headers(withAuth: auth))
          .timeout(ApiConstants.requestTimeout);
      return _parse(res);
    } catch (e) {
      return Failure(_friendlyError(e));
    }
  }

  Future<Result<dynamic>> post(String path, {Object? body, bool auth = true}) async {
    try {
      final res = await _client
          .post(_uri(path), headers: await _headers(withAuth: auth), body: jsonEncode(body ?? {}))
          .timeout(ApiConstants.requestTimeout);
      return _parse(res);
    } catch (e) {
      return Failure(_friendlyError(e));
    }
  }

  Future<Result<dynamic>> put(String path, {Object? body, bool auth = true}) async {
    try {
      final res = await _client
          .put(_uri(path), headers: await _headers(withAuth: auth), body: jsonEncode(body ?? {}))
          .timeout(ApiConstants.requestTimeout);
      return _parse(res);
    } catch (e) {
      return Failure(_friendlyError(e));
    }
  }

  Future<Result<dynamic>> delete(String path, {bool auth = true}) async {
    try {
      final res = await _client
          .delete(_uri(path), headers: await _headers(withAuth: auth))
          .timeout(ApiConstants.requestTimeout);
      return _parse(res);
    } catch (e) {
      return Failure(_friendlyError(e));
    }
  }

  Result<dynamic> _parse(http.Response res) {
    final status = res.statusCode;
    dynamic decoded;
    try {
      decoded = res.body.isEmpty ? {} : jsonDecode(res.body);
    } catch (_) {
      decoded = res.body;
    }
    if (status >= 200 && status < 300) {
      return Success(decoded);
    }
    final message = (decoded is Map && decoded['message'] != null)
        ? decoded['message'].toString()
        : 'Request failed ($status)';
    return Failure(message);
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('TimeoutException')) return 'Server is taking too long to respond. Please try again.';
    if (msg.contains('SocketException')) return 'No internet connection. Please check your network.';
    return 'Something went wrong. Please try again.';
  }
}
