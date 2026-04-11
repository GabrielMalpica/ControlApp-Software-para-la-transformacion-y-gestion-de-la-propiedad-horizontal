import 'package:flutter/material.dart';

import '../../api/empresa_api.dart';
import '../../model/insumo_model.dart';
import '../../service/app_error.dart';
import '../../service/theme.dart';
import 'package:flutter_application_1/service/app_feedback.dart';

class ListaInsumosPage extends StatefulWidget {
  const ListaInsumosPage({super.key});

  @override
  State<ListaInsumosPage> createState() => _ListaInsumosPageState();
}

class _ListaInsumosPageState extends State<ListaInsumosPage> {
  final EmpresaApi _api = EmpresaApi();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String _search = '';
  CategoriaInsumo? _categoriaFiltro;
  List<InsumoResponse> _items = [];

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
      final data = await _api.listarCatalogo();
      if (!mounted) return;
      setState(() => _items = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<InsumoResponse> get _filtrados {
    final q = _search.trim().toLowerCase();
    return _items.where((item) {
      if (_categoriaFiltro != null && item.categoria != _categoriaFiltro) {
        return false;
      }

      if (q.isEmpty) return true;
      return [
        item.nombre,
        item.unidad,
        item.categoria.label,
        item.umbralBajo?.toString() ?? '',
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _confirmDelete(InsumoResponse item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar insumo'),
        content: Text('Se eliminara ${item.nombre} del catalogo de insumos.'),
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
      await _api.eliminarInsumo(item.id);
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('${item.nombre} eliminado del catalogo.')),
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

  Future<void> _editarInsumo(InsumoResponse insumo) async {
    final nombreCtrl = TextEditingController(text: insumo.nombre);
    final unidadCtrl = TextEditingController(text: insumo.unidad);
    final umbralCtrl = TextEditingController(
      text: insumo.umbralBajo?.toString() ?? '',
    );
    CategoriaInsumo categoria = insumo.categoria;
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar insumo'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) {
                    if (v == null || v.trim().length < 2) {
                      return 'Nombre muy corto';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: unidadCtrl,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Unidad requerida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<CategoriaInsumo>(
                  initialValue: categoria,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: CategoriaInsumo.values
                      .map(
                        (cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat.label),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) categoria = val;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: umbralCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Umbral bajo (opcional)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final parsed = int.tryParse(v.trim());
                    if (parsed == null || parsed < 0) return 'Numero invalido';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save != true) return;

    final umbralStr = umbralCtrl.text.trim();
    final umbral = umbralStr.isEmpty ? null : int.tryParse(umbralStr);

    try {
      await _api.editarInsumo(
        insumo.id,
        InsumoRequest(
          nombre: nombreCtrl.text.trim(),
          unidad: unidadCtrl.text.trim(),
          categoria: categoria,
          umbralBajo: umbral,
        ),
      );

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('${insumo.nombre} actualizado.')),
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
    final filtrados = _filtrados;
    final totalCategorias = _items.map((e) => e.categoria).toSet().length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Catalogo de insumos'),
        backgroundColor: AppTheme.primary,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  _HeaderCard(
                    totalTipos: _items.length,
                    totalCategorias: totalCategorias,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            labelText: 'Buscar insumo',
                            hintText: 'Nombre, unidad, categoria o umbral',
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
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<CategoriaInsumo?>(
                          initialValue: _categoriaFiltro,
                          decoration: const InputDecoration(
                            labelText: 'Categoria',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<CategoriaInsumo?>(
                              value: null,
                              child: Text('Todas'),
                            ),
                            ...CategoriaInsumo.values.map(
                              (cat) => DropdownMenuItem<CategoriaInsumo?>(
                                value: cat,
                                child: Text(cat.label),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _categoriaFiltro = value),
                        ),
                      ),
                    ],
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
                      title: 'No se pudieron cargar los insumos',
                      message: _error!,
                      actionLabel: 'Reintentar',
                      onAction: _load,
                    )
                  : filtrados.isEmpty
                  ? const _EmptyCard()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: filtrados.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = filtrados[index];
                          return _InsumoCard(
                            item: item,
                            onEdit: () => _editarInsumo(item),
                            onDelete: () => _confirmDelete(item),
                          );
                        },
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
  final int totalCategorias;

  const _HeaderCard({required this.totalTipos, required this.totalCategorias});

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
            'Administra el catalogo de insumos de la empresa',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aqui editas nombre, unidad, categoria y umbral de los insumos que usara la operacion.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(label: 'Insumos en catalogo', value: '$totalTipos'),
              _MetricChip(
                label: 'Categorias activas',
                value: '$totalCategorias',
              ),
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

class _InsumoCard extends StatelessWidget {
  final InsumoResponse item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InsumoCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

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
                child: Text(
                  item.nombre,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Editar insumo',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Eliminar insumo',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PlainChip(text: 'Unidad: ${item.unidad}'),
              _PlainChip(text: 'Categoria: ${item.categoria.label}'),
              _PlainChip(text: 'Umbral bajo: ${item.umbralBajo ?? '-'}'),
            ],
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No hay insumos que coincidan con los filtros actuales.',
          textAlign: TextAlign.center,
        ),
      ),
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
