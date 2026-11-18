// Vista Diaria del cronograma (borrador y definitivo): una columna por
// operario con sus tareas ubicadas por hora y, en pantalla ancha, el detalle
// de la tarea elegida, el avance del día y la ocupación de cada operario.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/tarea_labels.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/vistas_cronograma.dart';
import 'package:flutter_application_1/widgets/cronograma/desplazamiento_enlazado.dart';
import 'package:flutter_application_1/widgets/cronograma/vistas/vista_ui.dart';

class VistaDiariaCronograma extends StatefulWidget {
  final DateTime dia;

  /// Tareas ya filtradas (se toman solo las de [dia]).
  final List<TareaModel> tareas;
  final List<OperarioVista> operarios;
  final DateTime hoy;
  final bool borrador;

  /// Horario del conjunto ese día (horas enteras) y descanso en minutos.
  final int horaInicio;
  final int horaFin;
  final int? descansoInicio;
  final int? descansoFin;

  /// Nombre del festivo (si lo es) para el aviso del día.
  final String? nombreFestivo;

  /// Acciones de la página sobre la tarea elegida.
  final List<AccionTareaVista> Function(TareaModel tarea) acciones;

  /// Abre el detalle completo (hoja con todo y sus acciones).
  final ValueChanged<TareaModel> onAbrirDetalle;

  /// Barra de la página que, en pantallas angostas, se desplaza con el
  /// contenido en vez de quedar fija arriba.
  final Widget? cabecera;

  /// Excluidas pendientes (preventivas que no cupieron) del período.
  final List<PreventivaExcluidaBorradorModel> excluidas;
  final ValueChanged<PreventivaExcluidaBorradorModel>? onTapExcluida;

  /// Lleva a Planeación para ubicar las excluidas arrastrándolas.
  final VoidCallback? onProgramarExcluidas;

  const VistaDiariaCronograma({
    super.key,
    required this.dia,
    required this.tareas,
    required this.operarios,
    required this.hoy,
    required this.horaInicio,
    required this.horaFin,
    required this.acciones,
    required this.onAbrirDetalle,
    this.borrador = false,
    this.descansoInicio,
    this.descansoFin,
    this.nombreFestivo,
    this.cabecera,
    this.excluidas = const [],
    this.onTapExcluida,
    this.onProgramarExcluidas,
  });

  @override
  State<VistaDiariaCronograma> createState() => _VistaDiariaCronogramaState();
}

class _VistaDiariaCronogramaState extends State<VistaDiariaCronograma> {
  /// Altura de una hora: 110 px, o más si hay tareas muy cortas (hasta
  /// 200 px) para que un bloque de 10 minutos se pueda leer.
  double _pxHora = 110;
  final DesplazamientoEnlazado _enlace = DesplazamientoEnlazado();
  final ScrollController _vertical = ScrollController();
  final ScrollController _panel = ScrollController();

  late IndiceOperarios _indice;
  late ResumenDiario _resumen;
  int? _seleccionadaId;

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  @override
  void didUpdateWidget(covariant VistaDiariaCronograma old) {
    super.didUpdateWidget(old);
    if (!identical(old.tareas, widget.tareas) ||
        !identical(old.operarios, widget.operarios) ||
        !mismoDia(old.dia, widget.dia) ||
        old.horaInicio != widget.horaInicio ||
        old.horaFin != widget.horaFin) {
      if (!mismoDia(old.dia, widget.dia)) _seleccionadaId = null;
      _calcular();
    }
  }

  void _calcular() {
    _indice = IndiceOperarios(widget.operarios);
    _resumen = resumirDia(
      dia: widget.dia,
      tareas: widget.tareas,
      operarios: _indice,
      horaInicioJornada: widget.horaInicio,
      horaFinJornada: widget.horaFin,
    );
    var minima = 60;
    for (final c in _resumen.columnas) {
      for (final b in c.bloques) {
        minima = math.min(minima, math.max(5, b.fin - b.inicio));
      }
    }
    _pxHora = (26 * 60 / minima).clamp(110.0, 200.0);
  }

