import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// Estado del permiso de ubicación, leído sin mostrar ningún diálogo.
enum PermisoUbicacion {
  concedido,

  /// Todavía no se ha preguntado (o se puede volver a preguntar).
  porPreguntar,

  /// Negado: el navegador o el sistema ya no vuelve a preguntar, hay que
  /// activarlo a mano en la configuración.
  denegado,

  /// El navegador no deja consultarlo sin preguntar (Safari antiguo).
  desconocido,
}

/// Por qué no se pudo obtener la ubicación.
enum FalloUbicacion { permisoDenegado, gpsApagado, sinSenal }

class UbicacionException implements Exception {
  const UbicacionException(this.fallo);

  final FalloUbicacion fallo;

  String get mensaje => switch (fallo) {
    FalloUbicacion.permisoDenegado =>
      'No diste permiso de ubicación a ControlApp. Actívalo y vuelve a intentarlo.',
    FalloUbicacion.gpsApagado =>
      'La ubicación (GPS) del celular está apagada. Actívala y vuelve a intentarlo.',
    FalloUbicacion.sinSenal =>
      'No logramos ubicarte. Acércate a una ventana o a un lugar despejado y vuelve a intentarlo.',
  };

  @override
  String toString() => mensaje;
}

/// Ubicación del dispositivo para la asistencia por QR y la marca de agua de
/// las evidencias, igual en web y en la app nativa.
///
/// En web no se usa `timeLimit` ni `requestPermission()` de geolocator:
/// geolocator_web 4.1.x le pasa el tiempo límite al navegador en
/// microsegundos (10 s se vuelven casi 3 horas) y su `requestPermission()`
/// reporta cualquier falla, hasta una falta de señal, como "denegado para
/// siempre". Aquí la espera se controla del lado de Dart y el error del
/// navegador dice la causa real.
class UbicacionDispositivo {
  UbicacionDispositivo._();

  static Future<PermisoUbicacion> permiso() async {
    try {
      return switch (await Geolocator.checkPermission()) {
        LocationPermission.always ||
        LocationPermission.whileInUse => PermisoUbicacion.concedido,
        // En web 'prompt' llega como denied.
        LocationPermission.denied => PermisoUbicacion.porPreguntar,
        LocationPermission.deniedForever => PermisoUbicacion.denegado,
        LocationPermission.unableToDetermine => PermisoUbicacion.desconocido,
      };
    } catch (_) {
      return PermisoUbicacion.desconocido;
    }
  }

  /// Posición actual; si hace falta muestra el diálogo de permiso del
  /// navegador o del sistema. Acepta una lectura de hasta [edadMaxima] que el
  /// dispositivo ya tenga, que llega al instante. Lanza [UbicacionException]
  /// si no se pudo en [espera].
  static Future<Position> obtener({
    Duration espera = const Duration(seconds: 20),
    Duration edadMaxima = const Duration(seconds: 30),
  }) {
    return kIsWeb
        ? _obtenerWeb(espera, edadMaxima)
        : _obtenerNativa(espera, edadMaxima);
  }

  static Future<Position> _obtenerWeb(
    Duration espera,
    Duration edadMaxima,
  ) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: WebSettings(
          accuracy: LocationAccuracy.high,
          maximumAge: edadMaxima,
        ),
      ).timeout(espera);
    } on PermissionDeniedException {
      throw const UbicacionException(FalloUbicacion.permisoDenegado);
    } on PositionUpdateException {
      // POSITION_UNAVAILABLE: casi siempre la ubicación del celular apagada.
      throw const UbicacionException(FalloUbicacion.gpsApagado);
    } catch (_) {
      throw const UbicacionException(FalloUbicacion.sinSenal);
    }
  }

  static Future<Position> _obtenerNativa(
    Duration espera,
    Duration edadMaxima,
  ) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const UbicacionException(FalloUbicacion.gpsApagado);
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        throw const UbicacionException(FalloUbicacion.permisoDenegado);
      }

      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null &&
          DateTime.now().difference(ultima.timestamp) <= edadMaxima) {
        return ultima;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: espera,
        ),
      );
    } on UbicacionException {
      rethrow;
    } on LocationServiceDisabledException {
      throw const UbicacionException(FalloUbicacion.gpsApagado);
    } on PermissionDeniedException {
      throw const UbicacionException(FalloUbicacion.permisoDenegado);
    } catch (_) {
      throw const UbicacionException(FalloUbicacion.sinSenal);
    }
  }
}
