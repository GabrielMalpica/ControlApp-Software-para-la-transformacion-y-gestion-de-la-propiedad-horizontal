// Vista Mensual del cronograma (borrador y definitivo): indicadores del mes,
// carga por operario y la tabla de actividades × días con las iniciales del
// responsable en su color.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/tarea_labels.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/vistas_cronograma.dart';
import 'package:flutter_application_1/widgets/cronograma/desplazamiento_enlazado.dart';
import 'package:flutter_application_1/widgets/cronograma/vistas/vista_ui.dart';

class VistaMensualCronograma extends StatefulWidget {
  final int anio;
  final int mes;

  /// Tareas del mes ya filtradas.
  final List<TareaModel> tareas;

  /// Operarios del mes (definen el color de cada uno).
  final List<OperarioVista> operarios;
  final CalendarioVista calendario;
  final DateTime hoy;
  final AgrupacionMensual agrupacion;
  final bool borrador;

  /// Excluidas que se muestran como filas de seguimiento (vacío = ocultas).
  final List<PreventivaExcluidaBorradorModel> excluidasVisibles;

  /// Excluidas pendientes del mes (para el indicador del borrador).
  final int excluidasPendientes;

  final ValueChanged<TareaModel> onTapTarea;
  final ValueChanged<DateTime> onTapDia;
  final ValueChanged<PreventivaExcluidaBorradorModel>? onTapExcluida;
  final VoidCallback? onVerExcluidas;

  /// Barra de la página que, en pantallas angostas, se desplaza con el
  /// contenido en vez de quedar fija arriba.
  final Widget? cabecera;

  const VistaMensualCronograma({
    super.key,
    required this.anio,
    required this.mes,
    required this.tareas,
    required this.operarios,
    required this.calendario,
    required this.hoy,
    required this.agrupacion,
    required this.onTapTarea,
    required this.onTapDia,
    this.borrador = false,
    this.excluidasVisibles = const [],
    this.excluidasPendientes = 0,
    this.onTapExcluida,
    this.onVerExcluidas,
    this.cabecera,
  });

  @override
  State<VistaMensualCronograma> createState() => _VistaMensualCronogramaState();
}

class _VistaMensualCronogramaState extends State<VistaMensualCronograma> {
  final DesplazamientoEnlazado _enlace = DesplazamientoEnlazado();
  final ScrollController _vertical = ScrollController();

  /// Operario resaltado desde "Carga por operario" (null = todos).
  String? _resaltado;

  MatrizMensual? _matriz;
  ResumenMensual? _resumen;
  late IndiceOperarios _indice;

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  @override
  void didUpdateWidget(covariant VistaMensualCronograma old) {
    super.didUpdateWidget(old);
    if (!identical(old.tareas, widget.tareas) ||
        !identical(old.operarios, widget.operarios) ||
        !identical(old.excluidasVisibles, widget.excluidasVisibles) ||
        old.agrupacion != widget.agrupacion ||
        old.anio != widget.anio ||
        old.mes != widget.mes) {
      _calcular();
    }
    if (_resaltado != null &&
        !widget.operarios.any((o) => o.id == _resaltado)) {
      _resaltado = null;
    }
  }

  void _calcular() {
    _indice = IndiceOperarios(widget.operarios);
    _matriz = construirMatrizMensual(
      tareas: widget.tareas,
      operarios: _indice,
      anio: widget.anio,
      mes: widget.mes,
      agrupacion: widget.agrupacion,
      excluidas: widget.excluidasVisibles,
    );
    _resumen = resumirMes(
      tareas: widget.tareas,
      operarios: _indice,
      anio: widget.anio,
      mes: widget.mes,
      calendario: widget.calendario,
      hoy: widget.hoy,
    );
  }

  @override
  void dispose() {
    _enlace.dispose();
    _vertical.dispose();
    super.dispose();
  }

  int get _diasMes => DateTime(widget.anio, widget.mes + 1, 0).day;

  DateTime _fecha(int dia) => DateTime(widget.anio, widget.mes, dia);

  bool _esHoy(int dia) => mismoDia(_fecha(dia), widget.hoy);

