import 'package:flutter_application_1/api/operario_api.dart';
import 'package:flutter_application_1/api/supervisor_api.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';

class TareaCierreService {
  TareaCierreService({
    OperarioApi? operarioApi,
    SupervisorApi? supervisorApi,
  }) : _operarioApi = operarioApi ?? OperarioApi(),
       _supervisorApi = supervisorApi ?? SupervisorApi();

  final OperarioApi _operarioApi;
  final SupervisorApi _supervisorApi;

  static const Set<String> _estadosCerrables = {
    'ASIGNADA',
    'EN_PROCESO',
    'COMPLETADA',
  };

  static String _rol(String? value) => value?.trim().toLowerCase() ?? '';
  static String _id(String? value) => value?.trim() ?? '';

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

    final estado = (tarea.estado ?? '').trim().toUpperCase();
    if (!_estadosCerrables.contains(estado)) {
      return 'Esta tarea no esta disponible para cierre.';
    }

    final rolNormalizado = _rol(rol);
    final usuarioActual = _id(usuarioId);

    switch (rolNormalizado) {
      case 'gerente':
      case 'jefe_operaciones':
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
      case 'administrador':
        return 'Los administradores no pueden cerrar tareas.';
      default:
        return 'Tu rol no tiene permiso para cerrar tareas.';
    }
  }

  Future<void> cerrarTarea({
    required String? rol,
    required String? usuarioId,
    required TareaModel tarea,
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
        await _operarioApi.cerrarTareaConEvidencias(
          operarioId: operarioId,
          tareaId: tarea.id,
          observaciones: observaciones,
          insumosUsados: insumosUsados,
          evidencias: evidencias,
        );
        return;
      case 'gerente':
      case 'jefe_operaciones':
      case 'supervisor':
        await _supervisorApi.cerrarTareaConEvidencias(
          tareaId: tarea.id,
          observaciones: observaciones,
          insumosUsados: insumosUsados,
          evidencias: evidencias,
        );
        return;
      default:
        throw Exception('Tu rol no tiene permiso para cerrar tareas.');
    }
  }
}
