import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../api/asistencia_api.dart';
import '../../api/operario_api.dart';
import '../../model/asistencia_model.dart';
import '../../model/asistencia_pendiente_model.dart';
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
  appDesactualizada,
}

/// Cómo terminó una pasada de la cola.
class ResumenSincronizacion {
  final int enviados;

  /// Siguen en la cola por red o servidor (se reintentan solos).
  final int pendientes;

  /// Rechazados por el servidor en esta pasada.
  final int rechazados;
  final bool sesionExpirada;
  final bool appDesactualizada;

  const ResumenSincronizacion({
    this.enviados = 0,
    this.pendientes = 0,
    this.rechazados = 0,
    this.sesionExpirada = false,
    this.appDesactualizada = false,
  });

  static const vacio = ResumenSincronizacion();
}

/// Lo que la cola necesita del servidor. En la app es HTTP
/// ([TransporteSyncHttp]); en las pruebas, un doble.
abstract class TransporteSync {
  /// Envía un cierre guardado. Devuelve true si el servidor ya lo tenía.
  Future<bool> enviarCierre(
    CierreTareaPendiente cierre,
    List<EvidenciaAdjunto> evidencias,
  );

  /// ¿El servidor ya registró este cierre?
  Future<EstadoCierreRemoto> consultarCierre(
    int operarioId,
    String clienteCierreId,
  );

  Future<AsistenciaCheckinResultado> enviarAsistencia(AsistenciaPendiente a);

  Future<ResultadoRenovacion> renovarSesion();
}

class TransporteSyncHttp implements TransporteSync {
  TransporteSyncHttp({
    OperarioApi? operarioApi,
    AsistenciaApi? asistenciaApi,
    SessionService? session,
  }) : _operarioApi = operarioApi ?? OperarioApi(),
       _asistenciaApi = asistenciaApi ?? AsistenciaApi(),
       _session = session ?? SessionService();

  final OperarioApi _operarioApi;
  final AsistenciaApi _asistenciaApi;
  final SessionService _session;

  /// Un cierre con varias fotos y datos móviles lentos puede tardar.
  static const Duration tiempoLimiteEnvio = Duration(seconds: 120);

  @override
  Future<bool> enviarCierre(
    CierreTareaPendiente cierre,
    List<EvidenciaAdjunto> evidencias,
  ) {
    return _operarioApi.cerrarTareaConEvidencias(
      operarioId: int.parse(cierre.usuarioId),
      tareaId: cierre.tareaId,
      accion: cierre.accion,
      observaciones: cierre.observaciones,
      insumosUsados: cierre.insumosUsados,
      evidencias: evidencias,
      clienteCierreId: cierre.clienteCierreId,
      fechaFinalizarTarea: cierre.fechaCierreLocal,
      sinConexion: true,
      horaEstimada: cierre.fechaCierreEstimada,
      timeout: tiempoLimiteEnvio,
    );
  }

  @override
  Future<EstadoCierreRemoto> consultarCierre(
    int operarioId,
    String clienteCierreId,
  ) {
    return _operarioApi.consultarCierre(
      operarioId: operarioId,
      clienteCierreId: clienteCierreId,
    );
  }

  @override
  Future<AsistenciaCheckinResultado> enviarAsistencia(AsistenciaPendiente a) {
    return _asistenciaApi.checkin(
      conjuntoId: a.conjuntoId,
      qrPayload: a.qrPayload,
      latitud: a.latitud,
      longitud: a.longitud,
      precisionMetros: a.precisionMetros,
      clienteRegistroId: a.clienteRegistroId,
      sinConexion: true,
      registradaEn: a.registradaEn,
      registradaEnEstimada: a.registradaEnEstimada,
      timeout: const Duration(seconds: 45),
    );
  }

  @override
  Future<ResultadoRenovacion> renovarSesion() => _session.renovarSesionApp();
}

