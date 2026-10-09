// lib/pages/recursos/centro_recursos_page.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/api/recursos_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/permission_service.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/recursos/asignar_recurso_sheet.dart';
import 'package:flutter_application_1/widgets/recursos/necesidad_recurso_card.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';
import 'package:flutter_application_1/widgets/recursos/reserva_acciones.dart';
import 'package:flutter_application_1/widgets/recursos/resource_list_view.dart';
import 'package:flutter_application_1/widgets/recursos/resource_timeline.dart';
import 'package:flutter_application_1/widgets/searchable_select_field.dart';

bool _puedeAsignarClase(ClaseRecurso clase) => PermissionService.instance.can(
      clase == ClaseRecurso.maquinaria ? 'maquinaria.asignar' : 'herramientas.asignar',
    );

bool _puedeAsignarAlgo() =>
    PermissionService.instance.canAny(const ['maquinaria.asignar', 'herramientas.asignar']);

DateTime _inicioDia(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _lunes(DateTime d) => _inicioDia(d).subtract(Duration(days: d.weekday - DateTime.monday));

/// Rango de fechas de trabajo de la página.
class _Rango {
  final DateTime desde;
  final DateTime hasta;
  const _Rango(this.desde, this.hasta);

  bool igual(_Rango o) => desde == o.desde && hasta == o.hasta;
}

/// Centro de planificación de recursos de la empresa: necesidades pendientes,
/// agenda de cada unidad (dónde está y dónde estará), alertas y configuración
/// logística. Reemplaza la agenda de recursos anterior.
class CentroRecursosPage extends StatefulWidget {
  const CentroRecursosPage({
    super.key,
    required this.empresaNit,
    this.conjuntoIdInicial,
    this.pestanaInicial = 0,
    this.api,
  });

  /// Para pruebas: permite inyectar un cliente falso.
  final RecursosApi? api;

  final String empresaNit;
  final String? conjuntoIdInicial;

  /// 0 Pendientes · 1 Agenda · 2 Alertas · 3 Configuración
  final int pestanaInicial;

  @override
  State<CentroRecursosPage> createState() => _CentroRecursosPageState();
}

class _CentroRecursosPageState extends State<CentroRecursosPage> with SingleTickerProviderStateMixin {
  late final RecursosApi _api = widget.api ?? RecursosApi();
  late _Rango _rango;
  late String _preset;
  String? _conjuntoId;
  List<Conjunto> _conjuntos = const [];
  bool _puedeConfigurar = false;
  late TabController _tabs;
  int _alertasAltas = 0;

  @override
  void initState() {
    super.initState();
    final lunes = _lunes(DateTime.now());
    _rango = _Rango(lunes, lunes.add(const Duration(days: 6)));
    _preset = 'semana';
    _conjuntoId = widget.conjuntoIdInicial;
    _tabs = TabController(length: 4, vsync: this, initialIndex: widget.pestanaInicial.clamp(0, 3));
    _cargarContexto();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarContexto() async {
    var rol = '';
    try {
      rol = (await SessionService().getRol())?.toLowerCase() ?? '';
    } catch (_) {
      // Sin sesión legible: la configuración queda en solo lectura.
    }
    if (!mounted) return;
    setState(() => _puedeConfigurar = rol == 'gerente' || rol == 'jefe_operaciones');
    try {
      final lista = await GerenteApi().listarConjuntosSelector();
      if (!mounted) return;
      setState(() => _conjuntos = lista);
    } catch (_) {
      // Sin listado de conjuntos el filtro simplemente no se muestra.
    }
    try {
      final alertas = await _api.alertas(empresaNit: widget.empresaNit);
      if (!mounted) return;
      setState(() => _alertasAltas = alertas.alta);
    } catch (_) {
      // El contador es informativo; la pestaña de alertas muestra el error si lo hay.
    }
  }

  void _aplicarPreset(String preset) {
    final hoy = _inicioDia(DateTime.now());
    final lunes = _lunes(hoy);
    final rango = switch (preset) {
      'hoy' => _Rango(hoy, hoy),
      'proxima' => _Rango(lunes.add(const Duration(days: 7)), lunes.add(const Duration(days: 13))),
      '14' => _Rango(hoy, hoy.add(const Duration(days: 13))),
      'mes' => _Rango(DateTime(hoy.year, hoy.month, 1), DateTime(hoy.year, hoy.month + 1, 0)),
      _ => _Rango(lunes, lunes.add(const Duration(days: 6))),
    };
    setState(() {
      _preset = preset;
      _rango = rango;
    });
  }

  Future<void> _elegirRango() async {
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      initialDateRange: DateTimeRange(start: _rango.desde, end: _rango.hasta),
      helpText: 'Rango de la agenda (máx. 93 días)',
    );
    if (elegido == null) return;
    var fin = _inicioDia(elegido.end);
    final ini = _inicioDia(elegido.start);
    if (fin.difference(ini).inDays > 92) {
      fin = ini.add(const Duration(days: 92));
      if (mounted) {
        AppFeedback.showInfo(context, message: 'El rango se ajustó a 93 días, el máximo para la agenda.');
      }
    }
    setState(() {
      _preset = 'personalizado';
      _rango = _Rango(ini, fin);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.assignment_late_outlined), text: 'Pendientes'),
      const Tab(icon: Icon(Icons.view_timeline_outlined), text: 'Agenda'),
      Tab(
        icon: Badge(
          isLabelVisible: _alertasAltas > 0,
          label: Text('$_alertasAltas'),
          child: const Icon(Icons.notification_important_outlined),
        ),
        text: 'Alertas',
      ),
      const Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Logística'),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Centro de recursos'),
        // El AppBar es verde: pestañas en blanco para que se lean.
        bottom: TabBar(
          controller: _tabs,
          isScrollable: MediaQuery.sizeOf(context).width < 520,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.accent,
          indicatorWeight: 3,
          tabs: tabs,
        ),
      ),
      body: Column(
        children: [
          _BarraFiltrosComunes(
            rango: _rango,
            preset: _preset,
            onPreset: _aplicarPreset,
            onElegirRango: _elegirRango,
            conjuntos: _conjuntos,
            conjuntoId: _conjuntoId,
            onConjunto: (v) => setState(() => _conjuntoId = v),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _PendientesTab(api: _api, empresaNit: widget.empresaNit, rango: _rango, conjuntoId: _conjuntoId),
                _AgendaTab(api: _api, empresaNit: widget.empresaNit, rango: _rango, conjuntoId: _conjuntoId),
                _AlertasTab(
                  api: _api,
                  empresaNit: widget.empresaNit,
                  rango: _rango,
                  conjuntoId: _conjuntoId,
                  onTotalAltas: (n) {
                    if (n != _alertasAltas) setState(() => _alertasAltas = n);
                  },
                ),
                _ConfiguracionTab(api: _api, empresaNit: widget.empresaNit, editable: _puedeConfigurar),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraFiltrosComunes extends StatelessWidget {
  const _BarraFiltrosComunes({
    required this.rango,
    required this.preset,
    required this.onPreset,
    required this.onElegirRango,
    required this.conjuntos,
    required this.conjuntoId,
    required this.onConjunto,
  });

  final _Rango rango;
  final String preset;
  final ValueChanged<String> onPreset;
  final VoidCallback onElegirRango;
  final List<Conjunto> conjuntos;
  final String? conjuntoId;
  final ValueChanged<String?> onConjunto;

  @override
  Widget build(BuildContext context) {
    const presets = {
      'hoy': 'Hoy',
      'semana': 'Esta semana',
      'proxima': 'Próxima semana',
      '14': '14 días',
      'mes': 'Este mes',
    };
    return Material(
      color: AppTheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final e in presets.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: preset == e.key,
                onSelected: (_) => onPreset(e.key),
              ),
            ActionChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(
                '${RecursoEstilos.fechaCorta.format(rango.desde)} – ${RecursoEstilos.fechaCorta.format(rango.hasta)}',
              ),
              onPressed: onElegirRango,
            ),
            if (conjuntos.isNotEmpty)
              SizedBox(
                width: 300,
                child: SearchableSelectField<String>(
                  label: 'Conjunto',
                  value: conjuntoId,
                  placeholder: 'Todos los conjuntos',
                  clearLabel: 'Todos los conjuntos',
                  prefixIcon: const Icon(Icons.apartment_outlined),
                  options: [
                    for (final c in conjuntos) SearchableSelectOption(value: c.nit, label: c.nombre, subtitle: c.nit),
                  ],
                  onChanged: onConjunto,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ======================================================================
 * Pendientes
 * ====================================================================== */

class _PendientesTab extends StatefulWidget {
  const _PendientesTab({required this.api, required this.empresaNit, required this.rango, required this.conjuntoId});

  final RecursosApi api;
  final String empresaNit;
  final _Rango rango;
  final String? conjuntoId;

  @override
  State<_PendientesTab> createState() => _PendientesTabState();
}

class _PendientesTabState extends State<_PendientesTab> with AutomaticKeepAliveClientMixin {
  NecesidadesResponse? _data;
  bool _cargando = true;
  String? _error;
  ClaseRecurso? _clase;
  String _cobertura = 'SIN_CUBRIR';
  bool _soloObligatorias = false;
  final _buscar = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant _PendientesTab old) {
    super.didUpdateWidget(old);
    if (!old.rango.igual(widget.rango) || old.conjuntoId != widget.conjuntoId) _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await widget.api.necesidades(
        empresaNit: widget.empresaNit,
        desde: widget.rango.desde,
        hasta: widget.rango.hasta,
        conjuntoId: widget.conjuntoId,
        clase: _clase,
        cobertura: _cobertura == 'TODAS' ? null : _cobertura,
        soloObligatorias: _soloObligatorias,
        q: _buscar.text,
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = _data;
    final porDia = <DateTime, List<NecesidadRecursoModel>>{};
    for (final n in data?.necesidades ?? const <NecesidadRecursoModel>[]) {
      porDia.putIfAbsent(_inicioDia(n.tarea.fechaInicio), () => []).add(n);
    }
    final dias = porDia.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<ClaseRecurso?>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: null, label: Text('Todo')),
                  ButtonSegment(value: ClaseRecurso.maquinaria, label: Text('Maquinaria')),
                  ButtonSegment(value: ClaseRecurso.herramienta, label: Text('Herramientas')),
                ],
                selected: {_clase},
                onSelectionChanged: (s) {
                  setState(() => _clase = s.first);
                  _cargar();
                },
              ),
              DropdownButton<String>(
                value: _cobertura,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'SIN_CUBRIR', child: Text('Sin cubrir')),
                  DropdownMenuItem(value: 'PENDIENTE', child: Text('Sin ninguna unidad')),
                  DropdownMenuItem(value: 'PARCIAL', child: Text('Parciales')),
                  DropdownMenuItem(value: 'CUBIERTA', child: Text('Cubiertas')),
                  DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
                ],
                onChanged: (v) {
                  setState(() => _cobertura = v ?? 'SIN_CUBRIR');
                  _cargar();
                },
              ),
              FilterChip(
                label: const Text('Solo obligatorias'),
                selected: _soloObligatorias,
                onSelected: (v) {
                  setState(() => _soloObligatorias = v);
                  _cargar();
                },
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _buscar,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _cargar(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar tarea',
                    suffixIcon: _buscar.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _buscar.clear();
                              _cargar();
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data != null)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                EstadoPill(texto: '${data.resumen.pendientes} sin asignar', color: AppTheme.red),
                EstadoPill(texto: '${data.resumen.parciales} parciales', color: const Color(0xFFB7791F)),
                EstadoPill(texto: '${data.resumen.cubiertas} cubiertas', color: AppTheme.green),
                if (data.resumen.conConflicto > 0)
                  EstadoPill(
                    texto: '${data.resumen.conConflicto} con conflicto',
                    color: AppTheme.red,
                    icono: Icons.warning_amber_rounded,
                  ),
              ],
            ),
          const SizedBox(height: 8),
          if (_cargando && data == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            _ErrorBox(mensaje: _error!, onRetry: _cargar)
          else if (dias.isEmpty)
            const _Vacio(
              icono: Icons.task_alt,
              titulo: 'No hay necesidades con estos filtros',
              detalle:
                  'Las necesidades aparecen cuando se publica un cronograma con preventivas que piden maquinaria o herramientas.',
            )
          else
            for (final dia in dias) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  RecursoEstilos.capitalizar(RecursoEstilos.diaLargo.format(dia)),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryDark),
                ),
              ),
              for (final n in porDia[dia]!)
                NecesidadRecursoCard(
                  necesidad: n,
                  api: widget.api,
                  empresaNit: widget.empresaNit,
                  puedeAsignar: _puedeAsignarClase(n.clase),
                  onCambio: _cargar,
                ),
            ],
        ],
      ),
    );
  }
}

