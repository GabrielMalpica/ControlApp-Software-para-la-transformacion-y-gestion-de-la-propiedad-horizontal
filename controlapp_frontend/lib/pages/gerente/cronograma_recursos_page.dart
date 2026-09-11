import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../api/cronograma_herramienta_api.dart';
import '../../api/cronograma_maquinaria_api.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../model/necesidad_maquinaria_model.dart';
import '../../model/recurso_calendario_item.dart';
import '../../service/app_error.dart';
import '../../service/app_feedback.dart';
import '../../service/permission_service.dart';
import '../../service/theme.dart';
import '../../widgets/searchable_select_field.dart';
import '../../widgets/skeleton.dart';

/// Cronograma de recursos (maquinaria y/o herramientas) en calendario.
///
/// Un solo widget cubre los dos casos de uso:
/// - Agenda de recursos de un conjunto: alterna maquinaria/herramientas con
///   pestañas (`todosLosConjuntos: false`). Si `conjuntoIdInicial` viene
///   dado (se abrió desde la agenda de ESE conjunto), el selector queda fijo;
///   si no, es un buscador (hay demasiados conjuntos para una lista plana).
/// - Agenda general de la empresa (`todosLosConjuntos: true`): maquinaria y
///   herramientas de TODOS los conjuntos juntas, sin pestañas ni selector,
///   solo para quien tenga permiso de asignar maquinaria o herramientas
///   (gerente y jefe de operaciones, hoy).
///
/// El calendario y el panel de detalle van uno junto al otro (mesa de
/// trabajo), no en una hoja modal: en pantallas anchas quedan lado a lado, en
/// angostas el panel cae debajo del calendario.
class CronogramaRecursosPage extends StatefulWidget {
  final String empresaNit;
  final String? conjuntoIdInicial;
  final TipoRecursoCal tipoInicial;
  final bool todosLosConjuntos;
  final String titulo;

  const CronogramaRecursosPage({
    super.key,
    required this.empresaNit,
    required this.titulo,
    this.conjuntoIdInicial,
    this.tipoInicial = TipoRecursoCal.maquinaria,
    this.todosLosConjuntos = false,
  });

  @override
  State<CronogramaRecursosPage> createState() => _CronogramaRecursosPageState();
}

class _CronogramaRecursosPageState extends State<CronogramaRecursosPage> {
  final _maqApi = CronogramaMaquinariaApi();
  final _herApi = CronogramaHerramientaApi();
  final _gerenteApi = GerenteApi();

  late TipoRecursoCal _tipoActivo;

  bool get _conjuntoFijo => widget.conjuntoIdInicial != null;

  bool get _puedeAsignar {
    if (widget.todosLosConjuntos) {
      return PermissionService.instance.can('maquinaria.asignar') ||
          PermissionService.instance.can('herramientas.asignar');
    }
    return _tipoActivo == TipoRecursoCal.maquinaria
        ? PermissionService.instance.can('maquinaria.asignar')
        : PermissionService.instance.can('herramientas.asignar');
  }

  DateTime _focusedDay = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay;

  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  List<Conjunto> _conjuntos = [];
  String? _conjuntoSeleccionado;

  Map<DateTime, List<RecursoCalendarioItem>> _porDia = {};
  Map<String, List<MaquinaCandidata>> _maquinariasPorTipo = {};

  @override
  void initState() {
    super.initState();
    _tipoActivo = widget.tipoInicial;
    _init();
  }

  Future<void> _init() async {
    if (!widget.todosLosConjuntos) {
      try {
        final lista = await _gerenteApi.listarConjuntos();
        if (!mounted) return;
        setState(() {
          _conjuntos = lista;
          _conjuntoSeleccionado = widget.conjuntoIdInicial ??
              (lista.isNotEmpty ? lista.first.nit : null);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _cargando = false;
          _error = AppError.messageOf(e);
        });
        return;
      }
    }
    await _cargar();
  }

  DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    final conjuntoId = widget.todosLosConjuntos ? null : _conjuntoSeleccionado;
    final incluirMaquinaria = widget.todosLosConjuntos || _tipoActivo == TipoRecursoCal.maquinaria;
    final incluirHerramientas = widget.todosLosConjuntos || _tipoActivo == TipoRecursoCal.herramienta;

    try {
      final items = <RecursoCalendarioItem>[];
      final maquinariasPorTipo = <String, List<MaquinaCandidata>>{};

      if (incluirMaquinaria) {
        final r = await _maqApi.listarNecesidades(
          empresaNit: widget.empresaNit,
          anio: _focusedDay.year,
          mes: _focusedDay.month,
          conjuntoId: conjuntoId,
        );
        maquinariasPorTipo.addAll(r.maquinariasPorTipo);
        items.addAll(r.necesidades.map(RecursoCalendarioItem.deMaquinaria));
      }
      if (incluirHerramientas) {
        final r = await _herApi.listarNecesidades(
          empresaNit: widget.empresaNit,
          anio: _focusedDay.year,
          mes: _focusedDay.month,
          conjuntoId: conjuntoId,
        );
        items.addAll(r.necesidades.map(RecursoCalendarioItem.deHerramienta));
      }

      final porDia = <DateTime, List<RecursoCalendarioItem>>{};
      for (final item in items) {
        (porDia[_key(item.fecha)] ??= []).add(item);
      }

      if (!mounted) return;
      setState(() {
        _porDia = porDia;
        _maquinariasPorTipo = maquinariasPorTipo;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = AppError.messageOf(e);
      });
    }
  }

  List<RecursoCalendarioItem> _itemsDelDia(DateTime day) =>
      _porDia[_key(day)] ?? const [];

  String _cantidadLabel(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String get _ambitoLabel {
    if (widget.todosLosConjuntos) return 'Todos los conjuntos';
    final match = _conjuntos.where((c) => c.nit == _conjuntoSeleccionado);
    return match.isNotEmpty ? match.first.nombre : (_conjuntoSeleccionado ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.titulo, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.todosLosConjuntos) _buildControles(),
          if (_procesando) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: _cargando
                ? const SkeletonList()
                : _error != null
                    ? _buildError()
                    : _buildWorkbench(),
          ),
        ],
      ),
    );
  }

  Widget _buildControles() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildSelectorConjunto()),
          const SizedBox(width: 10),
          _buildTabsTipo(),
        ],
      ),
    );
  }

  Widget _buildSelectorConjunto() {
    // Viene de la agenda de un conjunto específico: queda fijo, no se cambia.
    if (_conjuntoFijo) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.apartment, size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _ambitoLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.lock_outline, size: 15, color: AppTheme.textMuted),
          ],
        ),
      );
    }

    if (_conjuntos.isEmpty) return const SizedBox.shrink();
    // Muchos conjuntos: mejor un buscador que una lista plana.
    return SearchableSelectField<String>(
      label: 'Conjunto',
      value: _conjuntoSeleccionado,
      prefixIcon: Icon(Icons.apartment, color: AppTheme.textMuted),
      searchHint: 'Buscar conjunto por nombre',
      options: _conjuntos
          .map((c) => SearchableSelectOption<String>(value: c.nit, label: c.nombre))
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          _conjuntoSeleccionado = v;
          _selectedDay = null;
        });
        _cargar();
      },
    );
  }

  Widget _buildTabsTipo() {
    Widget tab(TipoRecursoCal tipo, String label, IconData icon) {
      final activo = _tipoActivo == tipo;
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: activo
            ? null
            : () {
                setState(() {
                  _tipoActivo = tipo;
                  _selectedDay = null;
                });
                _cargar();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: activo ? AppTheme.surface : null,
            borderRadius: BorderRadius.circular(8),
            boxShadow: activo
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: activo ? AppTheme.primaryDark : AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: activo ? AppTheme.primaryDark : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab(TipoRecursoCal.maquinaria, 'Maquinaria', Icons.precision_manufacturing),
          tab(TipoRecursoCal.herramienta, 'Herramientas', Icons.handyman),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // ================== Mesa de trabajo: calendario + panel ==================

  Widget _buildWorkbench() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth >= 900;
        final calendario = _panel(child: _buildCalendarioContenido());
        final rail = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panel(padding: const EdgeInsets.all(16), child: _buildRailContenido()),
            const SizedBox(height: 12),
            _panel(padding: const EdgeInsets.all(16), child: _buildHowto()),
          ],
        );

        if (ancho) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: calendario),
                const SizedBox(width: 12),
                SizedBox(width: 360, child: rail),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(children: [calendario, const SizedBox(height: 12), rail]),
        );
      },
    );
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry padding = EdgeInsets.zero}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceSoft, width: 1.4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCalendarioContenido() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Necesidades · $_ambitoLabel',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              _legendDot(AppTheme.accent, 'Pendiente'),
              _legendDot(AppTheme.green, 'Cubierta'),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TableCalendar<RecursoCalendarioItem>(
            locale: 'es',
            firstDay: DateTime(2023, 1, 1),
            lastDay: DateTime(2032, 12, 31),
            focusedDay: _focusedDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            rowHeight: 92,
            daysOfWeekHeight: 26,
            selectedDayPredicate: (day) =>
                _selectedDay != null && isSameDay(_selectedDay, day),
            eventLoader: _itemsDelDia,
            onDaySelected: (selectedDay, focusedDay) {
              if (_itemsDelDia(selectedDay).isEmpty) return;
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
                _selectedDay = null;
              });
              _cargar();
            },
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
              weekendStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) => _dayCell(day, hoy: false, seleccionado: false),
              todayBuilder: (context, day, focusedDay) => _dayCell(day, hoy: true, seleccionado: false),
              selectedBuilder: (context, day, focusedDay) =>
                  _dayCell(day, hoy: isSameDay(day, DateTime.now()), seleccionado: true),
              outsideBuilder: (context, day, focusedDay) => const SizedBox.shrink(),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _dayCell(DateTime day, {required bool hoy, required bool seleccionado}) {
    final items = _itemsDelDia(day);
    final tieneItems = items.isNotEmpty;
    final mostrados = items.take(2).toList();
    final restantes = items.length - mostrados.length;

    return Container(
      margin: const EdgeInsets.all(2.5),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: seleccionado
            ? AppTheme.primary.withValues(alpha: 0.14)
            : tieneItems
                ? AppTheme.surfaceSoft
                : null,
        borderRadius: BorderRadius.circular(12),
        border: seleccionado ? Border.all(color: AppTheme.primary, width: 1.4) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: hoy ? AppTheme.primary : null, shape: BoxShape.circle),
            child: Text(
              '${day.day}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: hoy ? Colors.white : AppTheme.text),
            ),
          ),
          if (mostrados.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...mostrados.map(_itemChip),
            if (restantes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '+$restantes más',
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _itemChip(RecursoCalendarioItem item) {
    final color = item.cubierta ? AppTheme.green : const Color(0xFF8A5A00);
    final bg = item.cubierta ? AppTheme.green.withValues(alpha: 0.14) : AppTheme.accent.withValues(alpha: 0.24);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(
              child: Text(
                item.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================== Panel de detalle (siempre visible) ==================

  Widget _buildRailContenido() {
    if (_selectedDay == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month_outlined, size: 30, color: AppTheme.surfaceSoft),
          const SizedBox(height: 10),
          const Text('Elige un día en el calendario', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          const SizedBox(height: 4),
          Text(
            'Los días con un punto ámbar tienen máquinas o herramientas por asignar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      );
    }

    return _DiaDetalleContent(
      dia: _selectedDay!,
      items: _itemsDelDia(_selectedDay!),
      agruparPorConjunto: widget.todosLosConjuntos,
      puedeAsignar: _puedeAsignar,
      maquinariasPorTipo: _maquinariasPorTipo,
      onAsignarMaquinaria: _asignarMaquinaria,
      onAsignarHerramienta: _asignarHerramienta,
      onLiberarMaquinaria: _liberarMaquinaria,
      onLiberarHerramienta: _liberarHerramienta,
      cantidadLabel: _cantidadLabel,
    );
  }

  Widget _buildHowto() {
    final pasos = [
      'El punto ámbar en un día = falta asignar; el verde = ya cubierto por completo.',
      'Al asignar, primero aparece lo propio del conjunto y luego el préstamo de empresa.',
      'Cada candidata muestra su franja de entrega → recogida antes de confirmar.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cómo se lee', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.text)),
        const SizedBox(height: 8),
        for (var i = 0; i < pasos.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(top: 1, right: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(5)),
                  child: Text('${i + 1}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppTheme.secondary)),
                ),
                Expanded(child: Text(pasos[i], style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.4))),
              ],
            ),
          ),
      ],
    );
  }

  // ================== Acciones ==================

  Future<void> _asignarMaquinaria(RecursoCalendarioItem item, int maquinariaId) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await _maqApi.asignarMaquinaria(
        empresaNit: widget.empresaNit,
        tareaIds: item.tareaIds,
        maquinariaId: maquinariaId,
      );
      await _cargar();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text('${item.titulo} asignada.')));
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text(AppError.messageOf(e))));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _asignarHerramienta(RecursoCalendarioItem item) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await _herApi.asignarHerramienta(
        empresaNit: widget.empresaNit,
        tareaIds: item.tareaIds,
        herramientaId: item.herramientaRaw!.herramientaId,
      );
      await _cargar();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text('${item.titulo} asignada.')));
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text(AppError.messageOf(e))));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _liberarMaquinaria(int usoId) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await _maqApi.liberarAsignacion(empresaNit: widget.empresaNit, usoId: usoId);
      await _cargar();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, const SnackBar(content: Text('Maquinaria liberada.')));
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text(AppError.messageOf(e))));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _liberarHerramienta(int usoId) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await _herApi.liberarAsignacion(empresaNit: widget.empresaNit, usoId: usoId);
      await _cargar();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, const SnackBar(content: Text('Herramienta liberada.')));
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text(AppError.messageOf(e))));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }
}

