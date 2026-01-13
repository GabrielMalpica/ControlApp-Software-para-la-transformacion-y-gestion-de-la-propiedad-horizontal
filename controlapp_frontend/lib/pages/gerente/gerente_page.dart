import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/festivos_page.dart';
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

/// Acciones del menú superior (AppBar)
enum _QuickAction {
  // Usuarios
  usuariosGestion,
  usuarioCrear,

  // Conjuntos
  conjuntoCrear,
  conjuntosGestion,

  // Insumos
  insumoCrear,
  insumosCatalogo,

  // Maquinaria
  maquinariaCrear,
  maquinariaCatalogo,

  // Tareas
  tareaCrear,

  // Solicitudes
  solicitudInsumo,
  solicitudMaquinaria,

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
    // Si por alguna razón no encuentra el NIT seleccionado, vuelve al primero.
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _hayConjunto => _conjuntoSeleccionado != null;

  /// Para acciones que requieren NIT
  bool _requiereConjuntoOrWarn() {
    if (_hayConjunto) return true;
    _snack(
      "Primero crea un conjunto (arriba en Atajos) para usar esta opción.",
    );
    return false;
  }

  /// 🔹 Tarjetas compactas
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

  /// Menú superior “más pro”: PopupMenuButton agrupado
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
      item(
        _QuickAction.conjuntoCrear,
        "Crear conjunto",
        Icons.add_business,
        enabled: true,
      ),
      item(
        _QuickAction.conjuntosGestion,
        "Gestión de conjuntos",
        Icons.business,
        enabled: true,
      ),

      const PopupMenuDivider(),

      header("Insumos", Icons.inventory_2_outlined),
      item(
        _QuickAction.insumoCrear,
        "Crear insumo",
        Icons.inventory,
        enabled: enabledNit,
      ),
      item(
        _QuickAction.insumosCatalogo,
        "Catálogo de insumos",
        Icons.list_alt,
        enabled: true,
      ),

      const PopupMenuDivider(),

      header("Maquinaria", Icons.precision_manufacturing_outlined),
      item(
        _QuickAction.maquinariaCrear,
        "Crear maquinaria",
        Icons.build,
        enabled: true,
      ),
      item(
        _QuickAction.maquinariaCatalogo,
        "Catálogo de maquinaria",
        Icons.construction,
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
        "Solicitud de insumo",
        Icons.inventory_2_outlined,
        enabled: enabledNit,
      ),
      item(
        _QuickAction.solicitudMaquinaria,
        "Solicitud de maquinaria",
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
      item(
        _QuickAction.festivosCrear,
        "Crear días festivos",
        Icons.event,
        enabled: true,
      ),
    ];
  }

  void _handleQuickAction(_QuickAction action) {
    final String? nit = _conjuntoSeleccionado?.nit;

    // Helpers de navegación
    void go(Widget page) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    switch (action) {
      // Usuarios (requiere nit)
      case _QuickAction.usuariosGestion:
        if (!_requiereConjuntoOrWarn()) return;
        go(ListaUsuariosPage(nit: nit!));
        return;

      case _QuickAction.usuarioCrear:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearUsuarioPage(nit: nit!));
        return;

      // Conjuntos (no requiere nit)
      case _QuickAction.conjuntoCrear:
        // Si tu CrearConjuntoPage realmente necesita nit, le mandamos '' para evitar null.
        go(CrearConjuntoPage(nit: nit ?? ''));
        return;

      case _QuickAction.conjuntosGestion:
        go(ListaConjuntosPage(nit: nit ?? ''));
        return;

      // Insumos
      case _QuickAction.insumoCrear:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearInsumoPage(nit: nit!));
        return;

      case _QuickAction.insumosCatalogo:
        go(const ListaInsumosPage());
        return;

      // Maquinaria
      case _QuickAction.maquinariaCrear:
        // En tu código original estaba hardcodeado. Lo dejo igual.
        go(const CrearMaquinariaPage(nit: '901191875-4'));
        return;

      case _QuickAction.maquinariaCatalogo:
        go(const ListaMaquinariaPage());
        return;

      // Tareas
      case _QuickAction.tareaCrear:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearTareaPage(nit: nit!));
        return;

      // Solicitudes
      case _QuickAction.solicitudInsumo:
        if (!_requiereConjuntoOrWarn()) return;
        go(SolicitudInsumoPage(nit: nit!));
        return;

      case _QuickAction.solicitudMaquinaria:
        if (!_requiereConjuntoOrWarn()) return;
        go(SolicitudMaquinariaPage(nit: nit!));
        return;

      // Cronogramas
      case _QuickAction.cronogramaCrear:
        if (!_requiereConjuntoOrWarn()) return;
        go(CrearCronogramaPage(nit: nit!));
        return;

      // Festivos
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

    // No hay conjuntos: igual puedes abrir el menú superior y crear uno.
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsuariosConjuntoPage(conjuntoNit: nit),
                  ),
                ),
              ),
              _smallCard(
                "Tareas",
                Icons.assignment,
                AppTheme.green,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TareasPage(nit: nit)),
                ),
              ),
              _smallCard(
                "Solicitudes",
                Icons.pending_actions,
                AppTheme.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SolicitudesPage(nit: nit)),
                ),
              ),
              _smallCard(
                "Maquinaria",
                Icons.precision_manufacturing,
                AppTheme.red,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MaquinariaPage(nit: nit)),
                ),
              ),
              _smallCard(
                "Inventario",
                Icons.inventory_2_outlined,
                AppTheme.yellow,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => InventarioPage(nit: nit)),
                ),
              ),
              _smallCard(
                "Cronograma",
                Icons.calendar_month,
                Colors.purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CronogramaPage(nit: nit)),
                ),
              ),
              _smallCard(
                "Reportes",
                Icons.bar_chart,
                Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReportesPage(nit: nit)),
                ),
              ),
              _smallCard(
                "Definir tarea preventiva",
                Icons.build_circle_outlined,
                Colors.deepOrange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PreventivasPage(nit: nit)),
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
    final bool enabledNit = _hayConjunto; // habilita/deshabilita items del menú

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Panel del Gerente",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
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
        ],
      ),
      body: _buildBody(),
    );
  }
}
