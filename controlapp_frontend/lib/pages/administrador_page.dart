import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/administrador_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
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
        _error = AppError.messageOf(e);
        _loading = false;
      });
    }
  }

  int _gridCountForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) logout(context);
  }

  /// 🔹 Tarjeta simple
  Widget _simpleCard(
    String title,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return DashboardTile(
      title: title,
      color: color,
      icon: icon,
      onTap: onTap,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4EE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black12.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.apartment, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Conjunto seleccionado",
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        conjunto.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "NIT: ${conjunto.nit}",
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButton<String>(
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
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ✅ Acciones del admin (por ahora sin menú derecha)
          LayoutBuilder(
            builder: (context, c) {
              final cols = _gridCountForWidth(c.maxWidth);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
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
                ],
              );
            },
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
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
