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

/// Cuadrícula por horas de solo lectura con tarjetas legibles: ícono de
/// categoría, hora, nombre y estado. Escala base: 1 hora = 80 px; si hay
/// tareas muy seguidas, la escala sube sola para que ninguna tarjeta pise a
/// la siguiente.
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
  static const double _pxHoraBase = 80;

  /// Altura con la que una tarjeta se alcanza a leer (hora + nombre).
  static const double _altoMinTarjeta = 40;

  /// Tope de la escala (480 px por hora) para tareas de pocos minutos.
  static const double _pxPorMinutoMax = 8;

  /// Hasta dónde se mide el espacio libre debajo de cada tarjeta.
  static const Duration _espacioMedido = Duration(minutes: 60);
  static const double _anchoHoras = 64;
  static const double _anchoMinColumna = 190;

  /// Píxeles por minuto de la cuadrícula que se está dibujando.
  double _pxMin = _pxHoraBase / 60;

  final _horizontal = DesplazamientoEnlazado();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calculadas = [for (final c in widget.columnas) _calcular(c)];

    // Escala: la tarjeta con menos espacio libre antes de la siguiente
    // (en su misma franja) debe quedar de al menos [_altoMinTarjeta].
    var espacioMin = double.infinity;
    for (final c in calculadas) {
      for (var i = 0; i < c.tareas.length; i++) {
        final m = _minutos(c.tareas[i].fechaInicio, c.layout[i].visualFin);
        if (m > 0) espacioMin = math.min(espacioMin, m);
      }
    }
    _pxMin = espacioMin.isFinite
        ? (_altoMinTarjeta / espacioMin).clamp(
            _pxHoraBase / 60,
            _pxPorMinutoMax,
          )
        : _pxHoraBase / 60;

    var minH = 24;
    var maxH = 0;
    for (final c in calculadas) {
      for (var i = 0; i < c.tareas.length; i++) {
        final t = c.tareas[i];
        final ini = t.fechaInicio.toLocal();
        final f = t.fechaFin.toLocal();
        minH = math.min(minH, ini.hour);
        if (!mismoDia(ini, f)) {
          maxH = 24;
          continue;
        }
        // Incluye lo que la tarjeta ocupa de más por su altura mínima.
        final finVisual = ini.add(
          Duration(
            seconds: (_altoTarjeta(t, c.layout[i]) / _pxMin * 60).ceil(),
          ),
        );
        final fin = finVisual.isAfter(f) ? finVisual : f;
        final finH = mismoDia(ini, fin)
            ? fin.hour + (fin.minute > 0 || fin.second > 0 ? 1 : 0)
            : 24;
        maxH = math.max(maxH, math.min(24, finH));
      }
    }
    if (minH >= maxH) {
      minH = 7;
      maxH = 16;
    }
    final horas = maxH - minH;
    final alto = horas * _pxMin * 60;
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
                          for (final col in calculadas)
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
    final pxHora = _pxMin * 60;
    return SizedBox(
      width: _anchoHoras,
      height: horas * pxHora + 8,
      child: Stack(
        children: [
          for (var i = 0; i <= horas; i++)
            Positioned(
              top: i * pxHora - (i == 0 ? 0 : 9),
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
    return ((l.hour - minH) * 60 + l.minute + l.second / 60) * _pxMin;
  }

  static double _minutos(DateTime desde, DateTime hasta) =>
      hasta.toLocal().difference(desde.toLocal()).inSeconds / 60;

  /// Carriles de una columna. El fin visual que devuelve el layout ya viene
  /// recortado al inicio de la siguiente tarea de la misma franja: es el
  /// espacio máximo que puede ocupar la tarjeta sin pisar a otra.
  _ColumnaCalculada _calcular(ColumnaHoras col) {
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
    ], minVisual: _espacioMedido);
    return _ColumnaCalculada(col, tareas, layout);
  }

  /// Alto de la tarjeta: su duración real, al menos [_altoMinTarjeta], pero
  /// nunca más que el espacio libre antes de la tarea siguiente.
  double _altoTarjeta(TareaModel t, WeekLayoutOutput l) {
    final real = math.max(1.0, _minutos(t.fechaInicio, t.fechaFin)) * _pxMin;
    final espacio = _minutos(t.fechaInicio, l.visualFin) * _pxMin;
    final deseado = math.max(real, _altoMinTarjeta);
    return math.max(14.0, math.min(deseado, espacio) - 2);
  }

  Widget _columna(_ColumnaCalculada c, double ancho, int minH, int horas) {
    final col = c.columna;
    final tareas = c.tareas;
    final layout = c.layout;
    return Container(
      width: ancho,
      height: horas * _pxMin * 60 + 8,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppTheme.primary.withValues(alpha: 0.12)),
        ),
      ),
      child: Stack(
        children: [
          for (var i = 0; i <= horas; i++)
            Positioned(
              top: i * _pxMin * 60,
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
    final top = _top(t.fechaInicio, minH) + 1;
    final alto = _altoTarjeta(t, l);
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
                              maxLines: alto >= 38 ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: alto < 24 ? 12 : 13,
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

class _ColumnaCalculada {
  final ColumnaHoras columna;
  final List<TareaModel> tareas;
  final List<WeekLayoutOutput> layout;

  const _ColumnaCalculada(this.columna, this.tareas, this.layout);
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
