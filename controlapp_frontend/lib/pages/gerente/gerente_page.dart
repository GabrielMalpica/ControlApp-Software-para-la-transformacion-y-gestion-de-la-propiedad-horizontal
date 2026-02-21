import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/agenda_maquinaria_page.dart';
import 'package:flutter_application_1/pages/compartidos/reportes_dashboard_page.dart';
import 'package:flutter_application_1/pages/crear_herramienta_page.dart';
import 'package:flutter_application_1/pages/festivos_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_maquinaria_global_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_page.dart';
import 'package:flutter_application_1/pages/gerente/crear_insumo_page.dart';
import 'package:flutter_application_1/pages/gerente/crear_maquinaria_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_conjuntos_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_insumos_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_maquinaria_page.dart';
import 'package:flutter_application_1/pages/gerente/reportes_general_dashboard_page.dart';
import 'package:flutter_application_1/pages/gerente/usuarios_conjunto_page.dart';
import 'package:flutter_application_1/pages/gerente/zonificacion_page.dart';
import 'package:flutter_application_1/pages/lista_herramientas_page.dart';
import 'package:flutter_application_1/pages/preventivas_page.dart';
import 'package:flutter_application_1/pages/tareas_page.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';

import '../../service/theme.dart';
import '../inventario_page.dart';
import 'crear_usuario_page.dart';
import 'lista_usuarios_page.dart';
import '../crear_tarea_page.dart';
import '../solicitudes_page.dart';
import '../cronograma_page.dart';
import '../crear_cronograma_page.dart';
import 'crear_conjunto_page.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

/// ---------- TOP LEVEL HELPERS (para que no rompa en Flutter Web) ----------

class _Tile {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _Tile(this.title, this.icon, this.color, this.onTap);
}

class _TileSection {
  final String title;
  final List<_Tile> tiles;
  const _TileSection(this.title, this.tiles);
}

class _BubblePatternPainter extends CustomPainter {
  final Color color;
  _BubblePatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paintA = Paint()..color = color.withOpacity(0.20);
    final paintB = Paint()..color = color.withOpacity(0.12);

    // Patrón determinístico (sin random real)
    final seed = (size.width * 13.7 + size.height * 7.3).floor();
    final r = math.Random(seed);

    for (int i = 0; i < 28; i++) {
      final x = r.nextDouble() * size.width;
      final y = r.nextDouble() * size.height;
      final rad = 2.0 + r.nextDouble() * 7.0;
      canvas.drawCircle(Offset(x, y), rad, (i % 2 == 0) ? paintA : paintB);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Acciones del menú superior (AppBar)
enum _QuickAction {
  // Usuarios
  usuariosGestion,
  usuarioCrear,

  // Conjuntos
  conjuntoCrear,
  conjuntosGestion,

  // Creación general
  crearInsumo,
  crearMaquinaria,
  crearHerramienta,

  // Catálogos
  catalogoInsumos,
  catalogoMaquinaria,
  catalogoHerramientas,

  // Tareas
  tareaCrear,

  // Solicitudes
  solicitudInsumo,
  agendaMaquinaria,

  // Cronogramas
  cronogramaCrear,

  // Festivos
  festivosCrear,
}

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
    try {
      return _conjuntos.firstWhere((c) => c.nit == _conjuntoSeleccionadoNit);
    } catch (_) {
      return _conjuntos.isNotEmpty ? _conjuntos.first : null;
    }
  }

  bool get _hayConjunto => _conjuntoSeleccionado != null;

  @override
  void initState() {
    super.initState();
    _cargarConjuntos();
  }

  Future<void> _cargarConjuntos() async {
    try {
      final lista = await _gerenteApi.listarConjuntos();
      setState(() {
        _conjuntos = lista;
        _cargandoConjuntos = false;
        _errorConjuntos = null;
        if (_conjuntos.isNotEmpty) {
          _conjuntoSeleccionadoNit = _conjuntos.first.nit;
        } else {
          _conjuntoSeleccionadoNit = null;
        }
      });
    } catch (e) {
      setState(() {
        _cargandoConjuntos = false;
        _errorConjuntos = e.toString();
      });
    }
  }

