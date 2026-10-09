// lib/widgets/recursos/reserva_acciones.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/recursos_api.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/recursos/asignar_recurso_sheet.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';

/// Pide el motivo y cancela la reserva (queda en el histórico). True si se canceló.
Future<bool> cancelarReservaConMotivo(
  BuildContext context, {
  required RecursosApi api,
  required ReservaRecursoModel reserva,
  String? empresaNit,
}) {
  return cancelarReservaPorId(
    context,
    api: api,
    reservaId: reserva.id,
    etiqueta: reserva.recursoEtiqueta,
    detalle: reserva.tareaDescripcion != null
        ? '${reserva.tareaDescripcion} · ${reserva.conjuntoNombre ?? ''}'
        : null,
    empresaNit: empresaNit,
  );
}

/// Igual que [cancelarReservaConMotivo] cuando solo se conoce el id (p. ej. desde una alerta).
Future<bool> cancelarReservaPorId(
  BuildContext context, {
  required RecursosApi api,
  required int reservaId,
  required String etiqueta,
  String? detalle,
  String? empresaNit,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final motivo = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Liberar $etiqueta'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detalle != null) Text(detalle, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            TextFormField(
              controller: controller,
              autofocus: true,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ej.: se envía a otro conjunto, asignación por error',
              ),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe el motivo.' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Volver')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) Navigator.of(ctx).pop(controller.text.trim());
          },
          child: const Text('Liberar recurso'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (motivo == null || !context.mounted) return false;

  try {
    await api.cancelarReserva(empresaNit: empresaNit, reservaId: reservaId, motivo: motivo);
    if (context.mounted) {
      AppFeedback.showInfo(context, title: 'Recurso liberado', message: '$etiqueta quedó disponible.');
    }
    return true;
  } catch (e) {
    if (context.mounted) AppFeedback.showError(context, message: AppError.messageOf(e));
    return false;
  }
}

/// Detalle de una reserva (al tocar una barra de la agenda) con sus acciones.
/// Devuelve true si cambió algo.
Future<bool> mostrarDetalleReserva(
  BuildContext context, {
  required RecursosApi api,
  required ReservaRecursoModel reserva,
  String? empresaNit,
  required bool puedeAsignar,
}) async {
  final cambio = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      final r = reserva;
      final titulo = r.esMantenimiento
          ? 'Mantenimiento programado'
          : r.esPrestamo
              ? 'Préstamo a ${r.conjuntoNombre ?? 'conjunto'}'
              : r.tareaDescripcion ?? 'Reserva';
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.recursoEtiqueta, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 2),
            Text(titulo, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            _fila(Icons.apartment_outlined, r.conjuntoNombre ?? 'Bodega de la empresa'),
            _fila(Icons.schedule, 'Uso: ${RecursoEstilos.capitalizar(RecursoEstilos.rangoUso(r.usoInicio, r.usoFin))}'),
            if (r.tieneVentanaLogistica)
              _fila(
                Icons.local_shipping_outlined,
                'Fuera de bodega: ${RecursoEstilos.fechaHora.format(r.bloqueoInicio)} → ${RecursoEstilos.fechaHora.format(r.bloqueoFin)}',
              ),
            _fila(
              Icons.swap_horiz,
              r.deEmpresa ? 'Recurso de la empresa (préstamo)' : 'Recurso del conjunto',
            ),
            if (r.responsables.isNotEmpty) _fila(Icons.person_outline, r.responsables.join(', ')),
            if (r.supervisor != null) _fila(Icons.badge_outlined, 'Supervisor: ${r.supervisor}'),
            if (r.observacion != null) _fila(Icons.notes, r.observacion!),
            _fila(
              Icons.flag_outlined,
              r.cancelada
                  ? 'Cancelada${r.motivoCancelacion != null ? ': ${r.motivoCancelacion}' : ''}'
                  : r.finalizada
                      ? 'Finalizada'
                      : 'Vigente',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (puedeAsignar && r.vigente && r.esTarea && r.necesidadId != null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await mostrarAsignarRecursoSheet(
                        ctx,
                        necesidadId: r.necesidadId!,
                        empresaNit: empresaNit,
                        reemplazarReservaId: r.id,
                        reemplazarEtiqueta: r.recursoEtiqueta,
                        api: api,
                      );
                      if (ok && ctx.mounted) Navigator.of(ctx).pop(true);
                    },
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Cambiar unidad'),
                  ),
                if (puedeAsignar && r.vigente && !r.esPrestamo)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.red),
                    onPressed: () async {
                      final ok = await cancelarReservaConMotivo(ctx, api: api, reserva: r, empresaNit: empresaNit);
                      if (ok && ctx.mounted) Navigator.of(ctx).pop(true);
                    },
                    icon: const Icon(Icons.link_off),
                    label: Text(r.esMantenimiento ? 'Quitar bloqueo' : 'Liberar recurso'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => mostrarHistorialUnidad(ctx, api: api, clase: r.clase, unidadId: r.unidadId, empresaNit: empresaNit),
                  icon: const Icon(Icons.history),
                  label: const Text('Historial de la unidad'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return cambio == true;
}

Widget _fila(IconData icono, String texto) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );

