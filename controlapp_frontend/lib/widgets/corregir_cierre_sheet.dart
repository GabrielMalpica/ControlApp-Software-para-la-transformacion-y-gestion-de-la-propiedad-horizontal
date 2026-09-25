import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/api/tarea_api.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/permission_service.dart';
import 'package:flutter_application_1/utils/evidence_utils.dart';
import 'package:flutter_application_1/utils/pickers/camera_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/clipboard_image_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/file_pick_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

import 'evidencia_gallery.dart';

/// Estados de tarea sobre los que tiene sentido corregir el cierre: los que
/// ya pasaron por evidencias/insumos y no tienen un flujo activo propio.
const _estadosCorregibles = {'APROBADA', 'NO_COMPLETADA', 'RECHAZADA'};

bool estadoCorregible(String? estado) =>
    _estadosCorregibles.contains((estado ?? '').toUpperCase());

bool puedeCorregirCierre(TareaModel tarea) {
  if (!PermissionService.instance.can('tareas.editar_cierre')) return false;
  return estadoCorregible(tarea.estado);
}

/// Carga la tarea y su inventario, y abre la hoja de corrección de cierre.
/// Devuelve `true` si se guardó una corrección (para que quien la llama
/// recargue su lista).
///
/// Con [soloEvidencias] la hoja solo permite cambiar las fotos/archivos de la
/// tarea (sin tocar insumos ni observaciones).
Future<bool> abrirCorregirCierre(
  BuildContext context, {
  required int tareaId,
  bool soloEvidencias = false,
}) async {
  if (!PermissionService.instance.can('tareas.editar_cierre')) {
    AppFeedback.showError(
      context,
      message: 'No tienes permiso para corregir el cierre de tareas.',
    );
    return false;
  }

  final tareaApi = TareaApi();

  final TareaModel tarea;
  try {
    tarea = await tareaApi.obtenerTarea(tareaId);
  } catch (e) {
    if (context.mounted) {
      AppFeedback.showError(context, message: AppError.messageOf(e));
    }
    return false;
  }

  if (!_estadosCorregibles.contains((tarea.estado ?? '').toUpperCase())) {
    if (context.mounted) {
      AppFeedback.showError(
        context,
        message:
            'Solo se puede corregir el cierre de tareas aprobadas, no completadas o rechazadas.',
      );
    }
    return false;
  }

  List<InventarioItemResponse> inventario = const [];
  final conjuntoId = tarea.conjuntoId;
  if (!soloEvidencias && conjuntoId != null && conjuntoId.trim().isNotEmpty) {
    try {
      inventario = await InventarioApi().listarInventarioConjunto(conjuntoId);
    } catch (_) {
      // Sin inventario disponible: se puede seguir corrigiendo evidencias.
    }
  }

  if (!context.mounted) return false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CorregirCierreSheet(
      tarea: tarea,
      inventario: inventario,
      soloEvidencias: soloEvidencias,
    ),
  );

  return result == true;
}

class CorregirCierreSheet extends StatefulWidget {
  final TareaModel tarea;
  final List<InventarioItemResponse> inventario;
  final bool soloEvidencias;

  const CorregirCierreSheet({
    super.key,
    required this.tarea,
    this.inventario = const [],
    this.soloEvidencias = false,
  });

  @override
  State<CorregirCierreSheet> createState() => _CorregirCierreSheetState();
}

class _ConsumoRow {
  int? insumoId;
  final TextEditingController qtyCtrl;
  _ConsumoRow({this.insumoId, String? cantidadTexto})
    : qtyCtrl = TextEditingController(text: cantidadTexto ?? '');
}

class _CorregirCierreSheetState extends State<CorregirCierreSheet> {
  final _motivoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  final Set<String> _evidenciasEliminadas = {};
  final List<SelectedUploadFile> _evidenciasNuevas = [];
  final List<_ConsumoRow> _rows = [];

  bool _insumosDirty = false;
  bool _guardando = false;

  bool get _esMovil =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  bool get _puedeTomarFoto => kIsWeb || _esMovil;
  bool get _puedePegarImagen => kIsWeb && ClipboardImageCapture.isSupported;

  ClipboardImageDispose? _disposeClipboardListener;
  bool _esperandoPegado = false;

  @override
  void initState() {
    super.initState();
    _obsCtrl.text = widget.tarea.observaciones ?? '';

    for (final item in widget.tarea.insumosUsados ?? const []) {
      InventarioItemResponse? invItem;
      try {
        invItem = widget.inventario.firstWhere(
          (x) => x.insumoId == item.insumoId,
        );
      } catch (_) {
        invItem = null;
      }

      final contenido = invItem?.contenidoPorUnidad;
      final cantidadMostrada = (contenido != null && contenido > 0)
          ? item.cantidad * contenido
          : item.cantidad;

      _rows.add(
        _ConsumoRow(
          insumoId: invItem != null ? item.insumoId : null,
          cantidadTexto: _formatNum(cantidadMostrada),
        ),
      );
    }

    if (_puedePegarImagen) {
      _disposeClipboardListener = ClipboardImageCapture.registerPasteListener(
        _onClipboardImagePasted,
      );
    }
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    _obsCtrl.dispose();
    for (final r in _rows) {
      r.qtyCtrl.dispose();
    }
    _disposeClipboardListener?.call();
    super.dispose();
  }