/* ======================================================================
 * Agenda
 * ====================================================================== */

class _AgendaTab extends StatefulWidget {
  const _AgendaTab({required this.api, required this.empresaNit, required this.rango, required this.conjuntoId});

  final RecursosApi api;
  final String empresaNit;
  final _Rango rango;
  final String? conjuntoId;

  @override
  State<_AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<_AgendaTab> with AutomaticKeepAliveClientMixin {
  AgendaRecursosResponse? _data;
  bool _cargando = true;
  String? _error;
  final _buscar = TextEditingController();
  ClaseRecurso? _clase;
  EstadoDiaRecurso? _estado;
  String? _propietario;
  bool _soloConReservas = false;
  bool? _timeline;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant _AgendaTab old) {
    super.didUpdateWidget(old);
    if (!old.rango.igual(widget.rango) || old.conjuntoId != widget.conjuntoId) _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await widget.api.agenda(
        empresaNit: widget.empresaNit,
        desde: widget.rango.desde,
        hasta: widget.rango.hasta,
        q: _buscar.text,
        clase: _clase,
        conjuntoId: widget.conjuntoId,
        estado: _estado,
        propietario: _propietario,
        soloConReservas: _soloConReservas,
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _tapReserva(UnidadAgendaModel u, ReservaRecursoModel r) async {
    final cambio = await mostrarDetalleReserva(
      context,
      api: widget.api,
      reserva: r,
      empresaNit: widget.empresaNit,
      puedeAsignar: _puedeAsignarClase(u.clase),
    );
    if (cambio) _cargar();
  }

  Future<void> _tapUnidad(UnidadAgendaModel u) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(u.etiqueta, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '${u.tipoNombre} · ${RecursoEstilos.etiquetaEstadoInventario(u.estado)} · ahora: ${u.estadoActual.etiqueta}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historial de uso'),
              onTap: () => Navigator.of(ctx).pop('historial'),
            ),
            if (_puedeAsignarClase(u.clase))
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Programar mantenimiento'),
                subtitle: const Text('Bloquea la unidad esos días para que nadie la reserve.'),
                onTap: () => Navigator.of(ctx).pop('mantenimiento'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'historial') {
      await mostrarHistorialUnidad(context, api: widget.api, clase: u.clase, unidadId: u.id, empresaNit: widget.empresaNit);
    } else if (accion == 'mantenimiento') {
      final ok = await _programarMantenimiento(u);
      if (ok) _cargar();
    }
  }

