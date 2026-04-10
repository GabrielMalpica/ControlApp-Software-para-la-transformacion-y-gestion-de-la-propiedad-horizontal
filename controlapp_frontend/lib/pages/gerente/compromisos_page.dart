import 'package:flutter/material.dart';

import '../../api/administrador_api.dart';
import '../../api/gerente_api.dart';
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

  List<_CompromisoItem> _items = [];
  bool _loading = true;
  String? _adminId;

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
      final items = raw.map(_CompromisoItem.fromJson).toList();
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
        _items = [_CompromisoItem.fromJson(raw), ..._items];
        _controller.clear();
      });
    } catch (e) {
      _snack(AppError.messageOf(e));
    }
  }

  Future<void> _toggle(_CompromisoItem item, bool valor) async {
    final old = item.completado;
    setState(() {
      item.completado = valor;
    });
    try {
      if (widget.usarFlujoAdministrador) {
        _adminId ??= await _sessionService.getUserId();
        await _adminApi.actualizarPqrs(
          adminId: _adminId!,
          id: item.id,
          completado: valor,
        );
      } else {
        await _api.actualizarCompromiso(id: item.id, completado: valor);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => item.completado = old);
      _snack(AppError.messageOf(e));
    }
  }

  Future<void> _editarTitulo(_CompromisoItem item) async {
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
      if (widget.usarFlujoAdministrador) {
        _adminId ??= await _sessionService.getUserId();
        await _adminApi.actualizarPqrs(
          adminId: _adminId!,
          id: item.id,
          titulo: nuevo,
        );
      } else {
        await _api.actualizarCompromiso(id: item.id, titulo: nuevo);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => item.titulo = old);
      _snack(AppError.messageOf(e));
    }
  }

  Future<void> _eliminar(_CompromisoItem item) async {
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

  @override
  Widget build(BuildContext context) {
    final pendientes = _items.where((e) => !e.completado).length;

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
                  Expanded(
                    child: _items.isEmpty
                        ? Center(
                            child: Text(
                              widget.emptyMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Row(
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
                                            vertical: 16,
                                          ),
                                          child: Text(
                                            item.titulo,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: item.completado
                                                  ? Colors.black45
                                                  : Colors.black87,
                                              decoration: item.completado
                                                  ? TextDecoration.lineThrough
                                                  : TextDecoration.none,
                                            ),
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

class _CompromisoItem {
  _CompromisoItem({
    required this.id,
    required this.titulo,
    required this.completado,
  });

  final int id;
  String titulo;
  bool completado;

  factory _CompromisoItem.fromJson(Map<String, dynamic> json) {
    return _CompromisoItem(
      id: (json['id'] as num).toInt(),
      titulo: (json['titulo'] ?? '').toString(),
      completado: json['completado'] == true,
    );
  }
}
