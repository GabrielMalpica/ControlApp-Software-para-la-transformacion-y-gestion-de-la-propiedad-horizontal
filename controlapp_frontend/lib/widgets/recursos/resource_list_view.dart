// lib/widgets/recursos/resource_list_view.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';

/// Vista "lista" de la agenda (por defecto en celular): unidad → día →
/// "Conjunto A · 7:00 a. m. – 10:00 a. m. · Pulido salón social".
class ResourceListView extends StatelessWidget {
  const ResourceListView({
    super.key,
    required this.grupos,
    required this.onTapReserva,
    required this.onTapUnidad,
    this.soloDiasConActividad = false,
  });

  final List<GrupoAgendaModel> grupos;
  final void Function(UnidadAgendaModel unidad, ReservaRecursoModel reserva) onTapReserva;
  final void Function(UnidadAgendaModel unidad) onTapUnidad;
  final bool soloDiasConActividad;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        for (final g in grupos) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Row(
              children: [
                Icon(RecursoEstilos.iconoClase(g.clase), size: 18, color: AppTheme.primaryDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    g.tipoNombre,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                Text(
                  '${g.disponiblesHoy}/${g.total} disponibles hoy',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          for (final u in g.unidades)
            _UnidadCard(
              unidad: u,
              soloDiasConActividad: soloDiasConActividad,
              onTapReserva: (r) => onTapReserva(u, r),
              onTapUnidad: () => onTapUnidad(u),
            ),
        ],
      ],
    );
  }
}

class _UnidadCard extends StatelessWidget {
  const _UnidadCard({
    required this.unidad,
    required this.soloDiasConActividad,
    required this.onTapReserva,
    required this.onTapUnidad,
  });

  final UnidadAgendaModel unidad;
  final bool soloDiasConActividad;
  final void Function(ReservaRecursoModel) onTapReserva;
  final VoidCallback onTapUnidad;

  @override
  Widget build(BuildContext context) {
    final u = unidad;
    final colorActual = RecursoEstilos.colorActual(u.estadoActual);
    final reservas = u.reservas.where((r) => !r.cancelada).toList();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.surfaceSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTapUnidad,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.etiqueta, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text(
                          '${u.esDeEmpresa ? 'De la empresa' : 'De ${u.conjuntoPropietarioNombre ?? 'un conjunto'}'}'
                          ' · ahora en ${u.ubicacionActual.isEmpty ? u.ubicacionBase : u.ubicacionActual}'
                          '${u.libreDesde != null ? ' · libre desde ${RecursoEstilos.fechaHora.format(u.libreDesde!)}' : ''}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  EstadoPill(texto: u.estadoActual.etiqueta, color: colorActual),
                  const SizedBox(width: 4),
                  const Icon(Icons.history, size: 18, color: AppTheme.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final dia in u.dias)
              ..._lineasDia(dia, reservas),
          ],
        ),
      ),
    );
  }

  List<Widget> _lineasDia(DiaRecursoModel dia, List<ReservaRecursoModel> reservas) {
    final ini = dia.fecha;
    final fin = ini.add(const Duration(days: 1));
    final delDia = reservas
        .where((r) => r.esTarea && r.usoInicio.isBefore(fin) && r.usoFin.isAfter(ini))
        .toList()
      ..sort((a, b) => a.usoInicio.compareTo(b.usoInicio));
    final etiquetaDia = RecursoEstilos.capitalizar(RecursoEstilos.diaCorto.format(ini));

    if (delDia.isEmpty) {
      if (soloDiasConActividad && dia.estado == EstadoDiaRecurso.disponible) return const [];
      final texto = switch (dia.estado) {
        EstadoDiaRecurso.enTraslado => 'En ${dia.conjuntoNombre ?? 'conjunto'} (entrega / recogida)',
        EstadoDiaRecurso.prestado => 'Prestada a ${dia.conjuntoNombre ?? 'un conjunto'}',
        _ => dia.estado.etiqueta,
      };
      return [
        _Linea(
          dia: etiquetaDia,
          texto: texto,
          color: RecursoEstilos.colorDia(dia.estado),
          onTap: () {
            final r = reservas.where((r) => r.bloqueoInicio.isBefore(fin) && r.bloqueoFin.isAfter(ini)).toList();
            if (r.isNotEmpty) onTapReserva(r.first);
          },
        ),
      ];
    }
    return [
      for (var i = 0; i < delDia.length; i++)
        _Linea(
          dia: i == 0 ? etiquetaDia : '',
          texto: '${delDia[i].conjuntoNombre ?? ''} · ${RecursoEstilos.rangoHoras(delDia[i].usoInicio, delDia[i].usoFin)}'
              '${delDia[i].tareaDescripcion != null ? ' · ${delDia[i].tareaDescripcion}' : ''}'
              '${delDia[i].finalizada ? ' (finalizada)' : ''}',
          color: RecursoEstilos.colorConjunto(delDia[i].conjuntoId),
          onTap: () => onTapReserva(delDia[i]),
        ),
    ];
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.dia, required this.texto, required this.color, required this.onTap});
  final String dia;
  final String texto;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: Text(dia, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Container(
              width: 4,
              height: 16,
              margin: const EdgeInsets.only(right: 8, top: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(child: Text(texto, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      ),
    );
  }
}
