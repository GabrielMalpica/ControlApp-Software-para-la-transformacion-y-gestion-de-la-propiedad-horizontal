import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/administrador_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/agenda_maquinaria_page.dart';
import 'package:flutter_application_1/pages/compartidos/reportes_dashboard_page.dart';
import 'package:flutter_application_1/pages/cronograma_page.dart';
import 'package:flutter_application_1/pages/gerente/usuarios_conjunto_page.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.12),
                        ),
                        child: Icon(icon, size: 44, color: color),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 46, color: color.withOpacity(0.10)),
            ],
          ),
        ),
      ),
    );
  }

  void _go(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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

          // ✅ Accesos permitidos para Administrador
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: [
              _simpleCard(
                "Inventario",
                AppTheme.yellow,
                Icons.inventory,
                onTap: () {
                  _go(
                    InventarioPage(
                      nit: conjunto.nit,
                      empresaId: AppConstants.empresaNit,
                    ),
                  );
                },
              ),
              _simpleCard(
                "Agenda maquinaria",
                AppTheme.red,
                Icons.precision_manufacturing,
                onTap: () =>
                    _go(AgendaMaquinariaPage(conjuntoId: conjunto.nit)),
              ),
              _simpleCard(
                "Cronograma",
                Colors.purple,
                Icons.calendar_month,
                onTap: () =>
                    _go(CronogramaPage(nit: conjunto.nit, soloLectura: true)),
              ),
              _simpleCard(
                "Reportes",
                Colors.teal,
                Icons.bar_chart,
                onTap: () =>
                    _go(ReportesDashboardPage(conjuntoIdInicial: conjunto.nit)),
              ),
              _simpleCard(
                "Usuarios conjunto",
                AppTheme.green,
                Icons.people_outline,
                onTap: () => _go(
                  UsuariosConjuntoPage(
                    conjuntoNit: conjunto.nit,
                    conjuntoInicial: conjunto,
                  ),
                ),
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
          const NotificacionesAction(),
          const CambiarContrasenaAction(),
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
