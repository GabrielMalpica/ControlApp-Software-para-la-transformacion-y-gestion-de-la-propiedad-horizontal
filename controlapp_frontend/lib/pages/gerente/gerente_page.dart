import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/gerente/crear_insumo_page.dart';
import 'package:flutter_application_1/pages/gerente/crear_maquinaria_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_conjuntos_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_insumos_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_maquinaria_page.dart';
import 'package:flutter_application_1/pages/gerente/usuarios_conjunto_page.dart';
import 'package:flutter_application_1/pages/preventivas_page.dart';
import 'package:flutter_application_1/pages/tareas_page.dart';
import '../../service/theme.dart';
import '../maquinaria_page.dart';
import '../inventario_page.dart';
import 'crear_usuario_page.dart';
import 'lista_usuarios_page.dart';
import '../crear_tarea_page.dart';
import '../solicitud_insumo_page.dart';
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
  final GerenteApi _gerenteApi = GerenteApi();

  List<Conjunto> _conjuntos = [];
  String? _conjuntoSeleccionadoNit;
  bool _cargandoConjuntos = true;
  String? _errorConjuntos;

  Conjunto? get _conjuntoSeleccionado {
    if (_conjuntoSeleccionadoNit == null) return null;
    return _conjuntos.firstWhere(
      (c) => c.nit == _conjuntoSeleccionadoNit,
      orElse: () => _conjuntos.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _cargarConjuntos();
  }

  Future<void> _cargarConjuntos() async {
    try {
      // Reutiliza el método que usas ya en ListaConjuntosPage
      final lista = await _gerenteApi.listarConjuntos(); // <-- ya lo tienes
      setState(() {
        _conjuntos = lista;
        _cargandoConjuntos = false;
        _errorConjuntos = null;
        if (_conjuntos.isNotEmpty) {
          _conjuntoSeleccionadoNit = _conjuntos.first.nit;
        }
      });
    } catch (e) {
      setState(() {
        _cargandoConjuntos = false;
        _errorConjuntos = e.toString();
      });
    }
  }

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

          // ---------------------------
          //        USUARIOS
          // ---------------------------
          ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text("Usuarios"),
            children: [
              ListTile(
                leading: const Icon(Icons.people),
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
            ],
          ),

          // ---------------------------
          //        CONJUNTOS
          // ---------------------------
          ExpansionTile(
            leading: const Icon(Icons.apartment),
            title: const Text("Conjuntos"),
            children: [
              ListTile(
                leading: const Icon(Icons.add_business),
                title: const Text("Crear conjunto"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CrearConjuntoPage(nit: nit),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.business),
                title: const Text("Gestión de conjuntos"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ListaConjuntosPage(nit: nit),
                  ),
                ),
              ),
            ],
          ),

          // ---------------------------
          //        INSUMOS
          // ---------------------------
          ExpansionTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text("Insumos"),
            children: [
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text("Crear insumos"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CrearInsumoPage(nit: nit),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text("Catálogo de insumos"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ListaInsumosPage()),
                  );
                },
              ),
            ],
          ),

          // ---------------------------
          //        MAQUINARIA
          // ---------------------------
          ExpansionTile(
            leading: const Icon(Icons.precision_manufacturing_outlined),
            title: const Text("Maquinaria"),
            children: [
              ListTile(
                leading: const Icon(Icons.build),
                title: const Text("Crear maquinaria"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CrearMaquinariaPage(nit: '901191875-4'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.build),
                title: const Text("Catálogo de maquinaria"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ListaMaquinariaPage(),
                    ),
                  );
                },
              ),
            ],
          ),

          // ---------------------------
          //        TAREAS
          // ---------------------------
          ExpansionTile(
            leading: const Icon(Icons.assignment),
            title: const Text("Tareas"),
            children: [
              ListTile(
                leading: const Icon(Icons.add_task),
                title: const Text("Crear tarea"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CrearTareaPage(nit: nit,)),
                ),
              ),
            ],
          ),

          // ---------------------------
          //        SOLICITUDES
          // ---------------------------
          ExpansionTile(
            leading: const Icon(Icons.shopping_cart),
            title: const Text("Solicitudes"),
            children: [
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text("Solicitud de insumo"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SolicitudInsumoPage(nit: nit),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.precision_manufacturing),
                title: const Text("Solicitud de maquinaria"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SolicitudMaquinariaPage(nit: nit),
                  ),
                ),
              ),
            ],
          ),

          // ---------------------------
          //        CRONOGRAMAS
          // ---------------------------
          ExpansionTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text("Cronogramas"),
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text("Crear cronograma"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CrearCronogramaPage(nit: nit),
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
    if (_cargandoConjuntos) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          title: const Text(
            "Panel del Gerente",
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorConjuntos != null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          title: const Text(
            "Panel del Gerente",
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: Center(child: Text("Error cargando conjuntos: $_errorConjuntos")),
      );
    }

    if (_conjuntoSeleccionado == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          title: const Text(
            "Panel del Gerente",
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: const Center(
          child: Text(
            "No hay conjuntos creados.\nCrea uno desde el menú de atajos.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final Conjunto conjunto = _conjuntoSeleccionado!;
    final String nit = conjunto.nit;

    return Scaffold(
      backgroundColor: AppTheme.background,
      endDrawer: _drawerAtajos(nit),
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Panel del Gerente",
          style: TextStyle(color: Colors.white),
        ),
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
            // 🔹 Cabecera Conjunto
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
                        setState(() {
                          _conjuntoSeleccionadoNit = v;
                        });
                      },
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
                        builder: (_) => UsuariosConjuntoPage(conjuntoNit: nit),
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
                        builder: (_) => CronogramaPage(nit: nit,),
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
                  "Definir tarea preventiva",
                  Icons.build_circle_outlined,
                  Colors.deepOrange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PreventivasPage(
                          nit: nit,
                        ), // o crea una DefinirTareaPreventivaPage(nit: nit)
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
