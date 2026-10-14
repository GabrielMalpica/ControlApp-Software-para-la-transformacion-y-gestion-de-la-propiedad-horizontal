import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'package:flutter_application_1/api/evidencia_api.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/service/ubicacion_service.dart';
import 'package:flutter_application_1/utils/pickers/camera_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/exif_captura.dart';
import 'package:flutter_application_1/utils/pickers/optimizar_imagen_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

/// Foto de evidencia con la hora de la toma y la ubicación GPS de ese
/// momento cuando el dispositivo la da. El backend convierte esos datos en la
/// marca de agua de auditoría (abajo a la derecha) antes de subir la foto a
/// Drive.
///
/// La ubicación es de mejor esfuerzo: sin permiso, sin GPS o sin señal la
/// foto se agrega igual, solo que sin coordenadas (y el cierre muestra
/// [ubicacionNegada] para que el operario sepa por qué).
class EvidenciaCamara {
  EvidenciaCamara._();

  /// Lo máximo que se espera al GPS después de tomar la foto (solo cuando no
  /// hay una ubicación reciente). Pasado esto la foto se agrega sin GPS.
  static const Duration _esperaMaximaGps = Duration(seconds: 4);
  static const Duration _vigenciaUbicacion = Duration(minutes: 2);

  /// Una foto de la galería tomada hace menos de esto se toma como recién
  /// tomada en el sitio: lleva la ubicación actual del celular, como las de
  /// la cámara de la app. Las más viejas solo llevan su hora de toma.
  static const Duration recienTomada = Duration(minutes: 30);

  /// true cuando el navegador o el celular negó el permiso de ubicación.
  static final ValueNotifier<bool> ubicacionNegada = ValueNotifier(false);

  static Position? _ultima;
  static Future<Position?>? _enCurso;

  /// Se llama al abrir un cierre: pide el permiso de ubicación si todavía no
  /// se ha preguntado y deja una posición lista, para que al tomar la foto no
  /// haya que esperar al GPS ni aparezca el diálogo de permiso en medio de la
  /// cámara.
  static Future<void> precalentarUbicacion() async {
    final permiso = await UbicacionDispositivo.permiso();
    if (permiso == PermisoUbicacion.denegado) {
      ubicacionNegada.value = true;
      return;
    }
    unawaited(_ubicacion());
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

    _precalentarDireccion(posicion);
    return foto.conCaptura(
      captura.conGps(posicion.latitude, posicion.longitude),
    );
  }

  /// Fotos elegidas de la galería: toma del EXIF la hora en que se tomaron
  /// (antes de reducirlas, porque al reducirlas se pierde) y, a las tomadas
  /// hace menos de [recienTomada] que no traen GPS propio, les pone la
  /// ubicación actual. Los PDF y las fotos sin EXIF (WhatsApp) quedan igual:
  /// en la marca de agua solo dirán cuándo se subieron.
  static Future<List<SelectedUploadFile>> prepararDeGaleria(
    Iterable<SelectedUploadFile> archivos,
  ) async {
    final ahora = DateTime.now();
    final conHora = [
      for (final a in archivos)
        a.captura != null ? a : a.conCaptura(capturaDesdeExif(a.bytes)),
    ];
    bool sinGpsYReciente(CapturaEvidencia? c) =>
        c != null && !c.tieneGps && esRecienTomada(c.tomadaEn, ahora);

    final optimizadas = OptimizadorImagen.optimizarTodas(conHora);
    final posicion = conHora.any((a) => sinGpsYReciente(a.captura))
        ? await _ubicacionDeLaFoto(_ubicacion())
        : null;
    final fotos = await optimizadas;
    if (posicion == null) return fotos;

    _precalentarDireccion(posicion);
    return [
      for (final f in fotos)
        sinGpsYReciente(f.captura)
            ? f.conCaptura(
                f.captura!.conGps(posicion.latitude, posicion.longitude),
              )
            : f,
    ];
  }

  static bool esRecienTomada(DateTime tomadaEn, DateTime ahora) {
    final edad = ahora.difference(tomadaEn);
    return edad <= recienTomada && edad >= const Duration(minutes: -1);
  }

  /// La dirección (calle, barrio, ciudad) se deja lista en el servidor
  /// mientras el operario termina el cierre; no se espera.
  static void _precalentarDireccion(Position posicion) {
    unawaited(
      EvidenciaApi().precalentarDireccion(
        posicion.latitude,
        posicion.longitude,
      ),
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
      final posicion = await UbicacionDispositivo.obtener(
        espera: const Duration(seconds: 20),
      );
      _ultima = posicion;
      ubicacionNegada.value = false;
      return posicion;
    } on UbicacionException catch (e) {
      if (e.fallo == FalloUbicacion.permisoDenegado) {
        ubicacionNegada.value = true;
      }
      return null;
    }
  }
}
