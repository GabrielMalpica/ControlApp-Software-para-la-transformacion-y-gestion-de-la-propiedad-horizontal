import 'package:flutter/material.dart';
import '../api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/supervisor/supervisor_tareas_page.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/cumpleanos_banner.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
import 'package:flutter_application_1/widgets/dashboard_shell.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';

import '../service/theme.dart';

import 'solicitudes_page.dart';
import 'agenda_maquinaria_page.dart';
import 'agenda_herramientas_page.dart';
import 'inventario_page.dart';
import 'cronograma_page.dart';
import 'cronograma_impresion_page.dart';
import 'reportes_page.dart';
import 'preventivas_page.dart';
import 'gerente/mapa_conjunto_page.dart';
import '../service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class _SupervisorTile {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _SupervisorTile(this.title, this.icon, this.color, this.onTap);
}

class _SupervisorSection {
  final String title;
  final List<_SupervisorTile> tiles;

  const _SupervisorSection(this.title, this.tiles);
}

class SupervisorPage extends StatefulWidget {
  const SupervisorPage({super.key});

  @override
  State<SupervisorPage> createState() => _SupervisorPageState();
}

class _SupervisorPageState extends State<SupervisorPage> {
  final GerenteApi _api = GerenteApi();

  List<Conjunto> _conjuntos = [];
  String? _conjuntoSeleccionadoNit;

  bool _cargandoConjuntos = true;
  String? _errorConjuntos;

