import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/conjunto_orders_api.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/conjunto_order_models.dart';
import 'package:flutter_application_1/pages/conjunto_orders_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/conjunto_cart_service.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_application_1/widgets/points_checkout_card.dart';
import 'package:intl/intl.dart';

class ConjuntoCartPage extends StatefulWidget {
  const ConjuntoCartPage({
    super.key,
    this.initialConjuntoId,
    this.initialConjuntoNombre,
  });

  final String? initialConjuntoId;
  final String? initialConjuntoNombre;

  @override
  State<ConjuntoCartPage> createState() => _ConjuntoCartPageState();
}

class _ConjuntoCartPageState extends State<ConjuntoCartPage> {
  final _cart = ConjuntoCartService.instance;
  final _ordersApi = ConjuntoOrdersApi();
  final _gerenteApi = GerenteApi();
  final _session = SessionService();
  final _notesCtrl = TextEditingController();
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: 'COP ');
  final String _idempotencyKey =
      'conjunto-${DateTime.now().microsecondsSinceEpoch}';

  bool _loadingContext = true;
  bool _submitting = false;
  String? _contextError;
  String? _role;
  String? _selectedConjuntoId;
  List<Conjunto> _conjuntos = const [];

  bool get _requiresSelector =>
      _role == 'gerente' || _role == 'jefe_operaciones';

  String? get _checkoutConjuntoId => _requiresSelector
      ? _selectedConjuntoId
      : widget.initialConjuntoId?.trim().isNotEmpty == true
      ? widget.initialConjuntoId!.trim()
      : null;

  String get _selectedConjuntoNombre {
    if (_requiresSelector) {
      for (final conjunto in _conjuntos) {
        if (conjunto.nit == _selectedConjuntoId) return conjunto.nombre;
      }
    }
    return widget.initialConjuntoNombre?.trim().isNotEmpty == true
        ? widget.initialConjuntoNombre!.trim()
        : 'Conjunto asignado';
  }

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() {
      _loadingContext = true;
      _contextError = null;
    });

    try {
      final role = await _session.getRol();
      var conjuntos = const <Conjunto>[];
      var selectedId = widget.initialConjuntoId;
      if (role == 'gerente' || role == 'jefe_operaciones') {
        conjuntos = (await _gerenteApi.listarConjuntos())
            .where((conjunto) => conjunto.activo)
            .toList();
        final initialExists = conjuntos.any(
          (conjunto) => conjunto.nit == selectedId,
        );
        selectedId = initialExists
            ? selectedId
            : conjuntos.isNotEmpty
            ? conjuntos.first.nit
            : null;
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _conjuntos = conjuntos;
        _selectedConjuntoId = selectedId;
        _loadingContext = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _contextError = AppError.messageOf(
          error,
          fallback: 'No se pudo preparar el checkout del conjunto.',
        );
        _loadingContext = false;
      });
    }
  }

  Future<void> _checkout() async {
    if (_cart.items.isEmpty || _submitting) return;
    if (_requiresSelector && _selectedConjuntoId == null) {
      AppFeedback.showError(
        context,
        message: 'Selecciona el conjunto que realizara la compra.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final pedido = await _ordersApi.crearPedido(
        items: _cart.items,
        conjuntoId: _checkoutConjuntoId,
        notas: _notesCtrl.text,
        idempotencyKey: _idempotencyKey,
      );
      _cart.clear();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.primary,
            size: 44,
          ),
          title: const Text('Pedido operativo creado'),
          content: Text(
            'Pedido #${pedido.id} para ${pedido.conjuntoNombre ?? _selectedConjuntoNombre}.\n\nTotal: ${_money.format(pedido.total)}\nEstado: pendiente de pago.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Ver pedidos'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ConjuntoOrdersPage(initialConjuntoId: pedido.conjuntoId),
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
              'Compra del conjunto',
              style: TextStyle(
                color: CommerceClayTokens.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Pedidos del conjunto',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConjuntoOrdersPage(
                      initialConjuntoId: _checkoutConjuntoId,
                    ),
                  ),
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
                      : '${_cart.unitsCount} ${_cart.unitsCount == 1 ? 'insumo' : 'insumos'} para el conjunto',
                  total: _money.format(_cart.total),
                  actionLabel: 'Crear pedido',
                  icon: Icons.inventory_2_rounded,
                  loading: _submitting,
                  onPressed: _loadingContext ? null : _checkout,
                ),
          body: items.isEmpty
              ? CommerceClayBackground(
                  child: CommerceStateView(
                    icon: Icons.inventory_2_outlined,
                    title: 'Aún no hay insumos',
                    message:
                        'Agrega productos desde la tienda para preparar la compra del conjunto.',
                    actionLabel: 'Volver a la tienda',
                    onAction: () => Navigator.pop(context),
                  ),
                )
              : CommerceClayBackground(
                  child: RefreshIndicator(
                    onRefresh: _loadContext,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                      children: <Widget>[
                        CommerceHeroCard(
                          eyebrow: 'Compra operativa',
                          title: 'Abastecimiento listo',
                          subtitle:
                              '${_cart.unitsCount} ${_cart.unitsCount == 1 ? 'unidad' : 'unidades'} · ${_money.format(_cart.total)}',
                          icon: Icons.apartment_rounded,
                        ),
                        const SizedBox(height: 16),
                        if (_loadingContext)
                          const LinearProgressIndicator()
                        else if (_contextError != null)
                          CommerceClayCard(
                            child: Column(
                              children: <Widget>[
                                Text(
                                  _contextError!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _loadContext,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          )
                        else
                          _ConjuntoCheckoutContext(
                            role: _role,
                            conjuntos: _conjuntos,
                            selectedId: _selectedConjuntoId,
                            fallbackName: _selectedConjuntoNombre,
                            onChanged: (value) =>
                                setState(() => _selectedConjuntoId = value),
                          ),
                        const SizedBox(height: 18),
                        const CommerceSectionHeader(
                          title: 'Insumos del pedido',
                          subtitle: 'Revisa cantidades y destino de entrega',
                        ),
                        const SizedBox(height: 12),
                        ...items.map(
                          (item) =>
                              _ConjuntoCartItemCard(item: item, money: _money),
                        ),
                        const SizedBox(height: 6),
                        PointsCheckoutCard(
                          key: ValueKey<String?>(_checkoutConjuntoId),
                          conjuntoId: _checkoutConjuntoId,
                        ),
                        const SizedBox(height: 12),
                        CommerceClayCard(
                          child: TextField(
                            controller: _notesCtrl,
                            minLines: 2,
                            maxLines: 4,
                            maxLength: 500,
                            decoration: const InputDecoration(
                              labelText: 'Notas para la compra (opcional)',
                              hintText: 'Agrega instrucciones para la tienda',
                              prefixIcon: Icon(Icons.notes_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _ConjuntoCheckoutContext extends StatelessWidget {
  const _ConjuntoCheckoutContext({
    required this.role,
    required this.conjuntos,
    required this.selectedId,
    required this.fallbackName,
    required this.onChanged,
  });

  final String? role;
  final List<Conjunto> conjuntos;
  final String? selectedId;
  final String fallbackName;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final needsSelector = role == 'gerente' || role == 'jefe_operaciones';
    return CommerceClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Destino de la compra',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            needsSelector
                ? 'Selecciona el conjunto que recibira estos insumos.'
                : 'La compra quedara asociada automaticamente a tu conjunto.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (needsSelector)
            DropdownButtonFormField<String>(
              initialValue: selectedId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Conjunto',
                prefixIcon: Icon(Icons.apartment_outlined),
              ),
              items: conjuntos
                  .map(
                    (conjunto) => DropdownMenuItem<String>(
                      value: conjunto.nit,
                      child: Text(
                        conjunto.nombre,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            )
          else
            Row(
              children: <Widget>[
                const Icon(Icons.verified_rounded, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fallbackName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ConjuntoCartItemCard extends StatelessWidget {
  const _ConjuntoCartItemCard({required this.item, required this.money});

  final ConjuntoCartItem item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cart = ConjuntoCartService.instance;
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
