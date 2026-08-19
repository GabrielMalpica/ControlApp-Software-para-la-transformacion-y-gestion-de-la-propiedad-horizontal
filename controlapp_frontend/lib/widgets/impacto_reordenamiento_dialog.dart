import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Un ajuste que la cascada de reordenamiento aplicó (o intentará aplicar)
/// sobre una tarea ajena a las que el usuario movió a mano.
class CambioCascadaReordenamiento {
  final int tareaId;
  final String descripcion;
  final List<String> operariosNombres;
  final bool esExcluida;
  final DateTime fechaInicioOriginal;
  final DateTime fechaFinOriginal;
  final DateTime? fechaInicioNueva;
  final DateTime? fechaFinNueva;
  final String motivo;

  CambioCascadaReordenamiento({
    required this.tareaId,
    required this.descripcion,
    required this.operariosNombres,
    required this.esExcluida,
    required this.fechaInicioOriginal,
    required this.fechaFinOriginal,
    required this.fechaInicioNueva,
    required this.fechaFinNueva,
    required this.motivo,
  });

  factory CambioCascadaReordenamiento.fromMap(Map<String, dynamic> json) {
    return CambioCascadaReordenamiento(
      tareaId: int.tryParse('${json['tareaId'] ?? 0}') ?? 0,
      descripcion: (json['descripcion'] ?? 'Tarea').toString(),
      operariosNombres: (json['operariosNombres'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      esExcluida: (json['accion'] ?? '').toString().toUpperCase() == 'EXCLUIDA',
      fechaInicioOriginal: _parseDate(json['fechaInicioOriginal']),
      fechaFinOriginal: _parseDate(json['fechaFinOriginal']),
      fechaInicioNueva: _tryParseDate(json['fechaInicioNueva']),
      fechaFinNueva: _tryParseDate(json['fechaFinNueva']),
      motivo: (json['motivo'] ?? '').toString(),
    );
  }
}

/// Muestra el impacto de un reordenamiento en cadena (tareas ajenas
/// reacomodadas o excluidas para poder aplicar el cambio solicitado) y, si
/// hay alguna exclusión, pide confirmación explícita antes de aplicar nada.
/// Devuelve true si el usuario confirma (o si no había nada que confirmar),
/// false si cancela.
Future<bool> showImpactoReordenamientoDialog(
  BuildContext context,
  List<dynamic> cambiosCascadaRaw,
) async {
  final cambios = cambiosCascadaRaw
      .whereType<Map>()
      .map(
        (item) =>
            CambioCascadaReordenamiento.fromMap(item.cast<String, dynamic>()),
      )
      .toList();
  final excluidas = cambios.where((c) => c.esExcluida).toList();
  if (cambios.isEmpty) return true;

  final confirmado = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        excluidas.isNotEmpty
            ? 'Este cambio va a excluir ${excluidas.length} tarea(s)'
            : 'Se van a reacomodar otras tareas',
        style: TextStyle(
          color: excluidas.isNotEmpty ? Colors.red.shade700 : null,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (excluidas.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'No quedó espacio libre ese día para reacomodarlas. Si '
                    'continúas, quedarán excluidas del borrador y podrás '
                    'reprogramarlas manualmente después.',
                  ),
                ),
              ...cambios.map(
                (cambio) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CambioCascadaCard(cambio: cambio),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: excluidas.isNotEmpty
              ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            excluidas.isNotEmpty ? 'Confirmar de todas formas' : 'Continuar',
          ),
        ),
      ],
    ),
  );

  return confirmado ?? false;
}

class _CambioCascadaCard extends StatelessWidget {
  final CambioCascadaReordenamiento cambio;

  const _CambioCascadaCard({required this.cambio});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = cambio.esExcluida ? Colors.red.shade700 : Colors.orange.shade800;
    final operarios = cambio.operariosNombres.isEmpty
        ? 'Sin operarios'
        : cambio.operariosNombres.join(', ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                cambio.esExcluida ? Icons.remove_circle : Icons.swap_horiz,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cambio.descripcion,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            operarios,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            cambio.esExcluida
                ? 'Se excluirá del borrador (estaba ${_formatRango(cambio.fechaInicioOriginal, cambio.fechaFinOriginal)}).'
                : 'De ${_formatHora(cambio.fechaInicioOriginal)}-${_formatHora(cambio.fechaFinOriginal)} '
                      'a ${_formatHora(cambio.fechaInicioNueva!)}-${_formatHora(cambio.fechaFinNueva!)}.',
            style: const TextStyle(fontSize: 13),
          ),
          if (cambio.motivo.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              cambio.motivo,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

DateTime _parseDate(dynamic value) => _tryParseDate(value) ?? DateTime.now();

DateTime? _tryParseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String _formatHora(DateTime value) => DateFormat('HH:mm').format(value);

String _formatRango(DateTime start, DateTime end) =>
    '${_formatHora(start)}-${_formatHora(end)}';
