import 'package:flutter/material.dart';

import '../api/herramienta_api.dart';
import '../model/herramienta_model.dart';
import '../service/app_constants.dart';
import '../service/app_error.dart';
import '../service/theme.dart';
import 'crear_herramienta_page.dart';
import 'stock_herramientas_empresa_page.dart';
import 'package:flutter_application_1/service/app_feedback.dart';

class ListaHerramientasPage extends StatefulWidget {
  final String? empresaId;

  const ListaHerramientasPage({super.key, this.empresaId});

  @override
  State<ListaHerramientasPage> createState() => _ListaHerramientasPageState();
}

class _ListaHerramientasPageState extends State<ListaHerramientasPage> {
  final _api = HerramientaApi();
  final _searchCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String _search = '';
  List<HerramientaResponse> _items = [];

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
      final out = await _api.listarHerramientas(
        empresaId: _empresaId,
        nombre: _search.trim().isEmpty ? null : _search.trim(),
        take: 100,
        skip: 0,
      );

      final data = (out['data'] as List?) ?? [];
      final parsed = data
          .whereType<Map>()
          .map(
            (row) => HerramientaResponse.fromJson(row.cast<String, dynamic>()),
          )
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

  Future<void> _openCreate() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CrearHerramientaPage(empresaId: _empresaId),
      ),
    );
    if (changed == true) {
      await _load();
    }
  }

  Future<void> _confirmDelete(HerramientaResponse item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar herramienta'),
        content: Text(
          'Se eliminara ${item.nombre} del catalogo. Si la herramienta tiene movimientos asociados, el sistema mostrara el motivo y no permitira eliminarla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _api.eliminarHerramienta(herramientaId: item.id);
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('${item.nombre} eliminada del catalogo.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Herramientas de la empresa'),
        backgroundColor: AppTheme.primary,
        actions: [
          IconButton(
            tooltip: 'Ver stock empresa',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      StockHerramientasEmpresaPage(empresaId: _empresaId),
                ),
              );
            },
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Nueva herramienta'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  _HeaderCard(totalTipos: _items.length),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: 'Buscar herramienta',
                      hintText: 'Nombre, categoria, unidad o modo',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchCtrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                                _load();
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                    onSubmitted: (_) => _load(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _StateCard(
                      icon: Icons.error_outline,
                      title: 'No se pudieron cargar las herramientas',
                      message: _error!,
                      actionLabel: 'Reintentar',
                      onAction: _load,
                    )
                  : _items.isEmpty
                  ? _StateCard(
                      icon: Icons.handyman_outlined,
                      title: 'Aun no hay herramientas en la empresa',
                      message:
                          'Primero crea la herramienta en el catalogo. El stock de empresa se administra en la pantalla separada de stock empresa.',
                      actionLabel: 'Crear herramienta',
                      onAction: _openCreate,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemBuilder: (context, index) => _ToolCard(
                          item: _items[index],
                          onDelete: () => _confirmDelete(_items[index]),
                        ),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: _items.length,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final int totalTipos;

  const _HeaderCard({required this.totalTipos});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aqui administras solo las herramientas de la empresa',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aqui solo defines el catalogo base. El stock de empresa se maneja en otra pantalla y el stock propio del conjunto se registra desde el inventario de cada conjunto.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(label: 'Tipos en catalogo', value: '$totalTipos'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final HerramientaResponse item;
  final VoidCallback onDelete;

  const _ToolCard({required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nombre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.categoria.label} · ${item.modoControl.label}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Eliminar herramienta',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PlainChip(text: 'Unidad: ${item.unidad}'),
              if (item.umbralBajo != null)
                _PlainChip(text: 'Alerta: ${item.umbralBajo}'),
              if (item.vidaUtilDias != null)
                _PlainChip(text: 'Vida util: ${item.vidaUtilDias} dias'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(item.modoControl.descripcion),
          ),
        ],
      ),
    );
  }
}

class _PlainChip extends StatelessWidget {
  final String text;

  const _PlainChip({required this.text});

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

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade700),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.arrow_forward),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
