import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/actualizacion_web/actualizacion_web_bridge.dart';
import 'package:flutter_application_1/service/actualizacion_web/version_web.dart';
import 'package:flutter_application_1/service/theme.dart';

/// "Versión de la app: 14 oct 2026, 2:41 p. m." (cuándo se publicó la
/// versión que está usando). Sirve para saber, preguntándole a alguien, si ya
/// tiene la última: las versiones anteriores a este texto no lo muestran.
/// Fuera del navegador no muestra nada.
class VersionWebTexto extends StatelessWidget {
  const VersionWebTexto({super.key, this.fechaHttpVersion});

  /// Para pruebas; por defecto la que guardó el arranque al abrir la app.
  final String? fechaHttpVersion;

  @override
  Widget build(BuildContext context) {
    final fecha = fechaHttp(
      fechaHttpVersion ?? ActualizacionWeb.fechaVersion(),
    );
    if (fecha == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Versión de la app: ${textoVersionWeb(fecha)}',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
      ),
    );
  }
}
