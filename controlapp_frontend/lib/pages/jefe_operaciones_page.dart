import 'package:flutter/material.dart';
import '../api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/jefe_operaciones/jefe_operaciones_pendientes_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_maquinaria_global_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_herramientas_global_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_page.dart';
import 'package:flutter_application_1/pages/cumpleanos_page.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/cumpleanos_banner.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';

import '../service/theme.dart';
import 'inventario_page.dart';
import 'solicitudes_page.dart';
import 'cronograma_page.dart';

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

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text("Error cargando conjuntos: $_error"),
        ),
      );
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

    return LayoutBuilder(
      builder: (context, c) {
        final cols = _gridCountForWidth(c.maxWidth);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CumpleanosBanner(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
                      child: const Icon(
                        Icons.apartment,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Conjunto seleccionado",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
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
                            "NIT: $nit",
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
                        border: Border.all(
                          color: Colors.black12.withValues(alpha: 0.08),
                        ),
                      ),
                      child: DropdownButton<String>(
                        value: _conjuntoSeleccionadoNit,
                        underline: const SizedBox.shrink(),
                        items: _conjuntos
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c.nit,
                                child: SizedBox(
                                  width: 220,
                                  child: Text(
                                    c.nombre,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _conjuntoSeleccionadoNit = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: [
                  _simpleCard(
                    "Tareas",
                    AppTheme.green,
                    Icons.assignment,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              JefeOperacionesPendientesPage(conjuntoId: nit),
                        ),
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
                        MaterialPageRoute(
                          builder: (_) => AgendaMaquinariaGlobalExcelPage(
                            empresaNit: AppConstants.empresaNit,
                          ),
                        ),
                      );
                    },
                  ),
                  _simpleCard(
                    "Inventario",
                    AppTheme.yellow,
                    Icons.inventory,
                    onTap: () {
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
                    "Compromisos",
                    Colors.indigo,
                    Icons.checklist_rounded,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompromisosPage(
                            nit: nit,
                            nombreConjunto: conjunto.nombre,
                          ),
                        ),
                      );
                    },
                  ),
                  _simpleCard(
                    "Herramientas",
                    Colors.orange,
                    Icons.handyman,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgendaHerramientasGlobalPage(
                            empresaNit: AppConstants.empresaNit,
                          ),
                        ),
                      );
                    },
                  ),
                  _simpleCard(
                    "Cumpleanos",
                    AppTheme.accent,
                    Icons.cake_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CumpleanosPage(),
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
                        MaterialPageRoute(
                          builder: (_) => CronogramaPage(nit: nit),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
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
          const NotificacionesAction(),
          const CambiarContrasenaAction(),
          IconButton(
            tooltip: "Recargar conjuntos",
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