/// Backoff exponencial para fallas de red/servidor: 30s, 2min, 10min, y
/// luego cada hora indefinidamente. Nada se abandona por una falla de
/// conectividad — solo un rechazo de negocio (4xx) lo saca de la cola
/// automática, y aun así queda guardado hasta que el operario lo descarte.
const List<Duration> _backoff = [
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
  Duration(hours: 1),
];

/// Drena hacia el backend la cola de lo que el operario hizo sin señal:
/// primero las asistencias por QR y luego los cierres de tarea, cada grupo
/// en orden de creación. Reintenta con backoff, renueva la sesión ante un
/// 401 y se pausa (sin perder nada) si la sesión ya no sirve o la app está
/// desactualizada.
///
/// Se dispara al volver la conexión, al volver la app a primer plano, con un
/// temporizador mientras haya pendientes esperando su reintento y, con la app
/// cerrada, desde WorkManager (`sincronizacion_fondo.dart`).
class TareaSyncEngine {
  TareaSyncEngine._({
    CierreTareaOfflineStore? store,
    TransporteSync? transporte,
    Future<String?> Function()? usuarioActual,
    DateTime Function()? ahora,
  }) : _store = store ?? CierreTareaOfflineStore.instance,
       _transporte = transporte ?? TransporteSyncHttp(),
       _usuarioActual = usuarioActual ?? (() => SessionService().getUserId()),
       _ahora = ahora ?? DateTime.now;

  static final TareaSyncEngine instance = TareaSyncEngine._();

  @visibleForTesting
  factory TareaSyncEngine.paraPruebas({
    required CierreTareaOfflineStore store,
    required TransporteSync transporte,
    required String usuarioId,
    DateTime Function()? ahora,
  }) => TareaSyncEngine._(
    store: store,
    transporte: transporte,
    usuarioActual: () async => usuarioId,
    ahora: ahora,
  );

  final CierreTareaOfflineStore _store;
  final TransporteSync _transporte;
  final Future<String?> Function() _usuarioActual;
  final DateTime Function() _ahora;

  /// Lo registra `sincronizacion_fondo.dart`: programa el trabajo de
  /// WorkManager (con restricción de red) cuando algo queda en la cola.
  static Future<void> Function()? programarEnFondo;

  /// Lo registra `sincronizacion_fondo.dart`: la cola quedó vacía (se cancela
  /// el trabajo periódico de respaldo).
  static Future<void> Function()? alQuedarSinPendientes;

  /// Lo registra `ActualizacionAppService`: el servidor dijo 426.
  static void Function()? alAppDesactualizada;

  /// true en el proceso de la app (lo pone `main`); false en el proceso de
  /// segundo plano de WorkManager.
  static bool esProcesoPrincipal = false;

  Future<ResumenSincronizacion>? _enCurso;
  bool _sesionExpirada = false;
  bool _appDesactualizada = false;
  StreamSubscription<void>? _conexionSub;
  Timer? _temporizador;

  final _cambiosController = StreamController<void>.broadcast();

  /// Se emite cada vez que cambia el estado de la cola (nuevo cierre,
  /// avance de sincronización, error, purga) para que la UI refresque.
  Stream<void> get onCambios => _cambiosController.stream;

  bool get sesionExpirada => _sesionExpirada;
  bool get appDesactualizada => _appDesactualizada;
  bool get sincronizando => _enCurso != null;

  void iniciar() {
    ConnectivityService.instance.iniciar();
    _conexionSub ??= ConnectivityService.instance.onConexionRestaurada.listen((
      _,
    ) {
      sincronizarAhora(ignorarEspera: true);
    });
    // `onConnectivityChanged` solo notifica cambios; si la app arranca con
    // conexión ya disponible, hay que intentar sincronizar una vez de
    // entrada en vez de esperar un cambio que quizás nunca llegue.
    sincronizarAhora(ignorarEspera: true);
  }

