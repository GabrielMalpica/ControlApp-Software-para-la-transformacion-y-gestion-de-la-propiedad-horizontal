import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pages/cronograma/secciones_actividades.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/widgets/cronograma/actividad_card.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_controles.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_ui.dart';

enum OrdenHoy { porHora, porTrabajador }

/// Vista "Hoy" del administrador: qué se está haciendo, qué falta y qué tuvo
/// novedad. Es la entrada del cronograma.
class CronogramaHoyView extends StatelessWidget {
  final DateTime dia;
  final DateTime ahora;

  /// Actividades del día con los filtros de trabajador, categoría y
  /// búsqueda (sin el filtro de estado: el resumen las cuenta todas).
  final List<TareaModel> base;
  final GrupoEstado? grupo;
  final ValueChanged<GrupoEstado?> onGrupo;
  final OrdenHoy orden;
  final ValueChanged<OrdenHoy> onOrden;
  final int? seleccionadaId;
  final ValueChanged<TareaModel> onAbrir;
  final ValueChanged<String> onElegirTrabajador;

  /// Fecha, filtros… (se desplaza junto con la lista).
  final Widget cabecera;

  /// Panel de detalle fijo a la derecha (solo en pantallas anchas).
  final Widget? panelDetalle;
  final String? festivo;
  final VoidCallback? onQuitarFiltros;

  /// Selector de trabajador: aparece al lado de "Ordenar" solo cuando se
  /// elige "Por trabajador".
  final Widget? selectorTrabajador;

  const CronogramaHoyView({
    super.key,
    required this.dia,
    required this.ahora,
    required this.base,
    required this.grupo,
    required this.onGrupo,
    required this.orden,
    required this.onOrden,
    required this.seleccionadaId,
    required this.onAbrir,
    required this.onElegirTrabajador,
    required this.cabecera,
    this.panelDetalle,
    this.festivo,
    this.onQuitarFiltros,
    this.selectorTrabajador,
  });

  bool get _esHoy => mismoDia(dia, ahora);

  @override
  Widget build(BuildContext context) {
    final filtradas = grupo == null
        ? base
        : base
              .where((t) => EstadoVisual.de(t, ahora: ahora).grupo == grupo)
              .toList();
    final resumen = contarPorGrupo(base, ahora: ahora);

    final hijos = <Widget>[
      cabecera,
      const SizedBox(height: 14),
      const GuiaCronogramaCard(),
      const SizedBox(height: 14),
      ResumenDiaTarjetas(
        resumen: resumen,
        seleccionado: grupo,
        onChanged: onGrupo,
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 14),
        child: Text(
          'Cada actividad compartida se cuenta una sola vez.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
        ),
      ),
      if (_esHoy && base.isNotEmpty) ...[
        _AhoraMismo(base: base, ahora: ahora, onAbrir: onAbrir),
        const SizedBox(height: 16),
      ],
      if (festivo != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Icon(Icons.celebration_outlined, color: Color(0xFFB91C1C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Festivo: $festivo',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF991B1B),
                  ),
                ),
              ),
            ],
          ),
        ),
      _SelectorOrden(
        orden: orden,
        onOrden: onOrden,
        selectorTrabajador: orden == OrdenHoy.porTrabajador
            ? selectorTrabajador
            : null,
      ),
      const SizedBox(height: 14),
      ..._lista(filtradas),
      const SizedBox(height: 40),
    ];

    final scroll = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          sliver: SliverList.list(children: hijos),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (panelDetalle == null || c.maxWidth < 1100) return scroll;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: scroll),
            Container(
              width: 420,
              margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: panelDetalle,
            ),
          ],
        );
      },
    );
  }

  List<Widget> _lista(List<TareaModel> filtradas) {
    if (filtradas.isEmpty) {
      final hayAlgo = base.isNotEmpty;
      return [
        VacioCronograma(
          mensaje: hayAlgo
              ? 'No hay actividades con estos filtros.'
              : (festivo != null
                    ? 'Es festivo y no hay actividades programadas.'
                    : 'No hay actividades programadas para este día.'),
          onQuitarFiltros: onQuitarFiltros,
        ),
      ];
    }
    if (orden == OrdenHoy.porTrabajador) {
      return seccionesPorTrabajador(
        tareas: filtradas,
        base: base,
        ahora: ahora,
        seleccionadaId: seleccionadaId,
        onAbrir: onAbrir,
        onElegirTrabajador: onElegirTrabajador,
      );
    }
    final out = <Widget>[];
    for (final (hora, tareas) in agruparPorHoraInicio(filtradas)) {
      out.add(EncabezadoHora(hora: hora, cantidad: tareas.length));
      out.add(
        RejillaTarjetas(
          hijos: [
            for (final t in tareas)
              ActividadCard(
                tarea: t,
                ahora: ahora,
                seleccionada: t.id == seleccionadaId,
                simultaneas: _conteoSimultaneas(t),
                onTap: () => onAbrir(t),
              ),
          ],
        ),
      );
      out.add(const SizedBox(height: 20));
    }
    return out;
  }

  int _conteoSimultaneas(TareaModel t) {
    final n = simultaneasDe(t, base).length;
    return n == 0 ? 0 : n + 1;
  }
}

