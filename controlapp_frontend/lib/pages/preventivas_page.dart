// lib/pages/preventivas_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/cronograma_preventivas_borrador_page.dart';
import '../api/catalogo_operativo_api.dart';
import '../api/preventiva_api.dart';
import '../api/gerente_api.dart';
import '../model/catalogo_operativo_model.dart';
import '../model/preventiva_model.dart' as pm;
import '../model/conjunto_model.dart';
import '../model/usuario_model.dart';
import '../service/app_error.dart';
import '../service/theme.dart';
import '../utils/frecuencia_utils.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'crear_preventiva_page.dart' as ce;
import 'package:flutter_application_1/widgets/skeleton.dart';

class PreventivasPage extends StatefulWidget {
  final String nit;

  const PreventivasPage({super.key, required this.nit});

  @override
  State<PreventivasPage> createState() => _PreventivasPageState();
}

class _PreventivasPageState extends State<PreventivasPage> {
  final _preventivaApi = DefinicionPreventivaApi();
  final _gerenteApi = GerenteApi();
  final _catalogoApi = CatalogoOperativoApi();
  final TextEditingController _busquedaCtrl = TextEditingController();

  bool _cargando = true;
  bool _generando = false;

  /// Modo seleccion multiple para borrar varias preventivas de una vez.
  bool _modoSeleccion = false;
  bool _eliminandoLote = false;
  final Set<int> _seleccionadas = <int>{};

  Conjunto? _conjunto;
  List<CategoriaTarea> _categorias = [];
  List<pm.DefinicionPreventiva> _items = [];
  List<Usuario> _operarios = [];
  String _busqueda = '';
  String _filtroFrecuencia = 'TODAS';
  String _filtroUbicacion = 'TODAS';
  String _filtroEstado = 'TODAS';
  String _filtroOperario = 'TODOS';
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

