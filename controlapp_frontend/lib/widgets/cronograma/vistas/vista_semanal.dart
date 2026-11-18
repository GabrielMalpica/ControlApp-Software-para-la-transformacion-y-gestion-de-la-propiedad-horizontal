// Vista Semanal del cronograma (borrador y definitivo): una fila por
// operario y una columna por día, con la carga del día y sus tareas.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/tarea_labels.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/vistas_cronograma.dart';
import 'package:flutter_application_1/widgets/cronograma/desplazamiento_enlazado.dart';
import 'package:flutter_application_1/widgets/cronograma/vistas/vista_ui.dart';

class VistaSemanalCronograma extends StatefulWidget {
  final DateTime inicioSemana;

  /// Tareas de la semana ya filtradas.
  final List<TareaModel> tareas;
  final List<OperarioVista> operarios;
  final CalendarioVista calendario;
  final DateTime hoy;
  final bool borrador;

  /// Días que se pueden ver (el borrador solo tiene su mes). null = todos.
  final bool Function(DateTime dia)? diaDisponible;

  final ValueChanged<TareaModel> onTapTarea;
  final ValueChanged<DateTime> onTapDia;

  /// Barra de la página que, en pantallas angostas, se desplaza con el
  /// contenido en vez de quedar fija arriba.
  final Widget? cabecera;

  /// Excluidas pendientes (preventivas que no cupieron) del período.
  final List<PreventivaExcluidaBorradorModel> excluidas;
  final ValueChanged<PreventivaExcluidaBorradorModel>? onTapExcluida;

  /// Lleva a Planeación para ubicar las excluidas arrastrándolas.
  final VoidCallback? onProgramarExcluidas;

  const VistaSemanalCronograma({
    super.key,
    required this.inicioSemana,
    required this.tareas,
    required this.operarios,
    required this.calendario,
    required this.hoy,
    required this.onTapTarea,
    required this.onTapDia,
    this.borrador = false,
    this.diaDisponible,
    this.excluidas = const [],
    this.onTapExcluida,
    this.onProgramarExcluidas,
    this.cabecera,
  });

  @override
  State<VistaSemanalCronograma> createState() => _VistaSemanalCronogramaState();
}

class _VistaSemanalCronogramaState extends State<VistaSemanalCronograma> {
  final DesplazamientoEnlazado _enlace = DesplazamientoEnlazado();
  final ScrollController _vertical = ScrollController();
  late IndiceOperarios _indice;
  late ResumenSemanal _resumen;

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  @override
  void didUpdateWidget(covariant VistaSemanalCronograma old) {
    super.didUpdateWidget(old);
    if (!identical(old.tareas, widget.tareas) ||
        !identical(old.operarios, widget.operarios) ||
        !mismoDia(old.inicioSemana, widget.inicioSemana)) {
      _calcular();
    }
  }

  void _calcular() {
    _indice = IndiceOperarios(widget.operarios);
    _resumen = resumirSemana(
      inicioSemana: widget.inicioSemana,
      tareas: widget.tareas,
      operarios: _indice,
      calendario: widget.calendario,
    );
  }

  @override
  void dispose() {
    _enlace.dispose();
    _vertical.dispose();
    super.dispose();
  }

  bool _disponible(DateTime d) => widget.diaDisponible?.call(d) ?? true;

