// lib/widgets/recursos/resource_timeline.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/interval_lanes.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';

/// Línea de tiempo de recursos: una fila por unidad (agrupadas por tipo) y una
/// columna por día.
///
/// - Barra tenue: ventana física (la unidad está fuera de bodega: entrega,
///   estadía y recogida, o traslado).
/// - Barra sólida: horas reales de uso en la tarea.
/// - Color de la barra: el conjunto (estable, para reconocerlo de un vistazo).
/// - Fondo del día: estado derivado (mantenimiento, no operativa...).
class ResourceTimeline extends StatelessWidget {
  const ResourceTimeline({
    super.key,
    required this.grupos,
    required this.dias,
    required this.onTapReserva,
    required this.onTapUnidad,
  });

  final List<GrupoAgendaModel> grupos;
  final List<DateTime> dias;
  final void Function(UnidadAgendaModel unidad, ReservaRecursoModel reserva) onTapReserva;
  final void Function(UnidadAgendaModel unidad) onTapUnidad;

  static const double _anchoEtiqueta = 190;
  static const double _altoCarril = 26;
  static const double _altoEncabezado = 44;

  @override
  Widget build(BuildContext context) {
    if (dias.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final disponible = math.max(0.0, constraints.maxWidth - _anchoEtiqueta - 2);
        final anchoDia = math.max(dias.length > 14 ? 44.0 : 96.0, disponible / dias.length);
        final anchoTotal = _anchoEtiqueta + anchoDia * dias.length;

        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: anchoTotal,
              child: Column(
                children: [
                  _Encabezado(dias: dias, anchoDia: anchoDia),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final g in grupos) ...[
                          _FilaGrupo(grupo: g, ancho: anchoTotal),
                          for (final u in g.unidades)
                            _FilaUnidad(
                              unidad: u,
                              dias: dias,
                              anchoDia: anchoDia,
                              onTapReserva: (r) => onTapReserva(u, r),
                              onTapUnidad: () => onTapUnidad(u),
                            ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.dias, required this.anchoDia});
  final List<DateTime> dias;
  final double anchoDia;

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    return SizedBox(
      height: ResourceTimeline._altoEncabezado,
      child: Row(
        children: [
          const SizedBox(
            width: ResourceTimeline._anchoEtiqueta,
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text('Recurso', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          for (final d in dias)
            Container(
              width: anchoDia,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _mismoDia(d, hoy) ? AppTheme.primary.withValues(alpha: 0.08) : null,
                border: const Border(left: BorderSide(color: AppTheme.surfaceSoft)),
              ),
              child: Text(
                anchoDia < 60 ? '${d.day}' : RecursoEstilos.capitalizar(RecursoEstilos.diaCorto.format(d)),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _mismoDia(d, hoy) ? FontWeight.w800 : FontWeight.w600,
                  color: d.weekday == DateTime.sunday ? AppTheme.textMuted : AppTheme.text,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _FilaGrupo extends StatelessWidget {
  const _FilaGrupo({required this.grupo, required this.ancho});
  final GrupoAgendaModel grupo;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      color: AppTheme.surfaceSoft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(RecursoEstilos.iconoClase(grupo.clase), size: 16, color: AppTheme.primaryDark),
          const SizedBox(width: 6),
          Text(grupo.tipoNombre, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text(
            '${grupo.total} unidad(es) · ${grupo.disponiblesHoy} disponible(s) hoy',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FilaUnidad extends StatelessWidget {
  const _FilaUnidad({
    required this.unidad,
    required this.dias,
    required this.anchoDia,
    required this.onTapReserva,
    required this.onTapUnidad,
  });

  final UnidadAgendaModel unidad;
  final List<DateTime> dias;
  final double anchoDia;
  final void Function(ReservaRecursoModel) onTapReserva;
  final VoidCallback onTapUnidad;

  @override
  Widget build(BuildContext context) {
    final inicio = dias.first;
    final fin = dias.last.add(const Duration(days: 1));
    final reservas = unidad.reservas.where((r) => !r.cancelada).toList();
    final packed = packIntervalsIntoLanes(
      reservas.map((r) => IntervalLaneInput(inicio: r.bloqueoInicio, fin: r.bloqueoFin)).toList(),
    );
    final alto = 10 + packed.laneCount * ResourceTimeline._altoCarril;
    final anchoBarras = anchoDia * dias.length;

    double x(DateTime t) {
      final minutos = t.difference(inicio).inMinutes;
      return (minutos / 1440 * anchoDia).clamp(0.0, anchoBarras);
    }

    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.surfaceSoft))),
      child: Row(
        children: [
          InkWell(
            onTap: onTapUnidad,
            child: SizedBox(
              width: ResourceTimeline._anchoEtiqueta,
              height: math.max(alto, 46),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unidad.etiqueta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      unidad.esDeEmpresa ? 'Empresa' : unidad.conjuntoPropietarioNombre ?? 'Conjunto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: anchoBarras,
            height: math.max(alto, 46),
            child: Stack(
              children: [
                // Fondo por día (estado derivado).
                for (var i = 0; i < unidad.dias.length && i < dias.length; i++)
                  Positioned(
                    left: i * anchoDia,
                    top: 0,
                    bottom: 0,
                    width: anchoDia,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _fondoDia(unidad.dias[i].estado),
                        border: const Border(left: BorderSide(color: AppTheme.surfaceSoft)),
                      ),
                    ),
                  ),
                // Línea de "ahora".
                if (DateTime.now().isAfter(inicio) && DateTime.now().isBefore(fin))
                  Positioned(
                    left: x(DateTime.now()),
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: Container(color: AppTheme.red.withValues(alpha: 0.6)),
                  ),
                for (var i = 0; i < reservas.length; i++)
                  _Barra(
                    reserva: reservas[i],
                    lane: packed.lanes[i].lane,
                    left: x(reservas[i].bloqueoInicio),
                    right: x(reservas[i].bloqueoFin),
                    usoLeft: x(reservas[i].usoInicio),
                    usoRight: x(reservas[i].usoFin),
                    onTap: () => onTapReserva(reservas[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color? _fondoDia(EstadoDiaRecurso e) {
    switch (e) {
      case EstadoDiaRecurso.mantenimiento:
        return AppTheme.accent.withValues(alpha: 0.18);
      case EstadoDiaRecurso.noOperativa:
        return AppTheme.red.withValues(alpha: 0.10);
      default:
        return null;
    }
  }
}

class _Barra extends StatelessWidget {
  const _Barra({
    required this.reserva,
    required this.lane,
    required this.left,
    required this.right,
    required this.usoLeft,
    required this.usoRight,
    required this.onTap,
  });

  final ReservaRecursoModel reserva;
  final int lane;
  final double left;
  final double right;
  final double usoLeft;
  final double usoRight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reserva;
    final color = r.esMantenimiento
        ? const Color(0xFFB7791F)
        : r.esPrestamo
            ? const Color(0xFF3F6FD8)
            : RecursoEstilos.colorConjunto(r.conjuntoId);
    final ancho = math.max(6.0, right - left);
    final top = 5.0 + lane * ResourceTimeline._altoCarril;
    final etiqueta = r.esMantenimiento
        ? 'Mantenimiento'
        : r.esPrestamo
            ? 'Préstamo · ${r.conjuntoNombre ?? ''}'
            : '${r.conjuntoNombre ?? ''}${r.tareaDescripcion != null ? ' · ${r.tareaDescripcion}' : ''}';

    return Positioned(
      left: left,
      top: top,
      width: ancho,
      height: ResourceTimeline._altoCarril - 4,
      child: Tooltip(
        message: '$etiqueta\n${RecursoEstilos.capitalizar(RecursoEstilos.rangoUso(r.usoInicio, r.usoFin))}'
            '${r.finalizada ? '\nFinalizada' : ''}',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: r.finalizada ? 0.10 : 0.20),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.65)),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (!r.esPrestamo)
                  Positioned(
                    left: math.max(0.0, usoLeft - left),
                    top: 0,
                    bottom: 0,
                    width: math.max(4.0, usoRight - usoLeft),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: r.finalizada ? 0.45 : 0.9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      etiqueta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _contraste(color, r),
                        shadows: const [Shadow(color: Colors.white70, blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _contraste(Color base, ReservaRecursoModel r) =>
      Color.lerp(base, Colors.black, 0.45) ?? AppTheme.text;
}

/// Leyenda compacta de la línea de tiempo.
class ResourceTimelineLeyenda extends StatelessWidget {
  const ResourceTimelineLeyenda({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t, {bool solido = true}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 10,
              decoration: BoxDecoration(
                color: solido ? c : c.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: c),
              ),
            ),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        item(AppTheme.primary, 'Horas de uso'),
        item(AppTheme.primary, 'Fuera de bodega (entrega / recogida)', solido: false),
        item(const Color(0xFF3F6FD8), 'Préstamo', solido: false),
        item(const Color(0xFFB7791F), 'Mantenimiento', solido: false),
      ],
    );
  }
}
