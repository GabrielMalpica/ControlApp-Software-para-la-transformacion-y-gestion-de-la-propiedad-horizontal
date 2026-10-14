import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/pagos_admin_api.dart';
import 'package:flutter_application_1/model/pago_admin_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';
import 'package:intl/intl.dart';

/// Panel de pagos (gerente / jefe de operaciones): historial de cobros de
/// Factus Pay de la app y de la tienda web, los que necesitan una decisión y
/// la conciliación con Factus.
class PagosAdminPage extends StatefulWidget {
  const PagosAdminPage({super.key});

  @override
  State<PagosAdminPage> createState() => _PagosAdminPageState();
}

enum _Filtro { todos, porRevisar, pagados, pendientes, fallidos }

class _PagosAdminPageState extends State<PagosAdminPage> {
  final _api = PagosAdminApi();
  final _money = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );
  final _date = DateFormat('dd/MM/yyyy · h:mm a');
  final _searchCtrl = TextEditingController();

  _Filtro _filtro = _Filtro.porRevisar;
  List<PagoAdminItem> _items = const [];
  int _total = 0;
  int _pagina = 1;
  bool _hayMas = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _conciliando = false;
  String? _error;
  SaludPagos? _salud;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Salud del webhook de Factus: informativa, si falla no bloquea la lista.
  Future<void> _cargarSalud() async {
    try {
      final salud = await _api.salud();
      if (mounted) setState(() => _salud = salud);
    } catch (_) {
      // La lista de pagos sigue sirviendo sin este resumen.
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<PagoAdminPagina> _fetch(int pagina) {
    return _api.listar(
      soloRequierenAccion: _filtro == _Filtro.porRevisar,
      estado: switch (_filtro) {
        _Filtro.pagados => 'PAGADO',
        _Filtro.pendientes => 'PENDIENTE',
        _Filtro.fallidos => 'FALLIDO',
        _ => null,
      },
      busqueda: _searchCtrl.text,
      pagina: pagina,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_cargarSalud());
    try {
      final page = await _fetch(1);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _pagina = 1;
        _hayMas = page.hayMas;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hayMas) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_pagina + 1);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _pagina = page.pagina;
        _hayMas = page.hayMas;
      });
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _conciliar() async {
    setState(() => _conciliando = true);
    try {
      final reporte = await _api.conciliar();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _ConciliacionDialog(reporte: reporte),
      );
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _conciliando = false);
    }
  }

  Future<void> _abrirDetalle(PagoAdminItem item) async {
    final cambio = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PagoDetalleSheet(cobroId: item.id, api: _api),
    );
    if (cambio == true && mounted) await _load();
  }

  static const _labels = <_Filtro, String>{
    _Filtro.porRevisar: 'Por revisar',
    _Filtro.todos: 'Todos',
    _Filtro.pagados: 'Pagados',
    _Filtro.pendientes: 'Pendientes',
    _Filtro.fallidos: 'Fallidos',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommerceClayTokens.canvas,
      appBar: AppBar(
        backgroundColor: CommerceClayTokens.canvas,
        foregroundColor: CommerceClayTokens.ink,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Pagos',
          style: TextStyle(
            color: CommerceClayTokens.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Conciliar con Factus',
            onPressed: _conciliando ? null : _conciliar,
            icon: _conciliando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_alt_rounded),
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
                  hintText: 'Buscar por referencia, pedido u orden',
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
                  for (final filtro in _labels.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: _filtro == filtro,
                        label: Text(_labels[filtro]!),
                        onSelected: (_) {
                          setState(() => _filtro = filtro);
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
    if (_loading) return const SkeletonList();
    if (_error != null) {
      return CommerceStateView(
        icon: Icons.wifi_off_rounded,
        title: 'No pudimos cargar los pagos',
        message: _error!,
        actionLabel: 'Intentar de nuevo',
        onAction: _load,
      );
    }
    // Un solo scroll: la salud del webhook va como primer elemento de la lista.
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[
          if (_salud != null) _SaludCard(salud: _salud!, date: _date),
          if (_items.isEmpty)
            CommerceStateView(
              icon: _filtro == _Filtro.porRevisar
                  ? Icons.task_alt_rounded
                  : Icons.receipt_long_outlined,
              title: _filtro == _Filtro.porRevisar
                  ? 'Nada por revisar'
                  : 'Sin pagos para mostrar',
              message: _filtro == _Filtro.porRevisar
                  ? 'Todos los pagos recibidos se aplicaron solos.'
                  : 'Prueba con otro filtro o busca por otra referencia.',
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$_total ${_total == 1 ? 'cobro' : 'cobros'}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          for (final item in _items)
            _PagoCard(
              item: item,
              money: _money,
              date: _date,
              onTap: () => _abrirDetalle(item),
            ),
          if (_hayMas)
            Center(
              child: TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? 'Cargando…' : 'Cargar más'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cómo se están confirmando los pagos: por el aviso de Factus (webhook) o
/// consultando seguido, y si el aviso está llegando.
class _SaludCard extends StatelessWidget {
  const _SaludCard({required this.salud, required this.date});

  final SaludPagos salud;
  final DateFormat date;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final alerta = salud.conNovedades;
    final titulo = salud.usaWebhook
        ? 'Pagos confirmados por aviso de Factus'
        : 'Verificación frecuente de pagos';
    final descripcion = salud.usaWebhook
        ? 'Factus avisa cada pago y el sistema lo confirma consultando su API.'
        : 'El sistema consulta a Factus seguido para detectar los pagos.';
    return CommerceClayCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      color: alerta ? CommerceClayTokens.orangeSoft : CommerceClayTokens.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                alerta ? Icons.warning_amber_rounded : Icons.bolt_rounded,
                color: alerta ? AppTheme.red : AppTheme.primaryDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(descripcion, style: textTheme.bodySmall),
          if (salud.motivo != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                salud.motivo!,
                style: textTheme.bodySmall?.copyWith(
                  color: AppTheme.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            !salud.webhookConfigurado
                ? 'El aviso de Factus (webhook) no está configurado.'
                : salud.ultimoWebhookEn == null
                ? 'Todavía no ha llegado ningún aviso de Factus.'
                : 'Último aviso de Factus: ${date.format(salud.ultimoWebhookEn!.toLocal())}',
            style: textTheme.bodySmall,
          ),
          Text(
            'Últimos 7 días: ${salud.confirmados7d} pago(s) confirmados, '
            '${salud.confirmadosPorWebhook7d} por aviso de Factus.',
            style: textTheme.bodySmall,
          ),
          if (salud.pagosSinWebhook24h > 0)
            Text(
              '${salud.pagosSinWebhook24h} pago(s) de las últimas 24 h llegaron '
              'sin aviso: revisa la URL y la llave del webhook en Factus.',
              style: textTheme.bodySmall?.copyWith(
                color: AppTheme.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (salud.avisosSinProcesar > 0)
            Text(
              'Avisos en proceso: ${salud.avisosSinProcesar}',
              style: textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

Color _colorEstado(String estado) {
  switch (estado) {
    case 'PAGADO':
    case 'RESUELTO':
    case 'DEVUELTO':
      return AppTheme.primary;
    case 'PAGADO_HUERFANO':
    case 'PAGADO_DUPLICADO':
    case 'DISCREPANCIA':
    case 'FALLIDO':
    case 'ERROR':
      return AppTheme.red;
    default:
      return CommerceClayTokens.muted;
  }
}

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final color = _colorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        pagoEstadoLabel(estado),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PagoCard extends StatelessWidget {
  const _PagoCard({
    required this.item,
    required this.money,
    required this.date,
    required this.onTap,
  });

  final PagoAdminItem item;
  final NumberFormat money;
  final DateFormat date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return CommerceClayCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      color: item.requiereAccion
          ? CommerceClayTokens.orangeSoft
          : CommerceClayTokens.surface,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  money.format(item.montoEsperado),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _EstadoChip(estado: item.estado),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.origen}${item.conjuntoNombre == null ? '' : ' · ${item.conjuntoNombre}'}',
            style: textTheme.bodyMedium,
          ),
          Text(
            '${item.esTienda ? 'Tienda web' : 'App'} · ${item.creadoEn == null ? '' : date.format(item.creadoEn!.toLocal())}',
            style: textTheme.bodySmall,
          ),
          if (item.requiereAccion)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Toca revisarlo',
                style: textTheme.labelMedium?.copyWith(
                  color: AppTheme.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PagoDetalleSheet extends StatefulWidget {
  const _PagoDetalleSheet({required this.cobroId, required this.api});

  final int cobroId;
  final PagosAdminApi api;

  @override
  State<_PagoDetalleSheet> createState() => _PagoDetalleSheetState();
}

class _PagoDetalleSheetState extends State<_PagoDetalleSheet> {
  final _money = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );
  final _date = DateFormat('dd/MM/yyyy · h:mm a');
  PagoAdminDetalle? _detalle;
  String? _error;
  bool _loading = true;
  bool _resolving = false;
  bool _verificando = false;
  bool _cambio = false;

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
      final detalle = await widget.api.detalle(widget.cobroId);
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
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

  Future<void> _resolver(String accion) async {
    final motivo = await _pedirMotivo(accion);
    if (motivo == null || !mounted) return;
    setState(() => _resolving = true);
    try {
      final detalle = await widget.api.resolver(
        widget.cobroId,
        accion: accion,
        motivo: motivo,
      );
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
        _cambio = true;
      });
      AppFeedback.showInfo(
        context,
        title: 'Cobro cerrado',
        message: 'Quedó registrado en el historial del cobro.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// Consulta el recaudo en Factus ahora. El backend solo lo marca pagado si
  /// la API de Factus lo confirma.
  Future<void> _verificar() async {
    final antes = _detalle?.item.estado;
    setState(() => _verificando = true);
    try {
      final detalle = await widget.api.verificar(widget.cobroId);
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
        _cambio = true;
      });
      final estado = detalle.item.estado;
      AppFeedback.showInfo(
        context,
        title: estado == 'PAGADO'
            ? 'Factus confirmó el pago'
            : 'Consulta hecha',
        message: estado != antes
            ? 'El cobro quedó: ${pagoEstadoLabel(estado)}.'
            : 'Factus todavía no reporta este pago.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<String?> _pedirMotivo(String accion) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          accion == 'DEVUELTO'
              ? 'Marcar como devuelto'
              : 'Marcar como resuelto',
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'Qué se hizo',
            helperText: accion == 'DEVUELTO'
                ? 'Esto solo deja constancia: la devolución se hace por fuera.'
                : 'Esto solo deja constancia; no reactiva el pedido.',
          ),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _cambio);
      },
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    final item = _detalle!.item;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _money.format(item.montoEsperado),
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _EstadoChip(estado: item.estado),
          ],
        ),
        const SizedBox(height: 6),
        Text(item.origen, style: textTheme.titleSmall),
        if (item.conjuntoNombre != null) Text(item.conjuntoNombre!),
        const SizedBox(height: 4),
        SelectableText(
          'Referencia ${item.referenceCode}',
          style: textTheme.bodySmall,
        ),
        if (item.montoProveedor != null &&
            item.montoProveedor != item.montoEsperado)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Factus confirmó ${_money.format(item.montoProveedor)}',
              style: textTheme.bodyMedium?.copyWith(
                color: AppTheme.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (item.pendienteSincronizarWoo)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'La tienda todavía no refleja este pago; se reintenta solo.',
              style: textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 14),
        _ConfirmacionInfo(
          item: item,
          webhooks: _detalle!.webhooks,
          date: _date,
        ),
        if (item.verificable) ...<Widget>[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _verificando ? null : _verificar,
            icon: _verificando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_rounded),
            label: Text(
              _verificando ? 'Consultando a Factus…' : 'Verificar con Factus',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Consulta el cobro en Factus ahora. Solo queda pagado si Factus '
            'lo confirma.',
            style: textTheme.bodySmall,
          ),
        ],
        if (item.requiereAccion) ...<Widget>[
          const SizedBox(height: 16),
          CommerceClayCard(
            color: CommerceClayTokens.orangeSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Este pago necesita una decisión',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'El dinero llegó pero no se pudo aplicar solo. Resuélvelo por '
                  'fuera (devolver el dinero, reactivar el pedido) y deja aquí '
                  'constancia de lo que hiciste.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton(
                      onPressed: _resolving
                          ? null
                          : () => _resolver('DEVUELTO'),
                      child: const Text('Se devolvió el dinero'),
                    ),
                    OutlinedButton(
                      onPressed: _resolving
                          ? null
                          : () => _resolver('RESUELTO'),
                      child: const Text('Se resolvió de otra forma'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Historial del cobro',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        for (final evento in _detalle!.eventos.reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              evento.tipo == 'ERROR'
                  ? Icons.error_outline_rounded
                  : evento.tipo == 'ACCION_MANUAL'
                  ? Icons.person_rounded
                  : Icons.history_rounded,
              size: 20,
            ),
            title: Text(
              evento.estadoNuevo != null &&
                      evento.estadoNuevo != evento.estadoAnterior
                  ? '${pagoEventoLabel(evento.tipo)} · ${pagoEstadoLabel(evento.estadoNuevo!)}'
                  : pagoEventoLabel(evento.tipo),
            ),
            subtitle: Text(
              [
                if (evento.detalle != null) evento.detalle!,
                if (evento.origen != null)
                  'Por: ${pagoOrigenLabel(evento.origen)}',
                if (evento.creadoEn != null)
                  _date.format(evento.creadoEn!.toLocal()),
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

/// Cómo se confirmó el pago (toda confirmación la decide la API de Factus;
/// esto dice qué la disparó), los avisos del webhook y el pagador.
class _ConfirmacionInfo extends StatelessWidget {
  const _ConfirmacionInfo({
    required this.item,
    required this.webhooks,
    required this.date,
  });

  final PagoAdminItem item;
  final List<PagoAdminWebhook> webhooks;
  final DateFormat date;

  String _fecha(DateTime value) => date.format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pendiente =
        item.estado == 'CREADO' ||
        item.estado == 'PENDIENTE' ||
        item.estado == 'VENCIDO';
    final lineas = <String>[
      if (item.pagadoDetectadoEn != null)
        'Pagado el ${_fecha(item.pagadoDetectadoEn!)}, confirmado con la API '
            'de Factus por ${pagoOrigenLabel(item.origenConfirmacion)}.',
      item.webhooksRecibidos == 0
          ? 'Sin avisos de Factus para este cobro.'
          : 'Avisos de Factus: ${item.webhooksRecibidos}'
                '${item.webhookPrimeroEn == null ? '' : ' (el primero: ${_fecha(item.webhookPrimeroEn!)})'}',
      if (item.ultimaVerificacionEn != null)
        'Última consulta a Factus: ${_fecha(item.ultimaVerificacionEn!)} '
            '(${pagoOrigenLabel(item.ultimaVerificacionOrigen)})',
      if (pendiente && item.qrExpiraEn != null)
        'El código vence: ${_fecha(item.qrExpiraEn!)}',
      if (item.pagador != null) 'Pagó: ${item.pagador}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Confirmación',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        for (final linea in lineas) Text(linea, style: textTheme.bodySmall),
        for (final aviso in webhooks)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '• ${aviso.recibidoEn == null ? '' : _fecha(aviso.recibidoEn!)} · '
              '${webhookResultadoLabel(aviso.resultado)}'
              '${aviso.detalle == null ? '' : '\n  ${aviso.detalle}'}',
              style: textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _ConciliacionDialog extends StatelessWidget {
  const _ConciliacionDialog({required this.reporte});

  final ConciliacionReporte reporte;

  @override
  Widget build(BuildContext context) {
    final ok = reporte.anomalias.isEmpty;
    return AlertDialog(
      icon: Icon(
        ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
        color: ok ? AppTheme.primary : AppTheme.red,
        size: 40,
      ),
      title: Text(ok ? 'Todo cuadra con Factus' : 'Conciliación con novedades'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Recaudos pagados en Factus: ${reporte.remotosPagados}'),
            if (!reporte.completo)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'El listado de Factus es muy largo y solo se revisó una parte.',
                ),
              ),
            for (final anomalia in reporte.anomalias) ...<Widget>[
              const Divider(),
              Text(
                anomalia.referenceCode,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(anomalia.detalle),
              if (anomalia.corregida)
                const Text(
                  'Corregido automáticamente',
                  style: TextStyle(color: AppTheme.primary),
                ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