  Color? _fondoColumna(int dia) {
    final f = _fecha(dia);
    if (_esHoy(dia)) return const Color(0xFFEFF7F2);
    if (widget.calendario.esFestivo(f)) return ColoresVista.festivo;
    if (widget.calendario.esDomingo(f)) return ColoresVista.domingo;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final matriz = _matriz!;
    final resumen = _resumen!;
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth;
        final wIzq = ancho >= 1100
            ? 270.0
            : ancho >= 700
            ? 220.0
            : 150.0;
        const wTotal = 52.0;
        const minDia = 30.0;
        // 32 de márgenes y 2 de los bordes de la tabla.
        final disponible = ancho - 34 - wIzq - wTotal;
        final wDia = math.max(minDia, disponible / _diasMes);
        final anchoDias = wDia * _diasMes + wTotal;
        final desborda = anchoDias > ancho - 34 - wIzq + 0.5;
        final geo = _Geometria(
          wIzq: wIzq,
          wDia: wDia,
          wTotal: wTotal,
          desborda: desborda,
        );

        final filas = <_ItemTabla>[];
        for (final g in matriz.grupos) {
          filas.add(_ItemTabla.grupo(g));
          for (final f in g.filas) {
            filas.add(_ItemTabla.fila(g, f));
          }
        }

        return Scrollbar(
          controller: _vertical,
          child: CustomScrollView(
            controller: _vertical,
            slivers: [
              if (widget.cabecera != null)
                SliverToBoxAdapter(child: widget.cabecera!),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                sliver: SliverToBoxAdapter(child: _buildIndicadores(resumen)),
              ),
              if (resumen.cargas.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: _buildCargaOperarios(resumen, ancho),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                sliver: SliverToBoxAdapter(child: _buildLeyenda()),
              ),
              if (desborda)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: AvisoDesplazarLados(
                      texto:
                          'La tabla sigue hacia los lados: desliza los días o usa las flechas.',
                      onIzquierda: () => _enlace.desplazar(-wDia * 7),
                      onDerecha: () => _enlace.desplazar(wDia * 7),
                    ),
                  ),
                ),
              if (matriz.grupos.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(child: _buildVacio()),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverPersistentHeader(
                    pinned: true,
                    delegate: EncabezadoFijoDelegate(
                      alto: 46,
                      child: _buildEncabezado(geo),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: filas.length,
                    itemBuilder: (context, i) {
                      final item = filas[i];
                      return item.fila == null
                          ? _buildFilaGrupo(item.grupo, geo)
                          : _buildFilaActividad(
                              item.grupo,
                              item.fila!,
                              geo,
                              i + 1,
                            );
                    },
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: _buildTotales(matriz, geo, filas.length + 1),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────── Resumen ───────────────────────

  Widget _buildIndicadores(ResumenMensual r) {
    final mes = mesCorto(widget.mes);
    final indicadores = <Widget>[
      IndicadorVista(
        etiqueta: widget.borrador ? 'Tareas del borrador' : 'Tareas del mes',
        valor: '${r.tareas}',
        detalle:
            '${r.actividades} ${r.actividades == 1 ? 'actividad' : 'actividades'} en '
            '${r.ubicaciones} ${r.ubicaciones == 1 ? 'ubicación' : 'ubicaciones'}',
      ),
      if (widget.borrador)
        IndicadorVista(
          etiqueta: 'Excluidas (no cupieron)',
          valor: '${widget.excluidasPendientes}',
          colorValor: widget.excluidasPendientes > 0
              ? ColoresVista.alerta
              : null,
          detalle: widget.excluidasPendientes > 0
              ? 'Tócalas para ubicarlas o descartarlas'
              : 'Todas las preventivas cupieron',
          onTap: widget.excluidasPendientes > 0 ? widget.onVerExcluidas : null,
        )
      else
        IndicadorVista(
          etiqueta: 'Días ya pasados, aún sin cerrar',
          valor: '${r.vencidas}',
          colorValor: r.vencidas > 0 ? ColoresVista.alerta : AppTheme.green,
          detalle: r.ultimoDiaPasado == 0
              ? 'El mes todavía no empieza'
              : r.vencidas == 0
              ? 'Todo lo anterior a hoy está cerrado'
              : r.ultimoDiaPasado == 1
              ? 'Del 1 de $mes, sin cerrar'
              : 'Del 1 al ${r.ultimoDiaPasado} de $mes. sin cerrar',
        ),
      IndicadorVista(
        etiqueta: 'Domingos y festivos',
        valor: decimalCorto(r.promedioDomingoFestivo),
        sufijo: 'tareas/día',
        detalle: r.operariosDomingoFestivo.isEmpty
            ? 'Sin tareas esos días'
            : r.operariosDomingoFestivo.length == 1
            ? 'Solo turno de ${r.operariosDomingoFestivo.first.nombreCorto}'
            : 'Turnos de ${unirConY(r.operariosDomingoFestivo.take(3).map((o) => o.nombreCorto.split(' ').first).toList())}'
                  '${r.operariosDomingoFestivo.length > 3 ? ' y otros' : ''}',
      ),
      IndicadorVista(
        etiqueta: 'Días hábiles',
        valor: r.minHabil == r.maxHabil
            ? '${r.maxHabil}'
            : '${r.minHabil}–${r.maxHabil}',
        sufijo: 'tareas/día',
        detalle: r.festivos.isEmpty
            ? 'Sin festivos este mes'
            : 'Festivos: ${unirConY(r.festivos.map((f) => '${diaCorto(f)} ${f.day}').toList())}',
      ),
    ];
    return FilaIndicadores(indicadores: indicadores);
  }

  Widget _buildCargaOperarios(ResumenMensual r, double ancho) {
    final maxTareas = r.cargas.fold<int>(0, (m, c) => math.max(m, c.tareas));
    final columnas = ancho >= 1100
        ? 4
        : ancho >= 700
        ? 2
        : 1;
    return CajaVista(
      child: LayoutBuilder(
        builder: (context, c) {
          const sep = 20.0;
          final w = (c.maxWidth - sep * (columnas - 1)) / columnas;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  const Text(
                    'Carga por operario',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ColoresVista.texto,
                    ),
                  ),
                  Text(
                    _resaltado == null
                        ? 'Toca un nombre para resaltar sus tareas en la tabla'
                        : 'Toca otra vez el nombre para ver a todos',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: ColoresVista.textoSuave,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: sep,
                runSpacing: 14,
                children: [
                  for (final carga in r.cargas)
                    SizedBox(
                      width: w,
                      child: _CargaOperario(
                        carga: carga,
                        fraccion: maxTareas == 0 ? 0 : carga.tareas / maxTareas,
                        seleccionado: _resaltado == carga.operario.id,
                        atenuado:
                            _resaltado != null &&
                            _resaltado != carga.operario.id,
                        onTap: () => setState(() {
                          _resaltado = _resaltado == carga.operario.id
                              ? null
                              : carga.operario.id;
                        }),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLeyenda() {
    final ejemplo = widget.operarios.isEmpty ? null : widget.operarios.first;
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ItemLeyenda(
          muestra: _ChipIniciales(
            texto: widget.agrupacion == AgrupacionMensual.operario
                ? '07'
                : ejemplo?.iniciales ?? 'AB',
            colores: coloresDeOperario(ejemplo),
          ),
          texto: widget.agrupacion == AgrupacionMensual.operario
              ? 'Hora de inicio, en el color del responsable'
              : widget.borrador
              ? 'Programada (iniciales del responsable)'
              : 'Asignada (iniciales del responsable)',
        ),
        if (!widget.borrador)
          const ItemLeyenda(
            muestra: _PuntoVencida(),
            texto: 'Fecha pasada sin cerrar',
          ),
        if (!widget.borrador)
          const ItemLeyenda(
            muestra: _ChipIniciales(
              texto: '✓',
              colores: ColoresVista.ejecutada,
            ),
            texto: 'Ejecutada',
          ),
        if (!widget.borrador)
          const ItemLeyenda(
            muestra: _ChipIniciales(
              texto: '✕',
              colores: ColoresVista.noEjecutada,
            ),
            texto: 'No ejecutada',
          ),
        const ItemLeyenda(
          muestra: _ChipIniciales(
            texto: 'EX',
            colores: ColoresVista.excluida,
            rayado: true,
          ),
          texto: 'Excluida',
        ),
        const ItemLeyenda(
          muestra: MuestraColor(
            fondo: ColoresVista.domingo,
            borde: Color(0xFFEADFB8),
          ),
          texto: 'Domingo',
        ),
        const ItemLeyenda(
          muestra: MuestraColor(
            fondo: ColoresVista.festivo,
            borde: Color(0xFFF2C4C4),
          ),
          texto: 'Festivo',
        ),
        const ItemLeyenda(
          muestra: MuestraColor(fondo: AppTheme.primary),
          texto: 'Hoy',
        ),
        const ItemLeyenda(
          muestra: Icon(
            Icons.touch_app_outlined,
            size: 16,
            color: ColoresVista.textoSuave,
          ),
          texto: 'Toca un día para abrir su vista diaria',
        ),
      ],
    );
  }

  Widget _buildVacio() {
    return CajaVista(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        children: [
          const Icon(
            Icons.event_busy,
            size: 40,
            color: ColoresVista.textoSuave,
          ),
          const SizedBox(height: 10),
          Text(
            widget.borrador
                ? 'El borrador de este mes no tiene tareas con los filtros elegidos.'
                : 'No hay tareas publicadas en este mes con los filtros elegidos.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: ColoresVista.texto),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Tabla ───────────────────────

  /// Envuelve la parte de los días de una fila: con desplazamiento lateral
  /// enlazado si no cabe, o fija si cabe.
  Widget _zonaDias(_Geometria geo, int clave, Widget dias) {
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

  Widget _buildEncabezado(_Geometria geo) {
    final dias = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var d = 1; d <= _diasMes; d++) _buildCabeceraDia(d, geo),
        SizedBox(
          width: geo.wTotal,
          child: const Center(
            child: Text(
              'Días',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ColoresVista.textoSuave,
              ),
            ),
          ),
        ),
      ],
    );
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9F8),
        border: Border(
          top: BorderSide(color: ColoresVista.borde),
          left: BorderSide(color: ColoresVista.borde),
          right: BorderSide(color: ColoresVista.borde),
          bottom: BorderSide(color: ColoresVista.borde),
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: geo.wIzq,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                widget.agrupacion == AgrupacionMensual.ubicacion
                    ? 'Ubicación / actividad'
                    : 'Operario / actividad',
                style: const TextStyle(
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

  Widget _buildCabeceraDia(int dia, _Geometria geo) {
    final f = _fecha(dia);
    final hoy = _esHoy(dia);
    final festivo = widget.calendario.esFestivo(f);
    final domingo = widget.calendario.esDomingo(f);
    final colorTexto = hoy
        ? Colors.white
        : festivo
        ? ColoresVista.festivoTexto
        : domingo
        ? ColoresVista.domingoTexto
        : ColoresVista.texto;
    final nombreFestivo = widget.calendario.nombreFestivo(f);
    return Tooltip(
      message:
          '${diaLargo(f)} $dia${nombreFestivo != null ? ' · $nombreFestivo' : ''}'
          ' · ver el día',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () => widget.onTapDia(f),
        child: Container(
          width: geo.wDia,
          height: 44,
          color: hoy ? null : _fondoColumna(dia),
          padding: hoy
              ? const EdgeInsets.symmetric(horizontal: 1, vertical: 3)
              : null,
          child: Container(
            decoration: hoy
                ? BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  letraDia(f),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colorTexto.withValues(alpha: hoy ? 0.9 : 0.75),
                  ),
                ),
                Text(
                  '$dia',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colorTexto,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bordesLaterales({required Widget child, Color? fondo}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fondo,
        border: const Border(
          left: BorderSide(color: ColoresVista.borde),
          right: BorderSide(color: ColoresVista.borde),
        ),
      ),
      child: child,
    );
  }

  Widget _buildFilaGrupo(GrupoMensual g, _Geometria geo) {
    final detalle = g.esExcluidas
        ? '${g.filas.length} ${g.filas.length == 1 ? 'preventiva' : 'preventivas'} sin lugar en el horario'
        : '${g.filas.length} ${g.filas.length == 1 ? 'actividad' : 'actividades'} · '
              'actividad en ${g.diasConActividad} de $_diasMes días';
    return _bordesLaterales(
      fondo: g.esExcluidas ? const Color(0xFFF1F2F4) : ColoresVista.grupo,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: ColoresVista.borde)),
        ),
        child: Row(
          children: [
            if (g.operario != null) ...[
              AvatarOperario(operario: g.operario, tamano: 22),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: g.titulo,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: g.esExcluidas
                            ? const Color(0xFF374151)
                            : ColoresVista.grupoTexto,
                      ),
                    ),
                    TextSpan(
                      text: '   $detalle',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ColoresVista.textoSuave,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilaActividad(
    GrupoMensual g,
    FilaMensual f,
    _Geometria geo,
    int clave,
  ) {
    const alto = 42.0;
    final etiqueta = SizedBox(
      width: geo.wIzq,
      height: alto,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    f.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ColoresVista.texto,
                    ),
                  ),
                ),
                if (f.especial) ...[
                  const SizedBox(width: 6),
                  MarcaEspecial(texto: etiquetaCorrectiva()),
                ],
              ],
            ),
            if (f.subtitulo.isNotEmpty)
              Text(
                f.subtitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: ColoresVista.textoSuave,
                ),
              ),
          ],
        ),
      ),
    );

    final dias = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var d = 1; d <= _diasMes; d++)
          Container(
            width: geo.wDia,
            height: alto,
            decoration: BoxDecoration(
              color: _fondoColumna(d),
              border: _esHoy(d)
                  ? const Border(
                      left: BorderSide(color: AppTheme.primary, width: 1.5),
                      right: BorderSide(color: AppTheme.primary, width: 1.5),
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: _buildCelda(g, f, d),
          ),
        SizedBox(
          width: geo.wTotal,
          height: alto,
          child: Center(
            child: Text(
              f.esExcluida ? '—' : '${f.dias}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ColoresVista.texto,
              ),
            ),
          ),
        ),
      ],
    );

    return _bordesLaterales(
      fondo: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: ColoresVista.bordeSuave)),
        ),
        child: Row(children: [etiqueta, _zonaDias(geo, clave, dias)]),
      ),
    );
  }

  Widget? _buildCelda(GrupoMensual g, FilaMensual f, int dia) {
    final ex = f.excluida;
    if (ex != null) {
      if (ex.fechaObjetivo.day != dia) return null;
      final ops = _indice.deExcluida(ex);
      final texto = ops.isEmpty ? 'EX' : ops.first.iniciales;
      final atenuado =
          _resaltado != null && !ops.any((o) => o.id == _resaltado);
      return Opacity(
        opacity: atenuado ? 0.2 : 1,
        child: Tooltip(
          message:
              'Excluida: ${ex.descripcion.trim()}\n'
              '${ops.isEmpty ? 'Sin operario' : ops.map((o) => o.nombreCorto).join(', ')}'
              ' · ${formatoHorasCorto(ex.duracionMinutos)}',
          child: InkWell(
            onTap: widget.onTapExcluida == null
                ? null
                : () => widget.onTapExcluida!(ex),
            borderRadius: BorderRadius.circular(5),
            child: _ChipIniciales(
              texto: texto,
              colores: ColoresVista.excluida,
              rayado: true,
            ),
          ),
        ),
      );
    }

    final tareas = f.porDia[dia];
    if (tareas == null || tareas.isEmpty) return null;
    final principal = tareas.first;
    final ops = <OperarioVista>{};
    for (final t in tareas) {
      ops.addAll(_indice.de(t));
    }
    final opPrincipal =
        g.operario ??
        (_indice.de(principal).isEmpty ? null : _indice.de(principal).first);
    final colores = coloresDeTarea(principal, opPrincipal);
    final tono = tonoDeTarea(principal);

    String texto;
    if (g.operario != null) {
      texto = principal.fechaInicio.toLocal().hour.toString().padLeft(2, '0');
    } else {
      texto = opPrincipal?.iniciales ?? '—';
    }

    final vencida =
        !widget.borrador && tareas.any((t) => estaVencida(t, widget.hoy));
    final atenuado = _resaltado != null && !ops.any((o) => o.id == _resaltado);
    final extras = g.operario == null ? ops.length - 1 : tareas.length - 1;

    final lineas = <String>[
      for (final t in tareas)
        '${hhmm(t.fechaInicio.toLocal())}–${hhmm(t.fechaFin.toLocal())} · '
            '${_indice.de(t).map((o) => o.nombreCorto).join(', ').ifEmpty('Sin operario')}'
            ' · ${etiquetaEstadoTarea(t, borrador: widget.borrador)}',
    ];

    return Opacity(
      opacity: atenuado ? 0.18 : 1,
      child: Tooltip(
        message: '${f.titulo} · ${f.subtitulo}\n${lineas.join('\n')}',
        waitDuration: const Duration(milliseconds: 300),
        child: InkWell(
          onTap: () => widget.onTapTarea(principal),
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _ChipIniciales(
                texto: tono == TonoTarea.abierta || g.operario != null
                    ? texto
                    : (tono == TonoTarea.ejecutada ? '✓' : '✕'),
                colores: colores,
              ),
              if (vencida)
                const Positioned(right: -3, top: -3, child: _PuntoVencida()),
              if (extras > 0)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: ColoresVista.texto,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+$extras',
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotales(MatrizMensual m, _Geometria geo, int clave) {
    final dias = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var d = 1; d <= _diasMes; d++)
          Container(
            width: geo.wDia,
            height: 40,
            color: _fondoColumna(d),
            alignment: Alignment.center,
            child: Text(
              '${m.totalPorDia[d] ?? 0}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: widget.calendario.esHabil(_fecha(d))
                    ? ColoresVista.texto
                    : ColoresVista.alerta,
              ),
            ),
          ),
        SizedBox(
          width: geo.wTotal,
          child: Center(
            child: Text(
              '${m.total}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: ColoresVista.texto,
              ),
            ),
          ),
        ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        border: Border.all(color: ColoresVista.borde),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: geo.wIzq,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Total tareas del día',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ColoresVista.texto,
                ),
              ),
            ),
          ),
          _zonaDias(geo, clave, dias),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}