/// Historial completo de una unidad: dónde estuvo, cuándo, para qué tarea,
/// quién la usó y cuánto tiempo (incluye reservas canceladas).
Future<void> mostrarHistorialUnidad(
  BuildContext context, {
  required RecursosApi api,
  required ClaseRecurso clase,
  required int unidadId,
  String? empresaNit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _HistorialUnidad(api: api, clase: clase, unidadId: unidadId, empresaNit: empresaNit),
    ),
  );
}

class _HistorialUnidad extends StatefulWidget {
  const _HistorialUnidad({required this.api, required this.clase, required this.unidadId, this.empresaNit});
  final RecursosApi api;
  final ClaseRecurso clase;
  final int unidadId;
  final String? empresaNit;

  @override
  State<_HistorialUnidad> createState() => _HistorialUnidadState();
}

class _HistorialUnidadState extends State<_HistorialUnidad> {
  late Future<HistorialUnidadResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.historial(empresaNit: widget.empresaNit, clase: widget.clase, unidadId: widget.unidadId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HistorialUnidadResponse>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(AppError.messageOf(snap.error), textAlign: TextAlign.center),
            ),
          );
        }
        final h = snap.data!;
        final horas = (h.minutosDeUso / 60).toStringAsFixed(1);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(h.etiqueta, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                EstadoPill(texto: h.estadoActual.etiqueta, color: RecursoEstilos.colorActual(h.estadoActual)),
                EstadoPill(texto: h.ubicacionActual, color: AppTheme.textMuted, icono: Icons.place_outlined),
                if (!h.reservable)
                  EstadoPill(texto: RecursoEstilos.etiquetaEstadoInventario(h.estado), color: AppTheme.red),
                if (h.libreDesde != null)
                  EstadoPill(
                    texto: 'Libre desde ${RecursoEstilos.fechaHora.format(h.libreDesde!)}',
                    color: AppTheme.secondary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${h.finalizadas} uso(s) finalizado(s) · $horas h de uso · ${h.conjuntosDistintos} conjunto(s) · ${h.canceladas} cancelada(s)',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const Divider(height: 24),
            if (h.reservas.isEmpty) const Text('Esta unidad todavía no tiene reservas registradas.'),
            for (final r in h.reservas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.esMantenimiento
                      ? Icons.build_outlined
                      : r.esPrestamo
                          ? Icons.handshake_outlined
                          : Icons.event_note_outlined,
                  color: r.cancelada ? AppTheme.textMuted : RecursoEstilos.colorConjunto(r.conjuntoId),
                ),
                title: Text(
                  r.esMantenimiento
                      ? 'Mantenimiento${r.observacion != null ? ' · ${r.observacion}' : ''}'
                      : '${r.conjuntoNombre ?? 'Conjunto'} · ${r.tareaDescripcion ?? (r.esPrestamo ? 'Préstamo' : 'Tarea')}',
                  style: TextStyle(decoration: r.cancelada ? TextDecoration.lineThrough : null),
                ),
                subtitle: Text(
                  [
                    RecursoEstilos.capitalizar(RecursoEstilos.rangoUso(r.usoInicio, r.usoFin)),
                    if (r.responsables.isNotEmpty) r.responsables.join(', '),
                    if (r.cancelada) 'Cancelada${r.motivoCancelacion != null ? ': ${r.motivoCancelacion}' : ''}',
                    if (r.finalizada) 'Finalizada',
                  ].join('\n'),
                ),
              ),
          ],
        );
      },
    );
  }
}
