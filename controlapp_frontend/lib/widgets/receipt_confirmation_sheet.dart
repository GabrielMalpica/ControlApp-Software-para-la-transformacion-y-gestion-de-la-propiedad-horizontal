import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';

/// Hoja para confirmar que un pedido de conjunto llegó.
///
/// Lo que se suma al inventario (insumo, unidad y cantidad por unidad
/// comprada) viene definido de WooCommerce y aquí solo se LEE: quien recibe no
/// lo edita. Lo que sí hace es reportar si algo no llegó o llegó incompleto;
/// solo lo recibido suma al inventario y se avisa a Control SAS.
///
/// Solo el equipo de Control SAS ([ReceiptPreview.puedeMapear]) puede
/// configurar un producto que todavía no tiene insumo.
///
/// Al confirmar devuelve la lista de novedades (vacía = todo llegó completo)
/// con la forma que espera el backend: `itemId`, `cantidadRecibida`, `nota`.
class ReceiptConfirmationSheet extends StatefulWidget {
  const ReceiptConfirmationSheet({
    super.key,
    required this.preview,
    this.onMapear,
  });

  final ReceiptPreview preview;

  /// Configura un producto sin insumo (solo equipo interno). Devuelve la vista
  /// previa actualizada.
  final Future<ReceiptPreview> Function(
    int itemId,
    int insumoId,
    double? factor,
  )?
  onMapear;

  @override
  State<ReceiptConfirmationSheet> createState() =>
      _ReceiptConfirmationSheetState();
}

class _ReceiptConfirmationSheetState extends State<ReceiptConfirmationSheet> {
  late ReceiptPreview _preview = widget.preview;
  final _recibido = <int, double>{};
  final _notas = <int, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _notas.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _recibidoDe(ReceiptPreviewItem item) =>
      _recibido[item.itemId] ?? item.cantidad;

  bool _incompleto(ReceiptPreviewItem item) =>
      _recibidoDe(item) < item.cantidad;

  bool get _hayNovedades => _preview.items.any(_incompleto);

  String _q(double value) {
    final text = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
    return text.replaceAll('.', ',');
  }

  /// Cuánto suma al inventario lo que llegó de este producto.
  double _inventarioDe(ReceiptPreviewItem item) {
    if (item.cantidad == 0) return 0;
    return _recibidoDe(item) * (item.cantidadInventario / item.cantidad);
  }

  void _cambiarRecibido(ReceiptPreviewItem item, double valor) {
    setState(() => _recibido[item.itemId] = valor.clamp(0, item.cantidad));
  }

  void _marcarCompleto(ReceiptPreviewItem item) {
    setState(() {
      _recibido.remove(item.itemId);
      _notas[item.itemId]?.clear();
    });
  }

  void _marcarIncompleto(ReceiptPreviewItem item) {
    final paso = item.cantidad % 1 == 0 ? 1.0 : 0.5;
    _cambiarRecibido(item, item.cantidad - paso);
  }

  Future<void> _mapear(
    ReceiptPreviewItem item,
    int insumoId,
    double? factor,
  ) async {
    final onMapear = widget.onMapear;
    if (onMapear == null) return;
    try {
      final updated = await onMapear(item.itemId, insumoId, factor);
      if (mounted) setState(() => _preview = updated);
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    }
  }

