import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/commerce_lifecycle_api.dart';
import 'package:flutter_application_1/api/resident_orders_api.dart';
import 'package:flutter_application_1/model/resident_order_models.dart';
import 'package:flutter_application_1/pages/commerce_order_detail_page.dart';
import 'package:flutter_application_1/pages/conjunto_cart_page.dart'
    show ComprobantePickerCard, MetodoPagoSelector;
import 'package:flutter_application_1/pages/resident_orders_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/resident_cart_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_application_1/widgets/points_checkout_card.dart';
import 'package:intl/intl.dart';

class ResidentCartPage extends StatefulWidget {
  const ResidentCartPage({super.key});

  @override
  State<ResidentCartPage> createState() => _ResidentCartPageState();
}

class _ResidentCartPageState extends State<ResidentCartPage> {
  final _cart = ResidentCartService.instance;
  final _ordersApi = ResidentOrdersApi();
  final _lifecycleApi = CommerceLifecycleApi();
  final _notesCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  String? _metodoPago;
  PlatformFile? _comprobanteFile;
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: 'COP ');
  final String _idempotencyKey =
      'resident-${DateTime.now().microsecondsSinceEpoch}';
  bool _submitting = false;

  int get _units => _cart.items.fold(0, (sum, item) => sum + item.quantity);

  @override
  void dispose() {
    _notesCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickComprobante() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || !mounted) return;
    setState(() => _comprobanteFile = file);
  }

  Future<void> _checkout() async {
    if (_cart.items.isEmpty || _submitting) return;
    if (_direccionCtrl.text.trim().length < 5) {
      AppFeedback.showError(
        context,
        message: 'Indica la dirección o punto de entrega.',
      );
      return;
    }
    if (_metodoPago == null) {
      AppFeedback.showError(
        context,
        message: 'Elige con qué método vas a transferir el pago.',
      );
      return;
    }
    if (_comprobanteFile == null) {
      AppFeedback.showError(
        context,
        message: 'Adjunta el comprobante de la transferencia para continuar.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final pedido = await _ordersApi.crearPedido(
        items: _cart.items,
        direccionEntrega: _direccionCtrl.text,
        metodoPago: _metodoPago!,
        notas: _notesCtrl.text,
        idempotencyKey: _idempotencyKey,
      );
      String? uploadError;
      try {
        await _lifecycleApi.subirComprobante(
          pedidoId: pedido.id,
          file: _comprobanteFile!,
          metodoPago: _metodoPago,
        );
      } catch (error) {
        uploadError = AppError.messageOf(error);
      }
      _cart.clear();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            uploadError == null
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            color: uploadError == null ? AppTheme.primary : AppTheme.red,
            size: 44,
          ),
          title: const Text('Pedido creado'),
          content: Text(
            uploadError == null
                ? 'Tu pedido #${pedido.id} fue registrado.\n\nTotal: ${_money.format(pedido.total)}\nEstado: pendiente de pago.\n\nTu comprobante ya quedó adjunto, un administrador lo revisará.'
                : 'Pedido #${pedido.id} creado, pero el comprobante no se pudo subir ($uploadError). Podrás adjuntarlo desde el detalle del pedido.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CommerceOrderDetailPage(pedidoId: pedido.id),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
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
          backgroundColor: CommerceClayTokens.canvas,
          appBar: AppBar(
            backgroundColor: CommerceClayTokens.canvas,
            foregroundColor: CommerceClayTokens.ink,
            surfaceTintColor: Colors.transparent,
            title: const Text(
              'Mi carrito',
              style: TextStyle(
                color: CommerceClayTokens.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Mis pedidos',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ResidentOrdersPage()),
                ),
                icon: const Icon(Icons.receipt_long_outlined),
              ),
            ],
          ),
          bottomNavigationBar: items.isEmpty
              ? null
              : CommerceCheckoutBar(
                  caption: _cart.payNowTotal > 0
                      ? 'A pagar ahora: ${_money.format(_cart.payNowTotal)}'
                      : '$_units ${_units == 1 ? 'artículo' : 'artículos'} en tu carrito',
                  total: _money.format(_cart.total),
                  actionLabel: 'Pedir ahora',
                  icon: Icons.lock_outline_rounded,
                  loading: _submitting,
                  onPressed: _checkout,
                ),
          body: items.isEmpty
              ? CommerceClayBackground(
                  child: CommerceStateView(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Tu carrito está vacío',
                    message:
                        'Explora la tienda y agrega los productos o servicios que necesitas.',
                    actionLabel: 'Volver a la tienda',
                    onAction: () => Navigator.pop(context),
                  ),
                )
              : CommerceClayBackground(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                    children: <Widget>[
                      CommerceHeroCard(
                        eyebrow: 'Tu compra',
                        title: 'Todo listo para pedir',
                        subtitle:
                            '$_units ${_units == 1 ? 'artículo seleccionado' : 'artículos seleccionados'} · ${_money.format(_cart.total)}',
                        icon: Icons.shopping_bag_rounded,
                      ),
                      const SizedBox(height: 22),
                      const CommerceSectionHeader(
                        title: 'Tu selección',
                        subtitle: 'Ajusta cantidades antes de finalizar',
                      ),
                      const SizedBox(height: 12),
                      ...items.map(
                        (item) =>
                            _ResidentCartItemCard(item: item, money: _money),
                      ),
                      const SizedBox(height: 6),
                      const PointsCheckoutCard(),
                      const SizedBox(height: 12),
                      CommerceClayCard(
                        child: TextField(
                          controller: _direccionCtrl,
                          minLines: 1,
                          maxLines: 2,
                          maxLength: 300,
                          decoration: const InputDecoration(
                            labelText: 'Dirección o punto de entrega',
                            hintText: 'Ej: Torre 4, Apto 302',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      MetodoPagoSelector(
                        value: _metodoPago,
                        onChanged: (value) =>
                            setState(() => _metodoPago = value),
                      ),
                      const SizedBox(height: 12),
                      ComprobantePickerCard(
                        file: _comprobanteFile,
                        onPickFile: _pickComprobante,
                      ),
                      const SizedBox(height: 12),
                      CommerceClayCard(
                        child: TextField(
                          controller: _notesCtrl,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            labelText: 'Notas para el pedido (opcional)',
                            hintText: 'Agrega instrucciones para la tienda',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _ResidentCartItemCard extends StatelessWidget {
  const _ResidentCartItemCard({required this.item, required this.money});

  final ResidentCartItem item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cart = ResidentCartService.instance;
    return CommerceClayCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 86,
            height: item.service == null ? 96 : 164,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: Colors.white),
            ),
            clipBehavior: Clip.antiAlias,
            child: CommerceNetworkImage(url: item.imageUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: item.service == null ? 96 : 164,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: 30,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: 'Quitar',
                          onPressed: () => cart.removeProduct(item.cartKey),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: AppTheme.red,
                        ),
                      ),
                    ],
                  ),
                  if (item.service != null) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      '${item.service!.date} · ${item.service!.slotLabel}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (item.service!.selectedAddons.isNotEmpty)
                      Text(
                        item.service!.selectedAddons
                            .map(
                              (group) =>
                                  '${group.groupLabel}: ${group.options.map((option) => option.label).join(', ')}',
                            )
                            .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CommerceClayTokens.muted,
                        ),
                      ),
                    Text(
                      '${item.service!.payChoice == 'full' ? 'Pago 100%' : 'Anticipo'} · A pagar ahora ${money.format(item.payNow)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      CommerceQuantityStepper(
                        compact: true,
                        quantity: item.quantity,
                        onDecrease: () =>
                            cart.setQuantity(item.cartKey, item.quantity - 1),
                        onIncrease: () =>
                            cart.setQuantity(item.cartKey, item.quantity + 1),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            '${item.quantity} × ${money.format(item.unitPrice)}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: CommerceClayTokens.muted),
                          ),
                          Text(
                            money.format(item.subtotal),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppTheme.primaryDark,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
