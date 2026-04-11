import 'package:flutter/material.dart';
import '../api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/jefe_operaciones/jefe_operaciones_pendientes_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_maquinaria_global_page.dart';
import 'package:flutter_application_1/pages/gerente/agenda_herramientas_global_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_page.dart';
import 'package:flutter_application_1/pages/gerente/compromisos_por_conjunto_page.dart';
import 'package:flutter_application_1/pages/cumpleanos_page.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/cumpleanos_banner.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
import 'package:flutter_application_1/widgets/dashboard_shell.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';

import '../service/theme.dart';
import 'inventario_page.dart';
import 'solicitudes_page.dart';
import 'cronograma_page.dart';

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
            'Coordina la operacion con el mismo tablero visual del gerente.',
        description:
            'Consulta solicitudes, tareas, inventario y compromisos desde el conjunto activo.',
        leadingBadge: 'Seguimiento operativo',
        child: Center(child: CircularProgressIndicator()),
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
        headline: 'Aun no hay conjuntos disponibles.',
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
      _JefeSection('Operacion diaria', [
        _JefeTile('Tareas', Icons.assignment, AppTheme.green, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JefeOperacionesPendientesPage(conjuntoId: nit),
            ),
          );
        }),
        _JefeTile('Solicitudes', Icons.pending_actions, AppTheme.primary, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SolicitudesPage(nit: nit)),
          );
        }),
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
        _JefeTile('Inventario', Icons.inventory, AppTheme.yellow, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  InventarioPage(nit: nit, empresaId: AppConstants.empresaNit),
            ),
          );
        }),
        _JefeTile('Cronograma', Icons.calendar_month, Colors.purple, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CronogramaPage(nit: nit)),
          );
        }),
      ]),
      _JefeSection('Analisis y control', [
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
        _JefeTile('Cumpleanos', Icons.cake_outlined, AppTheme.accent, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CumpleanosPage()),
          );
        }),
      ]),
    ];

    return DashboardScaffold(
      title: 'Panel del jefe de operaciones',
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
                value: compact ? conjunto.nit : conjunto.nombre,
                icon: Icons.apartment_rounded,
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
            onChanged: (v) => setState(() => _conjuntoSeleccionadoNit = v),
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
