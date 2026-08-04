import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../model/auditoria_model.dart';

/// Bloque compacto de "quién hizo qué" para el detalle de una tarea.
///
/// Muestra quién la creó y cuál fue el último movimiento; si no hay registro
/// (tareas anteriores a la auditoría) lo dice explícitamente en vez de inventar
/// un responsable.
class AuditoriaTrazabilidad extends StatelessWidget {
  final TrazabilidadEntidad? trazabilidad;
  final bool cargando;

  const AuditoriaTrazabilidad({
    super.key,
    required this.trazabilidad,
    this.cargando = false,
  });

  static final DateFormat _fmt = DateFormat('dd/MM/yyyy HH:mm', 'es');

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(fontSize: 12, color: Colors.grey.shade700);

    if (cargando) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Cargando trazabilidad...', style: estilo),
        ],
      );
    }

    final t = trazabilidad;
    if (t == null || !t.tieneDatos) {
      return Text('Sin registro de auditoría para esta tarea.', style: estilo);
    }

    final lineas = <String>[];

    if (t.creadoPor != null) {
      final fecha = t.creadoEn == null ? '' : ' el ${_fmt.format(t.creadoEn!)}';
      lineas.add('Creada por ${t.creadoPor!.etiqueta}$fecha.');
    }

    if (t.modificadoPor != null) {
      final fecha = t.modificadoEn == null
          ? ''
          : ' el ${_fmt.format(t.modificadoEn!)}';
      final accion = _accionLegible(t.ultimaAccion);
      lineas.add(
        'Último cambio: $accion por ${t.modificadoPor!.etiqueta}$fecha.',
      );
      final detalle = t.ultimaDescripcion?.trim();
      if (detalle != null && detalle.isNotEmpty) lineas.add(detalle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 14, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              'Trazabilidad',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final linea in lineas)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(linea, style: estilo),
          ),
      ],
    );
  }

  static String _accionLegible(String? accion) {
    switch (accion) {
      case 'EDITAR':
        return 'edición';
      case 'REEMPLAZAR':
        return 'reemplazo';
      case 'REPROGRAMAR':
        return 'reprogramación';
      case 'DIVIDIR':
        return 'división';
      case 'REORDENAR':
        return 'reordenamiento';
      case 'REASIGNAR_OPERARIO':
        return 'cambio de operario';
      case 'PUBLICAR':
        return 'publicación';
      case 'AGENDAR_EXCLUIDA':
        return 'agendamiento';
      case 'PROGRAMAR_CORRECTIVA':
        return 'programación como correctiva';
      case 'ELIMINAR':
        return 'eliminación';
      default:
        return (accion ?? 'cambio').toLowerCase();
    }
  }
}