// ====================================================================
// Contenido del panel de detalle del día (embebido, no en hoja modal)
// ====================================================================

class _DiaDetalleContent extends StatefulWidget {
  final DateTime dia;
  final List<RecursoCalendarioItem> items;
  final bool agruparPorConjunto;
  final bool puedeAsignar;
  final Map<String, List<MaquinaCandidata>> maquinariasPorTipo;
  final void Function(RecursoCalendarioItem item, int maquinariaId) onAsignarMaquinaria;
  final void Function(RecursoCalendarioItem item) onAsignarHerramienta;
  final void Function(int usoId) onLiberarMaquinaria;
  final void Function(int usoId) onLiberarHerramienta;
  final String Function(double) cantidadLabel;

  const _DiaDetalleContent({
    required this.dia,
    required this.items,
    required this.agruparPorConjunto,
    required this.puedeAsignar,
    required this.maquinariasPorTipo,
    required this.onAsignarMaquinaria,
    required this.onAsignarHerramienta,
    required this.onLiberarMaquinaria,
    required this.onLiberarHerramienta,
    required this.cantidadLabel,
  });

  @override
  State<_DiaDetalleContent> createState() => _DiaDetalleContentState();
}

class _DiaDetalleContentState extends State<_DiaDetalleContent> {
  final Set<int> _expandidos = {};

