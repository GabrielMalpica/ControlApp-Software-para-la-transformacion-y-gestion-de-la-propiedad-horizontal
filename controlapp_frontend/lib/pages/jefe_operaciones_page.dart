import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';

import '../service/theme.dart';
import 'maquinaria_page.dart';
import 'inventario_page.dart';
import 'crear_tarea_page.dart';
import 'tareas_page.dart';
import 'solicitudes_page.dart';
import 'cronograma_page.dart';
import 'crear_cronograma_page.dart';

class JefeOperacionesPage extends StatefulWidget {
  const JefeOperacionesPage({super.key});

  @override
  State<JefeOperacionesPage> createState() => _JefeOperacionesPageState();
}

class _JefeOperacionesPageState extends State<JefeOperacionesPage> {
  final GerenteApi _api = GerenteApi();

  List<Conjunto> _conjuntos = [];
  String? _conjuntoSeleccionadoNit;

  bool _loading = true;
  String? _error;

  Conjunto? get _conjuntoSeleccionado {
    if (_conjuntoSeleccionadoNit == null) return null;
    try {
      return _conjuntos.firstWhere((c) => c.nit == _conjuntoSeleccionadoNit);
    } catch (_) {
      return _conjuntos.isNotEmpty ? _conjuntos.first : null;
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarConjuntos();
  }

  Future<void> _cargarConjuntos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final lista = await _api.listarConjuntos();
      setState(() {
        _conjuntos = lista;
        _conjuntoSeleccionadoNit = lista.isNotEmpty ? lista.first.nit : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 🔹 Tarjeta simple
  Widget _simpleCard(
    String title,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black12.withOpacity(0.05), blurRadius: 5),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 Atajos (usa el NIT seleccionado)
  Widget _atajos(String nit) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12.withOpacity(0.05), blurRadius: 5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Atajos",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CrearTareaPage(nit: nit)),
                  );
                },
                icon: const Icon(Icons.assignment_add),
                label: const Text("Crear Tarea"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CrearCronogramaPage(nit: nit),
                    ),
                  );
                },
                icon: const Icon(Icons.calendar_today),
                label: const Text("Crear Cronograma"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(child: Text("Error cargando conjuntos: $_error"));
    }

    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) {
      return const Center(
        child: Text(
          "No hay conjuntos disponibles.\nPide al gerente que registre/asigne conjuntos.",
          textAlign: TextAlign.center,
        ),
      );
    }

    final nit = conjunto.nit;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Selector tipo gerente (más bonito que el Row simple)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.apartment, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Conjunto seleccionado",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          conjunto.nombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text("NIT: $nit", style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  DropdownButton<String>(
                    value: _conjuntoSeleccionadoNit,
                    underline: const SizedBox.shrink(),
                    items: _conjuntos
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.nit,
                            child: Text(
                              c.nombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _conjuntoSeleccionadoNit = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _simpleCard(
                "Tareas",
                AppTheme.green,
                Icons.assignment,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TareasPage(nit: nit)),
                  );
                },
              ),
              _simpleCard(
                "Solicitudes",
                AppTheme.primary,
                Icons.pending_actions,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SolicitudesPage(nit: nit),
                    ),
                  );
                },
              ),
              _simpleCard(
                "Maquinaria",
                AppTheme.red,
                Icons.precision_manufacturing,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MaquinariaPage(nit: nit)),
                  );
                },
              ),
              _simpleCard(
                "Inventario",
                AppTheme.yellow,
                Icons.inventory,
                onTap: () {
                  // ✅ FIX: inventario usa NIT del conjunto + empresaId
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InventarioPage(
                        nit: nit,
                        empresaId: AppConstants.empresaNit,
                      ),
                    ),
                  );
                },
              ),
              _simpleCard(
                "Cronograma",
                Colors.purple,
                Icons.calendar_month,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CronogramaPage(nit: nit, )),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 20),
          _atajos(nit),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Panel Jefe de Operaciones",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: "Recargar conjuntos",
            onPressed: _cargarConjuntos,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