class _SelectorOrden extends StatelessWidget {
  final OrdenHoy orden;
  final ValueChanged<OrdenHoy> onOrden;
  final Widget? selectorTrabajador;

  const _SelectorOrden({
    required this.orden,
    required this.onOrden,
    this.selectorTrabajador,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        const Text('Ordenar:', style: TextStyle(color: AppTheme.textMuted)),
        SegmentedButton<OrdenHoy>(
          segments: const [
            ButtonSegment(
              value: OrdenHoy.porHora,
              icon: Icon(Icons.schedule),
              label: Text('Por hora'),
            ),
            ButtonSegment(
              value: OrdenHoy.porTrabajador,
              icon: Icon(Icons.person_outline),
              label: Text('Por trabajador'),
            ),
          ],
          selected: {orden},
          onSelectionChanged: (s) => onOrden(s.first),
        ),
        if (selectorTrabajador != null)
          EntradaSuave(child: selectorTrabajador!),
      ],
    );
  }
}

/// Qué está haciendo cada persona según el horario.
class _AhoraMismo extends StatelessWidget {
  final List<TareaModel> base;
  final DateTime ahora;
  final ValueChanged<TareaModel> onAbrir;

  const _AhoraMismo({
    required this.base,
    required this.ahora,
    required this.onAbrir,
  });

  static final _hm = DateFormat('HH:mm');
  static final _h12 = DateFormat('h:mm a', 'es');

  @override
  Widget build(BuildContext context) {
    final trabajadores = trabajadoresDe(base);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Icon(Icons.schedule, color: Color(0xFF1D4ED8)),
              Semantics(
                header: true,
                child: Text(
                  'Ahora mismo · ${_h12.format(ahora)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Text(
                'Según el horario programado',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final w in trabajadores) _fila(w),
        ],
      ),
    );
  }

  Widget _fila(TrabajadorRef w) {
    final suyas = base.where((t) => tareaEsDe(t, w.id)).toList()
      ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    final actuales = suyas
        .where(
          (t) => !t.fechaInicio.isAfter(ahora) && t.fechaFin.isAfter(ahora),
        )
        .toList();
    TareaModel? siguiente;
    for (final t in suyas) {
      if (t.fechaInicio.isAfter(ahora)) {
        siguiente = t;
        break;
      }
    }
    final t = actuales.isNotEmpty ? actuales.first : null;
    final otras = actuales.length > 1
        ? ' (y ${actuales.length - 1} más a la vez)'
        : '';

    final texto = t == null
        ? (siguiente == null
              ? 'Sin actividad en este momento.'
              : 'Sin actividad ahora. Sigue a las ${_hm.format(siguiente.fechaInicio.toLocal())}: ${siguiente.descripcion}.')
        : '${t.descripcion}$otras';

    final contenido = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrabajadorAvatar(trabajador: w, tamano: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: TextStyle(
                    color: t == null ? AppTheme.textMuted : AppTheme.text,
                    fontWeight: t == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                if (t != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${_hm.format(t.fechaInicio.toLocal())}–${_hm.format(t.fechaFin.toLocal())} · ${t.ubicacionNombre ?? ''}',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                      EstadoChip(
                        estado: EstadoVisual.de(t, ahora: ahora),
                        compacto: true,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (t != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        child: t == null
            ? contenido
            : InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onAbrir(t),
                child: contenido,
              ),
      ),
    );
  }
}