  void detener() {
    _conexionSub?.cancel();
    _conexionSub = null;
    _temporizador?.cancel();
    _temporizador = null;
    ConnectivityService.instance.detener();
  }

  /// Llamar tras un login exitoso: reanuda la cola pausada por un 401.
  void notificarSesionRestaurada() {
    _sesionExpirada = false;
    sincronizarAhora(ignorarEspera: true);
  }

  /// Algo nuevo quedó en la cola: se pide a Android que lo envíe apenas haya
  /// internet (aunque la app se cierre) y se intenta ya mismo.
  Future<void> programarEnvio() async {
    _cambiosController.add(null);
    try {
      await programarEnFondo?.call();
    } catch (_) {}
    unawaited(sincronizarAhora(ignorarEspera: true));
  }

  /// Envía lo pendiente. [ignorarEspera]: no respeta el `nextAttemptAt` del
  /// backoff (volvió la señal, la app volvió a primer plano, el operario tocó
  /// "Sincronizar ahora"). Varias llamadas a la vez comparten una pasada.
  Future<ResumenSincronizacion> sincronizarAhora({
    String? usuarioId,
    bool ignorarEspera = false,
  }) {
    final enCurso = _enCurso;
    if (enCurso != null) return enCurso;
    if (_sesionExpirada || _appDesactualizada) {
      return Future.value(
        ResumenSincronizacion(
          sesionExpirada: _sesionExpirada,
          appDesactualizada: _appDesactualizada,
        ),
      );
    }
    final pasada = _sincronizar(usuarioId, ignorarEspera).whenComplete(() {
      _enCurso = null;
    });
    _enCurso = pasada;
    return pasada;
  }

  Future<ResumenSincronizacion> _sincronizar(
    String? usuarioId,
    bool ignorarEspera,
  ) async {
    final uid = usuarioId ?? await _usuarioActual();
    if (uid == null || uid.isEmpty) return ResumenSincronizacion.vacio;

    var enviados = 0;
    var pendientes = 0;
    var rechazados = 0;
    var detener = false;

    bool debeEsperar(CierreSyncEstado estado, DateTime? siguiente) {
      if (estado == CierreSyncEstado.sincronizado ||
          estado == CierreSyncEstado.error) {
        return true;
      }
      if (ignorarEspera || siguiente == null) return false;
      return siguiente.isAfter(_ahora());
    }

    void contar(ResultadoSincronizacion r) {
      switch (r) {
        case ResultadoSincronizacion.sincronizado:
          enviados++;
        case ResultadoSincronizacion.reintentable:
          pendientes++;
        case ResultadoSincronizacion.errorPermanente:
          rechazados++;
        case ResultadoSincronizacion.sesionExpirada:
          _sesionExpirada = true;
          pendientes++;
          detener = true;
        case ResultadoSincronizacion.appDesactualizada:
          _appDesactualizada = true;
          pendientes++;
          detener = true;
          alAppDesactualizada?.call();
      }
    }

    try {
      await _store.purgarSincronizados();

      // 1) Asistencias, en orden: una salida no puede llegar antes que su
      // entrada, así que si una falla por red las siguientes esperan.
      final asistencias = await _store.listarAsistencias(usuarioId: uid);
      for (final a in asistencias) {
        if (detener) break;
        if (debeEsperar(a.estadoSync, a.nextAttemptAt)) {
          if (a.estadoSync == CierreSyncEstado.pendiente) {
            pendientes++;
            break;
          }
          continue;
        }
        final r = await _procesarAsistencia(a);
        contar(r);
        if (r == ResultadoSincronizacion.reintentable) break;
      }

      // 2) Cierres de tarea, en orden de creación.
      final cierres = await _store.listarCierres(usuarioId: uid);
      for (final c in cierres) {
        if (detener) break;
        if (debeEsperar(c.estadoSync, c.nextAttemptAt)) {
          if (c.estadoSync == CierreSyncEstado.pendiente) pendientes++;
          continue;
        }
        contar(await _procesarCierre(c));
      }
    } finally {
      _cambiosController.add(null);
    }

    await _programarTemporizador(uid);
    if (pendientes == 0 && !_sesionExpirada && !_appDesactualizada) {
      try {
        await alQuedarSinPendientes?.call();
      } catch (_) {}
    }
    return ResumenSincronizacion(
      enviados: enviados,
      pendientes: pendientes,
      rechazados: rechazados,
      sesionExpirada: _sesionExpirada,
      appDesactualizada: _appDesactualizada,
    );
  }

