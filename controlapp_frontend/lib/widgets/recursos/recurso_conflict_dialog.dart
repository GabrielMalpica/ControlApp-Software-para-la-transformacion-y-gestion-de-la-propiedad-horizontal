// lib/widgets/recursos/recurso_conflict_dialog.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/api_exception.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';

/// ¿El error es un 409 RECURSO_OCUPADO de la agenda de recursos?
bool esConflictoRecurso(Object? error) =>
    error is ApiException && error.reason == 'RECURSO_OCUPADO';

/// Variante para respuestas que llegan como mapa (`{ok:false, reason, ...}`).
bool esConflictoRecursoMapa(Map<String, dynamic>? data) =>
    data != null && data['ok'] == false && (data['reason'] ?? data['code']) == 'RECURSO_OCUPADO';

/// Muestra los recursos en conflicto. Si [ofrecerLiberar] es true (p. ej. al
/// reprogramar), ofrece "Liberar recursos y continuar": devuelve true si el
/// usuario lo elige. Las reservas liberadas quedan canceladas en el histórico.
Future<bool> mostrarConflictoRecursos(
  BuildContext context, {
  required String mensaje,
  required List<ConflictoRecursoModel> conflictos,
  bool ofrecerLiberar = false,
  String titulo = 'Recurso no disponible',
}) async {
  final out = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        icon: const Icon(Icons.event_busy_outlined, color: AppTheme.red, size: 32),
        title: Text(titulo),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mensaje),
                if (conflictos.isNotEmpty) const SizedBox(height: 12),
                for (final c in conflictos)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.red.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.unidadEtiqueta, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(c.motivo, style: const TextStyle(fontSize: 13)),
                        if (c.ocupadoConjunto != null || c.ocupadoTarea != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (c.ocupadoConjunto != null) c.ocupadoConjunto!,
                              if (c.ocupadoTarea != null) c.ocupadoTarea!,
                              if (c.ocupadoDesde != null && c.ocupadoHasta != null)
                                '${RecursoEstilos.fechaHora.format(c.ocupadoDesde!)} → ${RecursoEstilos.fechaHora.format(c.ocupadoHasta!)}',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (ofrecerLiberar) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Si continúas, esos recursos se liberan (la reserva queda cancelada en el histórico) '
                    'y la necesidad vuelve a quedar pendiente para asignarle otra unidad.',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ofrecerLiberar ? 'No mover la tarea' : 'Entendido'),
          ),
          if (ofrecerLiberar)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.link_off),
              label: const Text('Liberar recursos y continuar'),
            ),
        ],
      );
    },
  );
  return out == true;
}

/// Atajo: muestra el diálogo a partir de una ApiException RECURSO_OCUPADO.
Future<bool> mostrarConflictoDesdeError(
  BuildContext context,
  ApiException error, {
  bool ofrecerLiberar = false,
}) {
  final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : null;
  return mostrarConflictoRecursos(
    context,
    mensaje: error.message,
    conflictos: ConflictoRecursoModel.desdeError(details),
    ofrecerLiberar: ofrecerLiberar,
    titulo: details?['title']?.toString() ?? 'Recurso no disponible',
  );
}
