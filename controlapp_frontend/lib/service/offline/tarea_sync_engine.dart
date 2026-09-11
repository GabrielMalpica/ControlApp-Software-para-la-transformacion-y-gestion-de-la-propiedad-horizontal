import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import '../../api/operario_api.dart';
import '../../model/cierre_tarea_pendiente_model.dart';
import '../../model/evidencia_adjunto_model.dart';
import '../app_error.dart';
import '../session_service.dart';
import 'cierre_tarea_offline_store.dart';
import 'connectivity_service.dart';
import 'error_classifier.dart';

enum ResultadoSincronizacion {
  sincronizado,
  reintentable,
  errorPermanente,
  sesionExpirada,
}

/// Backoff exponencial para fallas de red/servidor: 30s, 2min, 10min, y
/// luego cada hora indefinidamente. Un cierre nunca se abandona por una
/// falla de conectividad — solo un error de negocio (4xx) lo saca de la
/// cola automática.
const List<Duration> _backoff = [
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
  Duration(hours: 1),
];

/// Drena la cola de cierres pendientes del operario hacia el backend
/// cuando hay conexión real, respetando orden de creación, reintentos con
/// backoff, y pausando todo si la sesión expiró en vez de perder la cola.
class TareaSyncEngine {
  TareaSyncEngine._();
  static final TareaSyncEngine instance = TareaSyncEngine._();

  final CierreTareaOfflineStore _store = CierreTareaOfflineStore.instance;
  final OperarioApi _operarioApi = OperarioApi();
  final SessionService _session = SessionService();

  bool _sincronizando = false;
  bool _sesionExpirada = false;
  StreamSubscription<void>? _conexionSub;

  final _cambiosController = StreamController<void>.broadcast();

  /// Se emite cada vez que cambia el estado de la cola (nuevo cierre,
  /// avance de sincronización, error, purga) para que la UI refresque.
  Stream<void> get onCambios => _cambiosController.stream;

  bool get sesionExpirada => _sesionExpirada;

  void iniciar() {
    ConnectivityService.instance.iniciar();
    _conexionSub ??= ConnectivityService.instance.onConexionRestaurada.listen((
      _,
    ) {
      sincronizarAhora();
    });
    // `onConnectivityChanged` solo notifica cambios; si la app arranca con
    // conexión ya disponible, hay que intentar sincronizar una vez de
    // entrada en vez de esperar un cambio que quizás nunca llegue.
    sincronizarAhora();
  }

  void detener() {
    _conexionSub?.cancel();
    _conexionSub = null;
    ConnectivityService.instance.detener();
  }

  /// Llamar tras un login exitoso: reanuda la cola pausada por un 401.
  void notificarSesionRestaurada() {
    _sesionExpirada = false;
    sincronizarAhora();
  }

  Future<void> sincronizarAhora({String? usuarioId}) async {
    if (_sincronizando || _sesionExpirada) return;

    final uid = usuarioId ?? await _session.getUserId();
    if (uid == null || uid.isEmpty) return;

    _sincronizando = true;
    try {
      await _store.purgarSincronizados();
      final pendientes = await _store.listarCierres(usuarioId: uid);
      final ahora = DateTime.now();

      for (final cierre in pendientes) {
        if (cierre.estadoSync == CierreSyncEstado.sincronizado) continue;
        if (cierre.estadoSync == CierreSyncEstado.error) continue;
        if (cierre.nextAttemptAt != null &&
            cierre.nextAttemptAt!.isAfter(ahora)) {
          continue;
        }

        final resultado = await _procesarCierre(cierre);
        if (resultado == ResultadoSincronizacion.sesionExpirada) {
          _sesionExpirada = true;
          break;
        }
      }
    } finally {
      _sincronizando = false;
      _cambiosController.add(null);
    }
  }

  Future<void> reintentarManual({
    required String usuarioId,
    required String clienteCierreId,
  }) async {
    final cierres = await _store.listarCierres(usuarioId: usuarioId);
    final cierre = cierres.firstWhereOrNull(
      (c) => c.clienteCierreId == clienteCierreId,
    );
    if (cierre == null) return;

    final reiniciado = cierre.copyWith(
      estadoSync: CierreSyncEstado.pendiente,
      intentos: 0,
      nextAttemptAt: null,
      limpiarError: true,
    );
    await _store.actualizarCierre(reiniciado);
    _cambiosController.add(null);
    await sincronizarAhora(usuarioId: usuarioId);
  }

