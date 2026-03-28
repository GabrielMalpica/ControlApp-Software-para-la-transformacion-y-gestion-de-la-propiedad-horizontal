import 'package:flutter/material.dart';

import '../api/herramienta_api.dart';
import '../service/app_constants.dart';
import '../service/app_error.dart';
import '../service/theme.dart';
import 'package:flutter_application_1/service/app_feedback.dart';

class StockHerramientasEmpresaPage extends StatefulWidget {
  final String? empresaId;

  const StockHerramientasEmpresaPage({super.key, this.empresaId});

  @override
  State<StockHerramientasEmpresaPage> createState() =>
      _StockHerramientasEmpresaPageState();
}

class _StockHerramientasEmpresaPageState
    extends State<StockHerramientasEmpresaPage> {
  final _api = HerramientaApi();
  final _searchCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String _search = '';
  List<_StockEmpresaItem> _items = [];

  String get _empresaId => widget.empresaId ?? AppConstants.empresaNit;

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
      final raw = await _api.listarStockEmpresa(empresaId: _empresaId);
      final parsed = raw
          .whereType<Map>()
          .map((e) => _StockEmpresaItem.fromJson(e.cast<String, dynamic>()))
          .toList();

      if (!mounted) return;
      setState(() => _items = parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ajustar(_StockEmpresaItem item, {required bool sumar}) async {
    final ctrl = TextEditingController();

    try {
      final cantidad = await showDialog<num>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(sumar ? 'Agregar stock a empresa' : 'Descontar stock a empresa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Disponible: ${item.cantidad} ${item.unidad}'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: sumar ? 'Cantidad a agregar' : 'Cantidad a descontar',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = num.tryParse(ctrl.text.trim());
                if (parsed == null || parsed <= 0) return;
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      );

      if (cantidad == null) return;

      await _api.ajustarStockEmpresa(
        empresaId: _empresaId,
        herramientaId: item.herramientaId,
        delta: sumar ? cantidad : -cantidad,
      );

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Stock actualizado para ${item.nombre}.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items.where((item) {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return [item.nombre, item.unidad, item.categoria, item.modoControl]
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();

    final total = _items.fold<num>(0, (sum, item) => sum + item.cantidad);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Stock de herramientas empresa'),
        backgroundColor: AppTheme.primary,
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Este stock pertenece a la empresa',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Desde aqui sumas o descuentas existencias de empresa. Si un conjunto necesita herramientas, se registran como propias desde su inventario o se prestan mediante solicitud.',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Total en empresa: $total',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: 'Buscar en stock empresa',
                      hintText: 'Nombre, unidad, categoria o modo',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchCtrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _StateView(message: _error!, onRetry: _load)
                  : items.isEmpty
                  ? const _EmptyView()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Chip(text: 'Stock: ${item.cantidad} ${item.unidad}'),
                                  _Chip(text: item.categoria),
                                  _Chip(text: item.modoControl),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _ajustar(item, sumar: false),
                                      icon: const Icon(Icons.remove_circle_outline),
                                      label: const Text('Descontar'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _ajustar(item, sumar: true),
                                      icon: const Icon(Icons.add_circle_outline),
                                      label: const Text('Agregar'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockEmpresaItem {
  final int herramientaId;
  final String nombre;
  final String unidad;
  final String categoria;
  final String modoControl;
  final num cantidad;

  _StockEmpresaItem({
    required this.herramientaId,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    required this.modoControl,
    required this.cantidad,
  });

  static num _asNum(dynamic value, {num fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? fallback;
  }

  factory _StockEmpresaItem.fromJson(Map<String, dynamic> json) {
    final herramienta = (json['herramienta'] is Map)
        ? (json['herramienta'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    return _StockEmpresaItem(
      herramientaId: (json['herramientaId'] as num?)?.toInt() ?? 0,
      nombre: (herramienta['nombre'] ?? '-').toString(),
      unidad: (herramienta['unidad'] ?? 'unidad').toString(),
      categoria: (herramienta['categoria'] ?? 'OTROS').toString(),
      modoControl: (herramienta['modoControl'] ?? 'PRESTAMO').toString(),
      cantidad: _asNum(json['cantidad']),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;

  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No hay registros de stock en empresa para mostrar.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _StateView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