  Future<bool> _programarMantenimiento(UnidadAgendaModel u) async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: _inicioDia(DateTime.now()),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Días de mantenimiento de ${u.etiqueta}',
    );
    if (rango == null || !mounted) return false;
    final controller = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motivo del mantenimiento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(hintText: 'Ej.: cambio de aceite, revisión de motor'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 3) Navigator.of(ctx).pop(controller.text.trim());
            },
            child: const Text('Programar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (motivo == null || !mounted) return false;
    try {
      await widget.api.bloquearMantenimiento(
        empresaNit: widget.empresaNit,
        clase: u.clase,
        unidadId: u.id,
        desde: _inicioDia(rango.start),
        hasta: _inicioDia(rango.end).add(const Duration(days: 1)),
        motivo: motivo,
      );
      if (mounted) AppFeedback.showInfo(context, message: 'Mantenimiento programado para ${u.etiqueta}.');
      return true;
    } catch (e) {
      if (mounted) AppFeedback.showError(context, message: AppError.messageOf(e));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ancho = MediaQuery.sizeOf(context).width;
    final usarTimeline = _timeline ?? ancho >= 900;
    final data = _data;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _buscar,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _cargar(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar: Pulidora, PUL-02, marca…',
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _cargar),
                  ),
                ),
              ),
              SegmentedButton<ClaseRecurso?>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: null, label: Text('Todo')),
                  ButtonSegment(value: ClaseRecurso.maquinaria, label: Text('Maquinaria')),
                  ButtonSegment(value: ClaseRecurso.herramienta, label: Text('Herramientas')),
                ],
                selected: {_clase},
                onSelectionChanged: (s) {
                  setState(() => _clase = s.first);
                  _cargar();
                },
              ),
              DropdownButton<EstadoDiaRecurso?>(
                value: _estado,
                hint: const Text('Cualquier estado'),
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Cualquier estado')),
                  for (final e in EstadoDiaRecurso.values) DropdownMenuItem(value: e, child: Text(e.etiqueta)),
                ],
                onChanged: (v) {
                  setState(() => _estado = v);
                  _cargar();
                },
              ),
              DropdownButton<String?>(
                value: _propietario,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Empresa y conjuntos')),
                  DropdownMenuItem(value: 'EMPRESA', child: Text('Solo de la empresa')),
                  DropdownMenuItem(value: 'CONJUNTO', child: Text('Solo de conjuntos')),
                ],
                onChanged: (v) {
                  setState(() => _propietario = v);
                  _cargar();
                },
              ),
              FilterChip(
                label: const Text('Solo con reservas'),
                selected: _soloConReservas,
                onSelected: (v) {
                  setState(() => _soloConReservas = v);
                  _cargar();
                },
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, icon: Icon(Icons.view_timeline_outlined), label: Text('Línea de tiempo')),
                  ButtonSegment(value: false, icon: Icon(Icons.view_list_outlined), label: Text('Lista')),
                ],
                selected: {usarTimeline},
                onSelectionChanged: (s) => setState(() => _timeline = s.first),
              ),
            ],
          ),
        ),
        if (usarTimeline)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Align(alignment: Alignment.centerLeft, child: ResourceTimelineLeyenda()),
          ),
        if (_cargando) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null
              ? _ErrorBox(mensaje: _error!, onRetry: _cargar)
              : data == null
                  ? const SizedBox.shrink()
                  : data.grupos.isEmpty
                      ? const _Vacio(
                          icono: Icons.search_off,
                          titulo: 'No hay recursos con estos filtros',
                          detalle: 'Prueba con otro nombre o código, o quita algún filtro.',
                        )
                      : usarTimeline
                          ? ResourceTimeline(
                              grupos: data.grupos,
                              dias: data.dias,
                              onTapReserva: _tapReserva,
                              onTapUnidad: _tapUnidad,
                            )
                          : ResourceListView(
                              grupos: data.grupos,
                              onTapReserva: _tapReserva,
                              onTapUnidad: _tapUnidad,
                              soloDiasConActividad: data.dias.length > 14,
                            ),
        ),
      ],
    );
  }
}

