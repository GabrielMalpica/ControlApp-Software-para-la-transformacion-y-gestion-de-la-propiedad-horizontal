import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/conjunto_orders_api.dart';
import 'package:flutter_application_1/model/conjunto_order_models.dart';
import 'package:flutter_application_1/pages/commerce_order_detail_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:intl/intl.dart';

class ConjuntoOrdersPage extends StatefulWidget {
  const ConjuntoOrdersPage({super.key, this.initialConjuntoId});

  final String? initialConjuntoId;

  @override
  State<ConjuntoOrdersPage> createState() => _ConjuntoOrdersPageState();
}

class _ConjuntoOrdersPageState extends State<ConjuntoOrdersPage> {
  final _api = ConjuntoOrdersApi();
  final _money = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );
  final _date = DateFormat('dd/MM/yyyy · h:mm a');

  bool _loading = true;
  String? _error;
  String? _selectedConjuntoId;
  List<ConjuntoOrderSummary> _orders = const <ConjuntoOrderSummary>[];

  @override
  void initState() {
    super.initState();
    _selectedConjuntoId = widget.initialConjuntoId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.listarPedidos();
      if (!mounted) return;
      setState(() {
        _orders = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(error);
        _loading = false;
      });
    }
  }

  Future<void> _showDetail(int pedidoId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CommerceOrderDetailPage(pedidoId: pedidoId),
      ),
    );
    if (mounted) await _load();
  }

  List<ConjuntoOrderSummary> get _visibleOrders {
    final selected = _selectedConjuntoId;
    if (selected == null || selected.isEmpty) return _orders;
    return _orders.where((order) => order.conjuntoId == selected).toList();
  }

  Map<String, String> get _conjuntos {
    final result = <String, String>{};
    for (final order in _orders) {
      final id = order.conjuntoId;
      if (id == null || id.isEmpty) continue;
      result[id] = order.conjuntoNombre?.trim().isNotEmpty == true
          ? order.conjuntoNombre!.trim()
          : id;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommerceClayTokens.canvas,
      appBar: AppBar(
        backgroundColor: CommerceClayTokens.canvas,
        foregroundColor: CommerceClayTokens.ink,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Pedidos del conjunto',
          style: TextStyle(
            color: CommerceClayTokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              tooltip: 'Actualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      body: CommerceClayBackground(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: const <Widget>[
          CommerceHeroCard(
            eyebrow: 'Abastecimiento',
            title: 'Pedidos operativos',
            subtitle: 'Estamos actualizando el estado de las compras.',
            icon: Icons.local_shipping_rounded,
          ),
          SizedBox(height: 22),
          _OrderSkeleton(),
          SizedBox(height: 14),
          _OrderSkeleton(),
        ],
      );
    }
    if (_error != null) {
      return CommerceStateView(
        icon: Icons.wifi_off_rounded,
        title: 'No pudimos cargar los pedidos',
        message: _error!,
        actionLabel: 'Intentar de nuevo',
        onAction: _load,
      );
    }

    final visibleOrders = _visibleOrders;
    final conjuntos = _conjuntos;
    final total = visibleOrders.fold<double>(
      0,
      (sum, order) => sum + order.total,
    );
    final active = visibleOrders.where((order) {
      final status = order.estado.toLowerCase();
      return status != 'entregado' &&
          status != 'completed' &&
          status != 'cancelado' &&
          status != 'cancelled';
    }).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: <Widget>[
          CommerceHeroCard(
            eyebrow: 'Abastecimiento',
            title: active == 0
                ? 'Operación al día'
                : '$active ${active == 1 ? 'pedido activo' : 'pedidos activos'}',
            subtitle:
                '${visibleOrders.length} pedidos · ${_money.format(total)} acumulado',
            icon: Icons.local_shipping_rounded,
          ),
          if (conjuntos.length > 1) ...<Widget>[
            const SizedBox(height: 16),
            CommerceClayCard(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                initialValue: conjuntos.containsKey(_selectedConjuntoId)
                    ? _selectedConjuntoId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conjunto',
                  hintText: 'Todos los conjuntos',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Todos los conjuntos'),
                  ),
                  ...conjuntos.entries.map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedConjuntoId = value),
              ),
            ),
          ],
          const SizedBox(height: 24),
          CommerceSectionHeader(
            title: 'Compras operativas',
            subtitle: visibleOrders.isEmpty
                ? 'No hay pedidos con este filtro'
                : 'Toca un pedido para gestionar su estado',
          ),
          const SizedBox(height: 13),
          if (visibleOrders.isEmpty)
            CommerceStateView(
              icon: Icons.inventory_2_outlined,
              title: 'Sin pedidos por ahora',
              message:
                  'Las compras de insumos del conjunto aparecerán aquí para su seguimiento.',
              actionLabel: conjuntos.length > 1 ? 'Ver todos' : null,
              onAction: conjuntos.length > 1
                  ? () => setState(() => _selectedConjuntoId = '')
                  : null,
            )
          else
            ...visibleOrders.map(
              (order) => _ConjuntoOrderCard(
                order: order,
                money: _money,
                date: _date,
                onTap: () => _showDetail(order.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConjuntoOrderCard extends StatelessWidget {
  const _ConjuntoOrderCard({
    required this.order,
    required this.money,
    required this.date,
    required this.onTap,
  });

  final ConjuntoOrderSummary order;
  final NumberFormat money;
  final DateFormat date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CommerceClayCard(
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const CommerceClayIcon(
                icon: Icons.inventory_2_rounded,
                size: 48,
                iconSize: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Pedido #${order.id}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.apartment_rounded,
                          size: 14,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.conjuntoNombre ??
                                order.conjuntoId ??
                                'Conjunto',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CommerceStatusPill(status: order.estado),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: CommerceClayTokens.mint,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              order.items.isEmpty
                  ? '${order.cantidadItems} insumos · Woo #${order.wooOrderId}'
                  : order.items
                        .map((item) => item.nombreProducto)
                        .take(2)
                        .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CommerceClayTokens.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (order.pagarAhora > 0) ...<Widget>[
            const SizedBox(height: 9),
            Text(
              'A pagar ahora ${money.format(order.pagarAhora)} · ${order.fechaServicio?.substring(0, 10) ?? ''} · ${order.turnoServicio ?? 'Día completo'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      money.format(order.total),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (order.creadoEn != null)
                      Text(
                        date.format(order.creadoEn!.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Text(
                'Gestionar',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderSkeleton extends StatelessWidget {
  const _OrderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const CommerceClayCard(
      child: SizedBox(
        height: 100,
        child: Center(child: LinearProgressIndicator()),
      ),
    );
  }
}