  @override
  void didUpdateWidget(covariant _DiaDetalleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dia != widget.dia) _expandidos.clear();
  }

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<RecursoCalendarioItem>>{};
    if (widget.agruparPorConjunto) {
      for (final item in widget.items) {
        (grupos[item.conjuntoNombre] ??= []).add(item);
      }
    } else {
      grupos[''] = widget.items;
    }
    final nombresConjunto = grupos.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('EEEE d MMMM', 'es').format(widget.dia),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .2, color: AppTheme.secondary),
        ),
        const SizedBox(height: 12),
        for (final nombre in nombresConjunto) ...[
          if (widget.agruparPorConjunto) ...[
            Text(
              nombre,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.text),
            ),
            const SizedBox(height: 6),
          ],
          ...grupos[nombre]!.asMap().entries.map(
                (e) => _buildItem(context, e.value, e.key.hashCode ^ nombre.hashCode ^ e.value.hashCode),
              ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildItem(BuildContext context, RecursoCalendarioItem item, int key) {
    final expandido = _expandidos.contains(key);
    final esMaquinaria = item.tipo == TipoRecursoCal.maquinaria;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.surfaceSoft, width: 1.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                esMaquinaria ? Icons.precision_manufacturing : Icons.handyman,
                size: 18,
                color: item.cubierta ? AppTheme.green : const Color(0xFF8A5A00),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      esMaquinaria
                          ? item.titulo
                          : '${item.titulo} · ${widget.cantidadLabel(item.cantidadRequerida)} ${item.unidad}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    for (final t in item.tareasResumen)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(t, style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.cubierta
                      ? AppTheme.green.withValues(alpha: 0.14)
                      : AppTheme.accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.cantidadLabel(item.asignadas)}/${widget.cantidadLabel(item.cantidadRequerida)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: item.cubierta ? AppTheme.green : const Color(0xFF8A5A00),
                  ),
                ),
              ),
            ],
          ),

          if (esMaquinaria && item.maquinariaRaw!.asignaciones.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...item.maquinariaRaw!.asignaciones.map(
              (a) => _asignacionRow(
                titulo: '${a.maquinariaNombre} · ${a.marca}',
                onLiberar: widget.puedeAsignar ? () => widget.onLiberarMaquinaria(a.usoId) : null,
              ),
            ),
          ],
          if (!esMaquinaria && item.herramientaRaw!.asignaciones.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...item.herramientaRaw!.asignaciones.map(
              (a) => _asignacionRow(
                titulo:
                    '${widget.cantidadLabel(a.cantidad)} ${item.unidad} · ${a.esPrestamoEmpresa ? "Préstamo de empresa" : "Stock del conjunto"}',
                onLiberar: widget.puedeAsignar ? () => widget.onLiberarHerramienta(a.usoId) : null,
              ),
            ),
          ],

          if (widget.puedeAsignar && !item.cubierta) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  expandido ? _expandidos.remove(key) : _expandidos.add(key);
                }),
                icon: Icon(expandido ? Icons.expand_less : Icons.add_circle_outline, size: 16),
                label: Text(expandido ? 'Ocultar candidatas' : 'Asignar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                ),
              ),
            ),
            if (expandido) ...[
              const SizedBox(height: 8),
              esMaquinaria ? _candidatosMaquinaria(item) : _candidatosHerramienta(item),
            ],
          ],
        ],
      ),
    );
  }

  Widget _asignacionRow({required String titulo, VoidCallback? onLiberar}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(titulo, style: const TextStyle(fontSize: 12))),
          if (onLiberar != null)
            IconButton(
              icon: const Icon(Icons.link_off, size: 16, color: Colors.red),
              tooltip: 'Liberar',
              onPressed: onLiberar,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _candidatosMaquinaria(RecursoCalendarioItem item) {
    final necesidad = item.maquinariaRaw!;
    final todas = widget.maquinariasPorTipo[necesidad.tipoRaw] ?? const [];
    final candidatas = todas.where((m) => m.disponibleParaConjunto(item.conjuntoId)).toList()
      ..sort((a, b) {
        final pa = a.propietarioTipo == 'CONJUNTO' ? 0 : 1;
        final pb = b.propietarioTipo == 'CONJUNTO' ? 0 : 1;
        return pa - pb;
      });

    if (candidatas.isEmpty) {
      return Text('No hay máquinas operativas de este tipo.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted));
    }

    String? grupoActual;
    final tiles = <Widget>[];
    for (final m in candidatas) {
      final grupo = m.propietarioTipo == 'CONJUNTO' ? 'Del conjunto' : 'Préstamo de la empresa';
      if (grupo != grupoActual) {
        grupoActual = grupo;
        tiles.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: Text(
            grupo,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: .3),
          ),
        ));
      }
      final sugerida = m.id == necesidad.maquinariaSugeridaId;
      tiles.add(InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onAsignarMaquinaria(item, m.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.surfaceSoft, width: 1.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(sugerida ? Icons.star : Icons.precision_manufacturing,
                      size: 15, color: sugerida ? AppTheme.accent : AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(m.etiqueta, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                ],
              ),
              const SizedBox(height: 6),
              _EntregaRecogidaStrip(entrega: item.entrega, recogida: item.recogida, tarea: item.fecha),
            ],
          ),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: tiles);
  }

  Widget _candidatosHerramienta(RecursoCalendarioItem item) {
    final n = item.herramientaRaw!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.surfaceSoft, width: 1.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _capacidadChip(Icons.home_repair_service_outlined, 'Del conjunto: ${widget.cantidadLabel(n.capacidadConjunto)}'),
              _capacidadChip(Icons.local_shipping_outlined, 'De la empresa: ${widget.cantidadLabel(n.capacidadEmpresa)}'),
            ],
          ),
          const SizedBox(height: 8),
          _EntregaRecogidaStrip(entrega: item.entrega, recogida: item.recogida, tarea: item.fecha),
          const SizedBox(height: 4),
          Text(
            'Se toma primero del conjunto y, si falta, se completa con préstamo automático de la empresa.',
            style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => widget.onAsignarHerramienta(item),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: Text('Asignar ${widget.cantidadLabel(item.pendientes)} ${item.unidad}'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capacidadChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: AppTheme.surfaceSoft,
      side: BorderSide.none,
    );
  }
}

