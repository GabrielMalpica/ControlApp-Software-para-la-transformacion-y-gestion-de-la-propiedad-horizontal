import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/resident_orders_api.dart';
import 'package:flutter_application_1/model/resident_order_models.dart';
import 'package:flutter_application_1/pages/resident_orders_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/resident_cart_service.dart';
import 'package:intl/intl.dart';

class ResidentCartPage extends StatefulWidget {
  const ResidentCartPage({super.key});

  @override
  State<ResidentCartPage> createState() => _ResidentCartPageState();
}

class _ResidentCartPageState extends State<ResidentCartPage> {
  final _cart = ResidentCartService.instance;
  final _ordersApi = ResidentOrdersApi();
  final _notesCtrl = TextEditingController();
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: 'COP ');
  bool _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkout() async {
    if (_cart.items.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final pedido = await _ordersApi.crearPedido(
        items: _cart.items,
        notas: _notesCtrl.text,
      );
      _cart.clear();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Pedido creado'),
          content: Text(
            'Tu pedido #${pedido.id} fue creado correctamente.\n\nEstado: ${pedido.estadoWoo}\nTotal: ${_money.format(pedido.total)}\n\nSi tu tienda tiene pasarela activa, continua el pago desde la URL generada en la siguiente fase.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResidentOrdersPage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cart,
      builder: (context, _) {
        final items = _cart.items;
        return Scaffold(
          appBar: AppBar(title: const Text('Mi carrito')),
          body: items.isEmpty
              ? const Center(child: Text('Tu carrito esta vacio.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...items.map((item) => _CartItemCard(item: item, money: _money)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notas para el pedido (opcional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Total: ${_money.format(_cart.total)}'),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _submitting ? null : _checkout,
                              icon: const Icon(Icons.shopping_bag_outlined),
                              label: Text(_submitting ? 'Creando pedido...' : 'Crear pedido'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({required this.item, required this.money});

  final ResidentCartItem item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cart = ResidentCartService.instance;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
              child: item.imageUrl.isEmpty
                  ? const ColoredBox(
                      color: Color(0xFFF0F3F5),
                      child: Icon(Icons.inventory_2_outlined),
                    )
                  : Image.network(item.imageUrl, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(money.format(item.unitPrice)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => cart.setQuantity(item.productId, item.quantity - 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${item.quantity}'),
                      IconButton(
                        onPressed: () => cart.setQuantity(item.productId, item.quantity + 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => cart.removeProduct(item.productId),
                  icon: const Icon(Icons.delete_outline),
                ),
                Text(money.format(item.subtotal)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
