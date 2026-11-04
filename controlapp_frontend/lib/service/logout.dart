import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/service/offline/cierre_tarea_offline_store.dart';
import 'package:flutter_application_1/service/session_service.dart';

/// Cierra la sesión. Si hay cierres o asistencias guardados sin señal, avisa
/// primero: no se borran (quedan en el teléfono y se envían cuando ese usuario
/// vuelva a entrar con señal), pero mientras tanto nadie los envía.
Future<void> logout(BuildContext context) async {
  final pendientes = await _pendientesSinEnviar();
  if (pendientes > 0) {
    if (!context.mounted) return;
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tienes registros sin enviar'),
        content: Text(
          '$pendientes ${pendientes == 1 ? 'cierre o asistencia guardado' : 'cierres o asistencias guardados'} '
          'en este teléfono todavía no ${pendientes == 1 ? 'llegó' : 'llegaron'} al servidor. '
          'No se borran: se enviarán cuando vuelvas a entrar con tu usuario y haya señal. '
          'Mientras tengas la sesión cerrada no se envían.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Quedarme'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión igual'),
          ),
        ],
      ),
    );
    if (seguir != true) return;
  }

  NotificacionesCenter.instance.stop();
  // Cierra tambien en el servidor: revoca el token, la cookie de la sesion
  // web y el token de renovación de la app, no solo lo que hay en este
  // dispositivo.
  await AuthApi().logout();
  if (!context.mounted) return;
  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
}

Future<int> _pendientesSinEnviar() async {
  try {
    final uid = (await SessionService().getUserId())?.trim() ?? '';
    if (uid.isEmpty) return 0;
    return await CierreTareaOfflineStore.instance.contarSinEnviar(
      usuarioId: uid,
    );
  } catch (_) {
    return 0;
  }
}
