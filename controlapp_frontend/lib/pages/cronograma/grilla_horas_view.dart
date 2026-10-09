import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/utils/week_layout.dart';
import 'package:flutter_application_1/widgets/cronograma/desplazamiento_enlazado.dart';

/// Una columna de la cuadrícula: un trabajador (en un día) o un día (de un
/// trabajador).
class ColumnaHoras {
  final String titulo;
  final String subtitulo;
  final bool resaltada;
  final bool mostrarAhora;
  final List<TareaModel> tareas;

  const ColumnaHoras({
    required this.titulo,
    this.subtitulo = '',
    this.resaltada = false,
    this.mostrarAhora = false,
    required this.tareas,
  });
}

//// Cuadrícula por horas de solo lectura con tarjetas legibles: 1 hora =
/// 80 px, ícono de categoría, hora, nombre y estado.
///
/// Es un sliver: la cuadrícula completa se muestra a su altura natural y la
/// página se desplaza con un solo scroll vertical; la fila de nombres (o
/// días) queda fija arriba mientras se recorre. Si las columnas no caben, se
/// desplazan hacia los lados junto con esa fila (flechas o deslizando).
class GrillaHorasSliver extends StatefulWidget {
  final List<ColumnaHoras> columnas;
  final DateTime ahora;
  final int? seleccionadaId;
  final ValueChanged<TareaModel> onAbrir;

  const GrillaHorasSliver({
    super.key,
    required this.columnas,
    required this.ahora,
    required this.seleccionadaId,
    required this.onAbrir,
  });

  @override
  State<GrillaHorasSliver> createState() => _GrillaHorasSliverState();
}

class _GrillaHorasSliverState extends State<GrillaHorasSliver> {
  static const double _pxHora = 80;
  static const double _anchoHoras = 64;
  static const double _anchoMinColumna = 190;

  final _horizontal = DesplazamientoEnlazado();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var minH = 24;
    var maxH = 0;
    for (final c in widget.columnas) {
      for (final t in c.tareas) {
        final i = t.fechaInicio.toLocal();
        final f = t.fechaFin.toLocal();
        minH = math.min(minH, i.hour);
        final finH = f.hour + (f.minute > 0 ? 1 : 0);
        maxH = math.max(maxH, mismoDia(i, f) ? finH : 24);
      }
    }
    if (minH >= maxH) {
      minH = 7;
      maxH = 16;
    }
    final horas = maxH - minH;
    final alto = horas * _pxHora;
    final escala = MediaQuery.textScalerOf(context).scale(16) / 16;
    final altoTitulos = (56 * escala).clamp(56.0, 110.0);
    final altoAviso = (48 * escala).clamp(48.0, 90.0);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.crossAxisExtent;
        final disponible = ancho - _anchoHoras;
        final n = widget.columnas.length;
        final anchoCol = math.max(
          _anchoMinColumna,
          disponible / math.max(1, n),
        );
        final total = _anchoHoras + anchoCol * n;
        final desborda = total > ancho + 1;

