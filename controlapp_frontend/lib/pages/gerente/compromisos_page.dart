import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/theme.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class CompromisosPage extends StatefulWidget {
  final String nit;

  const CompromisosPage({super.key, required this.nit});

  @override
  State<CompromisosPage> createState() => _CompromisosPageState();
}

class _CompromisosPageState extends State<CompromisosPage> {
  static const _storagePrefix = 'gerente_compromisos_';

  final TextEditingController _controller = TextEditingController();
  List<_CompromisoItem> _items = [];
  bool _loading = true;

  String get _storageKey => '$_storagePrefix${widget.nit}';

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
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);

      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _items = [];
          _loading = false;
        });
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final parsed = <_CompromisoItem>[];
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          parsed.add(_CompromisoItem.fromJson(e));
          continue;
        }
        if (e is Map) {
          parsed.add(_CompromisoItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }

      if (!mounted) return;
      setState(() {
        _items = parsed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('No se pudieron cargar los compromisos.');
    }
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, payload);
  }

  Future<void> _agregar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;

    setState(() {
      _items = [
        _CompromisoItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          titulo: texto,
          completado: false,
        ),
        ..._items,
      ];
      _controller.clear();
    });

    try {
      await _guardar();
    } catch (_) {
      _snack('No se pudo guardar el compromiso.');
    }
  }

  Future<void> _toggle(String id, bool valor) async {
    setState(() {
      _items = _items
          .map((e) => e.id == id ? e.copyWith(completado: valor) : e)
          .toList();
    });

    try {
      await _guardar();
    } catch (_) {
      _snack('No se pudo actualizar el compromiso.');
    }
  }

  Future<void> _eliminar(String id) async {
    setState(() => _items = _items.where((e) => e.id != id).toList());
    try {
      await _guardar();
    } catch (_) {
      _snack('No se pudo eliminar el compromiso.');
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
        title: const Text('Compromisos'),
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
                      'Conjunto ${widget.nit}\nPendientes: $pendientes',
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
                          decoration: const InputDecoration(
                            labelText: 'Nuevo compromiso',
                            hintText: 'Ej: Llamar al administrador',
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
                          label: const Text('Agregar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _items.isEmpty
                        ? const Center(
                            child: Text(
                              'Aun no hay compromisos.\nAgrega el primero.',
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
                                          _toggle(item.id, v ?? false),
                                    ),
                                    Expanded(
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
                                    IconButton(
                                      tooltip: 'Eliminar',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _eliminar(item.id),
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
  final String id;
  final String titulo;
  final bool completado;

  const _CompromisoItem({
    required this.id,
    required this.titulo,
    required this.completado,
  });

  _CompromisoItem copyWith({String? id, String? titulo, bool? completado}) {
    return _CompromisoItem(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      completado: completado ?? this.completado,
    );
  }

  factory _CompromisoItem.fromJson(Map<String, dynamic> json) {
    return _CompromisoItem(
      id: (json['id'] ?? '').toString(),
      titulo: (json['titulo'] ?? '').toString(),
      completado: json['completado'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'titulo': titulo, 'completado': completado};
  }
}