  /// Mientras la app esté abierta, un reintento a la hora del siguiente
  /// `nextAttemptAt` (no se espera a que cambie la conectividad).
  Future<void> _programarTemporizador(String uid) async {
    _temporizador?.cancel();
    _temporizador = null;
    if (_sesionExpirada || _appDesactualizada) return;
    DateTime? proximo;
    try {
      final fechas = <DateTime?>[
        for (final a in await _store.listarAsistencias(usuarioId: uid))
          if (a.estadoSync == CierreSyncEstado.pendiente) a.nextAttemptAt,
        for (final c in await _store.listarCierres(usuarioId: uid))
          if (c.estadoSync == CierreSyncEstado.pendiente) c.nextAttemptAt,
      ].whereType<DateTime>();
      proximo = fechas.isEmpty
          ? null
          : fechas.reduce((a, b) => a.isBefore(b) ? a : b);
    } catch (_) {
      return;
    }
    if (proximo == null) return;
    var espera = proximo.difference(_ahora());
    if (espera < const Duration(seconds: 5)) {
      espera = const Duration(seconds: 5);
    }
    _temporizador = Timer(espera, () {
      _temporizador = null;
      sincronizarAhora();
    });
  }

  /// Cancela el temporizador (la app se fue a segundo plano: ahí manda
  /// WorkManager).
  void pausarTemporizador() {
    _temporizador?.cancel();
    _temporizador = null;
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

    await _store.actualizarCierre(
      cierre.copyWith(
        estadoSync: CierreSyncEstado.pendiente,
        nextAttemptAt: null,
        limpiarError: true,
      ),
    );
    _cambiosController.add(null);
    await sincronizarAhora(usuarioId: usuarioId, ignorarEspera: true);
  }

  Future<void> reintentarAsistencia({
    required String usuarioId,
    required String clienteRegistroId,
  }) async {
    final lista = await _store.listarAsistencias(usuarioId: usuarioId);
    final a = lista.firstWhereOrNull(
      (x) => x.clienteRegistroId == clienteRegistroId,
    );
    if (a == null) return;
    await _store.actualizarAsistencia(
      a.copyWith(
        estadoSync: CierreSyncEstado.pendiente,
        nextAttemptAt: null,
        limpiarError: true,
      ),
    );
    _cambiosController.add(null);
    await sincronizarAhora(usuarioId: usuarioId, ignorarEspera: true);
  }

  /// Solo por decisión del operario: nunca se descarta nada solo.
  Future<void> descartar(String clienteCierreId) async {
    await _store.eliminarCierre(clienteCierreId);
    _cambiosController.add(null);
  }

  Future<void> descartarAsistencia(String clienteRegistroId) async {
    await _store.eliminarAsistencia(clienteRegistroId);
    _cambiosController.add(null);
  }

  // ---------------------------------------------------------------------
  // Cierres
  // ---------------------------------------------------------------------

