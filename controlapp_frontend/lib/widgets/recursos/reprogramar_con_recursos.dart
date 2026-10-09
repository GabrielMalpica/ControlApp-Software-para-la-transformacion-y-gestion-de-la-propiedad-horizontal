// lib/widgets/recursos/reprogramar_con_recursos.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/tarea_api.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_conflict_dialog.dart';

/// Edita/reprograma una tarea respetando la agenda de recursos.
///
/// Si algún recurso reservado (maquinaria/herramienta) no está libre en el
/// nuevo horario, el backend responde 409 RECURSO_OCUPADO y NO mueve la tarea.
/// Aquí se muestra el conflicto y, solo si el usuario lo decide, se reintenta
/// liberando esos recursos (quedan cancelados en el histórico).
///
/// Devuelve la respuesta final del backend, o `null` si el usuario decidió no
/// mover la tarea.
Future<Map<String, dynamic>?> editarTareaConRecursos(
  BuildContext context, {
  required TareaApi api,
  required int tareaId,
  required TareaRequest req,
}) async {
  final resp = await api.editarTareaConRespuesta(tareaId, req);
  if (!esConflictoRecursoMapa(resp)) return resp;
  if (!context.mounted) return null;

  final liberar = await mostrarConflictoRecursos(
    context,
    titulo: resp['title']?.toString() ?? 'La tarea tiene recursos ocupados',
    mensaje: AppError.messageOf(resp, fallback: 'Un recurso reservado no está libre en el nuevo horario.'),
    conflictos: ConflictoRecursoModel.desdeError(resp),
    ofrecerLiberar: true,
  );
  if (!liberar) return null;

  return api.editarTareaConRespuesta(tareaId, req, liberarRecursosOcupados: true);
}
