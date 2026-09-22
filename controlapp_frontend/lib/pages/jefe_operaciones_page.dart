import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import '../api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/inventario_activo_model.dart';
import 'package:flutter_application_1/pages/jefe_operaciones/jefe_operaciones_pendientes_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_maquinaria_global_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_recursos_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_general_recursos_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_herramientas_global_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_por_conjunto_page.dart';
import 'package:flutter_application_1/pages/gerente/mapa_conjunto_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_insumos_page.dart';
import 'package:flutter_application_1/pages/cronograma_impresion_page.dart';
import 'package:flutter_application_1/pages/cumpleanos_page.dart';
import 'package:flutter_application_1/pages/plan_esperanza_page.dart';
import 'package:flutter_application_1/pages/reportes_page.dart';
import 'package:flutter_application_1/pages/inventario_activos_page.dart';
import 'package:flutter_application_1/pages/tareas_page.dart';
import 'package:flutter_application_1/pages/commerce_catalog_page.dart';
import 'package:flutter_application_1/pages/conjunto_orders_page.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/service/permission_service.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/cumpleanos_banner.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
import 'package:flutter_application_1/widgets/dashboard_shell.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';
import 'package:flutter_application_1/widgets/perfil_action.dart';
import 'package:flutter_application_1/widgets/responsive_appbar_actions.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

import '../service/theme.dart';
import 'inventario_resumen_page.dart';
import 'cronograma_page.dart';
import 'asistencia_grid_page.dart';
import 'asistencia_qr_page.dart';
import 'turnos_extra_page.dart';

class _JefeTile {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _JefeTile(this.title, this.icon, this.color, this.onTap);
}

class _JefeSection {
  final String title;
  final List<_JefeTile> tiles;

  const _JefeSection(this.title, this.tiles);
}

class JefeOperacionesPage extends StatefulWidget {
  const JefeOperacionesPage({super.key});

  @override
  State<JefeOperacionesPage> createState() => _JefeOperacionesPageState();
}

class _JefeOperacionesPageState extends State<JefeOperacionesPage> {
  final AuthApi _authApi = AuthApi();
  final GerenteApi _api = GerenteApi();