  Future<ResultadoSincronizacion> _procesarCierre(
    CierreTareaPendiente cierre, {
    bool yaRenovo = false,
  }) async {
    // Quedó "enviando" en el store: la app se cerró a mitad de un envío.
    final interrumpido =
        !yaRenovo && cierre.estadoSync == CierreSyncEstado.sincronizando;
    final actual = await _marcarCierre(
      cierre,
      estadoSync: CierreSyncEstado.sincronizando,
    );

    final operarioId = int.tryParse(cierre.usuarioId);
    if (operarioId == null) {
      await _marcarCierre(
        actual,
        estadoSync: CierreSyncEstado.error,
        ultimoError: 'No se pudo identificar al operario de este cierre.',
        intentos: actual.intentos + 1,
      );
      return ResultadoSincronizacion.errorPermanente;
    }

    try {
      // Un intento anterior pudo llegar al servidor aunque la respuesta se
      // perdiera: se pregunta antes de volver a subir las fotos.
      // Tras renovar la sesión no hace falta: un 401 no procesó nada.
      if (!yaRenovo && (actual.intentos > 0 || interrumpido)) {
        final remoto = await _transporte.consultarCierre(
          operarioId,
          actual.clienteCierreId,
        );
        if (remoto.procesado) {
          await _marcarCierre(
            actual,
            estadoSync: CierreSyncEstado.sincronizado,
            sincronizadoEn: _ahora(),
            limpiarError: true,
          );
          return ResultadoSincronizacion.sincronizado;
        }
      }

      await _transporte.enviarCierre(actual, _evidenciasDe(actual));
      await _marcarCierre(
        actual,
        estadoSync: CierreSyncEstado.sincronizado,
        sincronizadoEn: _ahora(),
        limpiarError: true,
      );
      return ResultadoSincronizacion.sincronizado;
    } catch (e) {
      return _manejarError(
        e,
        yaRenovo: yaRenovo,
        reintentar: () => _procesarCierre(actual, yaRenovo: true),
        marcarPendiente: (mensaje, {siguiente}) => _marcarCierre(
          actual,
          estadoSync: CierreSyncEstado.pendiente,
          ultimoError: mensaje,
          intentos: actual.intentos + 1,
          nextAttemptAt: siguiente,
        ),
        marcarRechazo: (mensaje, codigo) => _marcarCierre(
          actual,
          estadoSync: CierreSyncEstado.error,
          ultimoError: mensaje,
          intentos: actual.intentos + 1,
        ),
        intentos: actual.intentos,
      );
    }
  }

  static List<EvidenciaAdjunto> _evidenciasDe(CierreTareaPendiente cierre) {
    return cierre.evidencias.map((e) {
      if (e.bytesBase64 != null) {
        return EvidenciaAdjunto(
          nombre: e.nombre,
          bytes: base64Decode(e.bytesBase64!),
          captura: e.captura,
        );
      }
      return EvidenciaAdjunto(
        nombre: e.nombre,
        path: e.path,
        captura: e.captura,
      );
    }).toList();
  }

  Future<CierreTareaPendiente> _marcarCierre(
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
    return actualizado;
  }

  // ---------------------------------------------------------------------
  // Asistencias
  // ---------------------------------------------------------------------

  Future<ResultadoSincronizacion> _procesarAsistencia(
    AsistenciaPendiente asistencia, {
    bool yaRenovo = false,
  }) async {
    final actual = await _marcarAsistencia(
      asistencia,
      estadoSync: CierreSyncEstado.sincronizando,
    );
    try {
      final r = await _transporte.enviarAsistencia(actual);
      await _marcarAsistencia(
        actual,
        estadoSync: CierreSyncEstado.sincronizado,
        sincronizadoEn: _ahora(),
        tipoRegistrado: r.tipo,
        conjuntoNombre: r.conjuntoNombre,
        limpiarError: true,
      );
      return ResultadoSincronizacion.sincronizado;
    } catch (e) {
      return _manejarError(
        e,
        yaRenovo: yaRenovo,
        reintentar: () => _procesarAsistencia(actual, yaRenovo: true),
        marcarPendiente: (mensaje, {siguiente}) => _marcarAsistencia(
          actual,
          estadoSync: CierreSyncEstado.pendiente,
          ultimoError: mensaje,
          intentos: actual.intentos + 1,
          nextAttemptAt: siguiente,
        ),
        marcarRechazo: (mensaje, codigo) => _marcarAsistencia(
          actual,
          estadoSync: CierreSyncEstado.error,
          ultimoError: mensaje,
          codigoError: codigo,
          intentos: actual.intentos + 1,
        ),
        intentos: actual.intentos,
      );
    }
  }

