import 'package:flutter/material.dart';

import '../../api/administrador_api.dart';
import '../../api/gerente_api.dart';
import '../../model/compromiso_model.dart';
import '../../service/app_error.dart';
import '../../service/app_feedback.dart';
import '../../service/session_service.dart';
import '../../service/theme.dart';

class CompromisosPage extends StatefulWidget {
  final String nit;
  final String nombreConjunto;
  final String pageTitle;
  final String inputLabel;
  final String inputHint;
  final String emptyMessage;
  final String addButtonLabel;
  final bool usarFlujoAdministrador;

  const CompromisosPage({
    super.key,
    required this.nit,
    required this.nombreConjunto,
    this.pageTitle = 'Compromisos',
    this.inputLabel = 'Nuevo compromiso',
    this.inputHint = 'Ej: Llamar al administrador',
    this.emptyMessage = 'Aun no hay compromisos.\nAgrega el primero.',
    this.addButtonLabel = 'Agregar',
    this.usarFlujoAdministrador = false,
  });

  @override
  State<CompromisosPage> createState() => _CompromisosPageState();
}

class _CompromisosPageState extends State<CompromisosPage> {
  final GerenteApi _api = GerenteApi();
  final AdministradorApi _adminApi = AdministradorApi();
  final SessionService _sessionService = SessionService();
  final TextEditingController _controller = TextEditingController();

  List<CompromisoModel> _items = [];
  bool _loading = true;
  String? _adminId;
  _CompromisoFilter _filter = _CompromisoFilter.todos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      if (widget.usarFlujoAdministrador) {
        _adminId ??= await _sessionService.getUserId();
      }

