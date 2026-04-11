import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/administrador_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/widgets/dashboard_shell.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/cumpleanos_banner.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';
import '../service/theme.dart';
import 'compartidos/reportes_dashboard_page.dart';
import 'cronograma_page.dart';
import 'inventario_page.dart';
import 'gerente/compromisos_page.dart';

class _AdminTile {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _AdminTile(this.title, this.icon, this.color, this.onTap);
}

class _AdminSection {
  final String title;
  final List<_AdminTile> tiles;

  const _AdminSection(this.title, this.tiles);
}

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

  bool get _hayConjunto => _conjuntoSeleccionado != null;

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

  Widget _dashboardCard({
    required String title,
    required IconData icon,
    required Color accent,
    VoidCallback? onTap,
  }) {
    return DashboardTile(title: title, color: accent, icon: icon, onTap: onTap);
  }

  void _go(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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

  Widget _sectionGrid(List<_AdminTile> tiles, int crossAxisCount) {
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

  Widget _buildBody() {
    if (_loading) {
      return const DashboardScaffold(
        title: 'Panel del administrador',
        headline:
            'Gestiona tu conjunto con la misma vista central del sistema.',
        description:
            'Accede a inventario, PQRS y reportes del conjunto activo desde un tablero unificado.',
        leadingBadge: 'Operacion administrativa',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return DashboardScaffold(
        title: 'Panel del administrador',
        headline: 'No se pudieron cargar tus conjuntos.',
        description:
            'Recarga el panel para continuar con la operacion administrativa del servicio.',
        leadingBadge: 'Operacion administrativa',
        child: DashboardEmptyStateCard(
          title: 'Carga pendiente',
          message: _error!,
          icon: Icons.wifi_off_rounded,
        ),
      );
    }

    if (_conjuntoSeleccionado == null) {
      return const DashboardScaffold(
        title: 'Panel del administrador',
        headline: 'Aun no tienes conjuntos asignados.',
        description:
            'Cuando el gerente te asigne uno o mas conjuntos, aqui veras el mismo panel operativo del resto de roles.',
        leadingBadge: 'Operacion administrativa',
        child: DashboardEmptyStateCard(
          title: 'Sin conjuntos',
          message:
              'Pidele al gerente que te asigne un conjunto para habilitar inventario, PQRS y reportes.',
          icon: Icons.apartment_rounded,
        ),
      );
    }

    final conjunto = _conjuntoSeleccionado!;
    final sections = <_AdminSection>[
      _AdminSection('Operacion diaria', [
        _AdminTile(
          'PQRS',
          Icons.support_agent,
          Colors.indigo,
          () => _go(
            CompromisosPage(
              nit: conjunto.nit,
              nombreConjunto: conjunto.nombre,
              pageTitle: 'PQRS',
              inputLabel: 'Nueva PQRS',
              inputHint: 'Ej: Reporte de novedad o requerimiento',
              emptyMessage: 'Aun no hay PQRS.\nRegistra la primera.',
              addButtonLabel: 'Registrar',
              usarFlujoAdministrador: true,
            ),
          ),
        ),
        _AdminTile(
          'Inventario',
          Icons.inventory_2_outlined,
          AppTheme.yellow,
          () => _go(
            InventarioPage(
              nit: conjunto.nit,
              empresaId: AppConstants.empresaNit,
            ),
          ),
        ),
        _AdminTile(
          'Cronograma',
          Icons.calendar_month,
          Colors.purple,
          () => _go(CronogramaPage(nit: conjunto.nit)),
        ),
      ]),
      _AdminSection('Analisis y control', [
        _AdminTile(
          'Reportes',
          Icons.bar_chart,
          AppTheme.green,
          () => _go(
            ReportesDashboardPage(
              conjuntoIdInicial: conjunto.nit,
              permitirInformesPdf: false,
              soloResumenTipos: true,
            ),
          ),
        ),
      ]),
    ];

    return DashboardScaffold(
      title: 'Panel del administrador',
      headline: '',
      description: '',
      leadingBadge: null,
      trailing: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final cards = <Widget>[
            Expanded(
              child: DashboardStatusCard(
                label: 'Conjuntos asignados',
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
          if (_hayConjunto)
            IconButton(
              tooltip: 'Ver reportes',
              onPressed: () => _go(
                ReportesDashboardPage(
                  conjuntoIdInicial: _conjuntoSeleccionado!.nit,
                  permitirInformesPdf: false,
                  soloResumenTipos: true,
                ),
              ),
              icon: const Icon(Icons.bar_chart, color: Colors.white),
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