    // Las categorías solo enriquecen la lista: si fallan, se sigue sin ellas.
    List<CategoriaTarea> categorias = const [];
    try {
      categorias = await _catalogoApi.listarCategorias();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _conjunto = conjunto;
      _categorias = categorias;
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
  /// Quién ejecuta la preventiva de verdad. Igual que el generador: si tiene
  /// plazas (necesidades) vinculadas, manda quien ocupa cada plaza y los
  /// operarios directos solo son el respaldo. Antes se mostraban siempre los
  /// directos, así que al editar por plaza la lista seguía con los viejos.
  List<String> _operariosDePreventiva(pm.DefinicionPreventiva def) {
    if (def.necesidadesIds.isNotEmpty) {
      final plazas = _conjunto?.necesidades ?? const [];
      final nombres = <String>[];
      for (final id in def.necesidadesIds) {
        final plaza = plazas.where((n) => n.id == id).firstOrNull;
        if (plaza == null) {
          nombres.add('Plaza #$id');
          continue;
        }
        final nombre = plaza.operarioNombre?.trim() ?? '';
        nombres.add(
          nombre.isNotEmpty ? nombre : 'Plaza vacante (${plaza.etiqueta})',
        );
      }
      return nombres;
    }
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

  List<String> _operariosDisponibles() {
    final nombres =
        _items
            .expand(_operariosDePreventiva)
            .map((nombre) => nombre.trim())
            .where((nombre) => nombre.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return nombres;
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
      if (_filtroOperario != 'TODOS') {
        final operarios = _operariosDePreventiva(def)
            .map((nombre) => nombre.trim().toLowerCase())
            .where((nombre) => nombre.isNotEmpty);
        if (!operarios.contains(_filtroOperario.trim().toLowerCase())) {
          return false;
        }
      }
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
        _filtroOperario != 'TODOS' ||
        _ordenActual != 'PRIORIDAD_ASC';
  }

  void _limpiarFiltros() {
    _busquedaCtrl.clear();
    setState(() {
      _busqueda = '';
      _filtroFrecuencia = 'TODAS';
      _filtroUbicacion = 'TODAS';
      _filtroEstado = 'TODAS';
      _filtroOperario = 'TODOS';
      _ordenActual = 'PRIORIDAD_ASC';
    });
  }

  Widget _buildFiltros(int total, int visibles) {
    final ubicaciones =
        (_conjunto?.ubicaciones.map((u) => u.nombre).toSet().toList() ??
              <String>[])
          ..sort();
    final operarios = _operariosDisponibles();

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
                    items: ['TODAS', ...frecuenciasPreventivas]
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
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _filtroOperario,
                    decoration: const InputDecoration(
                      labelText: 'Operario',
                      border: OutlineInputBorder(),
                    ),
                    items: ['TODOS', ...operarios]
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              item == 'TODOS' ? 'Todos' : item,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _filtroOperario = value);
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

  void _entrarModoSeleccion(pm.DefinicionPreventiva def) {
    setState(() {
      _modoSeleccion = true;
      _seleccionadas
        ..clear()
        ..add(def.id);
    });
  }

  void _salirModoSeleccion() {
    setState(() {
      _modoSeleccion = false;
      _seleccionadas.clear();
    });
  }

  void _alternarSeleccion(pm.DefinicionPreventiva def) {
    setState(() {
      if (!_seleccionadas.remove(def.id)) {
        _seleccionadas.add(def.id);
      }
      // Al desmarcar la ultima se sale del modo seleccion.
      if (_seleccionadas.isEmpty) _modoSeleccion = false;
    });
  }

  void _seleccionarTodasVisibles(List<pm.DefinicionPreventiva> visibles) {
    setState(() {
      final ids = visibles.map((def) => def.id).toSet();
      final yaTodas = _seleccionadas.containsAll(ids);
      _seleccionadas
        ..clear()
        ..addAll(yaTodas ? const <int>[] : ids);
      if (_seleccionadas.isEmpty) _modoSeleccion = false;
    });
  }

  Future<void> _eliminarSeleccionadas() async {
    if (_seleccionadas.isEmpty || _eliminandoLote) return;

    final total = _seleccionadas.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar preventivas'),
        content: Text(
          total == 1
              ? '¿Eliminar la preventiva seleccionada?'
              : '¿Eliminar las $total preventivas seleccionadas?',
        ),
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

    setState(() => _eliminandoLote = true);
    try {
      final res = await _preventivaApi.eliminarVarias(
        widget.nit,
        _seleccionadas.toList(),
      );
      final eliminadas = (res['eliminadas'] as num?)?.toInt() ?? total;
      await _cargar();
      if (!mounted) return;
      _salirModoSeleccion();
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            eliminadas == 1
                ? 'Preventiva eliminada'
                : '$eliminadas preventivas eliminadas',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(AppError.messageOf(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _eliminandoLote = false);
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
    final destino = await showDialog<DateTime>(
      context: context,
      builder: (_) {
        final ahora = DateTime.now();
        final siguiente = DateTime(ahora.year, ahora.month + 1, 1);
        return AlertDialog(
          title: const Text('Generar borrador'),
          content: const Text(
            '¿Quieres generar el cronograma del mes actual o del mes siguiente?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(DateTime(ahora.year, ahora.month, 1)),
              child: const Text('Mes actual'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(siguiente),
              child: const Text('Mes siguiente'),
            ),
          ],
        );
      },
    );

    if (destino == null) return;

    final anio = destino.year;
    final mes = destino.month;

    setState(() => _generando = true);
    try {
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

  /* ===================== CATEGORÍA Y ORDEN INTERNO ===================== */

  void _mostrarMensaje(String mensaje, {bool error = false}) {
    if (!mounted) return;
    if (error) {
      AppFeedback.showError(context, message: mensaje);
    } else {
      AppFeedback.showInfo(context, message: mensaje);
    }
  }

  String _resumenAsignacion(AsignacionCategoriaResultado r) {
    final b = StringBuffer('${r.actualizadas} preventiva(s) actualizada(s).');
    if (r.omitidas.isNotEmpty) {
      b.write('\n\nNo se cambiaron ${r.omitidas.length}:');
      for (final o in r.omitidas.take(8)) {
        b.write('\n• ${o.descripcion}: ${o.motivo}');
      }
      if (r.omitidas.length > 8) b.write('\n• …');
    }
    return b.toString();
  }

  /// Asigna (o quita) la categoría a las preventivas seleccionadas.
  Future<void> _asignarCategoriaSeleccionadas() async {
    if (_seleccionadas.isEmpty) return;
    final activas = _categorias.where((c) => c.activa).toList();
    if (activas.isEmpty) {
      _mostrarMensaje(
        'Primero crea categorías en Atajos → Categorías y perfiles.',
      );
      return;
    }
    int? elegida;
    var quitar = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Categoría para ${_seleccionadas.length} preventiva(s)'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in activas)
                  ListTile(
                    dense: true,
                    title: Text(c.nombre),
                    selected: !quitar && elegida == c.id,
                    trailing: !quitar && elegida == c.id
                        ? const Icon(Icons.check, color: AppTheme.primary)
                        : null,
                    onTap: () => setLocal(() {
                      elegida = c.id;
                      quitar = false;
                    }),
                  ),
                const Divider(),
                ListTile(
                  dense: true,
                  title: const Text('Quitar categoría'),
                  selected: quitar,
                  trailing: quitar
                      ? const Icon(Icons.check, color: AppTheme.primary)
                      : null,
                  onTap: () => setLocal(() {
                    quitar = true;
                    elegida = null;
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: (elegida != null || quitar)
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await _catalogoApi.asignarCategoriaLote(
        widget.nit,
        ids: _seleccionadas.toList(),
        categoriaId: quitar ? null : elegida,
      );
      _salirModoSeleccion();
      await _cargar();
      _mostrarMensaje(_resumenAsignacion(r));
    } catch (e) {
      _mostrarMensaje(
        AppError.messageOf(e, fallback: 'No se pudo asignar la categoría.'),
        error: true,
      );
    }
  }

  /// Propone categorías por palabras clave; solo guarda lo que se confirme.
  Future<void> _sugerirCategorias() async {
    SugerenciasCategoriaResultado resultado;
    try {
      resultado = await _catalogoApi.sugerirCategorias(widget.nit);
    } catch (e) {
      _mostrarMensaje(
        AppError.messageOf(
          e,
          fallback: 'No se pudieron calcular las sugerencias.',
        ),
        error: true,
      );
      return;
    }
    if (!mounted) return;
    if (resultado.sugerencias.isEmpty) {
      _mostrarMensaje(
        resultado.sinSugerencia.isEmpty
            ? 'Todas las preventivas activas ya tienen categoría.'
            : 'No hay sugerencias: ${resultado.sinSugerencia.length} preventiva(s) '
                  'sin categoría no coinciden con ninguna palabra clave. '
                  'Asígnalas manualmente (mantén pulsada una preventiva para seleccionarla).',
      );
      return;
    }
    final aceptadas = <int>{...resultado.sugerencias.map((x) => x.defId)};
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Categorías sugeridas'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Revisa la propuesta: solo se guardan las marcadas.'
                  '${resultado.sinSugerencia.isEmpty ? '' : ' ${resultado.sinSugerencia.length} no tienen sugerencia.'}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final sug in resultado.sugerencias)
                        CheckboxListTile(
                          dense: true,
                          value: aceptadas.contains(sug.defId),
                          title: Text(sug.descripcion),
                          subtitle: Text(
                            '→ ${sug.categoriaNombre}'
                            '${sug.coincidencias.isEmpty ? '' : ' (${sug.coincidencias.join(', ')})'}',
                          ),
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              aceptadas.add(sug.defId);
                            } else {
                              aceptadas.remove(sug.defId);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: aceptadas.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text('Guardar ${aceptadas.length}'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final porCategoria = <int, List<int>>{};
    for (final sug in resultado.sugerencias) {
      if (aceptadas.contains(sug.defId)) {
        porCategoria.putIfAbsent(sug.categoriaId, () => []).add(sug.defId);
      }
    }
    var actualizadas = 0;
    final omitidas = <({int id, String descripcion, String motivo})>[];
    try {
      for (final entry in porCategoria.entries) {
        final r = await _catalogoApi.asignarCategoriaLote(
          widget.nit,
          ids: entry.value,
          categoriaId: entry.key,
        );
        actualizadas += r.actualizadas;
        omitidas.addAll(r.omitidas);
      }
    } catch (e) {
      _mostrarMensaje(
        AppError.messageOf(
          e,
          fallback: 'No se pudieron guardar las categorías.',
        ),
        error: true,
      );
    }
    await _cargar();
    _mostrarMensaje(
      _resumenAsignacion(
        AsignacionCategoriaResultado(
          actualizadas: actualizadas,
          omitidas: omitidas,
        ),
      ),
    );
  }

  /// Ordena (arrastrando) las preventivas de una categoría: 1 = primero del día.
  Future<void> _ordenarEnCategoria() async {
    final porCategoria = <int, List<pm.DefinicionPreventiva>>{};
    for (final d in _items) {
      final id = d.categoriaId;
      if (id != null) porCategoria.putIfAbsent(id, () => []).add(d);
    }
    final candidatas = _categorias
        .where((c) => (porCategoria[c.id]?.length ?? 0) >= 2)
        .toList();
    if (candidatas.isEmpty) {
      _mostrarMensaje(
        'No hay categorías con 2 o más preventivas en este conjunto. '
        'Asigna categorías primero.',
      );
      return;
    }
    final categoria = await showDialog<CategoriaTarea>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('¿Qué categoría quieres ordenar?'),
        children: [
          for (final c in candidatas)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, c),
              child: Text('${c.nombre} (${porCategoria[c.id]!.length})'),
            ),
        ],
      ),
    );
    if (categoria == null || !mounted) return;

    final lista = [...porCategoria[categoria.id]!]
      ..sort((a, b) {
        final oa = a.ordenEnCategoria ?? 1 << 30;
        final ob = b.ordenEnCategoria ?? 1 << 30;
        return oa != ob
            ? oa.compareTo(ob)
            : a.prioridad != b.prioridad
            ? a.prioridad.compareTo(b.prioridad)
            : a.id.compareTo(b.id);
      });
    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Orden en ${categoria.nombre}'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: Column(
              children: [
                const Text(
                  'Arrastra: la primera se programa antes dentro del día.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: lista.length,
                    onReorderItem: (oldIndex, newIndex) => setLocal(() {
                      lista.insert(newIndex, lista.removeAt(oldIndex));
                    }),
                    itemBuilder: (context, i) => ListTile(
                      key: ValueKey('orden_${lista[i].id}'),
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      title: Text(lista[i].descripcion),
                      subtitle: Text(
                        'Prioridad de selección ${lista[i].prioridad}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar orden'),
            ),
          ],
        ),
      ),
    );
    if (guardar != true) return;
    try {
      await _catalogoApi.ordenarEnCategoria(
        widget.nit,
        categoriaId: categoria.id,
        ids: lista.map((d) => d.id).toList(),
      );
      await _cargar();
      _mostrarMensaje('Orden guardado.');
    } catch (e) {
      _mostrarMensaje(
        AppError.messageOf(e, fallback: 'No se pudo guardar el orden.'),
        error: true,
      );
    }
  }

  /// Chip de categoría (y orden interno) de una preventiva.
  Widget _chipCategoria(pm.DefinicionPreventiva def) {
    final categoria = def.categoria;
    if (categoria == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.category_outlined, size: 14, color: Colors.black45),
          SizedBox(width: 4),
          Text(
            'Sin categoría',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );
    }
    final hex = categoria.colorHex?.replaceFirst('#', '');
    final color = hex != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)
        ? Color(int.parse('FF$hex', radix: 16))
        : AppTheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.category, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          def.ordenEnCategoria != null
              ? '${categoria.nombre} · #${def.ordenEnCategoria}'
              : categoria.nombre,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final visibles = _itemsFiltrados();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _modoSeleccion
          ? AppBar(
              backgroundColor: primary,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Salir de la selección',
                onPressed: _salirModoSeleccion,
              ),
              title: Text(
                '${_seleccionadas.length} seleccionadas',
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                IconButton(
                  onPressed: visibles.isEmpty
                      ? null
                      : () => _seleccionarTodasVisibles(visibles),
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Seleccionar/deseleccionar todas las visibles',
                ),
                IconButton(
                  onPressed: _eliminandoLote
                      ? null
                      : _asignarCategoriaSeleccionadas,
                  icon: const Icon(Icons.category_outlined),
                  tooltip: 'Asignar categoría a las seleccionadas',
                ),
                IconButton(
                  onPressed: _eliminandoLote ? null : _eliminarSeleccionadas,
                  icon: _eliminandoLote
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.delete),
                  tooltip: 'Eliminar seleccionadas',
                ),
              ],
            )
          : AppBar(
              backgroundColor: primary,
              title: Text(
                'Tareas preventivas - ${widget.nit}',
                style: const TextStyle(color: Colors.white),
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
                PopupMenuButton<String>(
                  tooltip: 'Categorías y orden del día',
                  icon: const Icon(Icons.category_outlined),
                  onSelected: (valor) {
                    if (valor == 'sugerir') _sugerirCategorias();
                    if (valor == 'ordenar') _ordenarEnCategoria();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'sugerir',
                      child: Text('Sugerir categorías'),
                    ),
                    PopupMenuItem(
                      value: 'ordenar',
                      child: Text('Ordenar dentro de una categoría'),
                    ),
                  ],
                ),
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
          ? const SkeletonList()
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

                            final seleccionada = _seleccionadas.contains(
                              def.id,
                            );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: seleccionada
                                    ? BorderSide(color: primary, width: 2)
                                    : BorderSide.none,
                              ),
                              elevation: 3,
                              child: ListTile(
                                selected: seleccionada,
                                selectedTileColor: primary.withValues(
                                  alpha: 0.06,
                                ),
                                onLongPress: () => _entrarModoSeleccion(def),
                                onTap: () => _modoSeleccion
                                    ? _alternarSeleccion(def)
                                    : _abrirFormulario(inicial: def),
                                contentPadding: const EdgeInsets.all(16),
                                leading: _modoSeleccion
                                    ? Checkbox(
                                        value: seleccionada,
                                        onChanged: (_) =>
                                            _alternarSeleccion(def),
                                      )
                                    : Icon(
                                        def.activo
                                            ? Icons.rule_folder
                                            : Icons.rule_folder_outlined,
                                        color: colorFrecuencia(def.frecuencia),
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
                                                etiquetaFrecuencia(
                                                  def.frecuencia,
                                                  diaSemana:
                                                      def.diaSemanaProgramado,
                                                  diaMes: def.diaMesProgramado,
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: colorFrecuencia(
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
                                          _chipCategoria(def),
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
