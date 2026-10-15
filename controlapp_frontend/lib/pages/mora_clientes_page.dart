import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/saldos_api.dart';
import 'package:flutter_application_1/model/saldo_servicio_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';
import 'package:intl/intl.dart';

/// "Clientes en mora" (gerente / jefe de operaciones): quién debe el saldo de
/// un servicio ya prestado y por eso no puede hacer pedidos. Desde aquí se
/// registra un pago hecho por fuera (efectivo, transferencia directa), lo que
/// levanta el bloqueo. Con [puedeGestionar] en false solo se consulta.
class MoraClientesPage extends StatefulWidget {
  const MoraClientesPage({super.key, this.puedeGestionar = true});

  final bool puedeGestionar;

  @override
  State<MoraClientesPage> createState() => _MoraClientesPageState();
}

class _MoraClientesPageState extends State<MoraClientesPage> {
  static const Map<String, String> _filtros = <String, String>{
    'PENDIENTE': 'En mora',
    'PAGADO': 'Pagados con Bre-B',
    'PAGADO_POR_FUERA': 'Pagados por fuera',
    'TODOS': 'Todos',
  };

  final _api = SaldosApi();
  final _searchCtrl = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );
  final _date = DateFormat('dd/MM/yyyy');

  String _filtro = 'PENDIENTE';
  bool _loading = true;
  String? _error;
  MoraListado? _listado;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listado = await _api.listarMora(
        estado: _filtro,
        q: _searchCtrl.text,
      );
      if (!mounted) return;
      setState(() => _listado = listado);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registrarPagoPorFuera(MoraCliente item) async {
    final motivo = await _pedirMotivo(item);
    if (motivo == null || !mounted) return;
    try {
      final habiaCodigo = await _api.registrarPagoPorFuera(item.id, motivo);
      if (!mounted) return;
      AppFeedback.showInfo(
        context,
        title: 'Saldo registrado como pagado',
        message: habiaCodigo
            ? 'Ya puede volver a pedir. Tenía un código de pago vigente: si lo paga igual, ese pago queda en Pagos > Por revisar.'
            : 'Ya puede volver a pedir.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    }
  }

  Future<String?> _pedirMotivo(MoraCliente item) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registrar pago por fuera'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${item.nombre} · ${_money.format(item.montoSaldo)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Cómo se pagó',
                helperText:
                    'Queda con tu nombre. No mueve dinero: solo cierra el saldo.',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.length < 5) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
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
          'Clientes en mora',
          style: TextStyle(
            color: CommerceClayTokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: CommerceClayBackground(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, correo, teléfono u orden',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            _load();
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: <Widget>[
                  for (final entry in _filtros.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: _filtro == entry.key,
                        label: Text(entry.value),
                        onSelected: (_) {
                          setState(() => _filtro = entry.key);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _listado == null) return const SkeletonList();
    if (_error != null) {
      return CommerceStateView(
        icon: Icons.wifi_off_rounded,
        title: 'No pudimos cargar la lista',
        message: _error!,
        actionLabel: 'Intentar de nuevo',
        onAction: _load,
      );
    }
    final listado = _listado;
    if (listado == null || listado.items.isEmpty) {
      return CommerceStateView(
        icon: Icons.check_circle_outline_rounded,
        title: _filtro == 'PENDIENTE'
            ? 'Nadie está en mora'
            : 'No hay saldos en esta lista',
        message: _filtro == 'PENDIENTE'
            ? 'Cuando un servicio con anticipo termine y no se pague el saldo, el cliente aparecerá aquí.'
            : 'Prueba con otro filtro o búsqueda.',
        actionLabel: 'Actualizar',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: <Widget>[
          CommerceClayCard(
            color: CommerceClayTokens.orangeSoft,
            child: Text(
              '${listado.clientesEnMora} en mora · '
              '${_money.format(listado.montoPendiente)} por cobrar',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          for (final item in listado.items) ...<Widget>[
            _MoraCard(
              item: item,
              money: _money,
              date: _date,
              puedeGestionar: widget.puedeGestionar,
              onPagoPorFuera: () => _registrarPagoPorFuera(item),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MoraCard extends StatelessWidget {
  const _MoraCard({
    required this.item,
    required this.money,
    required this.date,
    required this.puedeGestionar,
    required this.onPagoPorFuera,
  });

  final MoraCliente item;
  final NumberFormat money;
  final DateFormat date;
  final bool puedeGestionar;
  final VoidCallback onPagoPorFuera;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pedido = item.pedidoAppId != null
        ? 'Pedido #${item.pedidoAppId} (app) · orden #${item.wooOrderId}'
        : 'Orden #${item.wooOrderId} (página web)';
    return CommerceClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  item.nombre,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                money.format(item.montoSaldo),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (item.pendiente && item.diasEnMora != null)
            Text(
              item.diasEnMora == 0
                  ? 'En mora desde hoy'
                  : 'En mora hace ${item.diasEnMora} día${item.diasEnMora == 1 ? '' : 's'}',
              style: textTheme.labelMedium?.copyWith(color: AppTheme.red),
            ),
          const SizedBox(height: 6),
          if (item.documento != null) _Dato('Documento', item.documento!),
          if (item.telefono != null) _Dato('Teléfono', item.telefono!),
          if (item.correo != null) _Dato('Correo', item.correo!),
          if (item.direccion != null) _Dato('Dirección', item.direccion!),
          _Dato('Servicio', item.servicios),
          _Dato('Pedido', pedido),
          _Dato(
            'Pagos',
            'Total ${money.format(item.totalOrden)} · anticipo ${money.format(item.pagadoAntes)}',
          ),
          if (item.servicioTerminadoEn != null)
            _Dato(
              'Terminado',
              date.format(item.servicioTerminadoEn!.toLocal()),
            ),
          if (item.pedidosEnMora.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hizo pedidos estando en mora (no se pudo verificar en el momento): '
                '${item.pedidosEnMora.map((o) => '#$o').join(', ')}',
                style: textTheme.bodySmall?.copyWith(color: AppTheme.red),
              ),
            ),
          if (!item.pendiente) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              item.estado == 'PAGADO_POR_FUERA'
                  ? 'Pagado por fuera${item.resueltoPorNombre == null ? '' : ' · registró ${item.resueltoPorNombre}'}'
                        '${item.resolucionMotivo == null ? '' : ': ${item.resolucionMotivo}'}'
                  : 'Pagado con Bre-B${item.pagadoEn == null ? '' : ' el ${date.format(item.pagadoEn!.toLocal())}'}',
              style: textTheme.bodySmall,
            ),
          ],
          if (item.pendiente && puedeGestionar) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onPagoPorFuera,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Registrar pago por fuera'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SelectableText.rich(
        TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: '$etiqueta: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: valor),
          ],
        ),
      ),
    );
  }
}
