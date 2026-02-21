import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';

Future<void> logout(BuildContext context) async {
  final session = SessionService();
  NotificacionesCenter.instance.stop();
  await session.clear();
  if (!context.mounted) return;
  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
}
