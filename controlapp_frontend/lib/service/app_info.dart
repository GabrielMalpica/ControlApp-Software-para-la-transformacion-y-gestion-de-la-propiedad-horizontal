import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Versión instalada de la app nativa (Android). El backend la recibe en
/// cada petición (`X-App-Version` = versionCode, `X-App-Plataforma`) y la
/// auto-actualización la compara con `descargas/android.json`.
///
/// En web no aplica: la web se actualiza sola (ver `AvisoVersionNueva`).
class AppInfo {
  AppInfo._();

  static int? _versionCode;
  static String? _versionName;
  static Future<void>? _carga;

  static int? get versionCode => _versionCode;
  static String? get versionName => _versionName;

  /// `android` en la app nativa de Android; null en web y otras plataformas
  /// (no mandan cabeceras de versión).
  static String? get plataforma {
    if (kIsWeb) return null;
    return defaultTargetPlatform == TargetPlatform.android ? 'android' : null;
  }

  static Future<void> cargar() {
    if (kIsWeb) return Future.value();
    return _carga ??= _leer();
  }

  static Future<void> _leer() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _versionCode = int.tryParse(info.buildNumber.trim());
      _versionName = info.version.trim();
    } catch (_) {
      // Sin la información de versión las peticiones salen sin cabeceras y
      // el backend las trata como de una app que no reporta versión.
    }
  }

  /// Cabeceras de versión para las peticiones nativas (vacías en web).
  static Future<Map<String, String>> cabeceras() async {
    final plat = plataforma;
    if (plat == null) return const {};
    await cargar();
    final code = _versionCode;
    return {
      'X-App-Plataforma': plat,
      if (code != null) 'X-App-Version': '$code',
    };
  }

  @visibleForTesting
  static void fijarParaPruebas({int? versionCode, String? versionName}) {
    _versionCode = versionCode;
    _versionName = versionName;
    _carga = Future.value();
  }
}
