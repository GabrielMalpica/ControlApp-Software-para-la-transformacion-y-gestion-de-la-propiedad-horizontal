import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/widgets/dashboard_tile.dart';
import 'package:flutter_application_1/widgets/dashboard_shell.dart';

import '../service/theme.dart';
import 'tareas_page.dart';
import 'solicitudes_page.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/cumpleanos_banner.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';

class OperarioDashboardPage extends StatefulWidget {
  final String nit;
  const OperarioDashboardPage({super.key, required this.nit});

  @override
  State<OperarioDashboardPage> createState() => _OperarioDashboardPageState();
}

class _OperarioDashboardPageState extends State<OperarioDashboardPage> {
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
                  value: '2',
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
              const CumpleanosBanner(),
              const SizedBox(height: 18),
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
                    children: <Widget>[
                      _sectionHeader('Operacion diaria'),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: cols,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.05,
                        children: [
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
                          _simpleCard(
                            'Solicitudes',
                            AppTheme.primary,
                            Icons.pending_actions,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SolicitudesPage(nit: widget.nit),
                                ),
                              );
                            },
                          ),
                        ],
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