  Future<AsistenciaPendiente> _marcarAsistencia(
    AsistenciaPendiente a, {
    required CierreSyncEstado estadoSync,
    String? ultimoError,
    String? codigoError,
    int? intentos,
    DateTime? nextAttemptAt,
    DateTime? sincronizadoEn,
    String? tipoRegistrado,
    String? conjuntoNombre,
    bool limpiarError = false,
  }) async {
    final actualizado = a.copyWith(
      estadoSync: estadoSync,
      ultimoError: ultimoError,
      codigoError: codigoError,
      intentos: intentos,
      nextAttemptAt: nextAttemptAt,
      sincronizadoEn: sincronizadoEn,
      tipoRegistrado: tipoRegistrado,
      conjuntoNombre: conjuntoNombre,
      limpiarError: limpiarError,
    );
    await _store.actualizarAsistencia(actualizado);
    _cambiosController.add(null);
    return actualizado;
  }

  // ---------------------------------------------------------------------
  // Errores (comunes a cierres y asistencias)
  // ---------------------------------------------------------------------

  Future<ResultadoSincronizacion> _manejarError(
    Object error, {
    required bool yaRenovo,
    required Future<ResultadoSincronizacion> Function() reintentar,
    required Future<Object?> Function(String mensaje, {DateTime? siguiente})
    marcarPendiente,
    required Future<Object?> Function(String mensaje, String? codigo)
    marcarRechazo,
    required int intentos,
  }) async {
    switch (clasificarError(error)) {
      case ClaseError.sesionExpirada:
        final esCambioContrasena = error is ApiError && error.statusCode == 403;
        if (!esCambioContrasena && !yaRenovo) {
          final r = await _transporte.renovarSesion();
          if (r == ResultadoRenovacion.renovada) return reintentar();
          if (r == ResultadoRenovacion.sinRed) {
            await marcarPendiente(
              'Sin conexión para renovar la sesión. Se reintentará solo.',
              siguiente: _siguienteIntento(intentos),
            );
            return ResultadoSincronizacion.reintentable;
          }
        }
        await marcarPendiente(
          esCambioContrasena
              ? 'Cambia tu contraseña para enviar lo guardado.'
              : 'Tu sesión expiró. Inicia sesión para enviar lo guardado.',
        );
        return ResultadoSincronizacion.sesionExpirada;

      case ClaseError.appDesactualizada:
        await marcarPendiente(
          'Actualiza la app para enviar lo guardado. No se pierde nada.',
        );
        return ResultadoSincronizacion.appDesactualizada;

      case ClaseError.transitorio:
        await marcarPendiente(
          AppError.messageOf(
            error,
            fallback: 'Sin conexión. Se enviará cuando haya señal.',
          ),
          siguiente: _siguienteIntento(intentos),
        );
        return ResultadoSincronizacion.reintentable;

      case ClaseError.negocio:
        // Rechazo del servidor (tarea ya cerrada, reasignada, QR inválido…):
        // no se reintenta solo; el operario ve el motivo y decide.
        final mensaje = error is ApiError
            ? error.mensaje
            : AppError.messageOf(error);
        final codigo = error is ApiError ? error.codigo : null;
        await marcarRechazo(mensaje, codigo);
        return ResultadoSincronizacion.errorPermanente;
    }
  }

  DateTime _siguienteIntento(int intentosPrevios) {
    final espera = _backoff[intentosPrevios.clamp(0, _backoff.length - 1)];
    return _ahora().add(espera);
  }
}