  Future<void> descartar(String clienteCierreId) async {
    await _store.eliminarCierre(clienteCierreId);
    _cambiosController.add(null);
  }

  Future<ResultadoSincronizacion> _procesarCierre(
    CierreTareaPendiente cierre,
  ) async {
    await _marcar(cierre, estadoSync: CierreSyncEstado.sincronizando);

    final operarioId = int.tryParse(cierre.usuarioId);
    if (operarioId == null) {
      await _marcar(
        cierre,
        estadoSync: CierreSyncEstado.error,
        ultimoError: 'No se pudo identificar al operario de este cierre.',
        intentos: cierre.intentos + 1,
      );
      return ResultadoSincronizacion.errorPermanente;
    }

    final evidencias = cierre.evidencias.map((e) {
      if (e.bytesBase64 != null) {
        return EvidenciaAdjunto(
          nombre: e.nombre,
          bytes: base64Decode(e.bytesBase64!),
        );
      }
      return EvidenciaAdjunto(nombre: e.nombre, path: e.path);
    }).toList();

    try {
      await _operarioApi.cerrarTareaConEvidencias(
        operarioId: operarioId,
        tareaId: cierre.tareaId,
        accion: cierre.accion,
        observaciones: cierre.observaciones,
        insumosUsados: cierre.insumosUsados,
        evidencias: evidencias,
        clienteCierreId: cierre.clienteCierreId,
        fechaFinalizarTarea: cierre.fechaCierreLocal,
      );

      await _marcar(
        cierre,
        estadoSync: CierreSyncEstado.sincronizado,
        sincronizadoEn: DateTime.now(),
        limpiarError: true,
      );
      return ResultadoSincronizacion.sincronizado;
    } catch (e) {
      return _manejarError(cierre, e);
    }
  }

  Future<ResultadoSincronizacion> _manejarError(
    CierreTareaPendiente cierre,
    Object error,
  ) async {
    switch (clasificarError(error)) {
      case ClaseError.sesionExpirada:
        await _marcar(
          cierre,
          estadoSync: CierreSyncEstado.pendiente,
          ultimoError: 'Sesión expirada. Inicia sesión para sincronizar.',
        );
        return ResultadoSincronizacion.sesionExpirada;

      case ClaseError.transitorio:
        await _reintentarConBackoff(cierre, AppError.messageOf(error));
        return ResultadoSincronizacion.reintentable;

      case ClaseError.negocio:
        // 4xx de negocio (stock insuficiente, tarea ya cerrada, etc.): no
        // se reintenta solo, el operario debe revisarlo.
        await _marcar(
          cierre,
          estadoSync: CierreSyncEstado.error,
          ultimoError: AppError.messageOf(error),
          intentos: cierre.intentos + 1,
        );
        return ResultadoSincronizacion.errorPermanente;
    }
  }

  Future<void> _reintentarConBackoff(
    CierreTareaPendiente cierre,
    String mensaje,
  ) async {
    final intentos = cierre.intentos + 1;
    final espera = _backoff[(intentos - 1).clamp(0, _backoff.length - 1)];
    await _marcar(
      cierre,
      estadoSync: CierreSyncEstado.pendiente,
      ultimoError: mensaje,
      intentos: intentos,
      nextAttemptAt: DateTime.now().add(espera),
    );
  }

  Future<void> _marcar(
    CierreTareaPendiente cierre, {
    required CierreSyncEstado estadoSync,
    String? ultimoError,
    int? intentos,
    DateTime? nextAttemptAt,
    DateTime? sincronizadoEn,
    bool limpiarError = false,
  }) async {
    final actualizado = cierre.copyWith(
      estadoSync: estadoSync,
      ultimoError: ultimoError,
      intentos: intentos,
      nextAttemptAt: nextAttemptAt,
      sincronizadoEn: sincronizadoEn,
      limpiarError: limpiarError,
    );
    await _store.actualizarCierre(actualizado);
    _cambiosController.add(null);
  }
}