  List<Map<String, dynamic>> _novedades() {
    return <Map<String, dynamic>>[
      for (final item in _preview.items)
        if (_incompleto(item))
          <String, dynamic>{
            'itemId': item.itemId,
            'cantidadRecibida': _recibidoDe(item),
            if (_notas[item.itemId]?.text.trim().isNotEmpty ?? false)
              'nota': _notas[item.itemId]!.text.trim(),
          },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
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
              Text('Confirma la recepción', style: textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(_preview.mensaje),
              const SizedBox(height: 16),
              for (final item in _preview.items) _itemCard(item, textTheme),
              _avisoFinal(),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Volver'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _preview.puedeAplicar
                          ? () => Navigator.pop(context, _novedades())
                          : null,
                      icon: const Icon(Icons.inventory_rounded),
                      label: Text(
                        _hayNovedades
                            ? 'Confirmar con novedades'
                            : 'Confirmar recepción',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemCard(ReceiptPreviewItem item, TextTheme textTheme) {
    final incompleto = _incompleto(item);
    return CommerceClayCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(item.producto, style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('Pediste ${_q(item.cantidad)}', style: textTheme.bodySmall),
          const SizedBox(height: 10),
          if (item.insumo != null)
            _detalleFijo(item, textTheme)
          else
            _sinInsumo(item),
          if (item.insumo != null) ...<Widget>[
            const SizedBox(height: 12),
            _llegada(item),
            if (incompleto) ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                controller: _notas.putIfAbsent(
                  item.itemId,
                  TextEditingController.new,
                ),
                maxLength: 300,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: '¿Qué pasó? (opcional)',
                  hintText: 'Ej: una caja llegó rota',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Lo definido en WooCommerce: solo lectura.
  Widget _detalleFijo(ReceiptPreviewItem item, TextTheme textTheme) {
    final insumo = item.insumo!;
    final incompleto = _incompleto(item);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CommerceClayTokens.mint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_outline_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  incompleto
                      ? 'Se sumarán ${_q(_inventarioDe(item))} ${insumo.unidad} a «${insumo.nombre}»'
                      : 'Suma ${_q(_inventarioDe(item))} ${insumo.unidad} a «${insumo.nombre}»',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Definido en la tienda: no se puede cambiar aquí.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _llegada(ReceiptPreviewItem item) {
    final incompleto = _incompleto(item);
    final paso = item.cantidad % 1 == 0 ? 1.0 : 0.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.check_circle_outline_rounded),
              label: Text('Llegó completo'),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.report_gmailerrorred_rounded),
              label: Text('No llegó completo'),
            ),
          ],
          selected: <bool>{incompleto},
          onSelectionChanged: (seleccion) {
            if (seleccion.first) {
              _marcarIncompleto(item);
            } else {
              _marcarCompleto(item);
            }
          },
        ),
        if (incompleto) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              IconButton.filledTonal(
                tooltip: 'Menos',
                onPressed: _recibidoDe(item) <= 0
                    ? null
                    : () => _cambiarRecibido(item, _recibidoDe(item) - paso),
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text(
                  'Llegaron ${_q(_recibidoDe(item))} de ${_q(item.cantidad)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Más',
                onPressed: _recibidoDe(item) + paso >= item.cantidad - 0.0001
                    ? null
                    : () => _cambiarRecibido(item, _recibidoDe(item) + paso),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Producto que todavía no es un insumo del inventario.
  Widget _sinInsumo(ReceiptPreviewItem item) {
    if (!_preview.puedeMapear) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3DC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline_rounded, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Este producto aún no está configurado como insumo. Avisa a '
                'Control SAS para poder confirmar la recepción.',
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<int>(
          initialValue: item.insumo?.id,
          decoration: const InputDecoration(
            labelText: 'Mapeo pendiente',
            prefixIcon: Icon(Icons.link_off_rounded),
          ),
          items: _preview.insumosDisponibles
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
          // Solo se elige el insumo: la cantidad por unidad comprada es la que
          // ya tiene definida ese insumo.
          onChanged: (insumoId) {
            if (insumoId != null) _mapear(item, insumoId, null);
          },
        ),
      ],
    );
  }

  Widget _avisoFinal() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3DC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            _hayNovedades
                ? Icons.report_problem_rounded
                : Icons.warning_amber_rounded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _hayNovedades
                  ? 'Se registrará la novedad, se avisará a Control SAS y solo '
                        'se sumará al inventario lo que llegó. La entrada es '
                        'definitiva.'
                  : 'Esta entrada es definitiva. El stock solo se sumará una vez.',
            ),
          ),
        ],
      ),
    );
  }
}
