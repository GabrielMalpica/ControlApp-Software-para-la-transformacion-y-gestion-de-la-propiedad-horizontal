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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    if (_items.isEmpty) {
      return CommerceStateView(
        icon: _filtro == _Filtro.porRevisar
            ? Icons.task_alt_rounded
            : Icons.receipt_long_outlined,
        title: _filtro == _Filtro.porRevisar
            ? 'Nada por revisar'
            : 'Sin pagos para mostrar',
        message: _filtro == _Filtro.porRevisar
            ? 'Todos los pagos recibidos se aplicaron solos.'
            : 'Prueba con otro filtro o busca por otra referencia.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[
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

  Future<String?> _pedirMotivo(String accion) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          accion == 'DEVUELTO' ? 'Marcar como devuelto' : 'Marcar como resuelto',
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
                      onPressed: _resolving ? null : () => _resolver('DEVUELTO'),
                      child: const Text('Se devolvió el dinero'),
                    ),
                    OutlinedButton(
                      onPressed: _resolving ? null : () => _resolver('RESUELTO'),
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
              evento.estadoNuevo != null
                  ? '${evento.tipo} · ${pagoEstadoLabel(evento.estadoNuevo!)}'
                  : evento.tipo,
            ),
            subtitle: Text(
              [
                if (evento.detalle != null) evento.detalle!,
                if (evento.creadoEn != null)
                  _date.format(evento.creadoEn!.toLocal()),
              ].join('\n'),
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
