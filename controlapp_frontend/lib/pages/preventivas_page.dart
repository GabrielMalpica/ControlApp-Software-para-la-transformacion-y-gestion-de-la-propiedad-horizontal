// lib/pages/preventivas_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/cronograma_preventivas_borrador_page.dart';
import '../api/preventiva_api.dart';
import '../api/gerente_api.dart';
import '../model/preventiva_model.dart' as pm;
import '../model/conjunto_model.dart';
import '../model/usuario_model.dart';
import '../service/theme.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'crear_preventiva_page.dart' as ce;

class PreventivasPage extends StatefulWidget {
  final String nit;

  const PreventivasPage({super.key, required this.nit});

  @override
  State<PreventivasPage> createState() => _PreventivasPageState();
}

class _PreventivasPageState extends State<PreventivasPage> {
  final _preventivaApi = DefinicionPreventivaApi();
  final _gerenteApi = GerenteApi();
  final TextEditingController _busquedaCtrl = TextEditingController();

  bool _cargando = true;
  bool _generando = false;

  Conjunto? _conjunto;
  List<pm.DefinicionPreventiva> _items = [];
  List<Usuario> _operarios = [];
  String _busqueda = '';
  String _filtroFrecuencia = 'TODAS';
  String _filtroUbicacion = 'TODAS';
  String _filtroEstado = 'TODAS';
  String _ordenActual = 'PRIORIDAD_ASC';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);

    Conjunto? conjunto;
    List<pm.DefinicionPreventiva> defs = const [];
    Object? errorConjunto;
    Object? errorDefs;

    try {
      conjunto = await _gerenteApi.obtenerConjunto(widget.nit);
    } catch (e) {
      errorConjunto = e;
    }

    try {
      defs = await _preventivaApi.listarPorConjunto(widget.nit);
    } catch (e) {
      errorDefs = e;
    }

    if (!mounted) return;

    setState(() {
      _conjunto = conjunto;
      _items = defs;
      _operarios = conjunto?.operarios ?? [];
      _cargando = false;
    });

    if (errorDefs != null) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al cargar preventivas: $errorDefs'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (errorConjunto != null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Se cargaron las preventivas, pero no fue posible cargar el detalle del conjunto.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  String _nombreUbicacion(int id) {
    final u = _conjunto?.ubicaciones.firstWhere(
      (x) => x.id == id,
      orElse: () => UbicacionConElementos(
        id: id,
        nombre: 'Ubicación #$id',
        elementos: const [],
      ),
    );
    return u?.nombre ?? 'Ubicación #$id';
  }

  String _nombreElemento(int ubicacionId, int elementoId) {
    final u = _conjunto?.ubicaciones.firstWhere(
      (x) => x.id == ubicacionId,
      orElse: () => UbicacionConElementos(
        id: ubicacionId,
        nombre: '',
        elementos: const [],
      ),
    );
    final el = u?.elementosHoja.firstWhere(
      (e) => e.id == elementoId,
      orElse: () => Elemento(id: elementoId, nombre: 'Elemento #$elementoId'),
    );
    return el?.nombre ?? 'Elemento #$elementoId';
  }

  /// Devuelve la lista de nombres de operarios asignados
  List<String> _operariosDePreventiva(pm.DefinicionPreventiva def) {
    if (def.operariosIds.isEmpty) return [];

    final nombres = <String>[];
    for (final id in def.operariosIds) {
      final op = _operarios.firstWhere(
        (o) => int.tryParse(o.cedula) == id,
        orElse: () => Usuario(
          cedula: id.toString(),
          nombre: 'Operario #$id',
          correo: '',
          rol: '',
          telefono: BigInt.zero,
          fechaNacimiento: DateTime(2000, 1, 1),
        ),
      );
      nombres.add(op.nombre);
    }
    return nombres;
  }

  Color _colorFrecuencia(String frecuencia) {
    switch (frecuencia) {
      case 'DIARIA':
        return Colors.green;
      case 'SEMANAL':
        return Colors.blue;
      case 'MENSUAL':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _textoDimensionDuracion(pm.DefinicionPreventiva def) {
    if (def.duracionMinutosFija != null) {
      return '${def.duracionMinutosFija} minutos (duración fija)';
    }
    if (def.areaNumerica != null && def.unidadCalculo != null) {
      return '${def.areaNumerica} ${def.unidadCalculo} (por rendimiento)';
    }
    return '-';
  }

  bool _coincideBusqueda(pm.DefinicionPreventiva def) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;

    final ubicacion = _nombreUbicacion(def.ubicacionId);
    final elemento = _nombreElemento(def.ubicacionId, def.elementoId);
    final operarios = _operariosDePreventiva(def).join(' ');
    final dimension = _textoDimensionDuracion(def);

    final bag = [
      def.descripcion,
      def.frecuencia,
      ubicacion,
      elemento,
      operarios,
      dimension,
      def.activo ? 'activa' : 'inactiva',
      'prioridad ${def.prioridad}',
    ].join(' ').toLowerCase();

    return bag.contains(q);
  }

  List<pm.DefinicionPreventiva> _itemsFiltrados() {
    final filtrados = _items.where((def) {
      if (!_coincideBusqueda(def)) return false;
      if (_filtroFrecuencia != 'TODAS' && def.frecuencia != _filtroFrecuencia) {
        return false;
      }
      if (_filtroUbicacion != 'TODAS' &&
          _nombreUbicacion(def.ubicacionId) != _filtroUbicacion) {
        return false;
      }
      if (_filtroEstado == 'ACTIVAS' && !def.activo) return false;
      if (_filtroEstado == 'INACTIVAS' && def.activo) return false;
      return true;
    }).toList();

    filtrados.sort((a, b) {
      switch (_ordenActual) {
        case 'PRIORIDAD_DESC':
          final byPriority = b.prioridad.compareTo(a.prioridad);
          if (byPriority != 0) return byPriority;
          return a.descripcion.toLowerCase().compareTo(
            b.descripcion.toLowerCase(),
          );
        case 'DESCRIPCION_ASC':
          return a.descripcion.toLowerCase().compareTo(
            b.descripcion.toLowerCase(),
          );
        case 'UBICACION_ASC':
          final byUbicacion = _nombreUbicacion(a.ubicacionId)
              .toLowerCase()
              .compareTo(_nombreUbicacion(b.ubicacionId).toLowerCase());
          if (byUbicacion != 0) return byUbicacion;
          return _nombreElemento(
            a.ubicacionId,
            a.elementoId,
          ).toLowerCase().compareTo(
            _nombreElemento(b.ubicacionId, b.elementoId).toLowerCase(),
          );
        case 'FRECUENCIA_ASC':
          final byFrecuencia = a.frecuencia.compareTo(b.frecuencia);
          if (byFrecuencia != 0) return byFrecuencia;
          return a.descripcion.toLowerCase().compareTo(
            b.descripcion.toLowerCase(),
          );
        case 'PRIORIDAD_ASC':
        default:
          final byPriority = a.prioridad.compareTo(b.prioridad);
          if (byPriority != 0) return byPriority;
          return a.descripcion.toLowerCase().compareTo(
            b.descripcion.toLowerCase(),
          );
      }
    });

    return filtrados;
  }

  bool _hayFiltrosActivos() {
    return _busqueda.trim().isNotEmpty ||
        _filtroFrecuencia != 'TODAS' ||
        _filtroUbicacion != 'TODAS' ||
        _filtroEstado != 'TODAS' ||
        _ordenActual != 'PRIORIDAD_ASC';
  }

  void _limpiarFiltros() {
    _busquedaCtrl.clear();
    setState(() {
      _busqueda = '';
      _filtroFrecuencia = 'TODAS';
      _filtroUbicacion = 'TODAS';
      _filtroEstado = 'TODAS';
      _ordenActual = 'PRIORIDAD_ASC';
    });
  }

  Widget _buildFiltros(int total, int visibles) {
    final ubicaciones =
        (_conjunto?.ubicaciones.map((u) => u.nombre).toSet().toList() ??
              <String>[])
          ..sort();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar preventiva',
                hintText: 'Actividad, zona, área, operario, prioridad...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busqueda.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() => _busqueda = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (value) => setState(() => _busqueda = value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _filtroUbicacion,
                    decoration: const InputDecoration(
                      labelText: 'Zona / ubicación',
                      border: OutlineInputBorder(),
                    ),
                    items: ['TODAS', ...ubicaciones]
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              item == 'TODAS' ? 'Todas' : item,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _filtroUbicacion = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _filtroFrecuencia,
                    decoration: const InputDecoration(
                      labelText: 'Frecuencia',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['TODAS', 'DIARIA', 'SEMANAL', 'MENSUAL']
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item == 'TODAS' ? 'Todas' : item),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _filtroFrecuencia = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _filtroEstado,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['TODAS', 'ACTIVAS', 'INACTIVAS']
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              item == 'TODAS'
                                  ? 'Todas'
                                  : item == 'ACTIVAS'
                                  ? 'Activas'
                                  : 'Inactivas',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _filtroEstado = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _ordenActual,
                    decoration: const InputDecoration(
                      labelText: 'Ordenar por',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'PRIORIDAD_ASC',
                        child: Text('Prioridad: alta a baja'),
                      ),
                      DropdownMenuItem(
                        value: 'PRIORIDAD_DESC',
                        child: Text('Prioridad: baja a alta'),
                      ),
                      DropdownMenuItem(
                        value: 'DESCRIPCION_ASC',
                        child: Text('Descripción A-Z'),
                      ),
                      DropdownMenuItem(
                        value: 'UBICACION_ASC',
                        child: Text('Zona / área'),
                      ),
                      DropdownMenuItem(
                        value: 'FRECUENCIA_ASC',
                        child: Text('Frecuencia'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _ordenActual = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    visibles == total
                        ? 'Mostrando $total preventivas'
                        : 'Mostrando $visibles de $total preventivas',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_hayFiltrosActivos())
                  TextButton.icon(
                    onPressed: _limpiarFiltros,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Limpiar filtros'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirFormulario({pm.DefinicionPreventiva? inicial}) async {
    if (_conjunto == null) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ce.CrearEditarPreventivaPage(
          nit: widget.nit,
          conjunto: _conjunto!,
          existente: inicial,
        ),
      ),
    );

    if (result == true) {
      await _cargar();
    }
  }

  Future<void> _eliminar(pm.DefinicionPreventiva def) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar tarea preventiva'),
        content: Text('¿Eliminar "${def.descripcion}" del conjunto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _preventivaApi.eliminar(widget.nit, def.id);
      await _cargar();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Definición eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _generarCronogramaBorradorYVer() async {
    final ahora = DateTime.now();
    final anio = ahora.year;
    final mes = ahora.month;

    setState(() => _generando = true);
    try {
      await _preventivaApi.generarCronogramaMensual(
        nit: widget.nit,
        anio: anio,
        mes: mes,
        tamanoBloqueMinutos: 60,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CronogramaPreventivasBorradorPage(
            nit: widget.nit,
            anio: anio,
            mes: mes,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al generar cronograma borrador: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final visibles = _itemsFiltrados();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: primary,
        title: Text(
          'Tareas preventivas - ${widget.nit}',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _generando ? null : _generarCronogramaBorradorYVer,
            icon: _generando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.calendar_view_month),
            tooltip: 'Generar cronograma borrador',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Text(
                'No hay tareas preventivas definidas para este conjunto.',
              ),
            )
          : Column(
              children: [
                _buildFiltros(_items.length, visibles.length),
                Expanded(
                  child: visibles.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No hay preventivas que coincidan con la búsqueda o los filtros seleccionados.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: visibles.length,
                          itemBuilder: (context, index) {
                            final def = visibles[index];
                            final ubicacionNombre = _nombreUbicacion(
                              def.ubicacionId,
                            );
                            final elementoNombre = _nombreElemento(
                              def.ubicacionId,
                              def.elementoId,
                            );
                            final nombresOps = _operariosDePreventiva(def);
                            final textoOps = nombresOps.isEmpty
                                ? 'Sin operarios asignados'
                                : nombresOps.join(', ');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 3,
                              child: ListTile(
                                onTap: () => _abrirFormulario(inicial: def),
                                contentPadding: const EdgeInsets.all(16),
                                leading: Icon(
                                  def.activo
                                      ? Icons.rule_folder
                                      : Icons.rule_folder_outlined,
                                  color: _colorFrecuencia(def.frecuencia),
                                  size: 32,
                                ),
                                title: Text(
                                  def.descripcion,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '📍 $ubicacionNombre · $elementoNombre',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '⏱ Dimensión / duración: ${_textoDimensionDuracion(def)}',
                                      ),
                                      if (def.consumoPrincipalPorUnidad !=
                                              null &&
                                          def.unidadCalculo != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            '🧴 Consumo principal: '
                                            '${def.consumoPrincipalPorUnidad} por ${def.unidadCalculo}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text('👷 Operarios: $textoOps'),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.repeat,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                def.frecuencia,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: _colorFrecuencia(
                                                    def.frecuencia,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.flag_outlined,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Prioridad ${def.prioridad}',
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                def.activo
                                                    ? Icons.check_circle
                                                    : Icons.pause_circle_filled,
                                                size: 16,
                                                color: def.activo
                                                    ? Colors.green
                                                    : Colors.orange,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                def.activo
                                                    ? 'Activa'
                                                    : 'Inactiva',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _eliminar(def),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