  @override
  Widget build(BuildContext context) {
    final r = _resumen;
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth;
        final wOp = ancho >= 1100
            ? 180.0
            : ancho >= 700
            ? 150.0
            : 118.0;
        const minDia = 150.0;
        // 32 de márgenes y 2 de los bordes de la tabla.
        final wDia = math.max(minDia, (ancho - 34 - wOp) / 7);
        final desborda = wDia * 7 > ancho - 34 - wOp + 0.5;
        final geo = (wOp: wOp, wDia: wDia, desborda: desborda);
        final filas = r.filas;
        return Scrollbar(
          controller: _vertical,
          child: CustomScrollView(
            controller: _vertical,
            slivers: [
              if (widget.cabecera != null)
                SliverToBoxAdapter(child: widget.cabecera!),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                sliver: SliverToBoxAdapter(child: _buildIndicadores(r)),
              ),
              if (widget.excluidas.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: CajaExcluidas(
                      titulo: 'Excluidas de esta semana',
                      excluidas: widget.excluidas,
                      operarios: _indice,
                      onTap: widget.onTapExcluida,
                      onProgramar: widget.onProgramarExcluidas,
                    ),
                  ),
                ),
              if (desborda)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: AvisoDesplazarLados(
                      texto:
                          'La semana sigue hacia los lados: desliza los días o usa las flechas.',
                      onIzquierda: () => _enlace.desplazar(-wDia * 2),
                      onDerecha: () => _enlace.desplazar(wDia * 2),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: EncabezadoFijoDelegate(
                    alto: 64,
                    child: _buildEncabezado(geo),
                  ),
                ),
              ),
              if (filas.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          left: BorderSide(color: ColoresVista.borde),
                          right: BorderSide(color: ColoresVista.borde),
                          bottom: BorderSide(color: ColoresVista.borde),
                        ),
                      ),
                      child: const Text(
                        'No hay tareas esta semana con los filtros elegidos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: filas.length,
                    itemBuilder: (context, i) => _buildFila(
                      filas[i],
                      geo,
                      i + 1,
                      ultima: i == filas.length - 1,
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    r.maxMinutosCelda > 0
                        ? 'La barra de cada día compara la carga programada contra el día más cargado '
                              'de la semana (${formatoHorasCorto(r.maxMinutosCelda)}). '
                              'Toca un día para abrir la vista diaria y una tarea para ver su detalle.'
                        : 'Toca un día para abrir la vista diaria.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: ColoresVista.textoSuave,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIndicadores(ResumenSemanal r) {
    final dias = r.dias;
    final festivos = dias.where(widget.calendario.esFestivo).toList();
    String capital(String s) =>
        s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    final detalleTotal = festivos.isEmpty
        ? 'Del ${diaCorto(dias.first)} ${dias.first.day} al ${diaCorto(dias.last)} ${dias.last.day}'
        : festivos.length == 1
        ? '${capital(diaLargo(festivos.first))} ${festivos.first.day} es festivo'
        : '${capital(unirConY(festivos.map((f) => '${diaLargo(f)} ${f.day}').toList()))} son festivos';
    final baja = r.cargaMasBaja;
    return FilaIndicadores(
      indicadores: [
        IndicadorVista(
          etiqueta: 'Tareas de la semana',
          valor: '${r.tareas}',
          detalle: detalleTotal,
        ),
        IndicadorVista(
          etiqueta: 'Horas programadas',
          valor: formatoHorasCorto(r.minutos),
          detalle: 'Suma de la jornada de cada operario',
        ),
        IndicadorVista(
          etiqueta: 'Día más cargado',
          valor: r.diaMasCargado == null
              ? '—'
              : '${capital(diaCorto(r.diaMasCargado!))} ${r.diaMasCargado!.day}',
          detalle: r.diaMasCargado == null
              ? 'Sin tareas esta semana'
              : '${r.tareasDiaMasCargado} tareas',
          onTap: r.diaMasCargado == null
              ? null
              : () => widget.onTapDia(r.diaMasCargado!),
        ),
        IndicadorVista(
          etiqueta: 'Carga más baja (día hábil)',
          valor: baja == null ? '—' : formatoHorasCorto(baja.minutos),
          colorValor: baja == null ? null : ColoresVista.alerta,
          detalle: baja == null
              ? 'Sin días hábiles con tareas'
              : '${r.operarioCargaMasBaja?.nombreCorto ?? ''}, ${diaLargo(baja.dia)} ${baja.dia.day}',
          onTap: baja == null ? null : () => widget.onTapDia(baja.dia),
        ),
      ],
    );
  }

  Widget _zonaDias(
    ({double wOp, double wDia, bool desborda}) geo,
    int clave,
    Widget dias,
  ) {
    if (!geo.desborda) return dias;
    return Expanded(
      child: NotificationListener<ScrollNotification>(
        onNotification: _enlace.alDesplazar,
        child: SingleChildScrollView(
          controller: _enlace.controlador(clave),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: dias,
        ),
      ),
    );
  }

  Color? _fondoDia(DateTime d) {
    if (!_disponible(d)) return const Color(0xFFF2F3F4);
    if (widget.calendario.esFestivo(d)) return ColoresVista.festivo;
    if (widget.calendario.esDomingo(d)) return ColoresVista.domingo;
    return null;
  }

  Widget _buildEncabezado(({double wOp, double wDia, bool desborda}) geo) {
    final dias = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in _resumen.dias)
          () {
            final hoy = mismoDia(d, widget.hoy);
            final festivo = widget.calendario.esFestivo(d);
            final domingo = widget.calendario.esDomingo(d);
            final etiqueta = festivo
                ? 'Festivo'
                : domingo
                ? 'Domingo'
                : null;
            final colorTexto = hoy
                ? Colors.white
                : festivo
                ? ColoresVista.festivoTexto
                : domingo
                ? ColoresVista.domingoTexto
                : ColoresVista.texto;
            final dia = diaCorto(d);
            return Tooltip(
              message: _disponible(d)
                  ? 'Ver ${diaLargo(d)} ${d.day}${widget.calendario.nombreFestivo(d) != null ? ' (${widget.calendario.nombreFestivo(d)})' : ''}'
                  : 'Este día es de otro mes',
              child: InkWell(
                onTap: _disponible(d) ? () => widget.onTapDia(d) : null,
                child: Container(
                  width: geo.wDia,
                  height: 62,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: hoy ? null : _fondoDia(d),
                    border: const Border(
                      left: BorderSide(color: ColoresVista.bordeSuave),
                    ),
                  ),
                  child: Container(
                    decoration: hoy
                        ? BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dia[0].toUpperCase() + dia.substring(1),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorTexto.withValues(alpha: 0.8),
                          ),
                        ),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: colorTexto,
                          ),
                        ),
                        if (etiqueta != null)
                          Text(
                            etiqueta,
                            style: TextStyle(fontSize: 10.5, color: colorTexto),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }(),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        border: Border.all(color: ColoresVista.borde),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: geo.wOp,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Operario',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ColoresVista.texto,
                ),
              ),
            ),
          ),
          _zonaDias(geo, 0, dias),
        ],
      ),
    );
  }

  Widget _buildFila(
    FilaSemanal fila,
    ({double wOp, double wDia, bool desborda}) geo,
    int clave, {
    required bool ultima,
  }) {
    final o = fila.operario;
    final etiqueta = SizedBox(
      width: geo.wOp,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AvatarOperario(operario: o, tamano: 28),
            const SizedBox(height: 8),
            Text(
              o?.nombreCorto ?? 'Sin operario',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ColoresVista.texto,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${fila.tareas} ${fila.tareas == 1 ? 'tarea' : 'tareas'} · ${formatoHorasCorto(fila.minutos)}',
              style: const TextStyle(
                fontSize: 12,
                color: ColoresVista.textoSuave,
              ),
            ),
          ],
        ),
      ),
    );

    final dias = IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final celda in fila.dias)
            Container(
              width: geo.wDia,
              constraints: const BoxConstraints(minHeight: 120),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _fondoDia(celda.dia),
                border: const Border(
                  left: BorderSide(color: ColoresVista.bordeSuave),
                ),
              ),
              child: _buildCelda(fila, celda),
            ),
        ],
      ),
    );

    // Sin esquinas redondeadas: Flutter no permite radio con un borde que no
    // tiene los cuatro lados.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: const BorderSide(color: ColoresVista.borde),
          right: const BorderSide(color: ColoresVista.borde),
          bottom: BorderSide(
            color: ultima ? ColoresVista.borde : ColoresVista.bordeSuave,
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [etiqueta, _zonaDias(geo, clave, dias)],
        ),
      ),
    );
  }

  Widget _buildCelda(FilaSemanal fila, CeldaSemanal celda) {
    if (!_disponible(celda.dia)) {
      return _CajaVacia(texto: 'Otro mes', rayado: true);
    }
    if (celda.tareas.isEmpty) {
      return _CajaVacia(
        texto: 'Sin tareas',
        onTap: () => widget.onTapDia(celda.dia),
      );
    }
    final maximo = _resumen.maxMinutosCelda;
    final fraccion = maximo == 0 ? 0.0 : celda.minutos / maximo;
    final colorBarra = fraccion >= 0.6
        ? AppTheme.primary
        : const Color(0xFFD97706);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => widget.onTapDia(celda.dia),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${celda.tareas.length} ${celda.tareas.length == 1 ? 'tarea' : 'tareas'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ColoresVista.texto,
                        ),
                      ),
                    ),
                    Text(
                      formatoHorasCorto(celda.minutos),
                      style: const TextStyle(
                        fontSize: 12,
                        color: ColoresVista.textoSuave,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                BarraCarga(valor: fraccion, color: colorBarra, alto: 5),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        for (final t in celda.tareas)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _ChipTareaSemana(
              tarea: t,
              operario: fila.operario,
              compartida: _indice.de(t).length > 1,
              vencida: !widget.borrador && estaVencida(t, widget.hoy),
              estado: etiquetaEstadoTarea(t, borrador: widget.borrador),
              onTap: () => widget.onTapTarea(t),
            ),
          ),
      ],
    );
  }
}

