import 'package:flutter_application_1/api/jefe_operaciones_api.dart';
import 'package:flutter_application_1/api/operario_api.dart';
import 'package:flutter_application_1/api/supervisor_api.dart';
import 'package:flutter_application_1/api/tarea_api.dart';
import 'package:flutter_application_1/model/cierre_tarea_pendiente_model.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/offline/cierre_tarea_offline_store.dart';
import 'package:flutter_application_1/service/offline/error_classifier.dart';
import 'package:flutter_application_1/service/offline/evidencia_persistencia.dart';
import 'package:flutter_application_1/service/offline/uuid_v4.dart';
import 'package:flutter_application_1/service/permission_service.dart';

/// Resultado de intentar cerrar una tarea: si el operario está sin
/// conexión, el cierre queda [guardadoLocalPendiente] en vez de fallar —
/// nunca se pierde el trabajo, se sincroniza solo cuando vuelva la señal.
enum CierreTareaResultado { enviadoAlServidor, guardadoLocalPendiente }

class TareaCierreService {
  TareaCierreService({
    TareaApi? tareaApi,
    JefeOperacionesApi? jefeOperacionesApi,
    OperarioApi? operarioApi,
    SupervisorApi? supervisorApi,
  }) : _tareaApi = tareaApi ?? TareaApi(),
       _jefeOperacionesApi = jefeOperacionesApi ?? JefeOperacionesApi(),
       _operarioApi = operarioApi ?? OperarioApi(),
       _supervisorApi = supervisorApi ?? SupervisorApi();

  final TareaApi _tareaApi;
  final JefeOperacionesApi _jefeOperacionesApi;
  final OperarioApi _operarioApi;
  final SupervisorApi _supervisorApi;

  static const Set<String> _estadosCerrables = {
    'ASIGNADA',
    'EN_PROCESO',
    'COMPLETADA',
  };

  static String _rol(String? value) => value?.trim().toLowerCase() ?? '';
  static String _id(String? value) => value?.trim() ?? '';
  static bool _esRutaNoDisponible(Object error) {
    final raw = error.toString();
    return raw.contains('404') || raw.contains('405');
  }

  bool puedeCerrar({
    required String? rol,
    required String? usuarioId,
    required TareaModel tarea,
    bool soloLectura = false,
  }) {
    return motivoNoPuedeCerrar(
          rol: rol,
          usuarioId: usuarioId,
          tarea: tarea,
          soloLectura: soloLectura,
        ) ==
        null;
  }

  String? motivoNoPuedeCerrar({
    required String? rol,
    required String? usuarioId,
    required TareaModel tarea,
    bool soloLectura = false,
  }) {
    if (soloLectura) {
      return 'Esta vista es solo lectura.';
    }

    if (!PermissionService.instance.can('tareas.cerrar')) {
      return 'Tu rol no tiene permiso para cerrar tareas.';
    }

    final estado = (tarea.estado ?? '').trim().toUpperCase();
    if (!_estadosCerrables.contains(estado)) {
      return 'Esta tarea no está disponible para cierre.';
    }

    final rolNormalizado = _rol(rol);
    final usuarioActual = _id(usuarioId);

    switch (rolNormalizado) {
      case 'gerente':
      case 'jefe_operaciones':
      case 'administrador':
        return null;
      case 'supervisor':
        final supervisorAsignado = _id(tarea.supervisorId);
        if (usuarioActual.isEmpty || supervisorAsignado != usuarioActual) {
          return 'Solo puedes cerrar las tareas que tienes asignadas para supervisar.';
        }
        return null;
      case 'operario':
        if (usuarioActual.isEmpty) {
          return 'No se pudo identificar el operario actual.';
        }
        final estaAsignado = tarea.operariosIds.any(
          (id) => _id(id) == usuarioActual,
        );
        if (!estaAsignado) {
          return 'Solo puedes cerrar las tareas que tienes asignadas.';
        }
        return null;
      default:
        return 'Tu rol no tiene permiso para cerrar tareas.';
    }
  }