      final raw = widget.usarFlujoAdministrador
          ? await _adminApi.listarPqrsConjunto(
              adminId: _adminId!,
              conjuntoId: widget.nit,
            )
          : await _api.listarCompromisosConjunto(widget.nit);
      final items = raw.map(CompromisoModel.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(AppError.messageOf(e));
    }
  }

  Future<void> _agregar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;

    try {
      if (widget.usarFlujoAdministrador) {
        _adminId ??= await _sessionService.getUserId();
      }

      final raw = widget.usarFlujoAdministrador
          ? await _adminApi.crearPqrsConjunto(
              adminId: _adminId!,
              conjuntoId: widget.nit,
              titulo: texto,
            )
          : await _api.crearCompromisoConjunto(
              conjuntoId: widget.nit,
              titulo: texto,
            );
      if (!mounted) return;
      setState(() {
        _items = [CompromisoModel.fromJson(raw), ..._items];
        _controller.clear();
      });
    } catch (e) {
      _snack(AppError.messageOf(e));
    }
  }

  Future<void> _toggle(CompromisoModel item, bool valor) async {
    final old = item.completado;
    setState(() {
      item.completado = valor;
    });
    try {
      final Map<String, dynamic> raw;
      if (widget.usarFlujoAdministrador) {
        _adminId ??= await _sessionService.getUserId();
        raw = await _adminApi.actualizarPqrs(
          adminId: _adminId!,
          id: item.id,
          completado: valor,
        );
      } else {
        raw = await _api.actualizarCompromiso(id: item.id, completado: valor);
      }
      if (!mounted) return;
      setState(() => item.updateFrom(CompromisoModel.fromJson(raw)));
    } catch (e) {
      if (!mounted) return;
      setState(() => item.completado = old);
      _snack(AppError.messageOf(e));
    }
  }

  Future<void> _editarTitulo(CompromisoModel item) async {
    final ctrl = TextEditingController(text: item.titulo);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar compromiso'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Compromiso',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (nuevo == null || nuevo.isEmpty || nuevo == item.titulo) return;

    final old = item.titulo;
    setState(() => item.titulo = nuevo);
    try {
      final Map<String, dynamic> raw;
      if (widget.usarFlujoAdministrador) {
        _adminId ??= await _sessionService.getUserId();
        raw = await _adminApi.actualizarPqrs(
          adminId: _adminId!,
          id: item.id,
          titulo: nuevo,
        );
      } else {
        raw = await _api.actualizarCompromiso(id: item.id, titulo: nuevo);
      }
      if (!mounted) return;
      setState(() => item.updateFrom(CompromisoModel.fromJson(raw)));
    } catch (e) {
      if (!mounted) return;
      setState(() => item.titulo = old);
      _snack(AppError.messageOf(e));
    }
  }

  Future<void> _eliminar(CompromisoModel item) async {
    try {
      if (widget.usarFlujoAdministrador) {
        _adminId ??= await _sessionService.getUserId();
        await _adminApi.eliminarPqrs(adminId: _adminId!, id: item.id);
      } else {
        await _api.eliminarCompromiso(item.id);
      }
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => x.id == item.id));
    } catch (e) {
      _snack(AppError.messageOf(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(msg)));
  }

  Color _ansColor(String color) {
    switch (color) {
      case 'green':
        return const Color(0xFF2E7D32);
      case 'orange':
        return const Color(0xFFEF6C00);
      case 'red':
        return const Color(0xFFC62828);
      default:
        return Colors.blueGrey;
    }
  }

  bool _matchesFilter(CompromisoModel item) {
    switch (_filter) {
      case _CompromisoFilter.todos:
        return true;
      case _CompromisoFilter.abiertos:
        return !item.completado;
      case _CompromisoFilter.criticos:
        return !item.completado && item.ansColor == 'red';
      case _CompromisoFilter.verdes:
        return !item.completado && item.ansColor == 'green';
      case _CompromisoFilter.naranjas:
        return !item.completado && item.ansColor == 'orange';
      case _CompromisoFilter.rojos:
        return !item.completado && item.ansColor == 'red';
      case _CompromisoFilter.cerrados:
        return item.completado;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _items.where((e) => !e.completado).length;
    final verdes = _items
        .where((e) => !e.completado && e.ansColor == 'green')
        .length;
    final naranjas = _items
        .where((e) => !e.completado && e.ansColor == 'orange')
        .length;
    final rojos = _items
        .where((e) => !e.completado && e.ansColor == 'red')
        .length;
    final filteredItems = _items.where(_matchesFilter).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.pageTitle),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text(
                      'Conjunto ${widget.nombreConjunto}\nPendientes: $pendientes',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountBadge(
                        label: 'Verdes',
                        value: verdes.toString(),
                        color: const Color(0xFF2E7D32),
                      ),
                      _CountBadge(
                        label: 'Naranjas',
                        value: naranjas.toString(),
                        color: const Color(0xFFEF6C00),
                      ),
                      _CountBadge(
                        label: 'Rojos',
                        value: rojos.toString(),
                        color: const Color(0xFFC62828),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _agregar(),
                          decoration: InputDecoration(
                            labelText: widget.inputLabel,
                            hintText: widget.inputHint,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _agregar,
                          icon: const Icon(Icons.add_task),
                          label: Text(widget.addButtonLabel),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterChipButton(
                          label: 'Todos',
                          selected: _filter == _CompromisoFilter.todos,
                          onTap: () =>
                              setState(() => _filter = _CompromisoFilter.todos),
                        ),
                        _FilterChipButton(
                          label: 'Abiertos',
                          selected: _filter == _CompromisoFilter.abiertos,
                          onTap: () => setState(
                            () => _filter = _CompromisoFilter.abiertos,
                          ),
                        ),
                        _FilterChipButton(
                          label: 'Criticos',
                          selected: _filter == _CompromisoFilter.criticos,
                          onTap: () => setState(
                            () => _filter = _CompromisoFilter.criticos,
                          ),
                        ),
                        _FilterChipButton(
                          label: 'Verdes',
                          selected: _filter == _CompromisoFilter.verdes,
                          onTap: () => setState(
                            () => _filter = _CompromisoFilter.verdes,
                          ),
                        ),
                        _FilterChipButton(
                          label: 'Naranjas',
                          selected: _filter == _CompromisoFilter.naranjas,
                          onTap: () => setState(
                            () => _filter = _CompromisoFilter.naranjas,
                          ),
                        ),
                        _FilterChipButton(
                          label: 'Rojos',
                          selected: _filter == _CompromisoFilter.rojos,
                          onTap: () =>
                              setState(() => _filter = _CompromisoFilter.rojos),
                        ),
                        _FilterChipButton(
                          label: 'Cerrados',
                          selected: _filter == _CompromisoFilter.cerrados,
                          onTap: () => setState(
                            () => _filter = _CompromisoFilter.cerrados,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _items.isEmpty
                        ? Center(
                            child: Text(
                              widget.emptyMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : filteredItems.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay compromisos para ese filtro.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              final ansColor = _ansColor(item.ansColor);
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: ansColor.withValues(alpha: 0.24),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: item.completado,
                                        onChanged: (v) =>
                                            _toggle(item, v ?? false),
                                      ),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _editarTitulo(item),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.titulo,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: item.completado
                                                        ? Colors.black45
                                                        : Colors.black87,
                                                    decoration: item.completado
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : TextDecoration.none,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _MetaChip(
                                                      icon:
                                                          Icons.person_outline,
                                                      label: item.autorLabel,
                                                    ),
                                                    _MetaChip(
                                                      icon: Icons
                                                          .schedule_rounded,
                                                      label:
                                                          item.antiguedadLabel,
                                                    ),
                                                    _MetaChip(
                                                      icon: Icons
                                                          .event_available_outlined,
                                                      label: item
                                                          .fechaCreacionLabel,
                                                    ),
                                                    _MetaChip(
                                                      icon: item.completado
                                                          ? Icons
                                                                .task_alt_outlined
                                                          : Icons
                                                                .timelapse_rounded,
                                                      label:
                                                          item.fechaCierreLabel,
                                                    ),
                                                    _MetaChip(
                                                      icon: Icons.flag_outlined,
                                                      label: item.ansLabel,
                                                      color: ansColor,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Editar',
                                        onPressed: () => _editarTitulo(item),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        onPressed: () => _eliminar(item),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
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

enum _CompromisoFilter {
  todos,
  abiertos,
  criticos,
  verdes,
  naranjas,
  rojos,
  cerrados,
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppTheme.primary : Colors.black12,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: chipColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
