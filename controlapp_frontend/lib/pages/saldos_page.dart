import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/saldos_api.dart';
import 'package:flutter_application_1/model/saldo_servicio_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_application_1/widgets/pago_factus_card.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.currency(
  locale: 'es_CO',
  symbol: r'$',
  decimalDigits: 0,
);
final _date = DateFormat('dd/MM/yyyy');

/// "Mis saldos": lo que falta pagar de servicios ya prestados (pagados con
/// anticipo). Mientras haya uno pendiente el servidor no deja hacer pedidos.
class SaldosPage extends StatefulWidget {
  const SaldosPage({super.key});

  @override
  State<SaldosPage> createState() => _SaldosPageState();
}

class _SaldosPageState extends State<SaldosPage> {
  final _api = SaldosApi();
  bool _loading = true;
  String? _error;
  List<SaldoServicio> _saldos = const <SaldoServicio>[];

  @override
  void initState() {
    super.initState();
    NotificacionesCenter.instance.saldoActualizado.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    NotificacionesCenter.instance.saldoActualizado.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saldos = await _api.listarMios();
      if (!mounted) return;
      setState(() => _saldos = saldos);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abrir(SaldoServicio saldo) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => SaldoPagoPage(saldoId: saldo.id)),
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
          'Mis saldos',
          style: TextStyle(
            color: CommerceClayTokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: CommerceClayBackground(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _saldos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return CommerceStateView(
        icon: Icons.wifi_off_rounded,
        title: 'No pudimos ver tus saldos',
        message: _error!,
        actionLabel: 'Intentar de nuevo',
        onAction: _load,
      );
    }
    if (_saldos.isEmpty) {
      return CommerceStateView(
        icon: Icons.check_circle_outline_rounded,
        title: 'Estás al día',
        message: 'No tienes saldos pendientes de servicios.',
        actionLabel: 'Volver',
        onAction: () => Navigator.pop(context),
      );
    }
    final pendientes = _saldos.where((s) => s.pendiente).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: <Widget>[
          if (pendientes.isNotEmpty)
            CommerceHeroCard(
              eyebrow: 'Saldo pendiente',
              title: _money.format(
                pendientes.fold<double>(0, (suma, s) => suma + s.montoSaldo),
              ),
              subtitle:
                  'Págalo para seguir haciendo pedidos en la app y en la página.',
              icon: Icons.account_balance_wallet_outlined,
            ),
          const SizedBox(height: 16),
          for (final saldo in _saldos) ...<Widget>[
            CommerceClayCard(
              onTap: () => _abrir(saldo),
              child: Row(
                children: <Widget>[
                  Icon(
                    saldo.pendiente
                        ? Icons.schedule_rounded
                        : Icons.check_circle_rounded,
                    color: saldo.pendiente
                        ? CommerceClayTokens.orange
                        : CommerceClayTokens.ink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          saldo.servicios,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          saldo.pendiente
                              ? 'Falta ${_money.format(saldo.montoSaldo)}'
                              : 'Pagado · ${_money.format(saldo.montoSaldo)}',
                        ),
                        if (saldo.servicioTerminadoEn != null)
                          Text(
                            'Servicio terminado el '
                            '${_date.format(saldo.servicioTerminadoEn!.toLocal())}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (saldo.pendiente) const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Pagar el saldo de un servicio: el código (QR y llave Bre-B) es solo por lo
/// que falta y el monto lo pone el servidor. El pago se confirma solo (aviso de
/// Factus -> campanita); "Ya pagué" aparece como respaldo.
class SaldoPagoPage extends StatefulWidget {
  const SaldoPagoPage({super.key, required this.saldoId});

  final int saldoId;

  @override
  State<SaldoPagoPage> createState() => _SaldoPagoPageState();
}

class _SaldoPagoPageState extends State<SaldoPagoPage> {
  final _api = SaldosApi();
  SaldoServicio? _saldo;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _pagoError;

  // Solo redibuja la tarjeta cuando toca ofrecer "Ya pagué"; no consulta nada.
  Timer? _yaPagueTimer;

  @override
  void initState() {
    super.initState();
    NotificacionesCenter.instance.saldoActualizado.addListener(_onAviso);
    _load();
  }

  @override
  void dispose() {
    _yaPagueTimer?.cancel();
    NotificacionesCenter.instance.saldoActualizado.removeListener(_onAviso);
    super.dispose();
  }

  void _onAviso() {
    final aviso = NotificacionesCenter.instance.saldoActualizado.value;
    if (aviso == null || aviso.referenciaId != widget.saldoId) return;
    if (!mounted || _busy) return;
    _load(silencioso: true);
  }

  void _usar(SaldoServicio saldo) {
    _yaPagueTimer?.cancel();
    _yaPagueTimer = null;
    _saldo = saldo;
    final falta = saldo.cobro?.faltaParaVerificarManual(DateTime.now());
    if (falta != null && falta > Duration.zero) {
      _yaPagueTimer = Timer(falta, () {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _load({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final saldo = await _api.obtener(widget.saldoId);
      if (!mounted) return;
      setState(() => _usar(saldo));
    } catch (error) {
      if (!mounted) return;
      if (!silencioso) setState(() => _error = AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generar() async {
    setState(() {
      _busy = true;
      _pagoError = null;
    });
    try {
      final saldo = await _api.pagar(widget.saldoId);
      if (!mounted) return;
      setState(() => _usar(saldo));
    } catch (error) {
      if (!mounted) return;
      setState(() => _pagoError = AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verificar() async {
    setState(() {
      _busy = true;
      _pagoError = null;
    });
    try {
      final saldo = await _api.verificar(widget.saldoId);
      if (!mounted) return;
      setState(() => _usar(saldo));
      AppFeedback.showInfo(
        context,
        title: saldo.pendiente ? 'Todavía no vemos el pago' : 'Saldo pagado',
        message: saldo.pendiente
            ? 'Si ya pagaste, espera unos segundos: se confirma solo.'
            : 'Ya puedes seguir haciendo pedidos.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          'Pagar saldo',
          style: TextStyle(
            color: CommerceClayTokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: CommerceClayBackground(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final saldo = _saldo;
    if (_loading && saldo == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || saldo == null) {
      return CommerceStateView(
        icon: Icons.wifi_off_rounded,
        title: 'No pudimos ver este saldo',
        message: _error ?? 'Intenta de nuevo.',
        actionLabel: 'Intentar de nuevo',
        onAction: _load,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
      children: <Widget>[
        CommerceClayCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                saldo.servicios,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text('Total del pedido: ${_money.format(saldo.totalOrden)}'),
              Text('Anticipo pagado: ${_money.format(saldo.pagadoAntes)}'),
              Text(
                saldo.pendiente
                    ? 'Falta por pagar: ${_money.format(saldo.montoSaldo)}'
                    : 'Saldo pagado: ${_money.format(saldo.montoSaldo)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (saldo.pendiente) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Mientras este saldo esté pendiente no podrás hacer pedidos nuevos.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (saldo.pendiente && saldo.cobro == null)
          // El código se genera cuando la persona decide pagar.
          CommerceClayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Paga con el QR o la llave Bre-B desde tu app bancaria o Nequi.',
                ),
                if (_pagoError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _pagoError!,
                    style: const TextStyle(color: CommerceClayTokens.orange),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _generar,
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(
                    _busy
                        ? 'Generando código…'
                        : 'Pagar ${_money.format(saldo.montoSaldo)} con Bre-B',
                  ),
                ),
              ],
            ),
          )
        else if (saldo.pendiente)
          PagoFactusCard(
            titulo: 'Pagar saldo',
            pago: saldo.cobro,
            money: _money,
            busy: _busy,
            error: _pagoError,
            onVerificar: _verificar,
            onGenerarNuevo: _generar,
          )
        else
          const CommerceClayCard(
            color: CommerceClayTokens.mint,
            child: Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Este saldo ya está pagado. ¡Gracias!',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Aviso "Tienes un saldo pendiente" para poner arriba del carrito y de los
/// pedidos. No consulta en bucle: carga al abrir y cuando la campanita trae un
/// aviso de saldo.
class SaldoPendienteBanner extends StatefulWidget {
  const SaldoPendienteBanner({super.key});

  @override
  State<SaldoPendienteBanner> createState() => _SaldoPendienteBannerState();
}

class _SaldoPendienteBannerState extends State<SaldoPendienteBanner> {
  final _api = SaldosApi();
  double _pendiente = 0;

  @override
  void initState() {
    super.initState();
    NotificacionesCenter.instance.saldoActualizado.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    NotificacionesCenter.instance.saldoActualizado.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final saldos = await _api.listarMios();
      if (!mounted) return;
      setState(() {
        _pendiente = saldos
            .where((s) => s.pendiente)
            .fold<double>(0, (suma, s) => suma + s.montoSaldo);
      });
    } catch (_) {
      // Es solo un aviso: si falla, el servidor igual bloquea al pedir.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendiente <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CommerceClayCard(
        color: CommerceClayTokens.orangeSoft,
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => const SaldosPage()),
          );
          if (mounted) await _load();
        },
        child: Row(
          children: <Widget>[
            const Icon(Icons.account_balance_wallet_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tienes un saldo pendiente de ${_money.format(_pendiente)} por un '
                'servicio ya prestado. Págalo para seguir haciendo pedidos.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
