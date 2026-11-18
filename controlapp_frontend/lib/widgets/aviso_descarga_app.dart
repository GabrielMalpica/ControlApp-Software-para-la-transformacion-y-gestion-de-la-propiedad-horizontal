import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_application_1/service/theme.dart';

/// Qué se sabe de la APK publicada en `/descargas/`.
enum DisponibilidadApk {
  /// Aún no se ha revisado (o no se pudo: sin señal). Se muestra igual.
  desconocida,

  /// `descargas/android.json` existe: hay APK para descargar.
  publicada,

  /// El servidor no tiene la APK (404, o responde con la página de la app).
  noPublicada,
}

/// Versión publicada, para mostrarla junto al botón.
class InfoApkPublicada {
  final String versionName;
  final int? tamanoBytes;

  const InfoApkPublicada({required this.versionName, this.tamanoBytes});

  String get resumen {
    final mb = tamanoBytes == null
        ? ''
        : ' · ${(tamanoBytes! / 1048576).toStringAsFixed(0)} MB';
    return versionName.isEmpty
        ? mb.replaceFirst(' · ', '')
        : 'Versión $versionName$mb';
  }
}

/// Lee `descargas/android.json` del mismo sitio. Devuelve la disponibilidad y,
/// si está publicada, la versión.
Future<(DisponibilidadApk, InfoApkPublicada?)> revisarApkPublicada(
  Uri manifiesto, {
  http.Client? cliente,
}) async {
  final c = cliente ?? http.Client();
  try {
    final r = await c
        .get(manifiesto, headers: const {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 10));
    final tipo = r.headers['content-type'] ?? '';
    if (r.statusCode == 404 || r.statusCode == 410) {
      return (DisponibilidadApk.noPublicada, null);
    }
    if (r.statusCode != 200) return (DisponibilidadApk.desconocida, null);
    // Sin la APK, Hostinger respondía con index.html (200, text/html).
    if (tipo.contains('text/html') || r.body.trimLeft().startsWith('<')) {
      return (DisponibilidadApk.noPublicada, null);
    }
    final json = jsonDecode(r.body);
    if (json is! Map || json['versionCode'] is! num) {
      return (DisponibilidadApk.noPublicada, null);
    }
    return (
      DisponibilidadApk.publicada,
      InfoApkPublicada(
        versionName: json['versionName']?.toString() ?? '',
        tamanoBytes: (json['tamanoBytes'] as num?)?.toInt(),
      ),
    );
  } catch (_) {
    return (DisponibilidadApk.desconocida, null);
  } finally {
    if (cliente == null) c.close();
  }
}

/// En la web abierta desde un celular Android: invita a instalar la app, que
/// funciona sin señal (los operarios no tienen internet en muchos conjuntos).
/// La APK se publica en `/descargas/controlapp.apk` del mismo sitio (workflow
/// "App Android y web"). Si no está publicada, el aviso no se muestra.
class AvisoDescargaApp extends StatefulWidget {
  const AvisoDescargaApp({
    super.key,
    this.forzarMostrar = false,
    this.revisar,
    this.abrir,
  });

  /// Para pruebas.
  final bool forzarMostrar;

  /// Para pruebas: reemplaza la consulta a `android.json`.
  final Future<(DisponibilidadApk, InfoApkPublicada?)> Function()? revisar;

  /// Para pruebas: reemplaza abrir la URL de la APK.
  final Future<bool> Function(Uri url)? abrir;

  static bool get aplica =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Uri get urlApk => Uri.base.resolve('/descargas/controlapp.apk');
  static Uri get urlManifiesto => Uri.base.resolve('/descargas/android.json');

  @override
  State<AvisoDescargaApp> createState() => _AvisoDescargaAppState();
}

class _AvisoDescargaAppState extends State<AvisoDescargaApp> {
  DisponibilidadApk _disponibilidad = DisponibilidadApk.desconocida;
  InfoApkPublicada? _info;
  bool _abriendo = false;

  bool get _visible => AvisoDescargaApp.aplica || widget.forzarMostrar;

  @override
  void initState() {
    super.initState();
    if (_visible) unawaited(_revisar());
  }

  Future<(DisponibilidadApk, InfoApkPublicada?)> _consultar() =>
      widget.revisar?.call() ??
      revisarApkPublicada(AvisoDescargaApp.urlManifiesto);

  Future<void> _revisar() async {
    final (d, info) = await _consultar();
    if (!mounted) return;
    setState(() {
      _disponibilidad = d;
      _info = info;
    });
  }

  Future<void> _descargar() async {
    if (_abriendo) return;
    setState(() => _abriendo = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // Se vuelve a revisar justo antes: si no está, se dice en vez de abrir
      // una página que regresa al inicio.
      final (d, info) = await _consultar();
      if (!mounted) return;
      if (d == DisponibilidadApk.noPublicada) {
        setState(() => _disponibilidad = d);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'La app todavía no está publicada para descargar. Intenta más tarde o avísale a tu supervisor.',
            ),
          ),
        );
        return;
      }
      if (info != null) setState(() => _info = info);
      final ok =
          await (widget.abrir?.call(AvisoDescargaApp.urlApk) ??
              launchUrl(
                AvisoDescargaApp.urlApk,
                mode: LaunchMode.externalApplication,
              ));
      if (!ok && mounted) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la descarga. Intenta de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _disponibilidad == DisponibilidadApk.noPublicada) {
      return const SizedBox.shrink();
    }
    final resumen = _info?.resumen ?? '';
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
            onPressed: _abriendo ? null : _descargar,
            icon: _abriendo
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: const Text('Descargar la app'),
          ),
          if (resumen.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              resumen,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Cómo instalarla:\n'
            '1. Toca "Descargar la app" y espera a que termine.\n'
            '2. Abre el archivo controlapp.apk (en la notificación o en Descargas).\n'
            '3. Si Android dice que no se puede instalar, toca "Ajustes" y activa "Permitir de esta fuente" para tu navegador; vuelve atrás.\n'
            '4. Toca "Instalar", abre ControlApp y entra con tu mismo correo y contraseña.\n'
            'Cuando haya una versión nueva, la app te avisará con el botón "Actualizar".',
            style: TextStyle(color: AppTheme.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