class _Geometria {
  final double wIzq;
  final double wDia;
  final double wTotal;
  final bool desborda;

  const _Geometria({
    required this.wIzq,
    required this.wDia,
    required this.wTotal,
    required this.desborda,
  });
}

class _ItemTabla {
  final GrupoMensual grupo;
  final FilaMensual? fila;

  const _ItemTabla.grupo(this.grupo) : fila = null;
  const _ItemTabla.fila(this.grupo, FilaMensual this.fila);
}

class _ChipIniciales extends StatelessWidget {
  final String texto;
  final ColoresOperario colores;
  final bool rayado;

  const _ChipIniciales({
    required this.texto,
    required this.colores,
    this.rayado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 20,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colores.fondo,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colores.borde),
      ),
      child: CustomPaint(
        painter: rayado ? const RayadoPainter() : null,
        child: Center(
          child: Text(
            texto,
            maxLines: 1,
            style: TextStyle(
              fontSize: texto.length > 2 ? 8.5 : 9.5,
              fontWeight: FontWeight.w800,
              color: colores.texto,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PuntoVencida extends StatelessWidget {
  const _PuntoVencida();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: ColoresVista.vencida,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.2),
      ),
    );
  }
}

class _CargaOperario extends StatelessWidget {
  final CargaOperarioMes carga;
  final double fraccion;
  final bool seleccionado;
  final bool atenuado;
  final VoidCallback onTap;

  const _CargaOperario({
    required this.carga,
    required this.fraccion,
    required this.seleccionado,
    required this.atenuado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = coloresDeOperario(carga.operario);
    return Opacity(
      opacity: atenuado ? 0.45 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: seleccionado ? c.fondo : Colors.white,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: seleccionado ? c.texto : ColoresVista.borde,
                    width: seleccionado ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AvatarOperario(operario: carga.operario, tamano: 26),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        carga.operario.nombreCorto,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: c.texto,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          BarraCarga(valor: fraccion),
          const SizedBox(height: 6),
          Text(
            '${carga.tareas} tareas · ${carga.dias} días · '
            '${decimalCorto(carga.porDia)} por día',
            style: const TextStyle(
              fontSize: 12,
              color: ColoresVista.textoSuave,
            ),
          ),
        ],
      ),
    );
  }
}
