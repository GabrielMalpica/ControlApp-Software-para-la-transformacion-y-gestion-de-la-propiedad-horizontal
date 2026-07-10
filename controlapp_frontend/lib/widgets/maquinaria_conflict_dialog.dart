import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../service/api_exception.dart';

bool hasMaquinariaConflictDetails(Object? error) {
  final payload = _MaquinariaConflictPayload.tryParse(error);
  return payload != null;
}

Future<bool> showMaquinariaConflictDialog(
  BuildContext context,
  Object? error, {
  String? fallbackTitle,
}) async {
  final payload = _MaquinariaConflictPayload.tryParse(error);
  if (payload == null) return false;

  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(fallbackTitle ?? payload.title),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(payload.message),
              if (payload.userHint != null && payload.userHint!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  payload.userHint!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...payload.conflictos.map(
                (conflicto) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ConflictCard(conflicto: conflicto),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  return true;
}

class _ConflictCard extends StatelessWidget {
  final _MaquinariaConflictItem conflicto;

  const _ConflictCard({required this.conflicto});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conflicto.maquinaNombre,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(context, _labelSolape(conflicto.tipoSolape)),
              _pill(
                context,
                'Solicitada: ${_formatDateTimeRange(conflicto.tareaSolicitada.usoInicio, conflicto.tareaSolicitada.usoFin)}',
              ),
              _pill(
                context,
                'Bloquea: ${_formatDateTimeRange(conflicto.ocupadoPor.usoInicio, conflicto.ocupadoPor.usoFin)}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(conflicto.motivo),
          const SizedBox(height: 12),
          _Section(title: 'Tarea que intentas mover/publicar', child: _TaskDetails(task: conflicto.tareaSolicitada)),
          const SizedBox(height: 12),
          _Section(title: 'Tarea que bloquea la maquinaria', child: _TaskDetails(task: conflicto.ocupadoPor)),
          if (conflicto.sugerencia != null) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Sugerencia de reprogramación',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (conflicto.sugerencia!.libreDesde != null)
                    Text('Libre desde: ${_formatDateTime(conflicto.sugerencia!.libreDesde!)}'),
                  if (conflicto.sugerencia!.inicioUsoSugerido != null &&
                      conflicto.sugerencia!.finUsoSugerido != null)
                    Text(
                      'Primer reintento sugerido: ${_formatDateTimeRange(conflicto.sugerencia!.inicioUsoSugerido!, conflicto.sugerencia!.finUsoSugerido!)}',
                    ),
                  if (conflicto.sugerencia!.nota != null &&
                      conflicto.sugerencia!.nota!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      conflicto.sugerencia!.nota!,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _TaskDetails extends StatelessWidget {
  final _TaskConflictSnapshot task;

  const _TaskDetails({required this.task});

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      'Tarea: ${task.descripcion} (#${task.tareaId})',
      'Conjunto: ${task.conjuntoLabel}',
      'Estado: ${task.estadoLabel}',
      'Uso real: ${_formatDateTimeRange(task.usoInicio, task.usoFin)}',
      'Reserva maquinaria: ${_formatDateTimeRange(task.reservaInicio, task.reservaFin)}',
      if (task.entrega != null || task.recogida != null)
        'Ventana logística: entrega ${task.entrega ?? '-'} / recogida ${task.recogida ?? '-'}',
      if (task.fuente != null && task.fuente!.isNotEmpty) 'Fuente: ${task.fuente}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(line),
            ),
          )
          .toList(),
    );
  }
}

class _MaquinariaConflictPayload {
  final String title;
  final String message;
  final String? userHint;
  final List<_MaquinariaConflictItem> conflictos;

  _MaquinariaConflictPayload({
    required this.title,
    required this.message,
    required this.userHint,
    required this.conflictos,
  });

  static _MaquinariaConflictPayload? tryParse(Object? error) {
    dynamic raw;
    if (error is ApiException) {
      raw = error.details;
    } else if (error is Map<String, dynamic>) {
      raw = error;
    } else {
      return null;
    }

    if (raw is! Map) return null;
    final data = raw.cast<String, dynamic>();
    final reason = (data['reason'] ?? data['code'] ?? '').toString().toUpperCase();
    final rawConflictos = data['conflictos'];
    if (reason != 'MAQUINARIA_NO_DISPONIBLE' && rawConflictos is! List) {
      return null;
    }

    final conflictos = (rawConflictos as List? ?? const [])
        .whereType<Map>()
        .map((item) => _MaquinariaConflictItem.fromMap(item.cast<String, dynamic>()))
        .toList();
    if (conflictos.isEmpty) return null;

    return _MaquinariaConflictPayload(
      title: (data['title'] ?? 'Conflicto de maquinaria').toString(),
      message: (data['message'] ?? 'La maquinaria no está disponible.').toString(),
      userHint: data['userHint']?.toString(),
      conflictos: conflictos,
    );
  }
}

class _MaquinariaConflictItem {
  final int maquinariaId;
  final String maquinaNombre;
  final String tipoSolape;
  final String motivo;
  final _TaskConflictSnapshot tareaSolicitada;
  final _TaskConflictSnapshot ocupadoPor;
  final _ConflictSuggestion? sugerencia;

  _MaquinariaConflictItem({
    required this.maquinariaId,
    required this.maquinaNombre,
    required this.tipoSolape,
    required this.motivo,
    required this.tareaSolicitada,
    required this.ocupadoPor,
    required this.sugerencia,
  });

  factory _MaquinariaConflictItem.fromMap(Map<String, dynamic> json) {
    return _MaquinariaConflictItem(
      maquinariaId: _asInt(json['maquinariaId']),
      maquinaNombre:
          (json['maquinaNombre'] ?? 'Maquinaria #${_asInt(json['maquinariaId'])}').toString(),
      tipoSolape: (json['tipoSolape'] ?? 'RESERVA_LOGISTICA').toString(),
      motivo: (json['motivo'] ?? 'La agenda de la maquinaria ya está ocupada.').toString(),
      tareaSolicitada: _TaskConflictSnapshot.fromMap(
        (json['tareaSolicitada'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      ocupadoPor: _TaskConflictSnapshot.fromMap(
        (json['ocupadoPor'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      sugerencia: json['sugerencia'] is Map
          ? _ConflictSuggestion.fromMap(
              (json['sugerencia'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}

class _TaskConflictSnapshot {
  final int tareaId;
  final String descripcion;
  final String conjuntoLabel;
  final String estadoLabel;
  final DateTime usoInicio;
  final DateTime usoFin;
  final DateTime reservaInicio;
  final DateTime reservaFin;
  final String? entrega;
  final String? recogida;
  final String? fuente;

  _TaskConflictSnapshot({
    required this.tareaId,
    required this.descripcion,
    required this.conjuntoLabel,
    required this.estadoLabel,
    required this.usoInicio,
    required this.usoFin,
    required this.reservaInicio,
    required this.reservaFin,
    required this.entrega,
    required this.recogida,
    required this.fuente,
  });

  factory _TaskConflictSnapshot.fromMap(Map<String, dynamic> json) {
    final conjuntoNombre = (json['conjuntoNombre'] ?? '').toString().trim();
    final conjuntoId = (json['conjuntoId'] ?? '').toString().trim();
    final estado = (json['estado'] ?? 'SIN_ESTADO').toString();
    return _TaskConflictSnapshot(
      tareaId: _asInt(json['tareaId']),
      descripcion: (json['descripcion'] ?? 'Tarea sin descripción').toString(),
      conjuntoLabel: conjuntoNombre.isNotEmpty
          ? '$conjuntoNombre${conjuntoId.isNotEmpty ? ' ($conjuntoId)' : ''}'
          : (conjuntoId.isNotEmpty ? conjuntoId : 'Sin conjunto'),
      estadoLabel: _beautifyEstado(estado),
      usoInicio: _parseDate(json['usoInicio']),
      usoFin: _parseDate(json['usoFin']),
      reservaInicio: _parseDate(json['reservaInicio']),
      reservaFin: _parseDate(json['reservaFin']),
      entrega: json['entrega']?.toString(),
      recogida: json['recogida']?.toString(),
      fuente: json['fuente']?.toString(),
    );
  }
}

class _ConflictSuggestion {
  final DateTime? libreDesde;
  final DateTime? inicioUsoSugerido;
  final DateTime? finUsoSugerido;
  final String? nota;

  _ConflictSuggestion({
    required this.libreDesde,
    required this.inicioUsoSugerido,
    required this.finUsoSugerido,
    required this.nota,
  });

  factory _ConflictSuggestion.fromMap(Map<String, dynamic> json) {
    return _ConflictSuggestion(
      libreDesde: _tryParseDate(json['libreDesde']),
      inicioUsoSugerido: _tryParseDate(json['inicioUsoSugerido']),
      finUsoSugerido: _tryParseDate(json['finUsoSugerido']),
      nota: json['nota']?.toString(),
    );
  }
}

int _asInt(dynamic value) => int.tryParse('${value ?? 0}') ?? 0;

DateTime _parseDate(dynamic value) => _tryParseDate(value) ?? DateTime.now();

DateTime? _tryParseDate(dynamic value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toLocal();
}

String _labelSolape(String tipo) {
  switch (tipo.toUpperCase()) {
    case 'USO_REAL':
      return 'Solape de uso real';
    case 'BORRADOR_INTERNO':
      return 'Conflicto con borrador';
    default:
      return 'Solape de reserva';
  }
}

String _beautifyEstado(String estado) => estado
    .split('_')
    .where((part) => part.trim().isNotEmpty)
    .map(
      (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
    )
    .join(' ');

String _formatDateTime(DateTime value) =>
    DateFormat('dd/MM/yyyy HH:mm').format(value);

String _formatDateTimeRange(DateTime start, DateTime end) =>
    '${_formatDateTime(start)} - ${_formatDateTime(end)}';