/* ======================================================================
 * Alertas
 * ====================================================================== */

class _AlertasTab extends StatefulWidget {
  const _AlertasTab({
    required this.api,
    required this.empresaNit,
    required this.rango,
    required this.conjuntoId,
    required this.onTotalAltas,
  });

  final RecursosApi api;
  final String empresaNit;
  final _Rango rango;
  final String? conjuntoId;
  final ValueChanged<int> onTotalAltas;

  @override
  State<_AlertasTab> createState() => _AlertasTabState();
}

class _AlertasTabState extends State<_AlertasTab> with AutomaticKeepAliveClientMixin {
  AlertasResponse? _data;
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant _AlertasTab old) {
    super.didUpdateWidget(old);
    if (!old.rango.igual(widget.rango) || old.conjuntoId != widget.conjuntoId) _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Las alertas miran desde hoy (lo pasado ya no se puede corregir).
      final hoy = _inicioDia(DateTime.now());
      final desde = widget.rango.desde.isBefore(hoy) ? hoy : widget.rango.desde;
      final hasta = widget.rango.hasta.isBefore(desde) ? desde : widget.rango.hasta;
      final data = await widget.api.alertas(
        empresaNit: widget.empresaNit,
        desde: desde,
        hasta: hasta,
        conjuntoId: widget.conjuntoId,
      );
      if (!mounted) return;
      setState(() => _data = data);
      widget.onTotalAltas(data.alta);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _accion(AlertaRecursoModel a) async {
    var cambio = false;
    if (a.tipo == 'RECURSO_NO_OPERATIVO' && a.necesidadId != null && a.reservaId != null) {
      cambio = await mostrarAsignarRecursoSheet(
        context,
        necesidadId: a.necesidadId!,
        empresaNit: widget.empresaNit,
        reemplazarReservaId: a.reservaId,
        api: widget.api,
      );
    } else if (a.esNecesidad && a.necesidadId != null) {
      cambio = await mostrarAsignarRecursoSheet(
        context,
        necesidadId: a.necesidadId!,
        empresaNit: widget.empresaNit,
        api: widget.api,
      );
    } else if (a.reservaId != null) {
      cambio = await cancelarReservaPorId(
        context,
        api: widget.api,
        reservaId: a.reservaId!,
        etiqueta: 'la reserva',
        detalle: a.mensaje,
        empresaNit: widget.empresaNit,
      );
    }
    if (cambio) _cargar();
  }

  String _textoAccion(AlertaRecursoModel a) {
    if (a.tipo == 'RECURSO_NO_OPERATIVO') return 'Cambiar unidad';
    if (a.esNecesidad) return 'Asignar';
    return 'Liberar';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = _data;
    final puede = _puedeAsignarAlgo();
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          if (_cargando && data == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            _ErrorBox(mensaje: _error!, onRetry: _cargar)
          else if (data == null || data.alertas.isEmpty)
            const _Vacio(
              icono: Icons.verified_outlined,
              titulo: 'Sin alertas',
              detalle: 'Todas las necesidades obligatorias del periodo tienen recurso y no hay reservas en conflicto.',
            )
          else
            for (final a in data.alertas)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: RecursoEstilos.colorSeveridad(a.severidad).withValues(alpha: 0.4)),
                ),
                child: ListTile(
                  leading: Icon(
                    a.esNecesidad ? Icons.assignment_late_outlined : Icons.warning_amber_rounded,
                    color: RecursoEstilos.colorSeveridad(a.severidad),
                  ),
                  title: Text(a.mensaje),
                  subtitle: Text(RecursoEstilos.capitalizar(RecursoEstilos.diaLargo.format(a.fecha))),
                  trailing: puede && (a.necesidadId != null || a.reservaId != null)
                      ? TextButton(onPressed: () => _accion(a), child: Text(_textoAccion(a)))
                      : null,
                ),
              ),
        ],
      ),
    );
  }
}

