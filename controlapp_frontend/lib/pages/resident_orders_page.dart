import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/resident_orders_api.dart';
import 'package:flutter_application_1/model/resident_order_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:intl/intl.dart';

class ResidentOrdersPage extends StatefulWidget {
  const ResidentOrdersPage({super.key});

  @override
  State<ResidentOrdersPage> createState() => _ResidentOrdersPageState();
}

class _ResidentOrdersPageState extends State<ResidentOrdersPage> {
  final _api = ResidentOrdersApi();
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: 'COP ');

  bool _loading = true;
  String? _error;
  List<ResidentOrderSummary> _orders = const [];

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pedidos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _orders.isEmpty
                  ? const Center(child: Text('Aun no tienes pedidos registrados.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, index) {
                          final order = _orders[index];
                          return Card(
                            child: ListTile(
                              title: Text('Pedido #${order.id}'),
                              subtitle: Text(
                                'Woo: ${order.wooOrderId}\nEstado: ${order.estadoWoo}\nItems: ${order.cantidadItems}',
                              ),
                              isThreeLine: true,
                              trailing: Text(_money.format(order.total)),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