        return DecoratedSliver(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.14)),
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: EncabezadoFijoDelegate(
                  alto: altoTitulos + 1 + (desborda ? altoAviso : 0),
                  child: Column(
                    children: [
                      if (desborda)
                        SizedBox(
                          height: altoAviso,
                          child: AvisoDesplazarLados(
                            texto:
                                'Hay más columnas hacia los lados. Usa las flechas o desliza la cuadrícula.',
                            onIzquierda: () =>
                                _horizontal.desplazar(-anchoCol * 2),
                            onDerecha: () =>
                                _horizontal.desplazar(anchoCol * 2),
                          ),
                        ),
                      SizedBox(
                        height: altoTitulos,
                        child: _filaTitulos(total, anchoCol),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _horizontal.alDesplazar,
                  child: SingleChildScrollView(
                    controller: _horizontal.controlador(1),
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: total,
                      height: alto + 8,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _columnaHoras(minH, horas),
                          for (final col in widget.columnas)
                            _columna(col, anchoCol, minH, horas),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _leyendas()),
            ],
          ),
        );
      },
    );
  }

  Widget _filaTitulos(double total, double anchoCol) {
    return NotificationListener<ScrollNotification>(
      onNotification: _horizontal.alDesplazar,
      child: SingleChildScrollView(
        controller: _horizontal.controlador(0),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: total,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: _anchoHoras,
                color: AppTheme.surfaceSoft,
                alignment: Alignment.center,
                child: const Text(
                  'Hora',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final col in widget.columnas)
                Container(
                  width: anchoCol,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: col.resaltada
                        ? AppTheme.primary
                        : AppTheme.surfaceSoft,
                    border: Border(
                      left: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        col.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: col.resaltada ? Colors.white : AppTheme.text,
                        ),
                      ),
                      if (col.subtitulo.isNotEmpty)
                        Text(
                          col.subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: col.resaltada
                                ? Colors.white70
                                : AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leyendas() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          _leyenda(
            const Icon(Icons.horizontal_rule, color: Color(0xFFDC2626)),
            'Hora actual',
          ),
          _leyenda(
            Icon(
              EstadoVisual.terminada.icono,
              color: EstadoVisual.terminada.color,
              size: 18,
            ),
            'Terminada',
          ),
          _leyenda(
            Icon(
              EstadoVisual.enCurso.icono,
              color: EstadoVisual.enCurso.color,
              size: 18,
            ),
            'En curso',
          ),
          _leyenda(
            Icon(
              EstadoVisual.pendiente.icono,
              color: EstadoVisual.pendiente.color,
              size: 18,
            ),
            'Pendiente o le toca ahora',
          ),
          _leyenda(
            Icon(
              EstadoVisual.atrasada.icono,
              color: EstadoVisual.atrasada.color,
              size: 18,
            ),
            'Con novedad',
          ),
          _leyenda(const Icon(Icons.group, size: 18), 'Compartida'),
        ],
      ),
    );
  }

  Widget _leyenda(Widget icono, String texto) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      icono,
      const SizedBox(width: 4),
      Flexible(child: Text(texto, style: const TextStyle(fontSize: 13.5))),
    ],
  );

  Widget _columnaHoras(int minH, int horas) {
    return SizedBox(
      width: _anchoHoras,
      height: horas * _pxHora + 8,
      child: Stack(
        children: [
          for (var i = 0; i <= horas; i++)
            Positioned(
              top: i * _pxHora - (i == 0 ? 0 : 9),
              right: 8,
              child: Text(
                '${(minH + i).toString().padLeft(2, '0')}:00',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (widget.columnas.any((c) => c.mostrarAhora))
            Positioned(
              top: _top(widget.ahora, minH) - 10,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  DateFormat('HH:mm').format(widget.ahora),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _top(DateTime d, int minH) {
    final l = d.toLocal();
    return ((l.hour - minH) * 60 + l.minute) / 60 * _pxHora;
  }

  Widget _columna(ColumnaHoras col, double ancho, int minH, int horas) {
    final tareas = [...col.tareas]
      ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    final layout = layoutWeekDayTasks([
      for (final t in tareas)
        WeekLayoutInput(
          inicio: t.fechaInicio.toLocal(),
          fin: t.fechaFin.isAfter(t.fechaInicio)
              ? t.fechaFin.toLocal()
              : t.fechaInicio.toLocal().add(const Duration(minutes: 1)),
        ),
    ], minVisual: const Duration(minutes: 26));
    return Container(
      width: ancho,
      height: horas * _pxHora + 8,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppTheme.primary.withValues(alpha: 0.12)),
        ),
      ),
      child: Stack(
        children: [
          for (var i = 0; i <= horas; i++)
            Positioned(
              top: i * _pxHora,
              left: 0,
              right: 0,
              child: Container(height: 1, color: const Color(0xFFE3EAE5)),
            ),
          if (col.mostrarAhora)
            Positioned(
              top: _top(widget.ahora, minH),
              left: 0,
              right: 0,
              child: Container(height: 3, color: const Color(0xFFDC2626)),
            ),
          for (var i = 0; i < tareas.length; i++)
            _tarjeta(tareas[i], layout[i], ancho, minH),
        ],
      ),
    );
  }

  Widget _tarjeta(TareaModel t, WeekLayoutOutput l, double ancho, int minH) {
    const pad = 4.0;
    final laneW = (ancho - pad * 2) / l.laneCount;
    final left = pad + laneW * l.lane;
    final width = laneW * l.laneSpan - 4;
    final top = _top(t.fechaInicio, minH) + 2;
    final altoReal =
        l.visualFin.difference(t.fechaInicio.toLocal()).inMinutes /
        60 *
        _pxHora;
    final alto = math.max(34.0, altoReal - 4);
    final visual = CategoriaVisual.deTarea(t);
    final estado = EstadoVisual.de(t, ahora: widget.ahora);
    final corta = alto < 64;
    final hm = DateFormat('HH:mm');
    final personas = trabajadoresDe([t]).length;
    final sel = t.id == widget.seleccionadaId;

    final etiqueta =
        '${hm.format(t.fechaInicio.toLocal())} a ${hm.format(t.fechaFin.toLocal())}. ${t.descripcion}. ${estado.etiqueta}. ${visual.nombre}.${personas > 1 ? ' Compartida por $personas personas.' : ''}';

    return Positioned(
      top: top,
      left: left,
      width: width,
      height: alto,
      child: Semantics(
        button: true,
        label: etiqueta,
        excludeSemantics: true,
        child: Tooltip(
          message:
              '${t.descripcion}\n${hm.format(t.fechaInicio.toLocal())}–${hm.format(t.fechaFin.toLocal())}',
          waitDuration: const Duration(milliseconds: 400),
          child: Material(
            color: estado.cerrada && !visual.esEspecial
                ? Colors.white
                : visual.fondo,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: sel
                    ? AppTheme.primary
                    : (visual.esEspecial
                          ? CategoriaVisual.especialAcento
                          : visual.acento.withValues(alpha: 0.45)),
                width: sel ? 3 : 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => widget.onAbrir(t),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                child: corta
                    ? Row(
                        children: [
                          Icon(visual.icono, size: 16, color: visual.acento),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${hm.format(t.fechaInicio.toLocal())} ${t.descripcion}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                          ),
                          Icon(estado.icono, size: 16, color: estado.color),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                visual.icono,
                                size: 16,
                                color: visual.acento,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${hm.format(t.fechaInicio.toLocal())}–${hm.format(t.fechaFin.toLocal())}',
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (personas > 1) ...[
                                const Icon(Icons.group, size: 16),
                                Text(
                                  '$personas',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Icon(estado.icono, size: 17, color: estado.color),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: Text(
                              t.descripcion,
                              overflow: TextOverflow.fade,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ayuda para construir las columnas por trabajador de un día.
List<ColumnaHoras> columnasPorTrabajador({
  required DateTime dia,
  required List<TareaModel> tareasDia,
  required List<TrabajadorRef> trabajadores,
  required DateTime ahora,
}) {
  final hoy = mismoDia(dia, ahora);
  return [
    for (final w in trabajadores)
      ColumnaHoras(
        titulo: w.nombre,
        subtitulo: w.cargo,
        mostrarAhora: hoy,
        tareas: tareasDia.where((t) => tareaEsDe(t, w.id)).toList(),
      ),
  ].where((c) => c.tareas.isNotEmpty).toList();
}

/// Columnas por día para la semana de una persona.
List<ColumnaHoras> columnasPorDia({
  required List<DateTime> dias,
  required List<TareaModel> tareas,
  required DateTime ahora,
}) {
  const nombres = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  return [
    for (final d in dias)
      ColumnaHoras(
        titulo: '${nombres[d.weekday - 1]} ${d.day}',
        subtitulo: mismoDia(d, ahora) ? 'Hoy' : '',
        resaltada: mismoDia(d, ahora),
        mostrarAhora: mismoDia(d, ahora),
        tareas: tareas.where((t) => mismoDia(t.fechaInicio, d)).toList(),
      ),
  ];
}

/// Nota bajo la cuadrícula cuando se ve un día con columnas por trabajador.
class NotaGrillaDia extends StatelessWidget {
  final DateTime dia;

  const NotaGrillaDia({super.key, required this.dia});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: AppTheme.textMuted, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${DateFormat("EEEE d 'de' MMMM", 'es').format(dia)}: una columna por trabajador, para que ninguna tarjeta quede diminuta. Para ver la semana de una persona, elígela en «Trabajador», al lado de «Por horas».',
            style: const TextStyle(color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }
}
