// lib/pages/preventivas_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/cronograma_preventivas_borrador_page.dart';
import '../api/preventiva_api.dart';
import '../api/gerente_api.dart';
import '../model/preventiva_model.dart' as pm;
import '../model/conjunto_model.dart';
import '../model/usuario_model.dart';
import '../service/theme.dart';
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

  bool _cargando = true;
  bool _generando = false;

  Conjunto? _conjunto;
  List<pm.DefinicionPreventiva> _items = [];
  List<Usuario> _operarios = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final conjunto = await _gerenteApi.obtenerConjunto(widget.nit);
      final defs = await _preventivaApi.listarPorConjunto(widget.nit);

      setState(() {
        _conjunto = conjunto;
        _items = defs;
        _operarios = conjunto.operarios;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar preventivas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
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
    final el = u?.elementos.firstWhere(
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
    if (def.duracionHorasFija != null) {
      return '${def.duracionHorasFija} h (duración fija)';
    }
    if (def.areaNumerica != null && def.unidadCalculo != null) {
      return '${def.areaNumerica} ${def.unidadCalculo} (por rendimiento)';
    }
    return '-';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Definición eliminada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
        tamanoBloqueHoras: 1,
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
      ScaffoldMessenger.of(context).showSnackBar(
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final def = _items[index];
                final ubicacionNombre = _nombreUbicacion(def.ubicacionId);
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
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📍 $ubicacionNombre · $elementoNombre'),
                          const SizedBox(height: 4),
                          Text(
                            '⏱ Dimensión / duración: ${_textoDimensionDuracion(def)}',
                          ),
                          if (def.consumoPrincipalPorUnidad != null &&
                              def.unidadCalculo != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '🧴 Consumo principal: '
                                '${def.consumoPrincipalPorUnidad} por ${def.unidadCalculo}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text('👷 Operarios: $textoOps'),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.repeat, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                def.frecuencia,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _colorFrecuencia(def.frecuencia),
                                ),
                              ),
                              const SizedBox(width: 12),
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
                                def.activo ? 'Activa' : 'Inactiva',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _eliminar(def),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