  void _snack(String msg) {
    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(msg)));
  }

  bool _requiereConjuntoOrWarn() {
    if (_hayConjunto) return true;
    _snack("Primero crea un conjunto (en Atajos) para usar esta opción.");
    return false;
  }

  // =========================
  // UI helpers (igual a foto)
  // =========================

  int _gridCountForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  Widget _dashboardCard({
    required String title,
    required IconData icon,
    required Color accent,
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
                          color: accent.withOpacity(0.12),
                        ),
                        child: Icon(icon, size: 44, color: accent),
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
              SizedBox(
                height: 46,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: accent.withOpacity(0.10)),
                    CustomPaint(painter: _BubblePatternPainter(accent)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conjuntoHeader({required String nombre, required String nit}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
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
                  nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "NIT: $nit",
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12.withOpacity(0.08)),
            ),
            child: DropdownButton<String>(
              value: _conjuntoSeleccionadoNit,
              underline: const SizedBox.shrink(),
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down),
              items: _conjuntos
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c.nit,
                      child: SizedBox(
                        width: 160,
                        child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _conjuntoSeleccionadoNit = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _sectionGrid(List<_Tile> tiles, int crossAxisCount) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.05,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) {
        final t = tiles[i];
        return _dashboardCard(
          title: t.title,
          icon: t.icon,
          accent: t.color,
          onTap: t.onTap,
        );
      },
    );
  }

  // =========================
  // PopupMenu (Atajos)
  // =========================

  List<PopupMenuEntry<_QuickAction>> _buildQuickMenuItems({
    required bool enabledNit,
  }) {
    PopupMenuItem<_QuickAction> item(
      _QuickAction v,
      String text,
      IconData icon, {
      bool enabled = true,
    }) {
      return PopupMenuItem<_QuickAction>(
        value: v,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 18, color: enabled ? null : Colors.grey),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
    }

    PopupMenuItem<_QuickAction> header(String text, IconData icon) {
      return PopupMenuItem<_QuickAction>(
        enabled: false,
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return [
      header("Usuarios", Icons.people_alt_outlined),
      item(
        _QuickAction.usuariosGestion,
        "Gestión de usuarios",
        Icons.people,
        enabled: enabledNit,
      ),
      item(
        _QuickAction.usuarioCrear,
        "Crear usuario",
        Icons.person_add_alt_1,
        enabled: enabledNit,
      ),

      const PopupMenuDivider(),

      header("Conjuntos", Icons.apartment),
      item(_QuickAction.conjuntoCrear, "Crear conjunto", Icons.add_business),
      item(
        _QuickAction.conjuntosGestion,
        "Gestión de conjuntos",
        Icons.business,
      ),

      const PopupMenuDivider(),

      header("Creación general", Icons.add_circle_outline),
      item(
        _QuickAction.crearInsumo,
        "Crear insumo",
        Icons.inventory,
        enabled: enabledNit,
      ),
      item(
        _QuickAction.crearMaquinaria,
        "Crear maquinaria",
        Icons.build,
        enabled: true,
      ),
      item(
        _QuickAction.crearHerramienta,
        "Crear herramienta",
        Icons.handyman,
        enabled: enabledNit,
      ),

      const PopupMenuDivider(),

      header("Catálogos", Icons.list_alt_outlined),
      item(
        _QuickAction.catalogoInsumos,
        "Catálogo de insumos",
        Icons.inventory_2_outlined,
        enabled: true,
      ),
      item(
        _QuickAction.catalogoMaquinaria,
        "Catálogo de maquinaria",
        Icons.precision_manufacturing_outlined,
        enabled: true,
      ),
      item(
        _QuickAction.catalogoHerramientas,
        "Catálogo de herramientas",
        Icons.handyman_outlined,
        enabled: true,
      ),

      const PopupMenuDivider(),

      header("Tareas", Icons.assignment),
      item(
        _QuickAction.tareaCrear,
        "Crear tarea",
        Icons.add_task,
        enabled: enabledNit,
      ),

      const PopupMenuDivider(),

      header("Solicitudes", Icons.shopping_cart_outlined),
      item(
        _QuickAction.solicitudInsumo,
        "Solicitudes de insumos",
        Icons.inventory_2_outlined,
        enabled: enabledNit,
      ),
      item(
        _QuickAction.agendaMaquinaria,
        "Agenda maquinaria",
        Icons.precision_manufacturing,
        enabled: enabledNit,
      ),

      const PopupMenuDivider(),

      header("Cronogramas", Icons.calendar_month),
      item(
        _QuickAction.cronogramaCrear,
        "Crear cronograma",
        Icons.calendar_today,
        enabled: enabledNit,
      ),

      const PopupMenuDivider(),

      header("Festivos", Icons.event_available),
      item(_QuickAction.festivosCrear, "Crear días festivos", Icons.event),
    ];
  }

  void _handleQuickAction(_QuickAction action) {
    final String? nit = _conjuntoSeleccionado?.nit;

    void go(Widget page) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    switch (action) {
      case _QuickAction.usuariosGestion:
        if (!_requiereConjuntoOrWarn()) return;
        go(ListaUsuariosPage(nit: nit!));
        return;

      case _QuickAction.usuarioCrear:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearUsuarioPage(nit: nit!));
        return;

      case _QuickAction.conjuntoCrear:
        go(CrearConjuntoPage(nit: nit ?? ''));
        return;

      case _QuickAction.conjuntosGestion:
        go(ListaConjuntosPage(nit: nit ?? ''));
        return;

      case _QuickAction.crearInsumo:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearInsumoPage(nit: nit!));
        return;

      case _QuickAction.crearMaquinaria:
        go(const CrearMaquinariaPage(nit: '901191875-4'));
        return;

      case _QuickAction.crearHerramienta:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearHerramientaPage(empresaId: '901191875-4'));
        return;

      case _QuickAction.catalogoInsumos:
        go(const ListaInsumosPage());
        return;

      case _QuickAction.catalogoMaquinaria:
        go(ListaMaquinariaGlobalPage(empresaNit: '901191875-4'));
        return;

      case _QuickAction.catalogoHerramientas:
        if (!_requiereConjuntoOrWarn()) return;
        go(ListaHerramientasPage(empresaId: '901191875-4'));
        return;

      case _QuickAction.tareaCrear:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearTareaPage(nit: nit!));
        return;

      case _QuickAction.solicitudInsumo:
        if (!_requiereConjuntoOrWarn()) return;
        // go(SolicitudInsumoPage(nit: nit!));
        return;

      case _QuickAction.agendaMaquinaria:
        if (!_requiereConjuntoOrWarn()) return;
        go(AgendaMaquinariaGlobalExcelPage(empresaNit: '901191875-4'));
        return;

      case _QuickAction.cronogramaCrear:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearCronogramaPage(nit: nit!));
        return;

      case _QuickAction.festivosCrear:
        go(FestivosPage());
        return;
    }
  }

  Widget _buildBody() {
    if (_cargandoConjuntos) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorConjuntos != null) {
      return Center(child: Text("Error cargando conjuntos: $_errorConjuntos"));
    }

    if (_conjuntoSeleccionado == null) {
      return const Center(
        child: Text(
          "No hay conjuntos creados.\nUsa 'Atajos' arriba para crear el primero.",
          textAlign: TextAlign.center,
        ),
      );
    }

    final Conjunto conjunto = _conjuntoSeleccionado!;
    final String nit = conjunto.nit;

    final sections = <_TileSection>[
      _TileSection("Operacion diaria", [
        _Tile(
          "Crear tarea correctiva",
          Icons.emergency_rounded,
          Colors.red,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CrearTareaPage(nit: nit)),
            );
          },
        ),
        _Tile("Tareas", Icons.assignment, AppTheme.green, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TareasPage(nit: nit)),
          );
        }),
        _Tile("Compromisos", Icons.checklist_rounded, Colors.indigo, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CompromisosPage(nit: nit)),
          );
        }),
        _Tile("Solicitudes", Icons.pending_actions, AppTheme.green, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SolicitudesPage(nit: nit)),
          );
        }),
      ]),
      _TileSection("Planeacion y recursos", [
        _Tile(
          "Definir tarea preventiva",
          Icons.build_circle_outlined,
          Colors.deepOrange,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PreventivasPage(nit: nit)),
            );
          },
        ),
        _Tile("Cronograma", Icons.calendar_month, Colors.purple, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CronogramaPage(nit: nit)),
          );
        }),
        _Tile("Maquinaria", Icons.precision_manufacturing, AppTheme.yellow, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AgendaMaquinariaPage(conjuntoId: nit),
            ),
          );
        }),
        _Tile("Inventario", Icons.inventory_2_outlined, AppTheme.yellow, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  InventarioPage(nit: nit, empresaId: '901191875-4'),
            ),
          );
        }),
      ]),
      _TileSection("Gestion de conjunto", [
        _Tile("Usuarios", Icons.people_outline, AppTheme.green, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsuariosConjuntoPage(conjuntoNit: nit),
            ),
          );
        }),
      ]),
      _TileSection("Analisis y control", [
        _Tile("Reporte conjunto", Icons.bar_chart, AppTheme.green, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportesDashboardPage(conjuntoIdInicial: nit),
            ),
          );
        }),
        _Tile(
          "Reportes generales",
          Icons.analytics_outlined,
          AppTheme.yellow,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ReportesGeneralDashboardPage(),
              ),
            );
          },
        ),
        _Tile("Zonificacion", Icons.map_outlined, Colors.teal, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ZonificacionPage()),
          );
        }),
      ]),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _conjuntoHeader(nombre: conjunto.nombre, nit: conjunto.nit),
          const SizedBox(height: 18),
          const Text(
            "Panel general",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final count = _gridCountForWidth(constraints.maxWidth);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader(s.title),
                            _sectionGrid(s.tiles, count),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool enabledNit = _hayConjunto;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        elevation: 0,
        title: const Text(
          "Panel del Gerente",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          const NotificacionesAction(),
          IconButton(
            tooltip: "Recargar conjuntos",
            onPressed: _cargarConjuntos,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          PopupMenuButton<_QuickAction>(
            tooltip: "Atajos",
            icon: const Icon(Icons.apps_rounded, color: Colors.white),
            onSelected: _handleQuickAction,
            itemBuilder: (_) => _buildQuickMenuItems(enabledNit: enabledNit),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
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

              if (ok == true) logout(context);
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _buildBody(),
    );
  }
}
