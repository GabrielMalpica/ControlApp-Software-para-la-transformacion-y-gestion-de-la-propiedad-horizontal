import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/model/profile_models.dart';
import 'package:flutter_application_1/pages/commerce_catalog_page.dart';
import 'package:flutter_application_1/pages/resident_cart_page.dart';
import 'package:flutter_application_1/pages/resident_orders_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final _authApi = AuthApi();

  bool _loading = true;
  String? _error;
  ProfileSummary? _perfil;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final perfil = await _authApi.perfilResumen();
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e, fallback: 'No se pudo cargar el perfil.');
        _loading = false;
      });
    }
  }

  String _rolLabel(String rol) {
    switch (rol) {
      case 'gerente':
        return 'Gerente';
      case 'administrador':
        return 'Administrador';
      case 'supervisor':
        return 'Supervisor';
      case 'operario':
        return 'Operario';
      case 'jefe_operaciones':
        return 'Jefe de operaciones';
      case 'residente':
        return 'Residente';
      default:
        return rol;
    }
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: const [CambiarContrasenaAction()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _InfoCard(
                        title: 'Cuenta',
                        children: [
                          _InfoRow(label: 'Nombre', value: _perfil!.user.nombre),
                          _InfoRow(label: 'Correo', value: _perfil!.user.correo),
                          _InfoRow(
                            label: 'Rol',
                            value: _rolLabel(_perfil!.user.rol),
                          ),
                          _InfoRow(
                            label: 'Estado',
                            value: _perfil!.user.activo ? 'Activo' : 'Inactivo',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Actividad comercial',
                        children: [
                          _MetricRow(
                            label: 'Pedidos realizados',
                            value: '${_perfil!.metricas.totalPedidos}',
                          ),
                          _MetricRow(
                            label: 'Pedidos completados',
                            value: '${_perfil!.metricas.pedidosCompletados}',
                          ),
                          _MetricRow(
                            label: 'Compras totales',
                            value: 'COP ${_formatMoney(_perfil!.metricas.totalCompras)}',
                          ),
                          _MetricRow(
                            label: 'Compras completadas',
                            value:
                                'COP ${_formatMoney(_perfil!.metricas.comprasCompletadas)}',
                          ),
                          _MetricRow(
                            label: 'Puntos',
                            value: '${_perfil!.metricas.puntos}',
                          ),
                          _MetricRow(
                            label: 'Beneficios activos',
                            value: '${_perfil!.metricas.beneficiosActivos}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Canal comercial',
                        children: [
                          Text(
                            _perfil!.user.rol == 'residente'
                                ? 'Explora productos y servicios del ecommerce desde la app.'
                                : 'Consulta el nuevo catalogo WooCommerce que alimentara compras del conjunto y de residentes.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              final initialScope = _perfil!.user.rol == 'residente'
                                  ? CommerceCatalogScope.residente
                                  : CommerceCatalogScope.todos;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommerceCatalogPage(
                                    title: 'Catalogo ecommerce',
                                    initialScope: initialScope,
                                    enableCart: _perfil!.user.rol == 'residente',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.storefront_outlined),
                            label: const Text('Abrir catalogo comercial'),
                          ),
                          if (_perfil!.user.rol == 'residente') ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const ResidentCartPage(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.shopping_cart_outlined),
                                  label: const Text('Mi carrito'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const ResidentOrdersPage(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  label: const Text('Mis pedidos'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      if (_perfil!.conjuntos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _InfoCard(
                          title: 'Conjuntos vinculados',
                          children: _perfil!.conjuntos
                              .map(
                                (item) => _InfoRow(
                                  label: item.nit,
                                  value: item.nombre,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (_perfil!.residente != null) ...[
                        const SizedBox(height: 16),
                        _InfoCard(
                          title: 'Unidad residencial',
                          children: [
                            _InfoRow(
                              label: 'Tipo',
                              value: _perfil!.residente!.tipoUnidad,
                            ),
                            if (_perfil!.residente!.sector.isNotEmpty)
                              _InfoRow(
                                label: 'Sector',
                                value: _perfil!.residente!.sector,
                              ),
                            _InfoRow(
                              label: 'Unidad',
                              value: _perfil!.residente!.unidad,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Este perfil ya queda listo para crecer con pedidos, recompensas y beneficios por rol.',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.primaryDark),
          ),
        ],
      ),
    );
  }
}