  Future<CierreTareaResultado> cerrarTarea({
    required String? rol,
    required String? usuarioId,
    required TareaModel tarea,
    String accion = 'COMPLETADA',
    String? observaciones,
    List<Map<String, num>> insumosUsados = const [],
    List<EvidenciaAdjunto> evidencias = const [],
  }) async {
    final motivo = motivoNoPuedeCerrar(
      rol: rol,
      usuarioId: usuarioId,
      tarea: tarea,
    );
    if (motivo != null) {
      throw Exception(motivo);
    }

    switch (_rol(rol)) {
      case 'operario':
        final operarioId = int.tryParse(_id(usuarioId));
        if (operarioId == null) {
          throw Exception('No se pudo identificar el operario actual.');
        }
        return _cerrarComoOperarioOfflineFirst(
          operarioId: operarioId,
          usuarioId: _id(usuarioId),
          tarea: tarea,
          accion: accion,
          observaciones: observaciones,
          insumosUsados: insumosUsados,
          evidencias: evidencias,
        );
      case 'gerente':
        try {
          await _tareaApi.cerrarTareaConEvidencias(
            tareaId: tarea.id,
            accion: accion,
            observaciones: observaciones,
            insumosUsados: insumosUsados,
            evidencias: evidencias,
          );
          return CierreTareaResultado.enviadoAlServidor;
        } catch (e) {
          if (!_esRutaNoDisponible(e)) rethrow;
        }
        await _supervisorApi.cerrarTareaConEvidencias(
          tareaId: tarea.id,
          accion: accion,
          observaciones: observaciones,
          insumosUsados: insumosUsados,
          evidencias: evidencias,
        );
        return CierreTareaResultado.enviadoAlServidor;
      case 'jefe_operaciones':
        try {
          await _jefeOperacionesApi.cerrarTareaConEvidencias(
            tareaId: tarea.id,
            accion: accion,
            observaciones: observaciones,
            insumosUsados: insumosUsados,
            evidencias: evidencias,
          );
          return CierreTareaResultado.enviadoAlServidor;
        } catch (e) {
          if (!_esRutaNoDisponible(e)) rethrow;
        }
        await _supervisorApi.cerrarTareaConEvidencias(
          tareaId: tarea.id,
          accion: accion,
          observaciones: observaciones,
          insumosUsados: insumosUsados,
          evidencias: evidencias,
        );
        return CierreTareaResultado.enviadoAlServidor;
      case 'supervisor':
      case 'administrador':
        await _supervisorApi.cerrarTareaConEvidencias(
          tareaId: tarea.id,
          accion: accion,
          observaciones: observaciones,
          insumosUsados: insumosUsados,
          evidencias: evidencias,
        );
        return CierreTareaResultado.enviadoAlServidor;
      default:
        throw Exception('Tu rol no tiene permiso para cerrar tareas.');
    }
  }

  /// Cierre de tarea para el rol operario: intenta enviarlo al backend de
  /// inmediato (camino de siempre, igual de rápido cuando hay conexión).
  /// Si la falla es de conectividad (timeout, sin red, 5xx, sesión
  /// expirada), en vez de perder el trabajo del operario se persiste
  /// localmente y queda pendiente de sincronizar. Si la falla es de
  /// negocio (datos inválidos, tarea ya cerrada, stock insuficiente), se
  /// relanza tal cual para que el operario la corrija — no tiene sentido
  /// encolar algo que el backend ya rechazó por su contenido.
  Future<CierreTareaResultado> _cerrarComoOperarioOfflineFirst({
    required int operarioId,
    required String usuarioId,
    required TareaModel tarea,
    required String accion,
    required String? observaciones,
    required List<Map<String, num>> insumosUsados,
    required List<EvidenciaAdjunto> evidencias,
  }) async {
    final clienteCierreId = generarUuidV4();
    final fechaCierre = DateTime.now();

    try {
      await _operarioApi.cerrarTareaConEvidencias(
        operarioId: operarioId,
        tareaId: tarea.id,
        accion: accion,
        observaciones: observaciones,
        insumosUsados: insumosUsados,
        evidencias: evidencias,
        clienteCierreId: clienteCierreId,
        fechaFinalizarTarea: fechaCierre,
      );
      return CierreTareaResultado.enviadoAlServidor;
    } catch (e) {
      if (clasificarError(e) == ClaseError.negocio) rethrow;

      final evidenciasPersistidas = await EvidenciaPersistencia.persistir(
        clienteCierreId: clienteCierreId,
        evidencias: evidencias,
      );

      await CierreTareaOfflineStore.instance.guardarCierre(
        CierreTareaPendiente(
          clienteCierreId: clienteCierreId,
          tareaId: tarea.id,
          rol: 'operario',
          usuarioId: usuarioId,
          accion: accion,
          observaciones: observaciones,
          insumosUsados: insumosUsados,
          fechaCierreLocal: fechaCierre,
          evidencias: evidenciasPersistidas,
          creadoEn: fechaCierre,
        ),
      );

      return CierreTareaResultado.guardadoLocalPendiente;
    }
  }
}
