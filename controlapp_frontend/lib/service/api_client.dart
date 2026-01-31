import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  final SessionService _session = SessionService();

  Uri _uri(String urlOrPath) {
    if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return Uri.parse(urlOrPath);
    }
    final base = AppConstants.baseUrl;
    return Uri.parse('$base$urlOrPath');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _session.getToken();
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-empresa-id': AppConstants.empresaNit,
    };

    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }

    if (kDebugMode) {
    }
    return h;
  }

  Future<http.Response> get(String urlOrPath) async {
    final uri = _uri(urlOrPath);
    return http.get(uri, headers: await _headers());
  }

  Future<http.Response> post(String urlOrPath, {Object? body}) async {
    final uri = _uri(urlOrPath);
    return http.post(
      uri,
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> put(String urlOrPath, {Object? body}) async {
    final uri = _uri(urlOrPath);
    return http.put(
      uri,
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> patch(String urlOrPath, {Object? body}) async {
    final uri = _uri(urlOrPath);
    return http.patch(
      uri,
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> delete(String urlOrPath) async {
    final uri = _uri(urlOrPath);
    return http.delete(uri, headers: await _headers());
  }
}
