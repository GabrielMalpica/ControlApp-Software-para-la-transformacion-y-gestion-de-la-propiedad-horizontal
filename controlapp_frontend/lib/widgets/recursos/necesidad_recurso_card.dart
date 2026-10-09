// lib/widgets/recursos/necesidad_recurso_card.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/recursos_api.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/recursos/asignar_recurso_sheet.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';
import 'package:flutter_application_1/widgets/recursos/reserva_acciones.dart';

/// Una necesidad de recurso de una tarea: qué pide, cuánto falta, qué unidades
/// tiene reservadas y acciones (asignar, cambiar unidad, liberar).
class NecesidadRecursoCard extends StatelessWidget {
  const NecesidadRecursoCard({
    super.key,
    required this.necesidad,
    required this.api,
    required this.puedeAsignar,
    required this.onCambio,
    this.empresaNit,
    this.mostrarConjunto = true,
  });

  final NecesidadRecursoModel necesidad;
  final RecursosApi api;
  final bool puedeAsignar;
  final VoidCallback onCambio;
  final String? empresaNit;
  final bool mostrarConjunto;

  @override
  Widget build(BuildContext context) {
    final n = necesidad;
    final t = n.tarea;
    final color = RecursoEstilos.colorCobertura(n.cobertura);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: n.tieneConflicto ? AppTheme.red : AppTheme.surfaceSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(RecursoEstilos.iconoClase(n.clase), color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${n.tipoNombre}${n.cantidad > 1 ? ' × ${n.cantidad}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.descripcion,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (mostrarConjunto) t.conjuntoNombre,
                          RecursoEstilos.capitalizar(RecursoEstilos.rangoUso(t.fechaInicio, t.fechaFin)),
                          if (t.operarios.isNotEmpty) t.operarios.join(', '),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    EstadoPill(texto: '${n.cobertura.etiqueta} ${n.asignadas}/${n.cantidad}', color: color),
                    const SizedBox(height: 4),
                    if (!n.obligatorio) const EstadoPill(texto: 'Opcional', color: AppTheme.textMuted),
                  ],
                ),
              ],
            ),
            for (final c in n.conflictos)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.red, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(c, style: const TextStyle(color: AppTheme.red, fontSize: 12.5))),
                  ],
                ),
              ),
            if (n.reservas.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final r in n.reservas.where((r) => r.esTarea))
                _ReservaFila(
                  reserva: r,
                  puedeAsignar: puedeAsignar,
                  onTap: () async {
                    final cambio = await mostrarDetalleReserva(
                      context,
                      api: api,
                      reserva: r,
                      empresaNit: empresaNit,
                      puedeAsignar: puedeAsignar,
                    );
                    if (cambio) onCambio();
                  },
                ),
            ],
            if (puedeAsignar && n.asignable) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () async {
                    final ok = await mostrarAsignarRecursoSheet(
                      context,
                      necesidadId: n.id,
                      empresaNit: empresaNit,
                      api: api,
                    );
                    if (ok) onCambio();
                  },
                  icon: const Icon(Icons.add_task),
                  label: Text(n.pendientes > 1 ? 'Asignar ${n.pendientes}' : 'Asignar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReservaFila extends StatelessWidget {
  const _ReservaFila({required this.reserva, required this.puedeAsignar, required this.onTap});
  final ReservaRecursoModel reserva;
  final bool puedeAsignar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reserva;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              r.finalizada ? Icons.check_circle_outline : Icons.event_available,
              size: 18,
              color: r.finalizada ? AppTheme.textMuted : AppTheme.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.recursoEtiqueta} · ${r.deEmpresa ? 'de la empresa' : 'del conjunto'}'
                '${r.deEmpresa && r.tieneVentanaLogistica ? ' · sale ${RecursoEstilos.fechaCorta.format(r.bloqueoInicio)}, vuelve ${RecursoEstilos.fechaCorta.format(r.bloqueoFin)}' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
