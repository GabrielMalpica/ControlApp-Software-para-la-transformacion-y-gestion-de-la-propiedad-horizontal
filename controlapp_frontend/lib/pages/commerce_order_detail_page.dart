import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/commerce_lifecycle_api.dart';
import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CommerceOrderDetailPage extends StatefulWidget {
  const CommerceOrderDetailPage({super.key, required this.pedidoId});

  final int pedidoId;

  @override
  State<CommerceOrderDetailPage> createState() =>
      _CommerceOrderDetailPageState();
}

class _CommerceOrderDetailPageState extends State<CommerceOrderDetailPage> {
  final _api = CommerceLifecycleApi();
  final _money = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );
  final _date = DateFormat('dd/MM/yyyy · h:mm a');

  CommerceOrderDetail? _order;
  String? _error;
  bool _loading = true;
  bool _acting = false;

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
      final order = await _api.obtenerPedido(widget.pedidoId);
      if (!mounted) return;
      setState(() {
        _order = order;
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

  String _label(String state) {
    switch (state) {
      case 'BORRADOR':
        return 'Borrador';
      case 'PENDIENTE_PAGO':
        return 'Reportar pago';
      case 'PAGADO':
        return 'Marcar pagado';
      case 'PENDIENTE_ENVIO':
        return 'Preparar envío';
      case 'ENVIADO':
        return 'Marcar enviado';
      case 'RECIBIDO':
        return 'Confirmar recepción';
      case 'ENTREGADO':
        return 'Confirmar entrega';
      case 'CANCELADO':
        return 'Cancelar pedido';
      default:
        return state.replaceAll('_', ' ');
    }
  }

  Future<void> _transition(String target) async {
    if (target == 'RECIBIDO' && _order!.esConjunto) {
      await _showReceiptPreview();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_label(target)),
        content: Text(
          target == 'CANCELADO'
              ? 'El pedido quedará cancelado y no podrá reactivarse.'
              : '¿Confirmas este cambio de estado?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _applyTransition(target);
  }

  Future<void> _applyTransition(String target) async {
    setState(() => _acting = true);
    try {
      final order = await _api.cambiarEstado(widget.pedidoId, target);
      if (!mounted) return;
      setState(() => _order = order);
      AppFeedback.showInfo(
        context,
        title: 'Pedido actualizado',
        message: 'El pedido ahora está en ${_label(target).toLowerCase()}.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _showReceiptPreview() async {
    setState(() => _acting = true);
    try {
      var preview = await _api.vistaPreviaRecepcion(widget.pedidoId);
      if (!mounted) return;
      setState(() => _acting = false);
      final apply = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: CommerceClayTokens.canvas,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Confirmar recepción',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(preview.mensaje),
                    const SizedBox(height: 16),
                    ...preview.items.map(
                      (item) => CommerceClayCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.producto,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Entrarán ${_quantity(item.cantidad)} unidades',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              initialValue: item.insumo?.id,
                              decoration: InputDecoration(
                                labelText: item.insumo == null
                                    ? 'Mapeo pendiente'
                                    : 'Insumo de inventario',
                                prefixIcon: Icon(
                                  item.insumo == null
                                      ? Icons.link_off_rounded
                                      : Icons.link_rounded,
                                ),
                              ),
                              items: preview.insumosDisponibles
                                  .map(
                                    (insumo) => DropdownMenuItem<int>(
                                      value: insumo.id,
                                      child: Text(
                                        '${insumo.nombre} (${insumo.unidad})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (insumoId) async {
                                if (insumoId == null) return;
                                try {
                                  final updated = await _api.mapearItem(
                                    pedidoId: widget.pedidoId,
                                    itemId: item.itemId,
                                    insumoId: insumoId,
                                  );
                                  setSheetState(() => preview = updated);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  AppFeedback.showError(
                                    context,
                                    message: AppError.messageOf(error),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3DC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.warning_amber_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Esta entrada es definitiva. El stock solo se sumará una vez.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            child: const Text('Volver'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: preview.puedeAplicar
                                ? () => Navigator.pop(sheetContext, true)
                                : null,
                            icon: const Icon(Icons.inventory_rounded),
                            label: const Text('Recibir'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (apply == true) await _applyTransition('RECIBIDO');
    } catch (error) {
      if (!mounted) return;
      setState(() => _acting = false);
      AppFeedback.showError(context, message: AppError.messageOf(error));
    }
  }

  String _quantity(double value) {
    return value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
  }

  String _serviceDateLabel(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  String _addonsLabel(List<dynamic> addons) {
    final labels = <String>[];
    for (final rawGroup in addons.whereType<Map<String, dynamic>>()) {
      final groupLabel = rawGroup['groupLabel']?.toString() ?? '';
      final options =
          (rawGroup['options'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map((option) => option['label']?.toString() ?? '')
              .where((label) => label.isNotEmpty)
              .join(', ');
      if (groupLabel.isNotEmpty && options.isNotEmpty) {
        labels.add('$groupLabel: $options');
      }
    }
    return labels.join(' · ');
  }

  Future<void> _openWhatsApp(CommerceOrderDetail order) async {
    if (order.whatsappPhone.isEmpty) {
      AppFeedback.showError(
        context,
        message: 'El número de WhatsApp no está configurado.',
      );
      return;
    }
    final services = order.items.map((item) => item.nombreProducto).join(', ');
    final payLabel = order.opcionPagoServicio == 'full' ? '100%' : 'Anticipo';
    final text =
        'Hola Control Limpieza. Envío comprobante de transferencia.\n\n'
        'Pedido: #${order.id}\n'
        'Servicio: $services\n'
        'Fecha solicitada: ${_serviceDateLabel(order.fechaServicio)}\n'
        'Valor pagado: ${_money.format(order.pagarAhora)} ($payLabel)\n\n'
        'Adjunto pantallazo.';
    final uri = Uri.https('wa.me', '/${order.whatsappPhone}', <String, String>{
      'text': text,
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      AppFeedback.showError(context, message: 'No se pudo abrir WhatsApp.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: CommerceClayTokens.canvas,
          foregroundColor: CommerceClayTokens.ink,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Pedido #${widget.pedidoId}',
            style: const TextStyle(
              color: CommerceClayTokens.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: CommerceClayBackground(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? CommerceStateView(
                  icon: Icons.wifi_off_rounded,
                  title: 'No pudimos abrir el pedido',
                  message: _error!,
                  actionLabel: 'Intentar de nuevo',
                  onAction: _load,
                )
              : _buildContent(_order!),
        ),
      ),
    );
  }

  Widget _buildContent(CommerceOrderDetail order) {
    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              CommerceHeroCard(
                eyebrow: 'Pedido #${order.id}',
                title: order.esConjunto
                    ? order.conjuntoNombre ?? 'Compra operativa'
                    : 'Compra personal',
                subtitle:
                    '${_money.format(order.total)}${order.creadoEn == null ? '' : ' · ${_date.format(order.creadoEn!.toLocal())}'}',
                icon: order.esConjunto
                    ? Icons.inventory_2_rounded
                    : Icons.shopping_bag_rounded,
                trailing: CommerceStatusPill(status: order.estado),
              ),
              const SizedBox(height: 16),
              CommerceClayCard(child: _OrderProgress(estado: order.estado)),
              if (order.pagarAhora > 0) ...<Widget>[
                const SizedBox(height: 16),
                CommerceClayCard(
                  color: CommerceClayTokens.mint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'A pagar ahora: ${_money.format(order.pagarAhora)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.primaryDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_serviceDateLabel(order.fechaServicio)} · ${order.turnoServicio ?? 'Día completo'} · ${order.opcionPagoServicio == 'full' ? 'Pago 100%' : 'Anticipo'}',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _openWhatsApp(order),
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('Enviar comprobante por WhatsApp'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (order.transicionesPermitidas.isNotEmpty)
                CommerceClayCard(
                  color: CommerceClayTokens.orangeSoft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Acciones disponibles',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: order.transicionesPermitidas.map((state) {
                          final cancel = state == 'CANCELADO';
                          return cancel
                              ? OutlinedButton.icon(
                                  onPressed: _acting
                                      ? null
                                      : () => _transition(state),
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: Text(_label(state)),
                                )
                              : FilledButton.icon(
                                  onPressed: _acting
                                      ? null
                                      : () => _transition(state),
                                  icon: Icon(
                                    state == 'RECIBIDO'
                                        ? Icons.inventory_rounded
                                        : Icons.arrow_forward_rounded,
                                  ),
                                  label: Text(_label(state)),
                                );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const CommerceSectionHeader(
                title: 'Productos',
                subtitle: 'Detalle de lo incluido en este pedido',
              ),
              const SizedBox(height: 10),
              ...order.items.map(
                (item) => CommerceClayCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceSoft,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          '${_quantity(item.cantidad)}×',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(item.nombreProducto),
                            if (item.fechaServicio != null)
                              Text(
                                '${_serviceDateLabel(item.fechaServicio)} · ${item.turnoServicio ?? 'Día completo'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (_addonsLabel(item.addonsServicio).isNotEmpty)
                              Text(
                                _addonsLabel(item.addonsServicio),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (item.pagarAhora > 0)
                              Text(
                                'A pagar ahora ${_money.format(item.pagarAhora)} · ${item.opcionPagoServicio == 'full' ? '100%' : 'Anticipo'}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.primaryDark,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            if (item.insumo != null)
                              Text(
                                'Insumo: ${item.insumo!.nombre}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _money.format(item.subtotal),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              if (order.entradasInventario.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                const CommerceSectionHeader(
                  title: 'Entrada aplicada',
                  subtitle: 'Inventario actualizado correctamente',
                ),
                const SizedBox(height: 10),
                CommerceClayCard(
                  color: const Color(0xFFE4F5EB),
                  child: Column(
                    children: order.entradasInventario
                        .map(
                          (entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.check_circle_rounded,
                              color: AppTheme.green,
                            ),
                            title: Text(entry.insumoNombre),
                            subtitle: Text(
                              '+${_quantity(entry.cantidad)} ${entry.unidad} · Stock ${_quantity(entry.stockActual)}',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const CommerceSectionHeader(
                title: 'Historial',
                subtitle: 'Movimientos y cambios del pedido',
              ),
              const SizedBox(height: 10),
              CommerceClayCard(
                child: Column(
                  children: order.historial.isEmpty
                      ? const <Widget>[Text('Sin cambios registrados.')]
                      : order.historial
                            .map(
                              (event) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.history_rounded),
                                title: Text(_label(event.estadoNuevo)),
                                subtitle: Text(
                                  '${event.cambiadoPor} · ${event.creadoEn == null ? '' : _date.format(event.creadoEn!.toLocal())}',
                                ),
                              ),
                            )
                            .toList(),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        if (_acting)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _OrderProgress extends StatelessWidget {
  const _OrderProgress({required this.estado});

  final String estado;

  static const _labels = <String>[
    'Pedido',
    'Preparación',
    'En camino',
    'Recibido',
    'Entregado',
  ];

  static const _icons = <IconData>[
    Icons.receipt_rounded,
    Icons.inventory_2_rounded,
    Icons.delivery_dining_rounded,
    Icons.move_to_inbox_rounded,
    Icons.check_rounded,
  ];

  int get _current => switch (estado.toUpperCase()) {
    'PAGADO' || 'PENDIENTE_ENVIO' => 1,
    'ENVIADO' => 2,
    'RECIBIDO' => 3,
    'ENTREGADO' || 'COMPLETED' => 4,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    if (estado == 'CANCELADO') {
      return const Row(
        children: <Widget>[
          Icon(Icons.cancel_rounded, color: AppTheme.red),
          SizedBox(width: 10),
          Expanded(child: Text('Este pedido fue cancelado.')),
        ],
      );
    }
    final current = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const CommerceSectionHeader(
          title: 'Seguimiento',
          subtitle: 'Así avanza tu pedido',
        ),
        const SizedBox(height: 18),
        Row(
          children: List<Widget>.generate(_labels.length * 2 - 1, (position) {
            if (position.isOdd) {
              final step = position ~/ 2;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 4,
                  decoration: BoxDecoration(
                    color: step < current
                        ? AppTheme.primary
                        : CommerceClayTokens.mint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }
            final index = position ~/ 2;
            final completed = index < current;
            final active = index == current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: active ? 38 : 34,
              height: active ? 38 : 34,
              decoration: BoxDecoration(
                color: completed
                    ? AppTheme.primary
                    : active
                    ? CommerceClayTokens.orange
                    : CommerceClayTokens.mint,
                shape: BoxShape.circle,
                boxShadow: active
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x42FF714B),
                          blurRadius: 13,
                          offset: Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                completed ? Icons.check_rounded : _icons[index],
                color: completed || active
                    ? Colors.white
                    : CommerceClayTokens.muted,
                size: 17,
              ),
            );
          }),
        ),
        const SizedBox(height: 9),
        Row(
          children: List<Widget>.generate(
            _labels.length,
            (index) => Expanded(
              child: Text(
                _labels[index],
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: index == current
                      ? CommerceClayTokens.orange
                      : index < current
                      ? AppTheme.primary
                      : CommerceClayTokens.muted,
                  fontWeight: index == current
                      ? FontWeight.w900
                      : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
