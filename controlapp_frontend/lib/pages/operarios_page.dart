import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
import 'package:flutter_application_1/widgets/dashboard_shell.dart';

import '../service/permission_service.dart';
import '../service/theme.dart';
import 'tareas_page.dart';
import 'solicitudes_page.dart';
import 'agenda_herramientas_page.dart';
import 'agenda_maquinaria_page.dart';
import 'cronograma_impresion_page.dart';
import 'cronograma_page.dart';
import 'inventario_page.dart';
import 'jefe_operaciones/jefe_operaciones_pendientes_page.dart';
import 'plan_esperanza_page.dart';
import 'reportes_page.dart';
import 'stock_herramientas_empresa_page.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/cumpleanos_banner.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';
import 'package:flutter_application_1/widgets/perfil_action.dart';
import 'package:flutter_application_1/pages/gerente/mapa_conjunto_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_por_conjunto_page.dart';
import 'package:flutter_application_1/pages/gerente/cronograma_maquinaria_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_insumos_page.dart';
import 'package:flutter_application_1/pages/gerente/lista_maquinaria_page.dart';

class OperarioDashboardPage extends StatefulWidget {
  final String nit;
  const OperarioDashboardPage({super.key, required this.nit});

  @override
  State<OperarioDashboardPage> createState() => _OperarioDashboardPageState();
}

class _OperarioDashboardPageState extends State<OperarioDashboardPage> {
  final AuthApi _authApi = AuthApi();

  bool _can(String permission) => PermissionService.instance.can(permission);

  @override
  void initState() {
    super.initState();
    _refreshSessionProfile();
  }

