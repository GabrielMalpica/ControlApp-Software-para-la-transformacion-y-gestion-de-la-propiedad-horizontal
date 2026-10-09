import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'package:flutter_application_1/api/evidencia_api.dart';
import 'package:flutter_application_1/utils/pickers/camera_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/optimizar_imagen_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

/// Foto de evidencia tomada con la cámara de la app, con la hora de la toma y
/// la ubicación GPS de ese momento cuando el dispositivo la da. El backend
/// convierte esos datos en la marca de agua de auditoría (abajo a la
/// derecha) antes de subir la foto a Drive.
///
/// La ubicación es de mejor esfuerzo: sin permiso, sin GPS o sin señal la
/// foto se agrega igual, solo que sin coordenadas.
class EvidenciaCamara {
  EvidenciaCamara._();

  /// Lo máximo que se espera al GPS después de tomar la foto (solo cuando no
  /// hay una ubicación reciente). Pasado esto la foto se agrega sin GPS.
  static const Duration _esperaMaximaGps = Duration(seconds: 4);
  static const Duration _vigenciaUbicacion = Duration(minutes: 2);

  static Position? _ultima;
  static Future<Position?>? _enCurso;

  /// Si el permiso de ubicación ya está concedido, pide una posición desde
  /// ya para que al tomar la foto no haya que esperar al GPS. No muestra
  /// ningún diálogo de permiso.
  static Future<void> precalentarUbicacion() async {
    try {
      final permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.always ||
          permiso == LocationPermission.whileInUse) {
        unawaited(_ubicacion());
      }
    } catch (_) {
      // Sin plugin de ubicación disponible: se sigue sin GPS.
    }
  }

  static Future<SelectedUploadFile?> tomarFoto() async {
    // En web la cámara tiene que abrirse dentro del mismo toque del usuario,
    // así que la ubicación se pide en paralelo. En la app nativa se pide al
    // volver de la cámara para no cruzar dos diálogos de permisos.
    final enParalelo = kIsWeb ? _ubicacion() : null;
    final original = await CameraCapture.pickPhoto();
    if (original == null) return null;

    // La foto se reduce (para que el cierre suba rápido) mientras se espera
    // el GPS: las dos cosas van a la vez.
    final optimizada = OptimizadorImagen.optimizar(original);

    // Sin hora de toma (p. ej. un archivo viejo elegido desde un PC) no es una
    // foto recién tomada: la ubicación actual no sería la de la foto.
    final captura = original.captura;
    if (captura == null) return optimizada;

    final posicion = await _ubicacionDeLaFoto(enParalelo ?? _ubicacion());
    final foto = await optimizada;
    if (posicion == null) return foto;

    // La dirección (calle, barrio, ciudad) se deja lista en el servidor
    // mientras el operario termina el cierre; no se espera.
    unawaited(
      EvidenciaApi().precalentarDireccion(
        posicion.latitude,
        posicion.longitude,
      ),
    );

    return foto.conCaptura(
      captura.conGps(posicion.latitude, posicion.longitude),
    );
  }

  /// Una ubicación de hace menos de 2 minutos sirve (el operario sigue en el
  /// sitio) y no hace esperar nada; [consulta] queda refrescándola para la
  /// próxima foto. Si no hay, se espera máximo [_esperaMaximaGps].
  static Future<Position?> _ubicacionDeLaFoto(
    Future<Position?> consulta,
  ) async {
    final reciente = _ultimaVigente();
    if (reciente != null) return reciente;

    final limite = DateTime.now().add(_esperaMaximaGps);
    final posicion = await _esperar(consulta, limite);
    if (posicion != null) return posicion;
    // Si la consulta ya terminó sin resultado (p. ej. se agotó mientras la
    // cámara estaba abierta) se intenta otra vez dentro del mismo límite; si
    // sigue pendiente (diálogo de permiso abierto) no se insiste.
    if (_enCurso == null) return _esperar(_ubicacion(), limite);
    return null;
  }

  static Future<Position?> _esperar(
    Future<Position?> consulta,
    DateTime limite,
  ) {
    final restante = limite.difference(DateTime.now());
    if (restante <= Duration.zero) return Future.value(null);
    return consulta.timeout(restante, onTimeout: () => null);
  }

  static Position? _ultimaVigente() {
    final ultima = _ultima;
    if (ultima == null) return null;
    final edad = DateTime.now().difference(ultima.timestamp);
    return edad <= _vigenciaUbicacion ? ultima : null;
  }

  static Future<Position?> _ubicacion() {
    return _enCurso ??= _leerUbicacion().whenComplete(() => _enCurso = null);
  }

  static Future<Position?> _leerUbicacion() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return null;
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _ultima = posicion;
      return posicion;
    } catch (_) {
      return null;
    }
  }
}
