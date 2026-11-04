import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';

import 'app_info.dart';
import 'http/cliente_http_app.dart';
import 'offline/tarea_sync_engine.dart';

/// `descargas/android.json`, lo que publica el workflow de GitHub Actions
/// junto a la APK.
class ManifiestoAndroid {
  final int versionCode;
  final String versionName;
  final Uri url;
  final String sha256;
  final int? tamanoBytes;
  final DateTime? publicadaEn;
  final int minimaVersionCode;
  final String notas;

  const ManifiestoAndroid({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.minimaVersionCode,
    this.tamanoBytes,
    this.publicadaEn,
    this.notas = '',
  });

  /// [base]: la URL del manifiesto, para resolver una `url` relativa.
  static ManifiestoAndroid? fromJson(Object? json, {Uri? base}) {
    if (json is! Map) return null;
    final code = json['versionCode'];
    final url = json['url']?.toString().trim() ?? '';
    final sha = json['sha256']?.toString().trim().toLowerCase() ?? '';
    if (code is! num || url.isEmpty || sha.length != 64) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final minima = json['minimaVersionCode'];
    return ManifiestoAndroid(
      versionCode: code.toInt(),
      versionName: json['versionName']?.toString() ?? '',
      url: base == null ? uri : base.resolveUri(uri),
      sha256: sha,
      minimaVersionCode: minima is num ? minima.toInt() : 0,
      tamanoBytes: (json['tamanoBytes'] as num?)?.toInt(),
      publicadaEn: DateTime.tryParse(json['publicadaEn']?.toString() ?? ''),
      notas: json['notas']?.toString() ?? '',
    );
  }
}

enum EstadoActualizacion {
  /// Está al día (o no se sabe).
  ninguna,

  /// Hay una versión más nueva: se ofrece, no se obliga.
  disponible,

  /// Por debajo de la mínima (o el servidor respondió 426): no se puede
  /// seguir sin actualizar. Lo guardado sin señal se conserva.
  obligatoria,
}

/// Decisión pura (probada en test/actualizacion_app_test.dart).
EstadoActualizacion decidirActualizacion({
  required int? instalada,
  required ManifiestoAndroid? manifiesto,
  bool servidorExige = false,
}) {
  if (servidorExige) return EstadoActualizacion.obligatoria;
  if (instalada == null || manifiesto == null) {
    return EstadoActualizacion.ninguna;
  }
  if (instalada < manifiesto.minimaVersionCode) {
    return EstadoActualizacion.obligatoria;
  }
  if (manifiesto.versionCode > instalada) {
    return EstadoActualizacion.disponible;
  }
  return EstadoActualizacion.ninguna;
}

/// ¿Toca volver a preguntar? Al abrir y al volver a la app, como mucho cada
/// [intervalo].
bool debeConsultarActualizacion({
  required DateTime? ultimaConsulta,
  required DateTime ahora,
  Duration intervalo = const Duration(minutes: 30),
}) {
  if (ultimaConsulta == null) return true;
  return ahora.difference(ultimaConsulta) >= intervalo;
}

/// Avance de la descarga de la APK nueva.
class ProgresoActualizacion {
  /// 0-100 mientras descarga; null en los demás estados.
  final int? porcentaje;
  final bool instalando;
  final String? error;

  const ProgresoActualizacion({
    this.porcentaje,
    this.instalando = false,
    this.error,
  });
}

/// Auto-actualización de la app Android desde
/// `https://controlapp.controlsas.com.co/descargas/` (sin Play Store). Ver
/// docs/app-android-sin-conexion.md, "App".
class ActualizacionAppService {
  ActualizacionAppService._();
  static final ActualizacionAppService instance = ActualizacionAppService._();

  static const String urlManifiesto = String.fromEnvironment(
    'APP_DESCARGAS_URL',
    defaultValue: 'https://controlapp.controlsas.com.co/descargas/android.json',
  );

  final ValueNotifier<EstadoActualizacion> estado = ValueNotifier(
    EstadoActualizacion.ninguna,
  );

  ManifiestoAndroid? _manifiesto;
  ManifiestoAndroid? get manifiesto => _manifiesto;
  bool _servidorExige = false;
  DateTime? _ultimaConsulta;
  Future<void>? _consultando;