  Future<void> _refreshSessionProfile() async {
    try {
      await _authApi.me();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Conjunto get _conjuntoActual => Conjunto(
    nit: widget.nit,
    nombre: 'Conjunto asignado',
    direccion: '',
    correo: '',
    activo: true,
    tipoServicio: const <String>[],
    consignasEspeciales: const <String>[],
    valorAgregado: const <String>[],
  );

  int _gridCountForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  /// 🔹 Tarjeta simple
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Panel del Operario",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          const PerfilAction(),
          const NotificacionesAction(),
          const CambiarContrasenaAction(),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: DashboardScaffold(
        title: 'Panel del operario',
        headline: '',
        description: '',
        leadingBadge: null,
        trailing: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final cards = <Widget>[
              Expanded(
                child: DashboardStatusCard(
                  label: 'Conjunto vinculado',
                  value: widget.nit,
                  icon: Icons.apartment_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const Expanded(
                child: DashboardStatusCard(
                  label: 'Accesos principales',
                  value: '3',
                  icon: Icons.touch_app_rounded,
                  color: AppTheme.green,
                ),
              ),
            ];

            if (compact) {
              return Column(
                children: <Widget>[
                  cards[0],
                  const SizedBox(height: 12),
                  cards[1],
                ],
              );
            }

            return Row(
              children: <Widget>[cards[0], const SizedBox(width: 12), cards[1]],
            );
          },
        ),
        child: DashboardSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ConjuntoSelectorCard(
                conjuntoActual: _conjuntoActual,
                conjuntos: <Conjunto>[_conjuntoActual],
                selectedNit: widget.nit,
                onChanged: (_) {},
              ),
              const SizedBox(height: 18),
              if (_can('cumpleanos.ver')) ...[
                const CumpleanosBanner(),
                const SizedBox(height: 18),
              ],
              Text(
                'Panel general',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = _gridCountForWidth(c.maxWidth);
                  final cards = <Widget>[
                    if (_can('tareas.ver'))
                      _simpleCard(
                        'Tareas',
                        AppTheme.green,
                        Icons.assignment,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TareasPage(nit: widget.nit),
                            ),
                          );
                        },
                      ),
                    if (_can('tareas.veredicto'))
                      _simpleCard(
                        'Veredictos de tareas',
                        AppTheme.green,
                        Icons.fact_check_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => JefeOperacionesPendientesPage(
                                conjuntoId: widget.nit,
                              ),
                            ),
                          );
                        },
                      ),
                    if (_can('solicitudes.ver'))
                      _simpleCard(
                        'Solicitudes',
                        AppTheme.primary,
                        Icons.pending_actions,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SolicitudesPage(nit: widget.nit),
                            ),
                          );
                        },
                      ),
                    if (_can('mapa_areas.ver'))
                      _simpleCard(
                        'Mapa de áreas',
                        Colors.teal,
                        Icons.account_tree_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  MapaConjuntoPage(conjuntoNit: widget.nit),
                            ),
                          );
                        },
                      ),
                    if (_can('compromisos.ver'))
                      _simpleCard(
                        'Compromisos',
                        Colors.indigo,
                        Icons.checklist_rounded,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CompromisosPage(
                                nit: widget.nit,
                                nombreConjunto: 'Conjunto asignado',
                              ),
                            ),
                          );
                        },
                      ),
                    if (_can('cronograma.ver'))
                      _simpleCard(
                        'Cronograma',
                        Colors.purple,
                        Icons.calendar_month,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CronogramaPage(nit: widget.nit),
                            ),
                          );
                        },
                      ),
                    if (_can('inventario.ver'))
                      _simpleCard(
                        'Inventario',
                        AppTheme.yellow,
                        Icons.inventory_2_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InventarioPage(
                                nit: widget.nit,
                                empresaId: AppConstants.empresaNit,
                              ),
                            ),
                          );
                        },
                      ),
                    if (_can('maquinaria.ver'))
                      _simpleCard(
                        'Maquinaria',
                        AppTheme.red,
                        Icons.precision_manufacturing,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AgendaMaquinariaPage(conjuntoId: widget.nit),
                            ),
                          );
                        },
                      ),
                    if (_can('herramientas.ver'))
                      _simpleCard(
                        'Herramientas',
                        Colors.orange,
                        Icons.handyman,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AgendaHerramientasPage(
                                conjuntoId: widget.nit,
                              ),
                            ),
                          );
                        },
                      ),
                    if (_can('plan_esperanza.acceso'))
                      _simpleCard(
                        'Plan Esperanza',
                        AppTheme.primary,
                        Icons.health_and_safety,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlanEsperanzaPage(
                                nit: widget.nit,
                                nombreConjunto: 'Conjunto asignado',
                              ),
                            ),
                          );
                        },
                      ),
                    if (_can('reportes.ver'))
                      _simpleCard(
                        'Reportes',
                        Colors.teal,
                        Icons.bar_chart,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReportesPage(
                                nit: widget.nit,
                                soloResumenTipos: true,
                              ),
                            ),
                          );
                        },
                      ),
                    if (_can('cronograma.imprimir'))
                      _simpleCard(
                        'Imprimir cronograma',
                        Colors.deepOrange,
                        Icons.print,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CronogramaImpresionPage(nit: widget.nit),
                            ),
                          );
                        },
                      ),
                    if (_can('compromisos.globales_ver'))
                      _simpleCard(
                        'Compromisos globales',
                        Colors.indigo.shade300,
                        Icons.rule_folder_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CompromisosPorConjuntoPage(),
                            ),
                          );
                        },
                      ),
                    if (_can('inventario.gestionar'))
                      _simpleCard(
                        'Gestionar insumos',
                        AppTheme.yellow,
                        Icons.inventory_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ListaInsumosPage(),
                            ),
                          );
                        },
                      ),
                    if (_can('maquinaria.asignar')) ...[
                      _simpleCard(
                        'Gestionar maquinaria',
                        AppTheme.red,
                        Icons.construction,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListaMaquinariaGlobalPage(
                                empresaNit: AppConstants.empresaNit,
                              ),
                            ),
                          );
                        },
                      ),
                      _simpleCard(
                        'Cronograma maquinaria',
                        AppTheme.red,
                        Icons.event_repeat,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CronogramaMaquinariaPage(
                                empresaNit: AppConstants.empresaNit,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    if (_can('herramientas.gestionar'))
                      _simpleCard(
                        'Stock de herramientas',
                        Colors.orange,
                        Icons.home_repair_service_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const StockHerramientasEmpresaPage(),
                            ),
                          );
                        },
                      ),
                  ];

                  if (cards.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Este rol no tiene accesos activos. Pidele al gerente que habilite permisos para continuar.',
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _sectionHeader('Operación diaria'),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: cols,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.05,
                        children: cards,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
