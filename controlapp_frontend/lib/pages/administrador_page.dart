import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/administrador_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';
import '../service/theme.dart';
import 'inventario_page.dart';

class AdministradorPage extends StatefulWidget {
  const AdministradorPage({super.key});

  @override
  State<AdministradorPage> createState() => _AdministradorPageState();
}

class _AdministradorPageState extends State<AdministradorPage> {
  final AdministradorApi _api = AdministradorApi();
  final SessionService _sessionService = SessionService();

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
      final adminId = await _sessionService.getUserId();
      final lista = await _api.listarMisConjuntos(adminId!);
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

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(child: Text("Error cargando conjuntos: $_error"));
    }

    if (_conjuntoSeleccionado == null) {
      return const Center(
        child: Text(
          "No tienes conjuntos asignados.\nPídele al gerente que te asigne uno.",
          textAlign: TextAlign.center,
        ),
      );
    }

    final conjunto = _conjuntoSeleccionado!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Selector de conjunto estilo gerente
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
                        Text(
                          "NIT: ${conjunto.nit}",
                          style: const TextStyle(fontSize: 12),
                        ),
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
                    onChanged: (v) {
                      setState(() => _conjuntoSeleccionadoNit = v);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ✅ Acciones del admin (por ahora sin menú derecha)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: [
              _simpleCard(
                "Inventario",
                AppTheme.yellow,
                Icons.inventory,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InventarioPage(
                        nit: conjunto.nit,
                        empresaId:
                            AppConstants.empresaNit, // ✅ arregla tu widget.,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
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
          "Panel Administrador",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: "Recargar",
            onPressed: _cargarConjuntos,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          // ✅ Sin PopupMenuButton por ahora (tal como pediste)
        ],
      ),
      body: _buildBody(),
    );
  }
}
