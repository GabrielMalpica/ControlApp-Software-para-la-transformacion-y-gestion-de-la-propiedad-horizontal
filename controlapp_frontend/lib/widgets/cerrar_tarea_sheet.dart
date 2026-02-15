import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../model/tarea_model.dart';
import '../model/inventario_item_model.dart';
import '../model/evidencia_adjunto_model.dart';

class CerrarTareaResult {
  final String? observaciones;
  final List<Map<String, num>> insumosUsados;

  /// ✅ Evidencias listas para multipart:
  /// - Mobile/Desktop: path
  /// - Web: bytes
  final List<EvidenciaAdjunto> evidencias;

  CerrarTareaResult({
    required this.insumosUsados,
    this.observaciones,
    this.evidencias = const [],
  });
}

class CerrarTareaSheet extends StatefulWidget {
  final TareaModel tarea;

  /// ✅ default seguro para evitar null/undefined
  final List<InventarioItemResponse> inventario;

  const CerrarTareaSheet({
    super.key,
    required this.tarea,
    this.inventario = const [],
  });

  @override
  State<CerrarTareaSheet> createState() => _CerrarTareaSheetState();
}

class _CerrarTareaSheetState extends State<CerrarTareaSheet> {
  final _obsCtrl = TextEditingController();

  /// filas para consumo
  final List<_ConsumoRow> _rows = [];

  /// ✅ evidencias unificadas (path o bytes)
  final List<EvidenciaAdjunto> _evidencias = [];

  @override
  void initState() {
    super.initState();
    // Si hay inventario, arrancamos con una fila para facilitar
    if (widget.inventario.isNotEmpty) _rows.add(_ConsumoRow());
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    for (final r in _rows) {
      r.qtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickEvidencias() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb, // ✅ en web necesitamos bytes
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );

    if (picked == null) return;

    final nuevos = <EvidenciaAdjunto>[];

    for (final f in picked.files) {
      final nombre = (f.name).trim().isEmpty ? 'archivo' : f.name.trim();

      // Web: bytes
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes != null && bytes.isNotEmpty) {
          nuevos.add(EvidenciaAdjunto(path: null, nombre: nombre, bytes: bytes));
        }
        continue;
      }

      // Mobile/Desktop: path
      final path = f.path;
      if (path != null && path.trim().isNotEmpty) {
        nuevos.add(EvidenciaAdjunto(path: path.trim(), nombre: nombre, bytes: null));
      }
    }

    if (nuevos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron leer archivos seleccionados.')),
      );
      return;
    }

    setState(() {
      for (final e in nuevos) {
        // Evitar duplicados: por path en mobile o por (nombre+len) en web
        final exists = _evidencias.any((x) {
          if (!kIsWeb) return (x.path ?? '') == (e.path ?? '');
          final xl = x.bytes?.length ?? 0;
          final el = e.bytes?.length ?? 0;
          return (x.nombre == e.nombre) && (xl == el) && xl > 0;
        });
        if (!exists) _evidencias.add(e);
      }
    });
  }

  List<Map<String, num>> _buildInsumosUsados() {
    final out = <Map<String, num>>[];
    for (final r in _rows) {
      if (r.insumoId == null) continue;
      final qty = num.tryParse(r.qtyCtrl.text.trim());
      if (qty == null || qty <= 0) continue;
      out.add({'insumoId': r.insumoId!, 'cantidad': qty});
    }
    return out;
  }

  String _displayName(EvidenciaAdjunto e) {
    // En mobile podemos mostrar filename desde path si viene, si no el nombre
    final p = e.path;
    if (p != null && p.trim().isNotEmpty) {
      final norm = p.replaceAll('\\', '/');
      final idx = norm.lastIndexOf('/');
      return idx >= 0 ? norm.substring(idx + 1) : norm;
    }
    return e.nombre;
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.82;
    final inv = widget.inventario; // ✅ nunca null

    return SizedBox(
      height: alto,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cerrar tarea',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              widget.tarea.descripcion,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),

            Card(
              elevation: 0,
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📸 Evidencias de cierre', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      'Adjunta fotos o PDF de evidencias para enviar al cierre.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickEvidencias,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Agregar archivos'),
                        ),
                        const SizedBox(width: 8),
                        Text('${_evidencias.length} archivo(s)'),
                      ],
                    ),
                    if (_evidencias.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ..._evidencias.map((e) {
                        return Row(
                          children: [
                            const Icon(Icons.insert_drive_file, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _displayName(e),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Quitar',
                              onPressed: () => setState(() => _evidencias.remove(e)),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Maquinaria
            if (widget.tarea.maquinariasAsignadas.isNotEmpty) ...[
              const Text('Maquinaria asignada', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.tarea.maquinariasAsignadas
                    .map((m) => Chip(
                          avatar: const Icon(Icons.precision_manufacturing, size: 18),
                          label: Text(m.nombre),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text('Maquinaria asignada: ninguna.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 12),
            ],

            // Herramientas
            if (widget.tarea.herramientasAsignadas.isNotEmpty) ...[
              const Text('Herramientas asignadas', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Column(
                children: widget.tarea.herramientasAsignadas.map((h) {
                  final qty = h.cantidad;
                  final estado = (h.estado ?? '').toUpperCase();

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.handyman, size: 20),
                    title: Text(h.nombre),
                    subtitle: estado.isEmpty ? null : Text('Estado: $estado'),
                    trailing: Text('x$qty'),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text('Herramientas asignadas: ninguna.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                const Text('Insumos usados', style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton.icon(
                  onPressed: inv.isEmpty ? null : () => setState(() => _rows.add(_ConsumoRow())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
              ],
            ),

            if (inv.isEmpty)
              Text(
                'No hay inventario disponible (o no se pudo cargar). Puedes cerrar sin insumos.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final row = _rows[i];

                    InventarioItemResponse? item;
                    if (row.insumoId != null) {
                      try {
                        item = inv.firstWhere((x) => x.insumoId == row.insumoId);
                      } catch (_) {
                        item = null;
                      }
                    }

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            DropdownButtonFormField<int>(
                              value: row.insumoId,
                              decoration: const InputDecoration(
                                labelText: 'Insumo',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: inv
                                  .map((x) => DropdownMenuItem<int>(
                                        value: x.insumoId,
                                        child: Text('${x.nombre} (${x.cantidad} ${x.unidad})'),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => row.insumoId = v),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: row.qtyCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Cantidad usada',
                                hintText: item == null ? 'Ej: 0.5' : 'En ${item.unidad}',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (item != null)
                                  Expanded(
                                    child: Text(
                                      'Stock: ${item.cantidad} ${item.unidad}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Quitar',
                                  onPressed: () => setState(() {
                                    row.qtyCtrl.dispose();
                                    _rows.removeAt(i);
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 10),
            TextField(
              controller: _obsCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                    CerrarTareaResult(
                      insumosUsados: _buildInsumosUsados(),
                      observaciones: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
                      evidencias: _evidencias, // ✅ listo para web+mobile
                    ),
                  );
                },
                icon: const Icon(Icons.send),
                label: const Text('Cerrar y enviar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsumoRow {
  int? insumoId;
  final TextEditingController qtyCtrl = TextEditingController();
}