  @override
  void dispose() {
    _enlace.dispose();
    _vertical.dispose();
    _panel.dispose();
    super.dispose();
  }

  TareaModel? get _seleccionada {
    final id = _seleccionadaId;
    if (id == null) return null;
    for (final c in _resumen.columnas) {
      for (final b in c.bloques) {
        if (b.tarea.id == id) return b.tarea;
      }
    }
    return null;
  }

  int get _minutosJornada {
    var m = (widget.horaFin - widget.horaInicio) * 60;
    final di = widget.descansoInicio;
    final df = widget.descansoFin;
    if (di != null && df != null && df > di) m -= df - di;
    return math.max(m, 60);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final conPanel = c.maxWidth >= 1150;
        final cuadricula = _buildCuadricula(conPanel: conPanel);
        if (!conPanel) return cuadricula;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cuadricula),
            SizedBox(
              width: 350,
              child: Scrollbar(
                controller: _panel,
                child: SingleChildScrollView(
                  controller: _panel,
                  padding: const EdgeInsets.fromLTRB(0, 4, 16, 24),
                  child: _buildPanel(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────── Cuadrícula ───────────────────────

  Widget _buildCuadricula({required bool conPanel}) {
    final r = _resumen;
    return LayoutBuilder(
      builder: (context, c) {
        final angosta = c.maxWidth < 700;
        final wHora = angosta ? 46.0 : 60.0;
        // 32 de márgenes y 2 de los bordes de la tabla.
        final disponible = c.maxWidth - 34 - wHora;
        final n = math.max(1, r.columnas.length);
        final minCol = angosta ? 150.0 : 175.0;
        final wCol = math.max(minCol, disponible / n);
        final desborda = wCol * n > disponible + 0.5;
        final alto = (r.hasta - r.desde) / 60 * _pxHora;

        final aviso = _avisoDelDia();
        return Scrollbar(
          controller: _vertical,
          child: CustomScrollView(
            controller: _vertical,
            slivers: [
              if (widget.cabecera != null)
                SliverToBoxAdapter(child: widget.cabecera!),
              if (aviso != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  sliver: SliverToBoxAdapter(child: aviso),
                ),
              if (widget.excluidas.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: CajaExcluidas(
                      titulo: 'Excluidas de este día',
                      excluidas: widget.excluidas,
                      operarios: _indice,
                      onTap: widget.onTapExcluida,
                      onProgramar: widget.onProgramarExcluidas,
                    ),
                  ),
                ),
              if (!conPanel)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  sliver: SliverToBoxAdapter(child: _buildResumenCompacto()),
                ),
              if (desborda)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: AvisoDesplazarLados(
                      texto:
                          'Hay más operarios hacia los lados: desliza o usa las flechas.',
                      onIzquierda: () => _enlace.desplazar(-wCol),
                      onDerecha: () => _enlace.desplazar(wCol),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: EncabezadoFijoDelegate(
                    alto: 58,
                    child: _buildEncabezado(wHora, wCol, desborda),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: ColoresVista.borde),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: wHora,
                          height: alto + 12,
                          child: _ColumnaHoras(
                            desde: r.desde,
                            hasta: r.hasta,
                            pxHora: _pxHora,
                          ),
                        ),
                        _envolver(
                          desborda,
                          1,
                          SizedBox(
                            width: wCol * n,
                            height: alto + 12,
                            child: _buildCuerpo(wCol, conPanel),
                          ),
                        ),
                      ],
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

  Widget? _avisoDelDia() {
    final d = widget.dia;
    final texto = widget.nombreFestivo != null
        ? 'Festivo (${widget.nombreFestivo}): solo trabajan las plazas que cubren festivos.'
        : d.weekday == DateTime.sunday
        ? 'Domingo: solo trabajan las plazas que cubren domingos.'
        : null;
    if (texto == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.nombreFestivo != null
            ? ColoresVista.festivo
            : ColoresVista.domingo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event,
            size: 18,
            color: widget.nombreFestivo != null
                ? ColoresVista.festivoTexto
                : ColoresVista.domingoTexto,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13, color: ColoresVista.texto),
            ),
          ),
        ],
      ),
    );
  }

  Widget _envolver(bool desborda, int clave, Widget hijo) {
    if (!desborda) return hijo;
    return Expanded(
      child: NotificationListener<ScrollNotification>(
        onNotification: _enlace.alDesplazar,
        child: SingleChildScrollView(
          controller: _enlace.controlador(clave),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: hijo,
        ),
      ),
    );
  }

  Widget _buildEncabezado(double wHora, double wCol, bool desborda) {
    final cabeceras = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final col in _resumen.columnas)
          Container(
            width: wCol,
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: ColoresVista.borde)),
            ),
            child: Row(
              children: [
                AvatarOperario(operario: col.operario, tamano: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        col.operario?.nombreCorto ?? 'Sin operario',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ColoresVista.texto,
                        ),
                      ),
                      Text(
                        col.tareas == 0
                            ? 'Sin turno hoy'
                            : '${col.tareas} ${col.tareas == 1 ? 'tarea' : 'tareas'} · ${formatoHorasCorto(col.minutos)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ColoresVista.textoSuave,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: ColoresVista.borde),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(width: wHora),
          _envolver(desborda, 0, cabeceras),
        ],
      ),
    );
  }

  Widget _buildCuerpo(double wCol, bool conPanel) {
    final r = _resumen;
    double y(int minuto) => (minuto - r.desde) / 60 * _pxHora + 6;
    final hijos = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: _LineasHoras(
            desde: r.desde,
            hasta: r.hasta,
            pxHora: _pxHora,
            columnas: r.columnas.length,
            wCol: wCol,
          ),
        ),
      ),
    ];

    final di = widget.descansoInicio;
    final df = widget.descansoFin;
    final hayDescanso =
        di != null && df != null && df > di && di >= r.desde && df <= r.hasta;

    for (var i = 0; i < r.columnas.length; i++) {
      final col = r.columnas[i];
      final x0 = i * wCol;
      if (hayDescanso && !col.bloques.any((b) => b.inicio < df && b.fin > di)) {
        hijos.add(
          Positioned(
            left: x0 + 1,
            width: wCol - 1,
            top: y(di),
            height: (df - di) / 60 * _pxHora,
            child: Container(
              color: const Color(0xFFF3F4F3),
              alignment: Alignment.center,
              child: Text(
                'Sin tareas ${hhmmMin(di)}–${hhmmMin(df)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ColoresVista.textoSuave,
                ),
              ),
            ),
          ),
        );
      }
      if (col.bloques.isEmpty) {
        hijos.add(
          Positioned(
            left: x0 + 12,
            width: wCol - 24,
            top: y(r.desde + 60),
            height: 84,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD5DAD7)),
              ),
              child: const Text(
                'Sin tareas este día.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: ColoresVista.textoSuave),
              ),
            ),
          ),
        );
        continue;
      }
      for (final b in col.bloques) {
        final anchoCarril = (wCol - 12) / b.carriles;
        final top = y(b.inicio);
        final alto = math.max(22.0, (b.fin - b.inicio) / 60 * _pxHora - 3);
        hijos.add(
          Positioned(
            left: x0 + 6 + b.carril * anchoCarril,
            width: anchoCarril - (b.carriles > 1 ? 3 : 0),
            top: top + 1,
            height: alto,
            child: _BloqueTarea(
              bloque: b,
              operario: col.operario,
              seleccionado: _seleccionadaId == b.tarea.id,
              vencida: !widget.borrador && estaVencida(b.tarea, widget.hoy),
              estado: etiquetaEstadoTarea(b.tarea, borrador: widget.borrador),
              onTap: () {
                if (conPanel) {
                  setState(() => _seleccionadaId = b.tarea.id);
                } else {
                  widget.onAbrirDetalle(b.tarea);
                }
              },
            ),
          ),
        );
      }
    }

    // Línea de "ahora" si se está viendo hoy.
    if (mismoDia(widget.dia, widget.hoy)) {
      final ahora = minutoDelDia(widget.hoy);
      if (ahora >= r.desde && ahora <= r.hasta) {
        hijos.add(
          Positioned(
            left: 0,
            right: 0,
            top: y(ahora),
            height: 2,
            child: const ColoredBox(color: Color(0xFFDC2626)),
          ),
        );
      }
    }

    return Stack(clipBehavior: Clip.hardEdge, children: hijos);
  }

  // ─────────────────────── Panel lateral ───────────────────────

  Widget _buildPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetalle(),
        const SizedBox(height: 14),
        _buildAvance(),
        const SizedBox(height: 14),
        _buildOcupacion(),
      ],
    );
  }

  Widget _tituloCaja(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      texto,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ColoresVista.texto,
      ),
    ),
  );

  Widget _buildDetalle() {
    final t = _seleccionada;
    if (t == null) {
      return CajaVista(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tituloCaja('Detalle de la tarea'),
            const Row(
              children: [
                Icon(Icons.touch_app_outlined, color: ColoresVista.textoSuave),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toca una tarea del día para ver aquí qué hay que hacer, '
                    'a qué hora y quién la hace.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: ColoresVista.textoSuave,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final ops = _indice.de(t);
    final inicio = t.fechaInicio.toLocal();
    final fin = t.fechaFin.toLocal();
    final tono = tonoDeTarea(t);
    final colorEstado = widget.borrador
        ? (const Color(0xFFFFF3D6), const Color(0xFF7A5300))
        : switch (tono) {
            TonoTarea.ejecutada => (
              ColoresVista.ejecutada.fondo,
              ColoresVista.ejecutada.texto,
            ),
            TonoTarea.noEjecutada => (
              ColoresVista.noEjecutada.fondo,
              ColoresVista.noEjecutada.texto,
            ),
            TonoTarea.abierta =>
              estaVencida(t, widget.hoy)
                  ? (const Color(0xFFFDEBD8), ColoresVista.alerta)
                  : (const Color(0xFFDCE8FB), const Color(0xFF1E3A8A)),
          };
    final elemento = elementoCorto(t.elementoNombre);
    final acciones = widget.acciones(t);
    return CajaVista(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _tituloCaja('Detalle de la tarea')),
              IconButton(
                tooltip: 'Cerrar detalle',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _seleccionadaId = null),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          if (ops.isEmpty)
            const Text(
              'Sin operario asignado',
              style: TextStyle(fontSize: 14, color: ColoresVista.textoSuave),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final o in ops)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AvatarOperario(operario: o, tamano: 28),
                      const SizedBox(width: 8),
                      Text(
                        o.nombreCorto,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ColoresVista.texto,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  ubicacionDe(t),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: ColoresVista.texto,
                  ),
                ),
              ),
              if (esEspecial(t)) ...[
                const SizedBox(width: 8),
                MarcaEspecial(texto: etiquetaCorrectiva()),
              ],
            ],
          ),
          if (elemento.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              elemento,
              style: const TextStyle(
                fontSize: 15,
                color: ColoresVista.textoSuave,
              ),
            ),
          ],
          if (t.descripcion.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              t.descripcion.trim(),
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: ColoresVista.texto,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PastillaVista(
                texto:
                    '${hhmm(inicio)} – ${hhmm(fin)} (${formatoHorasCorto(minutosDe(t))})',
                icono: Icons.schedule,
              ),
              PastillaVista(
                texto: estaVencida(t, widget.hoy) && !widget.borrador
                    ? 'Sin cerrar'
                    : etiquetaEstadoTarea(t, borrador: widget.borrador),
                fondo: colorEstado.$1,
                colorTexto: colorEstado.$2,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in acciones)
                a.principal
                    ? FilledButton.icon(
                        onPressed: a.onPressed,
                        icon: Icon(a.icono, size: 18),
                        label: Text(a.texto),
                        style: FilledButton.styleFrom(
                          backgroundColor: a.peligro
                              ? Colors.red.shade700
                              : AppTheme.primary,
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: a.onPressed,
                        icon: Icon(a.icono, size: 18),
                        label: Text(a.texto),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: a.peligro
                              ? Colors.red.shade700
                              : ColoresVista.texto,
                          side: BorderSide(
                            color: a.peligro
                                ? Colors.red.shade200
                                : ColoresVista.borde,
                          ),
                        ),
                      ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => widget.onAbrirDetalle(t),
            icon: const Icon(Icons.open_in_full, size: 16),
            label: const Text('Ver todo el detalle'),
          ),
        ],
      ),
    );
  }

  Widget _buildAvance() {
    final r = _resumen;
    return CajaVista(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloCaja(widget.borrador ? 'Resumen del día' : 'Avance del día'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PastillaVista(
                texto: '${r.tareas} ${r.tareas == 1 ? 'tarea' : 'tareas'}',
              ),
              if (!widget.borrador)
                PastillaVista(
                  texto:
                      '${r.ejecutadas} ${r.ejecutadas == 1 ? 'ejecutada' : 'ejecutadas'}',
                  fondo: ColoresVista.ejecutada.fondo,
                  colorTexto: ColoresVista.ejecutada.texto,
                ),
              if (!widget.borrador && r.noEjecutadas > 0)
                PastillaVista(
                  texto: '${r.noEjecutadas} no ejecutadas',
                  fondo: ColoresVista.noEjecutada.fondo,
                  colorTexto: ColoresVista.noEjecutada.texto,
                ),
              PastillaVista(
                texto:
                    '${r.ubicaciones} ${r.ubicaciones == 1 ? 'ubicación' : 'ubicaciones'}',
              ),
            ],
          ),
          if (!widget.borrador) ...[
            const SizedBox(height: 14),
            BarraCarga(valor: r.avance, alto: 8),
            const SizedBox(height: 10),
          ] else
            const SizedBox(height: 12),
          Text(
            widget.borrador
                ? 'Es un borrador: cuando lo publiques, aquí se verá el avance '
                      'a medida que los operarios cierren sus tareas.'
                : 'Cuando el operario cierra tareas en la app, esta barra avanza '
                      'y los bloques cambian a verde (ejecutada) o rojo (no ejecutada).',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: ColoresVista.textoSuave,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcupacion() {
    final cols = _resumen.columnas.where((c) => c.operario != null).toList();
    final maxMin = cols.fold<int>(0, (m, c) => math.max(m, c.minutos));
    final base = math.max(_minutosJornada, maxMin);
    return CajaVista(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloCaja('Ocupación por operario'),
          for (final c in cols) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.operario!.nombreCorto,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: ColoresVista.texto,
                    ),
                  ),
                ),
                Text(
                  c.minutos == 0 ? '—' : formatoHorasCorto(c.minutos),
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: ColoresVista.texto,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            BarraCarga(valor: base == 0 ? 0 : c.minutos / base),
            const SizedBox(height: 12),
          ],
          Text(
            'La barra llena es la jornada del conjunto '
            '(${formatoHorasCorto(_minutosJornada)}).',
            style: const TextStyle(
              fontSize: 12,
              color: ColoresVista.textoSuave,
            ),
          ),
        ],
      ),
    );
  }

  /// En pantallas angostas (sin panel lateral), el avance va arriba.
  Widget _buildResumenCompacto() {
    final r = _resumen;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PastillaVista(
          texto: '${r.tareas} ${r.tareas == 1 ? 'tarea' : 'tareas'}',
        ),
        if (!widget.borrador)
          PastillaVista(
            texto: '${r.ejecutadas} ejecutadas',
            fondo: ColoresVista.ejecutada.fondo,
            colorTexto: ColoresVista.ejecutada.texto,
          ),
        PastillaVista(
          texto:
              '${r.ubicaciones} ${r.ubicaciones == 1 ? 'ubicación' : 'ubicaciones'}',
        ),
        const Text(
          'Toca una tarea para ver su detalle.',
          style: TextStyle(fontSize: 12.5, color: ColoresVista.textoSuave),
        ),
      ],
    );
  }
}

