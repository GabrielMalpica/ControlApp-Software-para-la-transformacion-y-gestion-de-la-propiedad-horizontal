import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/model/planilla_usuario_model.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/planilla/planilla_tabla.dart';
import 'package:flutter_application_1/utils/planilla/vacaciones_planilla.dart';
import 'package:flutter_application_1/widgets/cronograma/desplazamiento_enlazado.dart';

/// Tabla tipo Excel con todos los datos del personal (planilla). Es un
/// sliver: va dentro del `CustomScrollView` de la página, así toda la pantalla
/// se desplaza con un solo scroll vertical; la fila de títulos queda fija
/// arriba y las columnas se desplazan juntas hacia los lados, con la primera
/// columna fija. La página debe envolver su `CustomScrollView` en un
/// `SelectionArea` para que el texto de las celdas se pueda seleccionar.
///
/// Columnas visibles, su orden y la agrupación se recuerdan en el
/// dispositivo por [contexto]. Ver docs/planilla-personal.md.
class TablaPlanillaSliver extends StatefulWidget {
  final List<PlanillaUsuario> filas;

  /// Separa lo que se recuerda en el dispositivo (p. ej. `general`,
  /// `conjunto`).
  final String contexto;
  final AgrupacionPlanilla agrupacionPorDefecto;

  /// Día de referencia para edades, antigüedad y vacaciones (hoy si es null).
  final DateTime? hoy;
  final String textoVacio;

  const TablaPlanillaSliver({
    super.key,
    required this.filas,
    required this.contexto,
    this.agrupacionPorDefecto = AgrupacionPlanilla.ninguna,
    this.hoy,
    this.textoVacio = 'No hay personas para mostrar con estos filtros.',
  });

  /// Clave de las preferencias guardadas para [contexto].
  static String clavePreferencias(String contexto) =>
      'planilla_usuarios_v1_$contexto';

  @override
  State<TablaPlanillaSliver> createState() => _TablaPlanillaSliverState();
}

class _TablaPlanillaSliverState extends State<TablaPlanillaSliver> {
  static const double _anchoAccion = 48;
  static const double _espacioBarra = 12;

  final _horizontal = DesplazamientoEnlazado();
  final _claveAreaTitulos = GlobalKey();
  late ConfigPlanilla _config = ConfigPlanilla.porDefecto(
    agrupacion: widget.agrupacionPorDefecto,
  );
  bool _cambiadaAntesDeCargar = false;
  Timer? _autoDesplazar;
  double _velocidad = 0;
  String? _arrastrando;