/* ======================================================================
 * Configuración logística
 * ====================================================================== */

class _ConfiguracionTab extends StatefulWidget {
  const _ConfiguracionTab({required this.api, required this.empresaNit, required this.editable});

  final RecursosApi api;
  final String empresaNit;
  final bool editable;

  @override
  State<_ConfiguracionTab> createState() => _ConfiguracionTabState();
}

class _ConfiguracionTabState extends State<_ConfiguracionTab> with AutomaticKeepAliveClientMixin {
  static const _nombresDias = {1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 0: 'Dom'};

  Set<int> _dias = {};
  final _margen = TextEditingController();
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _margen.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final c = await widget.api.configuracion(empresaNit: widget.empresaNit);
      if (!mounted) return;
      setState(() {
        _dias = c.diasEntregaRecursos.toSet();
        _margen.text = '${c.margenTrasladoMinutos}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    final margen = int.tryParse(_margen.text.trim());
    if (margen == null || margen < 0 || margen > 1440) {
      AppFeedback.showError(context, message: 'El margen de traslado debe estar entre 0 y 1440 minutos.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.api.guardarConfiguracion(
        empresaNit: widget.empresaNit,
        config: ConfigLogisticaRecursos(diasEntregaRecursos: _dias.toList()..sort(), margenTrasladoMinutos: margen),
      );
      if (mounted) {
        AppFeedback.showInfo(
          context,
          message: 'Configuración guardada. Aplica a las reservas nuevas o que se muevan; las vigentes conservan su ventana.',
        );
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, message: AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorBox(mensaje: _error!, onRetry: _cargar);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Entrega y recogida de recursos de la empresa', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Cuando un conjunto usa un recurso de la empresa, el recurso sale el día de entrega anterior a la tarea '
          'y vuelve el día de recogida siguiente (se saltan festivos). Durante esa ventana ningún otro conjunto '
          'puede reservarlo. Los recursos propios del conjunto solo se bloquean en las horas de la tarea.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            for (final e in _nombresDias.entries)
              FilterChip(
                label: Text(e.value),
                selected: _dias.contains(e.key),
                onSelected: widget.editable
                    ? (v) => setState(() => v ? _dias.add(e.key) : _dias.remove(e.key))
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Margen de traslado', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          _dias.isEmpty
              ? 'Sin días de entrega, la empresa trabaja por horas: cada uso se bloquea con este margen antes y después para el traslado.'
              : 'Solo aplica si no hay días de entrega marcados (modo por horas).',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _margen,
            enabled: widget.editable,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Minutos', suffixText: 'min'),
          ),
        ),
        const SizedBox(height: 20),
        if (widget.editable)
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              style: AppTheme.saveButtonStyle,
              onPressed: _guardando ? null : _guardar,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
          )
        else
          const Text(
            'Solo el gerente o el jefe de operaciones pueden cambiar esta configuración.',
            style: TextStyle(color: AppTheme.textMuted),
          ),
      ],
    );
  }
}

/* ======================================================================
 * Comunes
 * ====================================================================== */

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.mensaje, required this.onRetry});
  final String mensaje;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.red, size: 36),
          const SizedBox(height: 8),
          Text(mensaje, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.icono, required this.titulo, required this.detalle});
  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 44, color: AppTheme.textMuted),
          const SizedBox(height: 10),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(detalle, style: const TextStyle(color: AppTheme.textMuted), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