class _CajaVacia extends StatelessWidget {
  final String texto;
  final bool rayado;
  final VoidCallback? onTap;

  const _CajaVacia({required this.texto, this.rayado = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        painter: rayado
            ? const RayadoPainter(color: Color(0x14000000))
            : const _BordePunteado(),
        child: Center(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 12,
              color: ColoresVista.textoSuave,
            ),
          ),
        ),
      ),
    );
  }
}

class _BordePunteado extends CustomPainter {
  const _BordePunteado();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFCDD3CF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final path = Path()..addRRect(r);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), p);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_BordePunteado oldDelegate) => false;
}

class _ChipTareaSemana extends StatelessWidget {
  final TareaModel tarea;
  final OperarioVista? operario;
  final bool compartida;
  final bool vencida;
  final String estado;
  final VoidCallback onTap;

  const _ChipTareaSemana({
    required this.tarea,
    required this.operario,
    required this.compartida,
    required this.vencida,
    required this.estado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = coloresDeTarea(tarea, operario);
    final especial = esEspecial(tarea);
    final inicio = tarea.fechaInicio.toLocal();
    final fin = tarea.fechaFin.toLocal();
    return Tooltip(
      message:
          '${hhmm(inicio)}–${hhmm(fin)} · ${lugarDe(tarea)}\n${tarea.descripcion.trim()}\n'
          '$estado${compartida ? ' · compartida' : ''}${especial ? ' · ${etiquetaCorrectiva()}' : ''}',
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: c.fondo,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 24,
            padding: EdgeInsets.only(left: especial ? 0 : 6, right: 6),
            child: Row(
              children: [
                if (especial) ...[
                  const SizedBox(
                    width: 3,
                    height: 24,
                    child: ColoredBox(color: Color(0xFF6D28D9)),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  hhmm(inicio),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: c.texto,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    lugarDe(tarea),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: ColoresVista.texto,
                    ),
                  ),
                ),
                if (compartida) Icon(Icons.group, size: 12, color: c.texto),
                if (vencida) ...[
                  const SizedBox(width: 3),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: ColoresVista.vencida,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