  DateTime get _hoy => widget.hoy ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
  }

  @override
  void dispose() {
    _autoDesplazar?.cancel();
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _cargarPreferencias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        TablaPlanillaSliver.clavePreferencias(widget.contexto),
      );
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw);
      if (json is! Map || !mounted || _cambiadaAntesDeCargar) return;
      setState(() {
        _config = ConfigPlanilla.fromJson(
          json.cast<String, dynamic>(),
          agrupacionPorDefecto: widget.agrupacionPorDefecto,
        );
      });
    } catch (_) {
      // Preferencias dañadas o no disponibles: queda la vista por defecto.
    }
  }

  Future<void> _guardarPreferencias(ConfigPlanilla config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        TablaPlanillaSliver.clavePreferencias(widget.contexto),
        jsonEncode(config.toJson()),
      );
    } catch (_) {
      // Best effort: si no se guarda, la próxima vez se vuelve a ajustar.
    }
  }

  void _cambiar(ConfigPlanilla nueva) {
    _cambiadaAntesDeCargar = true;
    setState(() => _config = nueva);
    _guardarPreferencias(nueva);
  }

  /* ------------------------------- copiar ------------------------------- */

  Future<void> _copiar(String texto, String mensaje) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    AppFeedback.showInfo(context, title: 'Copiado', message: mensaje);
  }

  void _copiarTabla(List<GrupoPlanilla> grupos, List<ColumnaPlanilla> cols) {
    final personas = widget.filas.length;
    _copiar(
      tablaParaExcel(grupos, cols, _hoy),
      'Tabla copiada (${personas == 1 ? '1 persona' : '$personas personas'}, '
      '${cols.length} columnas). Pégala en Excel o en Google Sheets.',
    );
  }

  void _copiarFila(PlanillaUsuario u, List<ColumnaPlanilla> cols) {
    _copiar(
      filaParaExcel(u, cols, _hoy, conEncabezado: true),
      'Datos de ${u.nombre} copiados con sus títulos. Pégalos en Excel.',
    );
  }

  /* ------------------------------ arrastre ------------------------------ */

  /// Al arrastrar un título cerca del borde, la tabla se desplaza sola para
  /// poder soltarlo en una columna que no se ve.
  void _alArrastrar(DragUpdateDetails d) {
    final box = _claveAreaTitulos.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final x = box.globalToLocal(d.globalPosition).dx;
    const borde = 56.0;
    _velocidad = x < borde ? -14 : (x > box.size.width - borde ? 14 : 0);
    if (_velocidad == 0) {
      _autoDesplazar?.cancel();
      _autoDesplazar = null;
      return;
    }
    _autoDesplazar ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final c = _horizontal.controlador(0);
      if (!c.hasClients || _velocidad == 0) return;
      final p = c.position;
      final destino = (p.pixels + _velocidad).clamp(0.0, p.maxScrollExtent);
      if (destino != p.pixels) c.jumpTo(destino);
    });
  }

  void _finArrastre() {
    _autoDesplazar?.cancel();
    _autoDesplazar = null;
    _velocidad = 0;
    if (mounted) setState(() => _arrastrando = null);
  }

  /* -------------------------------- vista ------------------------------- */

  @override
  Widget build(BuildContext context) {
    final visibles = _config.visibles;
    final grupos = agruparPlanilla(widget.filas, _config.agrupacion);
    final agrupada = _config.agrupacion != AgrupacionPlanilla.ninguna;
    final items = <Object>[
      for (final g in grupos) ...[if (agrupada) g, ...g.filas],
    ];
    final escala = MediaQuery.textScalerOf(context).scale(16) / 16;
    final altoTitulos = (56 * escala).clamp(56.0, 130.0) + _espacioBarra;
    final altoAviso = (48 * escala).clamp(48.0, 90.0);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.crossAxisExtent;
        final primera = visibles.first;
        final anchoPrimera = math.min(
          primera.ancho,
          math.max(120.0, ancho * 0.38),
        );
        final resto = visibles.skip(1).toList();
        final anchoResto = resto.fold<double>(0, (s, c) => s + c.ancho);
        final desborda = anchoResto > ancho - _anchoAccion - anchoPrimera + 1;

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: SelectionContainer.disabled(
                child: _barra(grupos, visibles),
              ),
            ),
            if (widget.filas.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.textoVacio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              )
            else
              DecoratedSliver(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.14),
                  ),
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: EncabezadoFijoDelegate(
                        alto: altoTitulos + 1 + (desborda ? altoAviso : 0),
                        child: SelectionContainer.disabled(
                          child: Column(
                            children: [
                              if (desborda)
                                SizedBox(
                                  height: altoAviso,
                                  child: AvisoDesplazarLados(
                                    texto:
                                        'Hay más columnas hacia los lados. Usa las flechas, la barra o desliza la tabla.',
                                    onIzquierda: () =>
                                        _horizontal.desplazar(-ancho * 0.6),
                                    onDerecha: () =>
                                        _horizontal.desplazar(ancho * 0.6),
                                  ),
                                ),
                              SizedBox(
                                height: altoTitulos,
                                child: _filaTitulos(
                                  primera,
                                  anchoPrimera,
                                  resto,
                                  desborda,
                                ),
                              ),
                              const Divider(height: 1),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        if (item is GrupoPlanilla) return _filaGrupo(item);
                        return _fila(
                          item as PlanillaUsuario,
                          i,
                          primera,
                          anchoPrimera,
                          resto,
                          visibles,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _barra(List<GrupoPlanilla> grupos, List<ColumnaPlanilla> visibles) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _menuColumnas(visibles),
              _menuAgrupar(),
              FilledButton.tonalIcon(
                onPressed: widget.filas.isEmpty
                    ? null
                    : () => _copiarTabla(grupos, visibles),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Copiar tabla'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Arrastra el título de una columna para cambiarla de lugar (en el '
            'celular, mantenlo presionado y luego arrástralo). Puedes '
            'seleccionar el texto de las celdas, y "Copiar tabla" la deja '
            'lista para pegar en Excel.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  MenuStyle _estiloMenu(double ancho) => MenuStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.white),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
    elevation: const WidgetStatePropertyAll(6),
    minimumSize: WidgetStatePropertyAll(Size(ancho, 0)),
    maximumSize: WidgetStatePropertyAll(Size(ancho, 480)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  /// Abre el menú justo debajo del botón: si no cabe, primero sube la página.
  Future<void> _abrirDebajo(
    BuildContext context,
    MenuController controller,
    double alto,
  ) async {
    if (controller.isOpen) {
      controller.close();
      return;
    }
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached) {
      final abajo = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (MediaQuery.sizeOf(context).height - abajo < alto) {
        await Scrollable.ensureVisible(
          context,
          alignment: 0.1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
    controller.open();
  }

  Widget _menuColumnas(List<ColumnaPlanilla> visibles) {
    final anchoMenu = math.min(380.0, MediaQuery.sizeOf(context).width - 24);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: _estiloMenu(anchoMenu),
      menuChildren: [
        SizedBox(
          width: anchoMenu,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Marca las columnas que quieres ver. Las flechas las mueven '
                  'a la izquierda o a la derecha.',
                  style: TextStyle(fontSize: 13.5, color: AppTheme.textMuted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => _cambiar(_config.mostrarTodas()),
                      child: const Text('Mostrar todas'),
                    ),
                    TextButton(
                      onPressed: () => _cambiar(_config.restablecerOrden()),
                      child: const Text('Orden original'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final clave in _config.orden) _opcionColumna(clave),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => _abrirDebajo(context, controller, 480),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: controller.isOpen
              ? AppTheme.surfaceSoft
              : Colors.white,
        ),
        icon: const Icon(Icons.view_column_outlined),
        label: Text(
          'Columnas (${visibles.length} de ${columnasPlanilla.length})',
        ),
      ),
    );
  }

  Widget _opcionColumna(String clave) {
    final columna = columnaPlanilla(clave);
    if (columna == null) return const SizedBox.shrink();
    final visible = _config.esVisible(clave);
    final vis = _config.visibles.map((c) => c.clave).toList();
    final i = vis.indexOf(clave);
    return InkWell(
      onTap: () => _cambiar(_config.alternar(clave)),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Row(
          children: [
            Checkbox(
              value: visible,
              onChanged: (_) => _cambiar(_config.alternar(clave)),
            ),
            Expanded(
              child: Text(
                columna.titulo,
                style: TextStyle(
                  fontSize: 15,
                  color: visible ? AppTheme.text : AppTheme.textMuted,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Mover ${columna.titulo} a la izquierda',
              onPressed: visible && i > 0
                  ? () => _cambiar(_config.moverUnPaso(clave, -1))
                  : null,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              tooltip: 'Mover ${columna.titulo} a la derecha',
              onPressed: visible && i >= 0 && i < vis.length - 1
                  ? () => _cambiar(_config.moverUnPaso(clave, 1))
                  : null,
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
          ],
        ),
      ),
    );
  }

  static String _etiquetaAgrupacion(AgrupacionPlanilla a) => switch (a) {
    AgrupacionPlanilla.ninguna => 'Sin agrupar',
    AgrupacionPlanilla.conjunto => 'Por conjunto',
    AgrupacionPlanilla.rol => 'Por rol',
  };

  Widget _menuAgrupar() {
    final actual = _config.agrupacion;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: _estiloMenu(240),
      menuChildren: [
        for (final a in AgrupacionPlanilla.values)
          MenuItemButton(
            onPressed: () => _cambiar(_config.conAgrupacion(a)),
            leadingIcon: Icon(
              a == actual ? Icons.check_rounded : Icons.circle_outlined,
              color: a == actual ? AppTheme.primary : Colors.transparent,
            ),
            style: MenuItemButton.styleFrom(minimumSize: const Size(0, 48)),
            child: Text(_etiquetaAgrupacion(a)),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => _abrirDebajo(context, controller, 200),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor:
              controller.isOpen || actual != AgrupacionPlanilla.ninguna
              ? AppTheme.surfaceSoft
              : Colors.white,
        ),
        icon: const Icon(Icons.workspaces_outline),
        label: Text('Agrupar: ${_etiquetaAgrupacion(actual)}'),
      ),
    );
  }

  Widget _filaTitulos(
    ColumnaPlanilla primera,
    double anchoPrimera,
    List<ColumnaPlanilla> resto,
    bool desborda,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(width: _anchoAccion, color: AppTheme.surfaceSoft),
        _titulo(primera, anchoPrimera),
        Expanded(
          key: _claveAreaTitulos,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _horizontal.controlador(0),
              thumbVisibility: desborda,
              trackVisibility: desborda,
              interactive: true,
              thickness: 8,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: NotificationListener<ScrollNotification>(
                onNotification: _horizontal.alDesplazar,
                child: SingleChildScrollView(
                  controller: _horizontal.controlador(0),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final c in resto) _titulo(c, c.ancho)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _titulo(ColumnaPlanilla c, double ancho) {
    Widget celda({required bool resaltada, bool alaDerecha = false}) {
      final borde = BorderSide(color: AppTheme.primary.withValues(alpha: 0.12));
      const marca = BorderSide(color: AppTheme.primary, width: 4);
      return Container(
        width: ancho,
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6 + _espacioBarra),
        decoration: BoxDecoration(
          color: _arrastrando == c.clave
              ? AppTheme.primary.withValues(alpha: 0.10)
              : AppTheme.surfaceSoft,
          border: Border(
            left: resaltada && !alaDerecha ? marca : borde,
            right: resaltada && alaDerecha ? marca : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                c.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppTheme.text,
                ),
              ),
            ),
            const Icon(
              Icons.drag_indicator_rounded,
              size: 18,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      );
    }

    final ficha = Material(
      elevation: 6,
      color: AppTheme.primary,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          c.titulo,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );

    Widget arrastrable(bool tactil, Widget child) => _ArrastreColumna(
      tactil: tactil,
      data: c.clave,
      feedback: ficha,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => setState(() => _arrastrando = c.clave),
      onDragUpdate: _alArrastrar,
      onDragEnd: (_) => _finArrastre(),
      child: child,
    );

    return DragTarget<String>(
      key: ValueKey('titulo-${c.clave}'),
      onWillAcceptWithDetails: (d) => d.data != c.clave,
      onAcceptWithDetails: (d) => _cambiar(_config.mover(d.data, c.clave)),
      builder: (context, candidatos, _) {
        final origen = candidatos.isEmpty ? null : candidatos.first;
        final alaDerecha =
            origen != null &&
            _config.orden.indexOf(origen) < _config.orden.indexOf(c.clave);
        return Semantics(
          header: true,
          label: '${c.titulo}. Mantén presionado y arrastra para moverla.',
          excludeSemantics: true,
          child: arrastrable(
            true,
            arrastrable(
              false,
              celda(resaltada: origen != null, alaDerecha: alaDerecha),
            ),
          ),
        );
      },
    );
  }

  Widget _filaGrupo(GrupoPlanilla g) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _config.agrupacion == AgrupacionPlanilla.rol
                ? Icons.badge_outlined
                : Icons.apartment_rounded,
            color: AppTheme.primaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              g.encabezado,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(
    PlanillaUsuario u,
    int indice,
    ColumnaPlanilla primera,
    double anchoPrimera,
    List<ColumnaPlanilla> resto,
    List<ColumnaPlanilla> visibles,
  ) {
    final fondo = indice.isEven ? Colors.white : const Color(0xFFF7FAF8);
    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          color: fondo,
          border: Border(
            bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.10)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _anchoAccion,
              child: SelectionContainer.disabled(
                child: Center(
                  child: IconButton(
                    tooltip: 'Copiar fila de ${u.nombre}',
                    onPressed: () => _copiarFila(u, visibles),
                    icon: const Icon(
                      Icons.content_copy_rounded,
                      size: 20,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            _celda(primera, u, anchoPrimera),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: NotificationListener<ScrollNotification>(
                  onNotification: _horizontal.alDesplazar,
                  child: SingleChildScrollView(
                    controller: _horizontal.controlador(indice + 1),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final c in resto) _celda(c, u, c.ancho)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celda(ColumnaPlanilla c, PlanillaUsuario u, double ancho) {
    final valor = c.valor(u, _hoy);
    final esVacaciones = c.clave == 'vacaciones';
    final tono = esVacaciones ? _tonoVacaciones(u) : null;
    return Container(
      width: ancho,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: tono?.$1,
        border: Border(
          left: BorderSide(color: AppTheme.primary.withValues(alpha: 0.10)),
        ),
      ),
      child: Text(
        valor,
        style: TextStyle(
          fontSize: 14,
          height: 1.3,
          fontWeight: c.clave == 'nombre' || tono != null
              ? FontWeight.w700
              : FontWeight.w400,
          color: tono?.$2 ?? (u.activo ? AppTheme.text : AppTheme.textMuted),
        ),
      ),
    );
  }

  /// Fondo y texto de la celda de vacaciones según el estado (con contraste
  /// suficiente para leerse bien).
  (Color, Color)? _tonoVacaciones(PlanillaUsuario u) {
    if (u.rol == 'administrador' && u.fechaIngreso == null) return null;
    return switch (estadoVacacionesDe(u, _hoy).tipo) {
      TipoEstadoVacaciones.pendientes => (
        const Color(0xFFFDE8E8),
        const Color(0xFF8B1D1D),
      ),
      TipoEstadoVacaciones.deVacaciones => (
        const Color(0xFFFFF4CC),
        const Color(0xFF6B4E00),
      ),
      TipoEstadoVacaciones.programadas => (
        const Color(0xFFE3EEFB),
        const Color(0xFF16457A),
      ),
      TipoEstadoVacaciones.yaTomo || TipoEstadoVacaciones.primerAnio => (
        const Color(0xFFE6F4EA),
        const Color(0xFF14532D),
      ),
      TipoEstadoVacaciones.retirado ||
      TipoEstadoVacaciones.sinFechaIngreso => null,
    };
  }
}

/// Arrastre de un título de columna. Con mouse empieza al mover; con el dedo
/// o lápiz, después de mantener presionado, para que deslizar siga moviendo
/// la tabla hacia los lados.
class _ArrastreColumna extends Draggable<String> {
  final bool tactil;

  const _ArrastreColumna({
    required this.tactil,
    required super.child,
    required super.feedback,
    required super.data,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
  });

  static const _dispositivosTactiles = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    if (tactil) {
      return DelayedMultiDragGestureRecognizer(
          supportedDevices: _dispositivosTactiles,
        )
        ..onStart = (position) {
          final drag = onStart(position);
          if (drag != null) HapticFeedback.selectionClick();
          return drag;
        };
    }
    return ImmediateMultiDragGestureRecognizer(
      supportedDevices: const {PointerDeviceKind.mouse},
    )..onStart = onStart;
  }
}
