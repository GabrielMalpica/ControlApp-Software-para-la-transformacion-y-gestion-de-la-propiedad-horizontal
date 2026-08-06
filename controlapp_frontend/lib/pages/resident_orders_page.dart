import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/resident_orders_api.dart';
import 'package:flutter_application_1/model/resident_order_models.dart';
import 'package:flutter_application_1/pages/commerce_order_detail_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:intl/intl.dart';

class ResidentOrdersPage extends StatefulWidget {
  const ResidentOrdersPage({super.key});

  @override
  State<ResidentOrdersPage> createState() => _ResidentOrdersPageState();
}

class _ResidentOrdersPageState extends State<ResidentOrdersPage> {
  final _api = ResidentOrdersApi();
  final _money = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );
  final _date = DateFormat('dd/MM/yyyy · h:mm a');

  bool _loading = true;
  String? _error;
  List<ResidentOrderSummary> _orders = const <ResidentOrderSummary>[];

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommerceClayTokens.canvas,
      appBar: AppBar(
        backgroundColor: CommerceClayTokens.canvas,
        foregroundColor: CommerceClayTokens.ink,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Mis pedidos',
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
            eyebrow: 'Seguimiento',
            title: 'Tus compras',
            subtitle: 'Estamos consultando el estado de tus pedidos.',
            icon: Icons.delivery_dining_rounded,
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
        title: 'No pudimos ver tus pedidos',
        message: _error!,
        actionLabel: 'Intentar de nuevo',
        onAction: _load,
      );
    }
    if (_orders.isEmpty) {
      return CommerceStateView(
        icon: Icons.receipt_long_outlined,
        title: 'Tu primera compra empieza aquí',
        message:
            'Cuando hagas un pedido podrás seguir su avance desde esta pantalla.',
        actionLabel: 'Volver a la tienda',
        onAction: () => Navigator.pop(context),
      );
    }

    final active = _orders.where((order) {
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
            eyebrow: 'Seguimiento',
            title: active == 0
                ? 'Tus compras están al día'
                : '$active ${active == 1 ? 'pedido en curso' : 'pedidos en curso'}',
            subtitle:
                '${_orders.length} ${_orders.length == 1 ? 'compra registrada' : 'compras registradas'} en total.',
            icon: Icons.delivery_dining_rounded,
          ),
          const SizedBox(height: 24),
          const CommerceSectionHeader(
            title: 'Historial de compras',
            subtitle: 'Toca un pedido para ver todos sus detalles',
          ),
          const SizedBox(height: 13),
          ..._orders.map(
            (order) => _ResidentOrderCard(
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

class _ResidentOrderCard extends StatelessWidget {
  const _ResidentOrderCard({
    required this.order,
    required this.money,
    required this.date,
    required this.onTap,
  });

  final ResidentOrderSummary order;
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
                icon: Icons.shopping_bag_rounded,
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
                    Text(
                      order.creadoEn == null
                          ? '${order.cantidadItems} artículos'
                          : '${order.cantidadItems} artículos · ${date.format(order.creadoEn!.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CommerceStatusPill(status: order.estado),
            ],
          ),
          if (order.items.isNotEmpty) ...<Widget>[
            const SizedBox(height: 13),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: CommerceClayTokens.mint,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                order.items
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
          ],
          if (order.pagarAhora > 0) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'A pagar ahora ${money.format(order.pagarAhora)} · ${order.fechaServicio?.substring(0, 10) ?? ''} · ${order.turnoServicio ?? 'Día completo'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  money.format(order.total),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Ver detalle',
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