class _ColumnaHoras extends StatelessWidget {
  final int desde;
  final int hasta;
  final double pxHora;

  const _ColumnaHoras({
    required this.desde,
    required this.hasta,
    required this.pxHora,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var m = desde; m <= hasta; m += 60)
          Positioned(
            top: (m - desde) / 60 * pxHora + 6 - 8,
            right: 8,
            child: Text(
              '${m ~/ 60}:00',
              style: const TextStyle(
                fontSize: 12.5,
                color: ColoresVista.textoSuave,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}

class _LineasHoras extends CustomPainter {
  final int desde;
  final int hasta;
  final double pxHora;
  final int columnas;
  final double wCol;

  const _LineasHoras({
    required this.desde,
    required this.hasta,
    required this.pxHora,
    required this.columnas,
    required this.wCol,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hora = Paint()
      ..color = ColoresVista.bordeSuave
      ..strokeWidth = 1;
    final media = Paint()
      ..color = const Color(0xFFF5F6F5)
      ..strokeWidth = 1;
    for (var m = desde; m <= hasta; m += 30) {
      final y = (m - desde) / 60 * pxHora + 6;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        m % 60 == 0 ? hora : media,
      );
    }
    final col = Paint()
      ..color = ColoresVista.borde
      ..strokeWidth = 1;
    for (var i = 0; i < columnas; i++) {
      final x = i * wCol + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), col);
    }
  }

  @override
  bool shouldRepaint(_LineasHoras o) =>
      o.desde != desde ||
      o.hasta != hasta ||
      o.columnas != columnas ||
      o.wCol != wCol;
}

class _BloqueTarea extends StatelessWidget {
  final BloqueDiario bloque;
  final OperarioVista? operario;
  final bool seleccionado;
  final bool vencida;
  final String estado;
  final VoidCallback onTap;

  const _BloqueTarea({
    required this.bloque,
    required this.operario,
    required this.seleccionado,
    required this.vencida,
    required this.estado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = bloque.tarea;
    final c = coloresDeTarea(t, operario);
    final especial = esEspecial(t);
    final inicio = t.fechaInicio.toLocal();
    final elemento = elementoCorto(t.elementoNombre);
    final linea1 = '${hhmm(inicio)} · ${ubicacionDe(t)}';
    final linea2 = elemento.isEmpty ? t.descripcion.trim() : elemento;
    return Tooltip(
      message:
          '${hhmm(inicio)}–${hhmm(t.fechaFin.toLocal())} · ${lugarDe(t)}\n'
          '${t.descripcion.trim()}\n$estado',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: c.fondo,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(
            color: seleccionado ? AppTheme.primaryDark : c.borde,
            width: seleccionado ? 2.2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (especial)
                const SizedBox(
                  width: 4,
                  child: ColoredBox(color: Color(0xFF6D28D9)),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, cc) {
                    // Bloques cortos (10-15 min): una sola línea más chica
                    // y sin margen, recortada si aun así no cabe.
                    final diminuto = cc.maxHeight < 24;
                    final unaLinea = cc.maxHeight < 40;
                    final padV = diminuto ? 0.0 : 3.0;
                    final letra = diminuto ? 11.0 : 12.5;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(8, padV, 6, padV),
                      child: ClipRect(
                        child: Stack(
                          children: [
                            OverflowBox(
                              alignment: unaLinea
                                  ? Alignment.centerLeft
                                  : Alignment.topLeft,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: vencida ? 10 : 0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      unaLinea ? '$linea1 · $linea2' : linea1,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: letra,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                        color: c.texto,
                                      ),
                                    ),
                                    if (!unaLinea)
                                      Text(
                                        linea2,
                                        maxLines: cc.maxHeight > 60 ? 2 : 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.25,
                                          color: ColoresVista.texto,
                                        ),
                                      ),
                                    if (!unaLinea &&
                                        especial &&
                                        cc.maxHeight > 70) ...[
                                      const SizedBox(height: 3),
                                      MarcaEspecial(
                                        texto: etiquetaCorrectiva(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (vencida)
                              Positioned(
                                right: 0,
                                top: diminuto ? (cc.maxHeight - 8) / 2 : 3,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: ColoresVista.vencida,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
