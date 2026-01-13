import 'dart:convert';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  final Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'x-empresa-id': AppConstants.empresaNit,
  };

  Future<http.Response> get(String url) async {
    return await http.get(Uri.parse(url), headers: defaultHeaders);
  }

  Future<http.Response> post(String url, {Map<String, dynamic>? body}) async {
    return await http.post(
      Uri.parse(url),
      headers: defaultHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> put(String url, {Map<String, dynamic>? body}) async {
    return await http.put(
      Uri.parse(url),
      headers: defaultHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> patch(String url, {Map<String, dynamic>? body}) async {
    return await http.patch(
      Uri.parse(url),
      headers: defaultHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> delete(String url) async {
    return await http.delete(Uri.parse(url), headers: defaultHeaders);
  }
}
