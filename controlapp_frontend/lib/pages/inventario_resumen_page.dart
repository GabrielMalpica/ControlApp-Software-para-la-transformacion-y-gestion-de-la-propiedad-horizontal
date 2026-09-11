import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/inventario_activo_api.dart';
import 'package:flutter_application_1/model/inventario_activo_model.dart';
import 'package:flutter_application_1/pages/inventario_activos_page.dart';
import 'package:flutter_application_1/pages/inventario_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/permission_service.dart';

class InventarioResumenPage extends StatefulWidget {
  final String nit;
  final String empresaId;

  const InventarioResumenPage({
    super.key,
    required this.nit,
    required this.empresaId,
  });

  @override
  State<InventarioResumenPage> createState() => _InventarioResumenPageState();
}

class _InventarioResumenPageState extends State<InventarioResumenPage> {
  final _api = InventarioActivoApi();
  ResumenInventarioActivos? _summary;
  ResumenInventarioActivos? _companySummary;
  String? _error;

  bool get _approver =>
      PermissionService.instance.hasAnyRole(const [
        'gerente',
        'jefe_operaciones',
      ]) &&
      PermissionService.instance.canAny(const [
        'maquinaria.aprobar',
        'herramientas.aprobar',
      ]);

  bool get _canViewMachines => PermissionService.instance.can('maquinaria.ver');

  bool get _canViewTools => PermissionService.instance.can('herramientas.ver');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.resumen(empresaId: widget.empresaId, conjuntoId: widget.nit),
        if (_approver) _api.resumen(empresaId: widget.empresaId),
      ]);
      if (mounted) {
        setState(() {
          _summary = results.first;
          _companySummary = results.length > 1 ? results[1] : null;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = AppError.messageOf(error));
    }
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _InventoryCard(
        title: 'Insumos',
        subtitle: 'Inventario y movimientos actuales',
        icon: Icons.inventory_2_outlined,
        color: Colors.teal,
        onTap: () => _open(
          InventarioPage(
            nit: widget.nit,
            empresaId: widget.empresaId,
            soloInsumos: true,
          ),
        ),
      ),
      if (_canViewMachines)
        _InventoryCard(
          title: 'Maquinaria',
          value: _summary?.maquinaria,
          subtitle: 'Unidades propias y prestadas',
          icon: Icons.precision_manufacturing_outlined,
          color: Colors.orange,
          onTap: () => _open(
            InventarioActivosPage(
              empresaId: widget.empresaId,
              conjuntoId: widget.nit,
            ),
          ),
        ),
      if (_canViewTools)
        _InventoryCard(
          title: 'Herramientas',
          value: _summary?.herramientas,
          subtitle: 'Agrupadas por tipo, trazadas por unidad',
          icon: Icons.handyman_outlined,
          color: Colors.indigo,
          onTap: () => _open(
            InventarioActivosPage(
              empresaId: widget.empresaId,
              conjuntoId: widget.nit,
              initialClase: ClaseActivoInventario.herramienta,
            ),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Inventario del conjunto',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Consulta rápidamente qué insumos, máquinas y herramientas tiene este conjunto.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900
                    ? 3
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map((card) => SizedBox(width: width, child: card))
                      .toList(),
                );
              },
            ),
            if (_approver) ...[
              const SizedBox(height: 24),
              Text(
                'Gestión de empresa',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.warehouse_outlined),
                title: const Text('Inventario general de empresa'),
                subtitle: const Text(
                  'Activos empresariales sin duplicarlos por conjunto.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(
                  InventarioActivosPage(
                    empresaId: widget.empresaId,
                    soloEmpresa: true,
                  ),
                ),
              ),
              ListTile(
                leading: Badge(
                  label: Text((_companySummary?.pendientes ?? 0).toString()),
                  child: const Icon(Icons.approval_outlined),
                ),
                title: const Text('Solicitudes pendientes'),
                subtitle: const Text(
                  'Aprobar o rechazar registros de administradores.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(
                  InventarioActivosPage(
                    empresaId: widget.empresaId,
                    soloPendientes: true,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final String title;
  final int? value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _InventoryCard({
    required this.title,
    this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (value != null)
                    Text(
                      value.toString(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
      ),
    );
  }
}
