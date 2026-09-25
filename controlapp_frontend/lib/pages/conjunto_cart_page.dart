import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/commerce_lifecycle_api.dart';
import 'package:flutter_application_1/api/conjunto_orders_api.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/conjunto_order_models.dart';
import 'package:flutter_application_1/pages/commerce_order_detail_page.dart';
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
    this.initialConjuntoDireccion,
  });

  final String? initialConjuntoId;
  final String? initialConjuntoNombre;
  final String? initialConjuntoDireccion;

  @override
  State<ConjuntoCartPage> createState() => _ConjuntoCartPageState();
}

class _ConjuntoCartPageState extends State<ConjuntoCartPage> {
  final _cart = ConjuntoCartService.instance;
  final _ordersApi = ConjuntoOrdersApi();
  final _lifecycleApi = CommerceLifecycleApi();
  final _gerenteApi = GerenteApi();
  final _session = SessionService();
  final _notesCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  String? _metodoPago;
  PlatformFile? _comprobanteFile;
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: 'COP ');
  final String _idempotencyKey =
      'conjunto-${DateTime.now().microsecondsSinceEpoch}';

  bool _loadingContext = true;
  bool _submitting = false;
  String? _contextError;
  String? _role;
  String? _selectedConjuntoId;
  List<Conjunto> _conjuntos = const [];
  // La direccion de entrega SIEMPRE parte de la del conjunto (para eso son
  // los insumos), pero se puede editar puntualmente en el pedido -por eso
  // solo se auto-rellena mientras el usuario no la haya tocado a mano.
  bool _direccionEditadaManualmente = false;
  bool _prefillingDireccion = false;

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
    _direccionCtrl.addListener(() {
      if (!_prefillingDireccion) _direccionEditadaManualmente = true;
    });
    _loadContext();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  void _prefillDireccion(String? conjuntoId, List<Conjunto> conjuntos) {
    if (_direccionEditadaManualmente || !mounted) return;
    final direccion = _requiresSelector
        ? conjuntos.where((c) => c.nit == conjuntoId).firstOrNull?.direccion
        : widget.initialConjuntoDireccion;
    if (direccion == null || direccion.trim().isEmpty) return;
    _prefillingDireccion = true;
    setState(() => _direccionCtrl.text = direccion);
    _prefillingDireccion = false;
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
      _prefillDireccion(selectedId, conjuntos);
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
    if (_requiresSelector && _selectedConjuntoId == null) {
      AppFeedback.showError(
        context,
        message: 'Selecciona el conjunto que realizara la compra.',
      );
      return;
    }
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
        conjuntoId: _checkoutConjuntoId,
        notas: _notesCtrl.text,
        idempotencyKey: _idempotencyKey,
      );
      // El comprobante va pegado a la creación del pedido -no tiene sentido
      // dejarlo para despues- pero si esta subida puntual falla (ej. se cae
      // la red), el pedido ya existe: se avisa y se deja reintentar desde el
      // detalle, que tiene la misma opcion de adjuntar.
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
          title: const Text('Pedido operativo creado'),
          content: Text(
            uploadError == null
                ? 'Pedido #${pedido.id} para ${pedido.conjuntoNombre ?? _selectedConjuntoNombre}.\n\nTotal: ${_money.format(pedido.total)}\nEstado: pendiente de pago.\n\nTu comprobante ya quedó adjunto, un administrador lo revisará.'
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
                            onChanged: (value) {
                              setState(() => _selectedConjuntoId = value);
                              _prefillDireccion(value, _conjuntos);
                            },
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
                            controller: _direccionCtrl,
                            minLines: 1,
                            maxLines: 2,
                            maxLength: 300,
                            decoration: const InputDecoration(
                              labelText: 'Dirección o punto de entrega',
                              helperText:
                                  'Se sugiere la dirección registrada del conjunto; ajústala si hace falta.',
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

/// Selector del comprobante de pago, adjuntado DURANTE el checkout (no
/// despues) — compartido entre el checkout de conjunto y el de residente.
class ComprobantePickerCard extends StatelessWidget {
  const ComprobantePickerCard({
    super.key,
    required this.file,
    required this.onPickFile,
  });

  final PlatformFile? file;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final tiene = file != null;
    return CommerceClayCard(
      color: tiene ? CommerceClayTokens.mint : CommerceClayTokens.surface,
      child: Row(
        children: <Widget>[
          Icon(
            tiene ? Icons.check_circle_rounded : Icons.upload_file_rounded,
            color: tiene ? AppTheme.primary : CommerceClayTokens.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tiene ? 'Comprobante adjunto' : 'Comprobante de pago',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  tiene
                      ? file!.name
                      : 'Adjunta la captura o PDF de la transferencia.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPickFile,
            child: Text(tiene ? 'Cambiar' : 'Adjuntar'),
          ),
        ],
      ),
    );
  }
}

/// Selector de método de pago manual (Nequi/Bre-B) con su QR — compartido
/// entre el checkout de conjunto y el de residente, ver resident_cart_page.dart.
class MetodoPagoSelector extends StatelessWidget {
  const MetodoPagoSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return CommerceClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Método de pago',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Aún no hay pasarela automática: transfieres y luego adjuntas '
            'el comprobante en el detalle del pedido.',
            style: TextStyle(color: CommerceClayTokens.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kMetodoPagoLabel.entries
                .map(
                  (entry) => ChoiceChip(
                    selected: value == entry.key,
                    label: Text(entry.value),
                    onSelected: (_) => onChanged(entry.key),
                  ),
                )
                .toList(),
          ),
          if (value != null && kMetodoPagoQrAsset[value] != null) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                kMetodoPagoQrAsset[value]!,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 100,
                  alignment: Alignment.center,
                  color: Colors.white,
                  child: const Text('QR no configurado todavía.'),
                ),
              ),
            ),
          ],
        ],
      ),
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
