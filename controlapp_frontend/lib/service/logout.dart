import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';

Future<void> logout(BuildContext context) async {
  NotificacionesCenter.instance.stop();
  // Cierra tambien en el servidor: revoca el token y la cookie de la sesion
  // web, no solo lo que hay en este dispositivo.
  await AuthApi().logout();
  if (!context.mounted) return;
  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
}
