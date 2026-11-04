import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_application_1/service/theme.dart';

/// En la web abierta desde un celular Android: invita a instalar la app, que
/// funciona sin señal (los operarios no tienen internet en muchos conjuntos).
/// La APK se publica en `/descargas/controlapp.apk` del mismo sitio.
class AvisoDescargaApp extends StatelessWidget {
  const AvisoDescargaApp({super.key, this.forzarMostrar = false});

  /// Para pruebas.
  final bool forzarMostrar;

  static bool get aplica =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Uri get urlApk => Uri.base.resolve('/descargas/controlapp.apk');

  Future<void> _descargar(BuildContext context) async {
    final ok = await launchUrl(urlApk, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la descarga. Intenta de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!aplica && !forzarMostrar) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.android_rounded, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Descarga la app: funciona sin señal',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Con la app de Android puedes cerrar actividades y marcar asistencia aunque no haya internet; se envían solas cuando vuelve la señal.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _descargar(context),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Descargar la app'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Cómo instalarla:\n'
            '1. Toca "Descargar la app" y espera a que termine.\n'
            '2. Abre el archivo controlapp.apk (en la notificación o en Descargas).\n'
            '3. Si Android dice que no se puede instalar, toca "Ajustes" y activa "Permitir de esta fuente" para tu navegador; vuelve atrás.\n'
            '4. Toca "Instalar", abre ControlApp y entra con tu mismo correo y contraseña.',
            style: TextStyle(color: AppTheme.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