  String _formatNum(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  List<String> get _evidenciasVisibles => (widget.tarea.evidencias ?? const [])
      .where((e) => !_evidenciasEliminadas.contains(e))
      .toList();

  Future<void> _agregarDesdeArchivo() async {
    final archivos = await UniversalFilePick.pick(
      allowMultiple: true,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (archivos.isEmpty) return;
    setState(() => _evidenciasNuevas.addAll(archivos));
  }

  Future<void> _tomarFoto() async {
    if (!_puedeTomarFoto) return;
    try {
      final captura = await CameraCapture.pickPhoto();
      if (captura == null) return;
      setState(() => _evidenciasNuevas.add(captura));
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, message: 'No se pudo abrir la cámara: $e');
    }
  }

  void _activarPegado() {
    setState(() => _esperandoPegado = true);
    AppFeedback.showInfo(
      context,
      message:
          'Copia la imagen y presiona Ctrl+V dentro de esta ventana para adjuntarla.',
    );
  }

  void _onClipboardImagePasted(SelectedUploadFile file) {
    if (!mounted) return;
    setState(() {
      _evidenciasNuevas.add(file);
      _esperandoPegado = false;
    });
    AppFeedback.showInfo(
      context,
      message: 'Imagen pegada desde el portapapeles.',
    );
  }

  void _agregarFilaInsumo() {
    setState(() {
      _rows.add(_ConsumoRow());
      _insumosDirty = true;
    });
  }

  void _quitarFilaInsumo(int index) {
    setState(() {
      _rows[index].qtyCtrl.dispose();
      _rows.removeAt(index);
      _insumosDirty = true;
    });
  }

  /// Convierte lo que el usuario ve (unidad real) a la unidad de conteo que
  /// se guarda en insumosUsados, igual que hace CerrarTareaSheet.
  List<Map<String, num>> _buildInsumosUsados() {
    final out = <Map<String, num>>[];
    for (final r in _rows) {
      if (r.insumoId == null) continue;
      final qtyIngresada = num.tryParse(r.qtyCtrl.text.trim());
      if (qtyIngresada == null || qtyIngresada <= 0) continue;

      InventarioItemResponse? item;
      try {
        item = widget.inventario.firstWhere((x) => x.insumoId == r.insumoId);
      } catch (_) {
        item = null;
      }

      final contenido = item?.contenidoPorUnidad;
      final cantidadADescontar = (contenido != null && contenido > 0)
          ? qtyIngresada / contenido
          : qtyIngresada;

      out.add({'insumoId': r.insumoId!, 'cantidad': cantidadADescontar});
    }
    return out;
  }

  Future<void> _guardar() async {
    final motivo = _motivoCtrl.text.trim();
    if (motivo.length < 3) {
      AppFeedback.showError(
        context,
        message: 'Indica el motivo de la corrección (mínimo 3 caracteres).',
      );
      return;
    }
    if (widget.soloEvidencias &&
        _evidenciasEliminadas.isEmpty &&
        _evidenciasNuevas.isEmpty) {
      AppFeedback.showError(
        context,
        message: 'Quita o agrega al menos una evidencia para guardar.',
      );
      return;
    }
    if (_rows.any(
      (r) => r.insumoId == null && r.qtyCtrl.text.trim().isNotEmpty,
    )) {
      AppFeedback.showError(
        context,
        message: 'Selecciona un insumo para cada fila o elimínala.',
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      await TareaApi().corregirCierreTarea(
        tareaId: widget.tarea.id,
        motivo: motivo,
        evidenciasEliminar: _evidenciasEliminadas.toList(),
        insumosUsados: (_insumosDirty && !widget.soloEvidencias)
            ? _buildInsumosUsados()
            : null,
        observaciones: (widget.soloEvidencias || _obsCtrl.text.trim().isEmpty)
            ? null
            : _obsCtrl.text.trim(),
        nuevasEvidencias: _evidenciasNuevas,
      );
      if (!mounted) return;
      AppFeedback.showInfo(
        context,
        message: widget.soloEvidencias
            ? 'Evidencias actualizadas correctamente.'
            : 'Cierre corregido correctamente.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final alturaVisible =
        mq.size.height - mq.viewInsets.bottom - mq.padding.top;
    final objetivo = alturaVisible * 0.92;
    final alto = objetivo < 280.0 ? 280.0 : objetivo;
    final inv = widget.inventario;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: alto),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.soloEvidencias
                          ? 'Editar evidencias'
                          : 'Corregir cierre de tarea',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📸 Evidencias',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (_evidenciasVisibles.isEmpty &&
                          _evidenciasNuevas.isEmpty)
                        Text(
                          'Sin evidencias',
                          style: TextStyle(color: Colors.grey.shade700),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._evidenciasVisibles.map(
                              (url) => _EvidenciaActualTile(
                                url: url,
                                onQuitar: () => setState(
                                  () => _evidenciasEliminadas.add(url),
                                ),
                              ),
                            ),
                            ..._evidenciasNuevas.map(
                              (f) => _EvidenciaNuevaTile(
                                archivo: f,
                                onQuitar: () =>
                                    setState(() => _evidenciasNuevas.remove(f)),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      if (_puedePegarImagen && _esperandoPegado)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Text(
                              'Modo pegado activo: copia la imagen y presiona Ctrl+V.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_puedeTomarFoto)
                            OutlinedButton.icon(
                              onPressed: _tomarFoto,
                              icon: const Icon(Icons.photo_camera),
                              label: const Text('Tomar foto'),
                            ),
                          if (_puedePegarImagen)
                            OutlinedButton.icon(
                              onPressed: _activarPegado,
                              icon: const Icon(Icons.content_paste_rounded),
                              label: Text(
                                _esperandoPegado
                                    ? 'Esperando Ctrl+V'
                                    : 'Pegar imagen',
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _agregarDesdeArchivo,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Agregar archivos'),
                          ),
                        ],
                      ),
                      if (_evidenciasEliminadas.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${_evidenciasEliminadas.length} evidencia(s) se borrarán también de Google Drive al guardar.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (!widget.soloEvidencias) ...[
                Row(
                  children: [
                    const Text(
                      'Insumos usados',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: inv.isEmpty ? null : _agregarFilaInsumo,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Agregar'),
                    ),
                  ],
                ),
                if (inv.isEmpty && _rows.isEmpty)
                  Text(
                    'No hay inventario disponible para este conjunto.',
                    style: TextStyle(color: Colors.grey.shade700),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final row = _rows[i];
                      InventarioItemResponse? item;
                      if (row.insumoId != null) {
                        try {
                          item = inv.firstWhere(
                            (x) => x.insumoId == row.insumoId,
                          );
                        } catch (_) {
                          item = null;
                        }
                      }

                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              DropdownButtonFormField<int>(
                                initialValue: row.insumoId,
                                decoration: const InputDecoration(
                                  labelText: 'Insumo',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: inv
                                    .map(
                                      (x) => DropdownMenuItem<int>(
                                        value: x.insumoId,
                                        child: Text(
                                          '${x.nombre} (${x.disponibleTexto})',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  row.insumoId = v;
                                  _insumosDirty = true;
                                }),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: row.qtyCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => _insumosDirty = true,
                                decoration: InputDecoration(
                                  labelText: 'Cantidad usada',
                                  hintText: item == null
                                      ? 'Ej: 0.5'
                                      : (item.contenidoPorUnidad != null
                                            ? 'En ${item.unidadContenido}'
                                            : 'En ${item.unidad}'),
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
                                        'Stock: ${item.disponibleTexto}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'Quitar',
                                    onPressed: () => _quitarFilaInsumo(i),
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
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _motivoCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: widget.soloEvidencias
                      ? 'Motivo del cambio (obligatorio)'
                      : 'Motivo de la corrección (obligatorio)',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (!widget.soloEvidencias) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _obsCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    widget.soloEvidencias
                        ? 'Guardar evidencias'
                        : 'Guardar corrección',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenciaActualTile extends StatelessWidget {
  final String url;
  final VoidCallback onQuitar;

  const _EvidenciaActualTile({required this.url, required this.onQuitar});

  @override
  Widget build(BuildContext context) {
    final candidates = evidenceUrlCandidates(url);
    final isImg = isLikelyImageEvidence(url);

    return Stack(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.grey.shade50,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: candidates.isEmpty
                ? null
                : () => mostrarEvidenciaPreview(context, candidates),
            child: isImg
                ? EvidenceImage(
                    urls: candidates,
                    fit: BoxFit.cover,
                    fallback: Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.insert_drive_file_outlined,
                      color: Colors.grey.shade700,
                    ),
                  ),
          ),
        ),
        Positioned(top: -6, right: -6, child: _QuitarBadge(onTap: onQuitar)),
      ],
    );
  }
}

class _EvidenciaNuevaTile extends StatelessWidget {
  final SelectedUploadFile archivo;
  final VoidCallback onQuitar;

  const _EvidenciaNuevaTile({required this.archivo, required this.onQuitar});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.shade200),
            color: Colors.green.shade50,
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fiber_new, color: Colors.green),
              const SizedBox(height: 4),
              Text(
                archivo.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        Positioned(top: -6, right: -6, child: _QuitarBadge(onTap: onQuitar)),
      ],
    );
  }
}

class _QuitarBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _QuitarBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 14, color: Colors.white),
      ),
    );
  }
}
