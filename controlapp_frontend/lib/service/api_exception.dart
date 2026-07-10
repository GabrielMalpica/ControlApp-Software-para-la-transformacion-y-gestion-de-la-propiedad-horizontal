import 'dart:convert';

import 'app_error.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? reason;
  final dynamic details;

  ApiException({
    required this.statusCode,
    required this.message,
    this.reason,
    this.details,
  });

  factory ApiException.fromResponse({
    required int statusCode,
    required String body,
    required String fallback,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }

    String? reason;
    if (decoded is Map<String, dynamic>) {
      reason = decoded['reason']?.toString() ?? decoded['code']?.toString();
    }

    return ApiException(
      statusCode: statusCode,
      message: AppError.fromResponseBody(body, fallback: fallback),
      reason: reason,
      details: decoded ?? body,
    );
  }

  factory ApiException.fromMap(
    Map<String, dynamic> data, {
    int statusCode = 400,
    String fallback = 'No se pudo completar la solicitud.',
  }) {
    return ApiException(
      statusCode: statusCode,
      message: AppError.messageOf(data, fallback: fallback),
      reason: data['reason']?.toString() ?? data['code']?.toString(),
      details: data,
    );
  }

  @override
  String toString() => message;
}
