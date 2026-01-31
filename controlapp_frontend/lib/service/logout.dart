import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/session_service.dart';

Future<void> logout(BuildContext context) async {
  final session = SessionService();
  await session.clear();
  if (!context.mounted) return;
  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
}
