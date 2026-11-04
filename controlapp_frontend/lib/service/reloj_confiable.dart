import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http_parser/http_parser.dart' show parseHttpDate;
import 'package:shared_preferences/shared_preferences.dart';

/// Referencia guardada: la hora del servidor (cabecera `Date` de una
/// respuesta exitosa) y el reloj monotónico del celular en ese instante.
class ReferenciaReloj {
  final DateTime horaServidor;
  final int elapsedMs;

  const ReferenciaReloj({required this.horaServidor, required this.elapsedMs});
}

/// Dónde se guarda la referencia (SharedPreferences en la app; memoria en
/// las pruebas).
abstract class AlmacenReloj {
  Future<ReferenciaReloj?> leer();
  Future<void> guardar(ReferenciaReloj referencia);
}

class _AlmacenPreferencias implements AlmacenReloj {
  static const _kServidor = 'reloj_confiable_servidor_ms';
  static const _kElapsed = 'reloj_confiable_elapsed_ms';

  @override
  Future<ReferenciaReloj?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    final servidor = prefs.getInt(_kServidor);
    final elapsed = prefs.getInt(_kElapsed);
    if (servidor == null || elapsed == null) return null;
    return ReferenciaReloj(
      horaServidor: DateTime.fromMillisecondsSinceEpoch(servidor, isUtc: true),
      elapsedMs: elapsed,
    );
  }

  @override
  Future<void> guardar(ReferenciaReloj referencia) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kServidor,
      referencia.horaServidor.millisecondsSinceEpoch,
    );
    await prefs.setInt(_kElapsed, referencia.elapsedMs);
  }
}

/// Hora "confiable" para lo que se registra sin señal (fotos, cierres,
/// asistencia): la del servidor en la última respuesta exitosa más lo que
/// pasó desde entonces según `SystemClock.elapsedRealtime()` de Android, que
/// no cambia aunque el operario mueva la hora del celular.
///
/// Si el celular se reinició desde la última referencia (el reloj monotónico
/// volvió a empezar, quedó por debajo del guardado) no se puede estimar y se
/// devuelve null: el servidor usa entonces solo la hora del celular y la
/// marca como no verificada.
///
/// En web y en el proceso de segundo plano (sin el canal de MainActivity)
/// siempre devuelve null.
class RelojConfiable {
  RelojConfiable({Future<int?> Function()? leerElapsed, AlmacenReloj? almacen})
    : _leerElapsed = leerElapsed ?? _elapsedDeAndroid,
      _almacen = almacen ?? _AlmacenPreferencias();

  static final RelojConfiable instance = RelojConfiable();

  static const _canal = MethodChannel('controlapp/reloj');

  /// No se reescribe la referencia en disco más seguido que esto.
  static const Duration _cadaCuantoGuardar = Duration(seconds: 30);

  final Future<int?> Function() _leerElapsed;
  final AlmacenReloj _almacen;

  ReferenciaReloj? _enMemoria;
  bool _leidaDelAlmacen = false;
  DateTime? _ultimoGuardado;

  static Future<int?> _elapsedDeAndroid() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _canal.invokeMethod<int>('elapsedRealtime');
    } catch (_) {
      // Proceso de segundo plano o canal no registrado.
      return null;
    }
  }

  /// Hora del servidor (UTC) a partir de la cabecera `Date` de HTTP.
  static DateTime? horaDeCabeceraDate(String? valor) {
    final v = valor?.trim() ?? '';
    if (v.isEmpty) return null;
    try {
      return parseHttpDate(v).toUtc();
    } catch (_) {
      return null;
    }
  }

  /// Lógica pura de la estimación (ver la clase).
  static DateTime? estimar({
    required ReferenciaReloj? referencia,
    required int? elapsedActual,
  }) {
    if (referencia == null || elapsedActual == null) return null;
    if (elapsedActual < referencia.elapsedMs) return null; // se reinició
    return referencia.horaServidor.toUtc().add(
      Duration(milliseconds: elapsedActual - referencia.elapsedMs),
    );
  }

  /// Se llama con cada respuesta exitosa del servidor.
  Future<void> registrarHoraServidor(DateTime horaServidor) async {
    final elapsed = await _leerElapsed();
    if (elapsed == null) return;
    final ref = ReferenciaReloj(
      horaServidor: horaServidor.toUtc(),
      elapsedMs: elapsed,
    );
    _enMemoria = ref;
    _leidaDelAlmacen = true;
    final ahora = DateTime.now();
    final ultimo = _ultimoGuardado;
    if (ultimo != null && ahora.difference(ultimo).abs() < _cadaCuantoGuardar) {
      return;
    }
    _ultimoGuardado = ahora;
    try {
      await _almacen.guardar(ref);
    } catch (_) {
      // Mejor esfuerzo: la referencia en memoria sigue sirviendo.
    }
  }

  /// Hora estimada de este instante (UTC), o null si no se puede confiar.
  Future<DateTime?> estimarAhora() async {
    final elapsed = await _leerElapsed();
    if (elapsed == null) return null;
    if (!_leidaDelAlmacen) {
      _leidaDelAlmacen = true;
      try {
        _enMemoria ??= await _almacen.leer();
      } catch (_) {
        _enMemoria = null;
      }
    }
    return estimar(referencia: _enMemoria, elapsedActual: elapsed);
  }
}