  Conjunto? get _conjuntoSeleccionado {
    final nit = _conjuntoSeleccionadoNit;
    if (nit == null) return null;

    try {
      return _conjuntos.firstWhere((c) => c.nit == nit);
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
    if (!mounted) return;
    setState(() {
      _cargandoConjuntos = true;
      _errorConjuntos = null;
    });

    try {
      final lista = await _api.listarConjuntos();
      if (!mounted) return;
      setState(() {
        _conjuntos = lista;
        _conjuntoSeleccionadoNit = lista.isNotEmpty ? lista.first.nit : null;
        _cargandoConjuntos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorConjuntos = AppError.messageOf(e);
        _cargandoConjuntos = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(msg)));
  }

  void _go(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  bool _requiereConjuntoOrWarn() {
    if (_hayConjunto) return true;
    _snack("Primero selecciona un conjunto para continuar.");
    return false;
  }

  int _gridCountForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  /// Tarjeta pequeña tipo gerente
  Widget _smallCard(
    String title,
    IconData icon,
    Color color, {
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

  Widget _sectionGrid(List<_SupervisorTile> tiles, int crossAxisCount) {
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
        return _smallCard(t.title, t.icon, t.color, onTap: t.onTap);
      },
    );
  }

  Widget _buildBody() {
    if (_cargandoConjuntos) {
      return const DashboardScaffold(
        title: 'Panel del supervisor',
        headline: 'Coordina el trabajo diario con una vista mas clara.',
        description:
            'Aqui puedes revisar tareas, solicitudes, cronogramas e inventario desde el conjunto activo.',
        leadingBadge: 'Operacion en campo',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorConjuntos != null) {
      return DashboardScaffold(
        title: 'Panel del supervisor',
        headline: 'No se pudieron cargar los conjuntos.',
        description:
            'Intenta recargar para continuar con las validaciones y la operacion diaria.',
        leadingBadge: 'Operacion en campo',
        child: DashboardEmptyStateCard(
          title: 'Carga pendiente',
          message: _errorConjuntos!,
          icon: Icons.wifi_off_rounded,
        ),
      );
    }

    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) {
      return const DashboardScaffold(
        title: 'Panel del supervisor',
        headline: 'Aun no tienes conjuntos disponibles.',
        description:
            'Solicita al gerente que registre o asigne conjuntos para habilitar este panel.',
        leadingBadge: 'Operacion en campo',
        child: DashboardEmptyStateCard(
          title: 'Sin conjuntos',
          message:
              'Cuando tengas conjuntos asignados, aqui veras los accesos rapidos principales.',
          icon: Icons.apartment_rounded,
        ),
      );
    }

    final nit = conjunto.nit;
    final sections = <_SupervisorSection>[
      _SupervisorSection('Operacion diaria', [
        _SupervisorTile('Tareas', Icons.assignment, AppTheme.green, () {
          if (!_requiereConjuntoOrWarn()) return;
          _go(SupervisorTareasPage(nit: nit));
        }),
        _SupervisorTile(
          'Solicitudes',
          Icons.pending_actions,
          AppTheme.primary,
          () {
            if (!_requiereConjuntoOrWarn()) return;
            _go(SolicitudesPage(nit: nit));
          },
        ),
        _SupervisorTile('Cronograma', Icons.calendar_month, Colors.purple, () {
          if (!_requiereConjuntoOrWarn()) return;
          _go(CronogramaPage(nit: nit));
        }),
      ]),
      _SupervisorSection('Planeacion y recursos', [
        _SupervisorTile(
          'Inventario',
          Icons.inventory_2_outlined,
          AppTheme.yellow,
          () {
            if (!_requiereConjuntoOrWarn()) return;
            _go(InventarioPage(nit: nit, empresaId: AppConstants.empresaNit));
          },
        ),
        _SupervisorTile(
          'Maquinaria',
          Icons.precision_manufacturing,
          AppTheme.red,
          () {
            if (!_requiereConjuntoOrWarn()) return;
            _go(AgendaMaquinariaPage(conjuntoId: nit));
          },
        ),
        _SupervisorTile('Herramientas', Icons.handyman, Colors.orange, () {
          if (!_requiereConjuntoOrWarn()) return;
          _go(AgendaHerramientasPage(conjuntoId: nit));
        }),
        _SupervisorTile(
          'Preventivas',
          Icons.build_circle_outlined,
          Colors.deepOrange,
          () {
            if (!_requiereConjuntoOrWarn()) return;
            _go(PreventivasPage(nit: nit));
          },
        ),
        _SupervisorTile(
          'Mapa de areas',
          Icons.account_tree_outlined,
          Colors.teal,
          () {
            if (!_requiereConjuntoOrWarn()) return;
            _go(MapaConjuntoPage(conjuntoNit: nit));
          },
        ),
      ]),
      _SupervisorSection('Analisis y control', [
        _SupervisorTile('Reportes', Icons.bar_chart, Colors.teal, () {
          if (!_requiereConjuntoOrWarn()) return;
          _go(ReportesPage(nit: nit, soloResumenTipos: true));
        }),
        _SupervisorTile('Imprimir cronograma', Icons.print, Colors.deepOrange, () {
          if (!_requiereConjuntoOrWarn()) return;
          _go(CronogramaImpresionPage(nit: nit));
        }),
      ]),
    ];

    return DashboardScaffold(
      title: 'Panel del supervisor',
      headline: '',
      description: '',
      leadingBadge: null,
      trailing: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final cards = <Widget>[
            Expanded(
              child: DashboardStatusCard(
                label: 'Conjuntos disponibles',
                value: _conjuntos.length.toString(),
                icon: Icons.domain_rounded,
                color: AppTheme.primary,
              ),
            ),
            Expanded(
              child: DashboardStatusCard(
                label: 'Conjunto activo',
                value: conjunto.nombre,
                icon: Icons.fact_check_rounded,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConjuntoSelectorCard(
            conjuntoActual: conjunto,
            conjuntos: _conjuntos,
            selectedNit: _conjuntoSeleccionadoNit,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _conjuntoSeleccionadoNit = v);
            },
          ),
          const SizedBox(height: 18),
          const CumpleanosBanner(),
          const SizedBox(height: 18),
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
                  builder: (context, c) {
                    final cols = _gridCountForWidth(c.maxWidth);
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
                                  _sectionGrid(s.tiles, cols),
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
          "Panel del Supervisor",
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
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Seguro que quieres salir?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              );

              if (!context.mounted) return;
              if (ok == true) logout(context);
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
