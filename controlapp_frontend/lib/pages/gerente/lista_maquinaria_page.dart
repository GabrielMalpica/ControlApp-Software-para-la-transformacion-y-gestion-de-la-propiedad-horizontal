import 'package:flutter/material.dart';

import '../../api/empresa_api.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../model/maquinaria_model.dart';
import '../../service/theme.dart';
import '../../widgets/searchable_select_field.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class ListaMaquinariaGlobalPage extends StatefulWidget {
  final String empresaNit;
  const ListaMaquinariaGlobalPage({super.key, required this.empresaNit});

  @override
  State<ListaMaquinariaGlobalPage> createState() =>
      _ListaMaquinariaGlobalPageState();
}

class _ListaMaquinariaGlobalPageState extends State<ListaMaquinariaGlobalPage> {
  final EmpresaApi _empresaApi = EmpresaApi();
  final GerenteApi _gerenteApi = GerenteApi();

  bool _cargando = false;
  List<MaquinariaResponse> _items = [];

  // filtros
  Conjunto? _conjuntoFiltro;
  List<Conjunto> _conjuntos = [];
  bool _loadingConjuntos = true;
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  EstadoMaquinaria? _estadoFiltro;
  TipoMaquinariaFlutter? _tipoFiltro;
  PropietarioMaquinaria? _propFiltro;
  bool? _disponibleFiltro;

  @override
  void initState() {
    super.initState();
    _cargarConjuntos();
    _cargar();
  }

  Future<void> _cargarConjuntos() async {
    setState(() => _loadingConjuntos = true);
    try {
      final lista = await _gerenteApi.listarConjuntos(); // ya la tienes
      if (!mounted) return;
      setState(() {
        _conjuntos = lista;
        _loadingConjuntos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingConjuntos = false);
    }
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _empresaApi.listarMaquinariaFiltrada(
        conjuntoNit: _conjuntoFiltro?.nit,
        estado: _estadoFiltro,
        tipo: _tipoFiltro,
        propietario: _propFiltro,
        disponible: _disponibleFiltro,
      );
      if (!mounted) return;
      setState(() => _items = data);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al cargar maquinaria: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _limpiarFiltros() {
    setState(() {
      _conjuntoFiltro = null;
      _estadoFiltro = null;
      _tipoFiltro = null;
      _propFiltro = null;
      _disponibleFiltro = null;
    });
    _cargar();
  }

  String _subtitulo(MaquinariaResponse m) {
    final base = '${m.tipo.label} · ${m.estado.label}';

    // Prestada
    if (m.conjuntoNombre != null && m.conjuntoNombre!.trim().isNotEmpty) {
      return '$base · Prestada a ${m.conjuntoNombre}';
    }

    // Propietario (si lo tienes)
    if (m.propietarioTipo == PropietarioMaquinaria.CONJUNTO &&
        m.conjuntoPropietarioId != null) {
      return '$base · Propia del conjunto (${m.conjuntoPropietarioId})';
    }
    if (m.propietarioTipo == PropietarioMaquinaria.EMPRESA) {
      return '$base · Propia de la empresa';
    }

    // Disponible (si lo sigues manejando)
    if (m.disponible != null) {
      return m.disponible! ? '$base · Disponible' : '$base · No disponible';
    }

    return base;
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final filteredItems = _items.where((m) {
      final query = _busqueda.trim().toLowerCase();
      if (query.isEmpty) return true;
      return [
        m.nombre,
        m.marca,
        m.tipo.label,
        m.estado.label,
        m.conjuntoNombre ?? '',
        m.conjuntoPropietarioId ?? '',
      ].join(' ').toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text('Maquinaria', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // 🎛️ Barra de filtros
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _loadingConjuntos
                          ? const LinearProgressIndicator()
                          : SearchableSelectField<Conjunto>(
                              label: 'Filtrar por conjunto (prestada a)',
                              value: _conjuntoFiltro,
                              prefixIcon: const Icon(Icons.apartment_rounded),
                              searchHint: 'Buscar conjunto o NIT',
                              clearLabel: 'Todos',
                              options: _conjuntos
                                  .map(
                                    (c) => SearchableSelectOption<Conjunto>(
                                      value: c,
                                      label: c.nombre,
                                      subtitle: 'NIT: ${c.nit}',
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setState(() => _conjuntoFiltro = v);
                                _cargar();
                              },
                            ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Limpiar filtros',
                      onPressed: _limpiarFiltros,
                      icon: const Icon(Icons.filter_alt_off),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _busquedaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Buscar maquinaria',
                    hintText: 'Nombre, marca, tipo o conjunto',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _busqueda = value),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<EstadoMaquinaria?>(
                        initialValue: _estadoFiltro,
                        decoration: const InputDecoration(
                          labelText: 'Estado',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...EstadoMaquinaria.values.map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(e.label),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _estadoFiltro = v);
                          _cargar();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<TipoMaquinariaFlutter?>(
                        initialValue: _tipoFiltro,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...TipoMaquinariaFlutter.values.map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _tipoFiltro = v);
                          _cargar();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<PropietarioMaquinaria?>(
                        initialValue: _propFiltro,
                        decoration: const InputDecoration(
                          labelText: 'Propietario',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Todos')),
                          DropdownMenuItem(
                            value: PropietarioMaquinaria.EMPRESA,
                            child: Text('Empresa'),
                          ),
                          DropdownMenuItem(
                            value: PropietarioMaquinaria.CONJUNTO,
                            child: Text('Conjunto'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _propFiltro = v);
                          _cargar();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<bool?>(
                        initialValue: _disponibleFiltro,
                        decoration: const InputDecoration(
                          labelText: 'Disponible',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Todos')),
                          DropdownMenuItem(value: true, child: Text('Sí')),
                          DropdownMenuItem(value: false, child: Text('No')),
                        ],
                        onChanged: (v) {
                          setState(() => _disponibleFiltro = v);
                          _cargar();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 📄 Lista
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : filteredItems.isEmpty
                ? const Center(
                    child: Text('No hay maquinaria con esos filtros.'),
                  )
                : ListView.separated(
                    itemCount: filteredItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final m = filteredItems[index];
                      return ListTile(
                        title: Text('${m.nombre} (${m.marca})'),
                        subtitle: Text(_subtitulo(m)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
