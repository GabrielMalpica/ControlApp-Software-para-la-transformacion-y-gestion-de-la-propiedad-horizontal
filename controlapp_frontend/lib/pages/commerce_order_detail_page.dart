import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/commerce_lifecycle_api.dart';
import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_application_1/widgets/receipt_confirmation_sheet.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

const Map<String, String> kMetodoPagoLabel = <String, String>{
  'nequi': 'Nequi',
  'bre_b': 'Bre-B (llave)',
};

const Map<String, String> kMetodoPagoQrAsset = <String, String>{
  'nequi': 'assets/payment/qr_nequi.png',
  'bre_b': 'assets/payment/qr_breb.png',
};

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
  bool _uploadingComprobante = false;

  @override
  void initState() {
    super.initState();
    NotificacionesCenter.instance.pedidoActualizado.addListener(
      _onPedidoActualizado,
    );
    _load();
  }

  @override
  void dispose() {
    NotificacionesCenter.instance.pedidoActualizado.removeListener(
      _onPedidoActualizado,
    );
    super.dispose();
  }

  /// El backend crea una notificación cuando el pedido cambia por fuera de la
  /// app (p. ej. el pago se confirma en WooCommerce). La campanita ya consulta
  /// las notificaciones por su cuenta, así que aquí no se hace ninguna petición
  /// periódica propia: solo se recarga este pedido cuando llega su aviso.
  void _onPedidoActualizado() {
    final aviso = NotificacionesCenter.instance.pedidoActualizado.value;
    if (aviso == null || aviso.referenciaId != widget.pedidoId) return;
    if (!mounted || _loading || _acting || _uploadingComprobante) return;
    _reloadSilently();
  }

  Future<void> _reloadSilently() async {
    try {
      final order = await _api.obtenerPedido(widget.pedidoId);
      if (!mounted) return;
      setState(() => _order = order);
    } catch (_) {
      // Conserva lo que ya se ve; el usuario puede tirar para refrescar.
    }
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

  /// Texto del botón de acción para pasar el pedido a [state].
  String _label(String state) {
    switch (state) {
      case 'PENDIENTE_PAGO':
        return 'Reportar pago';
      case 'PAGADO':
        return 'Confirmar pago';
      case 'PENDIENTE_ENVIO':
        return 'Marcar en preparación';
      case 'ENVIADO':
        return 'Marcar en camino';
      case 'RECIBIDO':
        return 'Marcar recibido';
      case 'ENTREGADO':
        return 'Marcar entregado';
      case 'CANCELADO':
        return 'Cancelar pedido';
      default:
        return _stateName(state);
    }
  }

  /// Nombre del estado tal como lo ve el cliente (coincide con la etiqueta de
  /// estado y con el seguimiento del pedido).
  String _stateName(String state) {
    switch (state) {
      case 'BORRADOR':
        return 'Borrador';
      case 'PENDIENTE_PAGO':
        return 'Pendiente de pago';
      case 'PAGADO':
        return 'Pagado';
      case 'PENDIENTE_ENVIO':
        return 'En preparación';
      case 'ENVIADO':
        return 'En camino';
      case 'RECIBIDO':
        return 'Recibido';
      case 'ENTREGADO':
        return 'Entregado';
      case 'CANCELADO':
        return 'Cancelado';
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
              : '¿Marcar el pedido como ${_stateName(target).toLowerCase()}?',
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

  Future<void> _pickAndUploadComprobante() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || !mounted) return;

    setState(() => _uploadingComprobante = true);
    try {
      final order = await _api.subirComprobante(
        pedidoId: widget.pedidoId,
        file: file,
        metodoPago: _order?.metodoPago,
      );
      if (!mounted) return;
      setState(() => _order = order);
      AppFeedback.showInfo(
        context,
        title: 'Comprobante recibido',
        message: 'Un administrador lo revisará para confirmar el pago.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _uploadingComprobante = false);
    }
  }

  Future<void> _applyTransition(
    String target, {
    List<Map<String, dynamic>>? recepcion,
  }) async {
    setState(() => _acting = true);
    try {
      final order = await _api.cambiarEstado(
        widget.pedidoId,
        target,
        recepcion: recepcion,
      );
      if (!mounted) return;
      setState(() => _order = order);
      // Confirmar la recepción cierra el pedido: queda entregado sin otro paso.
      final recibido = target == 'RECIBIDO';
      AppFeedback.showInfo(
        context,
        title: recibido ? 'Recepción confirmada' : 'Pedido actualizado',
        message: recibido
            ? 'El pedido quedó entregado${order.esConjunto ? ' y el inventario ya se actualizó' : ''}.'
            : 'El pedido ahora está: ${_stateName(target).toLowerCase()}.',
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
      final preview = await _api.vistaPreviaRecepcion(widget.pedidoId);
      if (!mounted) return;
      setState(() => _acting = false);
      // Devuelve las novedades (vacío = llegó completo) o null si se cancela.
      final novedades = await showModalBottomSheet<List<Map<String, dynamic>>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: CommerceClayTokens.canvas,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        builder: (_) => ReceiptConfirmationSheet(
          preview: preview,
          onMapear: preview.puedeMapear
              ? (itemId, insumoId, factor) => _api.mapearItem(
                  pedidoId: widget.pedidoId,
                  itemId: itemId,
                  insumoId: insumoId,
                  factorConversion: factor,
                )
              : null,
        ),
      );
      if (novedades != null) {
        await _applyTransition('RECIBIDO', recepcion: novedades);
      }
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
              ? const SkeletonList()
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
                trailing: CommerceStatusPill(
                  status: order.estado,
                  onDark: true,
                ),
              ),
              const SizedBox(height: 16),
              CommerceClayCard(child: _OrderProgress(estado: order.estado)),
              for (final state in order.transicionesPermitidas.where(
                (state) => state != 'CANCELADO',
              )) ...<Widget>[
                const SizedBox(height: 16),
                OrderNextStepCard(
                  target: state,
                  esConjunto: order.esConjunto,
                  label: _label(state),
                  enabled: !_acting,
                  onPressed: () => _transition(state),
                ),
              ],
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
              if (order.estado == 'PENDIENTE_PAGO' ||
                  order.comprobanteUrl != null) ...<Widget>[
                const SizedBox(height: 16),
                _ComprobantePagoCard(
                  order: order,
                  uploading: _uploadingComprobante,
                  onPickFile: _pickAndUploadComprobante,
                ),
              ],
              if (order.verificacionComprobante != null) ...<Widget>[
                const SizedBox(height: 16),
                _VerificacionComprobanteCard(
                  verificacion: order.verificacionComprobante!,
                  money: _money,
                ),
              ],
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
                            if (item.llegoIncompleto)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Icon(
                                      Icons.report_problem_rounded,
                                      size: 16,
                                      color: AppTheme.red,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Llegaron ${_quantity(item.cantidadRecibida!)} de ${_quantity(item.cantidad)}'
                                        '${(item.novedadRecepcion ?? '').isEmpty ? '' : ' · ${item.novedadRecepcion}'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppTheme.red,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
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
                      : order.historial.map((event) {
                          final esWoo = event.cambiadoPorRol == 'woocommerce';
                          final quien = esWoo
                              ? 'WooCommerce (verificado en la tienda)'
                              : event.cambiadoPor;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              esWoo
                                  ? Icons.verified_rounded
                                  : Icons.history_rounded,
                              color: esWoo ? AppTheme.primary : null,
                            ),
                            title: Text(_stateName(event.estadoNuevo)),
                            subtitle: Text(
                              '$quien · ${event.creadoEn == null ? '' : _date.format(event.creadoEn!.toLocal())}',
                            ),
                          );
                        }).toList(),
                ),
              ),
              if (order.transicionesPermitidas.contains(
                'CANCELADO',
              )) ...<Widget>[
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _acting ? null : () => _transition('CANCELADO'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancelar pedido'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.red,
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
        if (_acting)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              // Overlay de accion en curso (no de carga de contenido): un
              // spinner comunica "procesando" mejor que un skeleton, que
              // sugeriria que va a aparecer contenido nuevo con esa forma.
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

/// Siguiente paso del pedido: la acción principal, con una frase que explica
/// qué pasa al confirmarla. Va en una tarjeta verde suave debajo del
/// seguimiento -es el avance normal del pedido, no una alerta-, y "Cancelar"
/// queda aparte y discreto para que nadie lo toque por error.
class OrderNextStepCard extends StatelessWidget {
  const OrderNextStepCard({
    super.key,
    required this.target,
    required this.esConjunto,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  /// Estado al que pasaría el pedido (p. ej. `RECIBIDO`).
  final String target;
  final bool esConjunto;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  ({String title, String message, String button, IconData icon}) get _copy {
    switch (target) {
      case 'RECIBIDO':
        return (
          title: '¿Ya llegó tu pedido?',
          message: esConjunto
              ? 'Revisa lo que llegó y avisa si algo falta. Al confirmar, lo '
                    'recibido se suma automáticamente al inventario del '
                    'conjunto y el pedido queda entregado.'
              : 'Confirma cuando lo tengas en tus manos: el pedido quedará '
                    'entregado.',
          button: 'Confirmar recepción',
          icon: Icons.inventory_2_rounded,
        );
      case 'ENTREGADO':
        return (
          title: 'Cierra tu pedido',
          message: 'Marca el pedido como entregado cuando todo esté en orden.',
          button: label,
          icon: Icons.task_alt_rounded,
        );
      case 'PAGADO':
        return (
          title: 'Pago por confirmar',
          message:
              'Revisa el comprobante y confirma el pago para que el pedido '
              'siga su curso.',
          button: label,
          icon: Icons.payments_rounded,
        );
      case 'PENDIENTE_ENVIO':
        return (
          title: 'Listo para preparar',
          message:
              'Pásalo a preparación. Quien hizo el pedido recibe un aviso.',
          button: label,
          icon: Icons.inventory_rounded,
        );
      case 'ENVIADO':
        return (
          title: 'Listo para despachar',
          message:
              'Al marcarlo en camino, el cliente recibe un aviso para '
              'confirmar cuando llegue.',
          button: label,
          icon: Icons.local_shipping_rounded,
        );
      default:
        return (
          title: 'Siguiente paso',
          message: 'Continúa con el pedido cuando estés listo.',
          button: label,
          icon: Icons.arrow_forward_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final textTheme = Theme.of(context).textTheme;
    return CommerceClayCard(
      color: CommerceClayTokens.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CommerceClayIcon(
                icon: copy.icon,
                size: 44,
                iconSize: 22,
                backgroundColor: Colors.white,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      copy.title,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.message,
                      style: textTheme.bodyMedium?.copyWith(
                        color: CommerceClayTokens.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enabled ? onPressed : null,
              icon: const Icon(Icons.check_rounded),
              label: Text(copy.button),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificacionComprobanteCard extends StatelessWidget {
  const _VerificacionComprobanteCard({
    required this.verificacion,
    required this.money,
  });

  final ComprobanteVerificacion verificacion;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final (
      String titulo,
      IconData icono,
      Color color,
    ) = switch (verificacion.veredicto) {
      'COINCIDE' => (
        'La lectura automática coincide con el pedido',
        Icons.verified_rounded,
        AppTheme.primary,
      ),
      'DUPLICADO' => (
        'Posible comprobante repetido',
        Icons.content_copy_rounded,
        AppTheme.red,
      ),
      'ILEGIBLE' => (
        'No se pudo leer el comprobante',
        Icons.visibility_off_rounded,
        AppTheme.red,
      ),
      _ => (
        'Revisa este comprobante manualmente',
        Icons.warning_amber_rounded,
        AppTheme.red,
      ),
    };

    return CommerceClayCard(
      color: CommerceClayTokens.orangeSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icono, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Es una lectura automática de la imagen, no una confirmación del '
            'banco: verifica que el dinero llegó a tu cuenta antes de '
            'confirmar el pago.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (verificacion.montoDetectado != null ||
              verificacion.referencia != null) ...<Widget>[
            const SizedBox(height: 10),
            if (verificacion.montoDetectado != null)
              Text('Valor leído: ${money.format(verificacion.montoDetectado)}'),
            if (verificacion.referencia != null)
              Text('Referencia: ${verificacion.referencia}'),
          ],
          const SizedBox(height: 8),
          for (final check in verificacion.checks)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    switch (check.ok) {
                      true => Icons.check_circle_rounded,
                      false => Icons.cancel_rounded,
                      null => Icons.help_outline_rounded,
                    },
                    size: 18,
                    color: switch (check.ok) {
                      true => AppTheme.primary,
                      false => AppTheme.red,
                      null => Colors.grey,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(check.detalle)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ComprobantePagoCard extends StatelessWidget {
  const _ComprobantePagoCard({
    required this.order,
    required this.uploading,
    required this.onPickFile,
  });

  final CommerceOrderDetail order;
  final bool uploading;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final metodo = order.metodoPago;
    final qrAsset = metodo == null ? null : kMetodoPagoQrAsset[metodo];
    final tieneComprobante = order.comprobanteUrl != null;

    return CommerceClayCard(
      color: tieneComprobante
          ? CommerceClayTokens.mint
          : CommerceClayTokens.orangeSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Pago',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Aún no hay pasarela de pago automática: transfiere y sube tu '
            'comprobante. Un administrador lo revisará para confirmar el pago.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (metodo != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Método elegido: ${kMetodoPagoLabel[metodo] ?? metodo}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (qrAsset != null && !tieneComprobante) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  qrAsset,
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    color: Colors.white,
                    child: const Text(
                      'QR no configurado todavía.\nPregunta a tu administrador cómo pagar.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          if (tieneComprobante)
            Row(
              children: <Widget>[
                const Icon(Icons.check_circle_rounded, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Comprobante enviado. En revisión.'),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(order.comprobanteUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Ver'),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: uploading ? null : onPickFile,
              icon: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(
                uploading ? 'Subiendo…' : 'Adjuntar comprobante de pago',
              ),
            ),
        ],
      ),
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