  bool _can(String permission) => PermissionService.instance.can(permission);

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
    _refreshSessionProfile();
    _cargarConjuntos();
  }

  Future<void> _refreshSessionProfile() async {
    try {
      await _authApi.me();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _cargarConjuntos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final lista = await _api.listarConjuntosSelector();
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
    return DashboardTile(title: title, color: color, icon: icon, onTap: onTap);
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

  Widget _sectionGrid(List<_JefeTile> tiles, int crossAxisCount) {
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
        return _simpleCard(t.title, t.color, t.icon, onTap: t.onTap);
      },
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const DashboardScaffold(
        title: 'Panel del jefe de operaciones',
        headline:
            'Coordina la operación con el mismo tablero visual del gerente.',
        description:
            'Consulta solicitudes, tareas, inventario y compromisos desde el conjunto activo.',
        leadingBadge: 'Seguimiento operativo',
        child: SkeletonDashboardGrid(tiles: 6, padding: EdgeInsets.zero),
      );
    }

    if (_error != null) {
      return DashboardScaffold(
        title: 'Panel del jefe de operaciones',
        headline: 'No se pudieron cargar los conjuntos.',
        description:
            'Recarga el panel para retomar la coordinacion operativa del servicio.',
        leadingBadge: 'Seguimiento operativo',
        child: DashboardEmptyStateCard(
          title: 'Carga pendiente',
          message: _error!,
          icon: Icons.wifi_off_rounded,
        ),
      );
    }

    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) {
      return const DashboardScaffold(
        title: 'Panel del jefe de operaciones',
        headline: 'Aún no hay conjuntos disponibles.',
        description:
            'Cuando haya conjuntos asignados, aqui veras el mismo tablero central con tus accesos operativos.',
        leadingBadge: 'Seguimiento operativo',
        child: DashboardEmptyStateCard(
          title: 'Sin conjuntos',
          message:
              'Pide al gerente que registre o asigne conjuntos para habilitar este panel.',
          icon: Icons.apartment_rounded,
        ),
      );
    }

    final nit = conjunto.nit;
    final sections = <_JefeSection>[
      _JefeSection('Operación diaria', [
        if (_can('plan_esperanza.acceso'))
          _JefeTile(
            'Plan Esperanza',
            Icons.health_and_safety,
            AppTheme.primary,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlanEsperanzaPage(
                    nit: nit,
                    nombreConjunto: conjunto.nombre,
                  ),
                ),
              );
            },
          ),
        if (_can('tareas.crear'))
          _JefeTile(
            'Crear y editar tareas',
            Icons.add_task,
            AppTheme.green,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TareasPage(nit: nit)),
              );
            },
          ),
        if (_can('compromisos.ver'))
          _JefeTile('Compromisos', Icons.checklist_rounded, Colors.indigo, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CompromisosPage(nit: nit, nombreConjunto: conjunto.nombre),
              ),
            );
          }),
      ]),
      _JefeSection('Planeacion y recursos', [
        if (_can('maquinaria.ver'))
          _JefeTile(
            'Maquinaria',
            Icons.precision_manufacturing,
            AppTheme.red,
            () {
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
        if (_can('herramientas.ver'))
          _JefeTile('Herramientas', Icons.handyman, Colors.orange, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AgendaHerramientasGlobalPage(
                  empresaNit: AppConstants.empresaNit,
                ),
              ),
            );
          }),
        if (_can('maquinaria.asignar') || _can('herramientas.asignar'))
          _JefeTile('Agenda de recursos', Icons.event_repeat, AppTheme.red, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AgendaRecursosPage(empresaNit: AppConstants.empresaNit),
              ),
            );
          }),
        if (_can('maquinaria.asignar') || _can('herramientas.asignar'))
          _JefeTile(
            'Agenda general de recursos',
            Icons.calendar_view_month,
            AppTheme.primary,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AgendaGeneralRecursosPage(
                    empresaNit: AppConstants.empresaNit,
                  ),
                ),
              );
            },
          ),
        if (_can('inventario.gestionar'))
          _JefeTile(
            'Gestionar insumos',
            Icons.inventory_outlined,
            AppTheme.yellow,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ListaInsumosPage()),
              );
            },
          ),
        if (_can('maquinaria.asignar'))
          _JefeTile(
            'Gestionar maquinaria',
            Icons.construction,
            AppTheme.red,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InventarioActivosPage(
                    empresaId: AppConstants.empresaNit,
                    soloEmpresa: true,
                  ),
                ),
              );
            },
          ),
        if (_can('herramientas.gestionar'))
          _JefeTile(
            'Stock de herramientas',
            Icons.home_repair_service_outlined,
            Colors.orange,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InventarioActivosPage(
                    empresaId: AppConstants.empresaNit,
                    initialClase: ClaseActivoInventario.herramienta,
                    soloEmpresa: true,
                  ),
                ),
              );
            },
          ),
        if (_can('inventario.ver'))
          _JefeTile('Inventario', Icons.inventory, AppTheme.yellow, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InventarioResumenPage(
                  nit: nit,
                  empresaId: AppConstants.empresaNit,
                ),
              ),
            );
          }),
        if (_can('mapa_areas.ver'))
          _JefeTile(
            'Mapa de áreas',
            Icons.account_tree_outlined,
            Colors.teal,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MapaConjuntoPage(conjuntoNit: nit),
                ),
              );
            },
          ),
        if (_can('cronograma.ver'))
          _JefeTile('Cronograma', Icons.calendar_month, Colors.purple, () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CronogramaPage(nit: nit)),
            );
          }),
        if (_can('cronograma.imprimir'))
          _JefeTile('Imprimir cronograma', Icons.print, Colors.deepOrange, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CronogramaImpresionPage(nit: nit),
              ),
            );
          }),
      ]),
      _JefeSection('Compras del conjunto', [
        _JefeTile(
          'Comprar insumos',
          Icons.storefront_outlined,
          AppTheme.primaryDark,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommerceCatalogPage(
                  title: 'Insumos para conjuntos',
                  initialScope: CommerceCatalogScope.conjunto,
                  enableCart: true,
                  initialConjuntoId: nit,
                  initialConjuntoNombre: conjunto.nombre,
                ),
              ),
            );
          },
        ),
        _JefeTile(
          'Pedidos de conjunto',
          Icons.receipt_long_outlined,
          Colors.deepOrange,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConjuntoOrdersPage(initialConjuntoId: nit),
              ),
            );
          },
        ),
      ]),
      _JefeSection('Analisis y control', [
        if (_can('reportes.ver'))
          _JefeTile('Reportes', Icons.bar_chart, Colors.teal, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportesPage(nit: nit, soloResumenTipos: true),
              ),
            );
          }),
        if (_can('compromisos.globales_ver'))
          _JefeTile(
            'Compromisos globales',
            Icons.rule_folder_outlined,
            Colors.indigo.shade300,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CompromisosPorConjuntoPage(),
                ),
              );
            },
          ),
        if (_can('cumpleanos.ver'))
          _JefeTile('Cumpleaños', Icons.cake_outlined, AppTheme.accent, () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CumpleanosPage()),
            );
          }),
      ]),
      _JefeSection('Asistencia', [
        if (_can('asistencia.ver'))
          _JefeTile(
            'Asistencia (todos los conjuntos)',
            Icons.fact_check_outlined,
            AppTheme.green,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AsistenciaGridPage()),
              );
            },
          ),
        if (_can('asistencia.turnos_extra.gestionar'))
          _JefeTile(
            'Turnos extra',
            Icons.swap_horiz_rounded,
            AppTheme.primary,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TurnosExtraPage()),
              );
            },
          ),
        if (_can('asistencia.qr.gestionar'))
          _JefeTile(
            'QR de asistencia',
            Icons.qr_code_2_rounded,
            Colors.teal,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AsistenciaQrPage(
                    conjuntoId: nit,
                    conjuntoNombre: conjunto.nombre,
                  ),
                ),
              );
            },
          ),
      ]),
    ].where((section) => section.tiles.isNotEmpty).toList();

    return DashboardScaffold(
      title: 'Panel del jefe de operaciones',
      headline: '',
      description: '',
      leadingBadge: null,
      trailing: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          // Sin Expanded aquí: cuando compact==true estas cards se apilan
          // en un Column dentro de un LayoutBuilder con alto no acotado
          // (el hero vive dentro de un scroll), y un Expanded ahí revienta
          // con "incoming height constraints are unbounded". Expanded solo
          // tiene sentido para repartir ANCHO en la fila horizontal.
          final cards = <Widget>[
            DashboardStatusCard(
              label: 'Conjuntos disponibles',
              value: _conjuntos.length.toString(),
              icon: Icons.domain_rounded,
              color: AppTheme.primary,
            ),
            DashboardStatusCard(
              label: 'Conjunto activo',
              value: compact ? conjunto.nit : conjunto.nombre,
              icon: Icons.apartment_rounded,
              color: AppTheme.green,
            ),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                cards[0],
                const SizedBox(height: 12),
                cards[1],
              ],
            );
          }

          return Row(
            children: <Widget>[
              Expanded(child: cards[0]),
              const SizedBox(width: 12),
              Expanded(child: cards[1]),
            ],
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConjuntoSelectorCard(
            conjuntoActual: conjunto,
            conjuntos: _conjuntos.where((c) => c.activo).toList(),
            selectedNit: _conjuntoSeleccionadoNit,
            onChanged: (v) => setState(() => _conjuntoSeleccionadoNit = v),
          ),
          const SizedBox(height: 18),
          if (_can('cumpleanos.ver')) ...[
            const CumpleanosBanner(),
            const SizedBox(height: 18),
          ],
          DashboardSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Panel general',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final count = _gridCountForWidth(constraints.maxWidth);
                    if (sections.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Este rol no tiene accesos activos. Pidele al gerente que habilite permisos para continuar.',
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: sections
                          .map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
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
          "Panel Jefe de Operaciones",
          style: TextStyle(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ResponsiveAppBarActions(
            background: AppTheme.primary,
            actions: [
              const PerfilAction(),
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
        ],
      ),
      body: _buildBody(),
    );
  }
}