/// Franja de días entrega -> recogida, con el mismo código de colores E/A/P/R
/// que ya usa la agenda de maquinaria/herramientas.
class _EntregaRecogidaStrip extends StatelessWidget {
  final DateTime entrega;
  final DateTime recogida;
  final DateTime tarea;

  const _EntregaRecogidaStrip({required this.entrega, required this.recogida, required this.tarea});

  static const _diasLetra = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];

  @override
  Widget build(BuildContext context) {
    final dias = <DateTime>[];
    for (var d = entrega.subtract(const Duration(days: 1));
        !d.isAfter(recogida.add(const Duration(days: 1)));
        d = d.add(const Duration(days: 1))) {
      dias.add(d);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entrega → recogida', style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Row(
          children: dias.map((d) {
            String code = '';
            Color bg = AppTheme.surfaceSoft;
            Color fg = AppTheme.textMuted;
            if (_sameDay(d, entrega)) {
              code = 'E';
              bg = Colors.blue.withValues(alpha: .16);
              fg = Colors.blue.shade800;
            } else if (_sameDay(d, recogida)) {
              code = 'R';
              bg = Colors.red.withValues(alpha: .16);
              fg = Colors.red.shade800;
            } else if (_sameDay(d, tarea)) {
              code = 'A';
              bg = Colors.green.withValues(alpha: .18);
              fg = Colors.green.shade800;
            } else if (d.isAfter(entrega) && d.isBefore(recogida)) {
              code = 'P';
              bg = Colors.amber.withValues(alpha: .20);
              fg = Colors.brown.shade800;
            }
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
                child: Text(
                  code.isEmpty ? _diasLetra[d.weekday % 7] : code,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
