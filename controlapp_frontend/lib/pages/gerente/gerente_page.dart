import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/gerente/lista_conjuntos_page.dart';
import '../../service/theme.dart';

import '../operarios_page.dart';
import '../administrador_page.dart';
import '../jefe_operaciones_page.dart';
import '../supervisor_page.dart';
import '../maquinaria_page.dart';
import '../inventario_page.dart';
import 'crear_usuario_page.dart';
import 'lista_usuarios_page.dart';
import '../crear_tarea_page.dart';
import '../solicitud_insumo_page.dart';
import '../tareas_page.dart';
import '../solicitudes_page.dart';
import '../cronograma_page.dart';
import '../reportes_page.dart';
import '../crear_cronograma_page.dart';
import 'crear_conjunto_page.dart';
import '../solicitud_maquinaria_page.dart';

class GerenteDashboardPage extends StatefulWidget {
  const GerenteDashboardPage({super.key});

  @override
  State<GerenteDashboardPage> createState() => _GerenteDashboardPageState();
}

class _GerenteDashboardPageState extends State<GerenteDashboardPage> {
  final List<String> proyectos = ['Proyecto 1', 'Proyecto 2', 'Proyecto 3'];
  String proyectoSeleccionado = 'Proyecto 1';

  final Map<String, dynamic> dataPorProyecto = {
    'Proyecto 1': {'nit': '1111'},
    'Proyecto 2': {'nit': '2222'},
    'Proyecto 3': {'nit': '3333'},
  };

  String get _nitActual => dataPorProyecto[proyectoSeleccionado]['nit'];

  /// 🔹 NUEVO DISEÑO — Tarjetas compactas
  Widget _smallCard(
    String title,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 Nuevo menú lateral derecho
  Drawer _drawerAtajos(String nit) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: AppTheme.primary),
            child: const Text(
              "Atajos rápidos",
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text("Gestión de usuarios"),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ListaUsuariosPage(nit: nit),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1),
            title: const Text("Crear usuario"),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CrearUsuarioPage(nit: nit)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text("Crear tarea"),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CrearTareaPage(nit: nit)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart),
            title: const Text("Solicitud de insumo"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SolicitudInsumoPage(nit: nit),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.apartment),
            title: const Text("Crear conjunto"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CrearConjuntoPage(nit: nit)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.apartment),
            title: const Text("Gestión conjuntos"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ListaConjuntosPage(nit: nit,)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.precision_manufacturing),
            title: const Text("Solicitud de maquinaria"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SolicitudMaquinariaPage(nit: nit),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text("Crear cronograma"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CrearCronogramaPage(nit: nit),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nit = _nitActual;

    return Scaffold(
      backgroundColor: AppTheme.background,

      /// 🔹 Drawer lateral derecho
      endDrawer: _drawerAtajos(nit),

      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Panel del Gerente",
          style: TextStyle(color: Colors.white),
        ),

        /// 🔹 Icono para abrir el menú derecho
        actions: [
          Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              );
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Cabecera Proyecto
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.business, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Proyecto activo",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            proyectoSeleccionado,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "NIT: $nit",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    DropdownButton<String>(
                      value: proyectoSeleccionado,
                      underline: const SizedBox.shrink(),
                      items: proyectos
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => proyectoSeleccionado = v!),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "Panel general",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),

            /// 🔹 GRID compacta y bonita
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _smallCard(
                  "Usuarios",
                  Icons.people_outline,
                  Colors.indigo,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ListaUsuariosPage(nit: nit),
                      ),
                    );
                  },
                ),
                _smallCard(
                  "Tareas",
                  Icons.assignment,
                  AppTheme.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TareasPage(nit: nit)),
                    );
                  },
                ),
                _smallCard(
                  "Solicitudes",
                  Icons.pending_actions,
                  AppTheme.primary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SolicitudesPage(nit: nit),
                      ),
                    );
                  },
                ),
                _smallCard(
                  "Maquinaria",
                  Icons.precision_manufacturing,
                  AppTheme.red,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MaquinariaPage(nit: nit),
                      ),
                    );
                  },
                ),
                _smallCard(
                  "Inventario",
                  Icons.inventory_2_outlined,
                  AppTheme.yellow,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InventarioPage(nit: nit),
                      ),
                    );
                  },
                ),
                _smallCard(
                  "Cronograma",
                  Icons.calendar_month,
                  Colors.purple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CronogramaPage(nit: nit),
                      ),
                    );
                  },
                ),
                _smallCard(
                  "Reportes",
                  Icons.bar_chart,
                  Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReportesPage(nit: nit)),
                    );
                  },
                ),
                _smallCard(
                  "Vistas por rol",
                  Icons.dashboard_customize,
                  Colors.blueAccent,
                  onTap: () {
                    // puedes dejar tu dialog anterior si quieres
                    _mostrarVistasDialog(context, nit);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// — Mantengo tu método original —
  void _mostrarVistasDialog(BuildContext context, String nit) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Seleccionar vista"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text("Administrador"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdministradorPage(nit: nit),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups),
              title: const Text("Operarios"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OperarioDashboardPage(nit: nit),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.business_center),
              title: const Text("Jefe de Operaciones"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => JefeOperacionesPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.supervisor_account),
              title: const Text("Supervisor"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SupervisorPage()),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }
}