  static bool get soportada =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Conecta los avisos de 426 del cliente HTTP y de la cola.
  void registrarAvisos() {
    if (!soportada) return;
    ClienteHttpApp.alAppDesactualizadaGlobal = marcarObligatoriaPorServidor;
    TareaSyncEngine.alAppDesactualizada = marcarObligatoriaPorServidor;
  }

  void marcarObligatoriaPorServidor() {
    if (_servidorExige) return;
    _servidorExige = true;
    _recalcular();
    // Para descargar hace falta el manifiesto (URL y sha256).
    if (_manifiesto == null) unawaited(consultar(forzar: true));
  }

  void _recalcular() {
    estado.value = decidirActualizacion(
      instalada: AppInfo.versionCode,
      manifiesto: _manifiesto,
      servidorExige: _servidorExige,
    );
  }

  /// Lee el manifiesto (máx. cada 30 min salvo [forzar]). Sin señal no pasa
  /// nada: se vuelve a intentar al volver a la app.
  Future<void> consultar({bool forzar = false}) {
    if (!soportada) return Future.value();
    final ahora = DateTime.now();
    if (!forzar &&
        !debeConsultarActualizacion(
          ultimaConsulta: _ultimaConsulta,
          ahora: ahora,
        )) {
      return Future.value();
    }
    return _consultando ??= _consultar().whenComplete(
      () => _consultando = null,
    );
  }

  Future<void> _consultar() async {
    try {
      await AppInfo.cargar();
      final uri = Uri.parse(urlManifiesto);
      final resp = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;
      final m = ManifiestoAndroid.fromJson(jsonDecode(resp.body), base: uri);
      if (m == null) return;
      _manifiesto = m;
      _ultimaConsulta = DateTime.now();
      _recalcular();
    } catch (_) {
      // Sin señal o manifiesto ilegible: se reintenta más tarde.
    }
  }

  /// Descarga la APK, verifica su sha256 y abre el instalador de Android.
  Stream<ProgresoActualizacion> descargarEInstalar() async* {
    final m = _manifiesto;
    if (m == null) {
      yield const ProgresoActualizacion(
        error:
            'No se pudo leer la versión nueva. Revisa la señal e intenta de nuevo.',
      );
      return;
    }
    try {
      await for (final e in OtaUpdate().execute(
        m.url.toString(),
        destinationFilename: 'controlapp-${m.versionCode}.apk',
        sha256checksum: m.sha256,
      )) {
        switch (e.status) {
          case OtaStatus.DOWNLOADING:
            yield ProgresoActualizacion(
              porcentaje: int.tryParse(e.value ?? '')?.clamp(0, 100),
            );
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            yield const ProgresoActualizacion(instalando: true);
          case OtaStatus.ALREADY_RUNNING_ERROR:
            yield const ProgresoActualizacion(
              error: 'La descarga ya está en curso.',
            );
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            yield const ProgresoActualizacion(
              error:
                  'Android no dejó instalar. Permite "Instalar apps desconocidas" para ControlApp en Ajustes e intenta de nuevo.',
            );
          case OtaStatus.CHECKSUM_ERROR:
            yield const ProgresoActualizacion(
              error:
                  'El archivo descargado no coincide con la versión publicada. Intenta de nuevo con buena señal.',
            );
          case OtaStatus.DOWNLOAD_ERROR:
          case OtaStatus.INTERNAL_ERROR:
          case OtaStatus.INSTALLATION_ERROR:
          case OtaStatus.CANCELED:
            yield const ProgresoActualizacion(
              error:
                  'No se pudo descargar la actualización. Revisa la señal e intenta de nuevo.',
            );
        }
      }
    } catch (_) {
      yield const ProgresoActualizacion(
        error:
            'No se pudo descargar la actualización. Revisa la señal e intenta de nuevo.',
      );
    }
  }

  @visibleForTesting
  void reiniciarParaPruebas() {
    _manifiesto = null;
    _servidorExige = false;
    _ultimaConsulta = null;
    estado.value = EstadoActualizacion.ninguna;
  }
}
