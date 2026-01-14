import 'dart:convert';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  final Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'x-empresa-id': AppConstants.empresaNit,
  };

  Uri _uri(String urlOrPath) {
    // Si ya viene completo (http/https), úsalo tal cual.
    if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return Uri.parse(urlOrPath);
    }
    // Si viene path (/empresa/...), lo pegamos al baseUrl.
    final base = AppConstants.baseUrl; // ej: http://localhost:3000
    return Uri.parse('$base$urlOrPath');
  }

  Future<http.Response> get(String urlOrPath) async {
    final uri = _uri(urlOrPath);
    final resp = await http.get(uri, headers: defaultHeaders);
    return resp;
  }

  Future<http.Response> post(String urlOrPath, {Object? body}) async {
    final uri = _uri(urlOrPath);
    return http.post(
      uri,
      headers: defaultHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> put(String urlOrPath, {Object? body}) async {
    final uri = _uri(urlOrPath);
    return http.put(
      uri,
      headers: defaultHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> patch(String urlOrPath, {Object? body}) async {
    final uri = _uri(urlOrPath);
    return http.patch(
      uri,
      headers: defaultHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> delete(String urlOrPath) async {
    final uri = _uri(urlOrPath);
    return http.delete(uri, headers: defaultHeaders);
  }
}
