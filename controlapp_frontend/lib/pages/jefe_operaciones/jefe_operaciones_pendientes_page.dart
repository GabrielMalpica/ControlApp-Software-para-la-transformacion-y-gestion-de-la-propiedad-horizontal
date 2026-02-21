import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:flutter_application_1/api/jefe_operaciones_api.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';

import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/utils/pickers/file_pick_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class JefeOperacionesPendientesPage extends StatefulWidget {
  final String? conjuntoId; // opcional
  const JefeOperacionesPendientesPage({super.key, this.conjuntoId});

  @override
  State<JefeOperacionesPendientesPage> createState() =>
      _JefeOperacionesPendientesPageState();
}

class _JefeOperacionesPendientesPageState
    extends State<JefeOperacionesPendientesPage> {
  final _api = JefeOperacionesApi();

  bool _loading = true;
  String? _error;
  List<TareaModel> _pendientes = [];

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await _api.listarPendientes(conjuntoId: widget.conjuntoId);
      setState(() => _pendientes = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          'Aprobar tareas',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text('Error:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_pendientes.isEmpty) {
      return const Center(child: Text('No hay tareas pendientes.'));
    }

    _pendientes.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _pendientes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final t = _pendientes[i];
        final ini = DateFormat('dd/MM/yyyy HH:mm', 'es').format(t.fechaInicio);
        final fin = DateFormat('dd/MM/yyyy HH:mm', 'es').format(t.fechaFin);
        final evCount = (t.evidencias ?? const []).length;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 1,
          child: ListTile(
            title: Text(
              t.descripcion,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🗓 $ini  →  $fin',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '🏢 ${t.conjuntoNombre ?? t.conjuntoId ?? "—"} • 📍 ${t.ubicacionNombre ?? "—"} • 🧩 ${t.elementoNombre ?? "—"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '👷 ${t.operariosNombres.isEmpty ? "Sin operarios" : t.operariosNombres.join(", ")}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '🧑‍💼 Supervisor: ${t.supervisorNombre ?? t.supervisorId ?? "—"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _pill(
                        evCount == 0
                            ? 'Sin evidencias'
                            : 'Evidencias: $evCount',
                        evCount == 0
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                      const SizedBox(width: 8),
                      _pill('Estado: ${t.estado ?? "—"}', Colors.blueGrey),
                    ],
                  ),
                ],
              ),
            ),
            onTap: () => _abrirDetalle(t),
          ),
        );
      },
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Future<void> _abrirDetalle(TareaModel t) async {
    // Enviamos TODO como SelectedUploadFile (web bytes, IO path/bytes)
    final archivos = <SelectedUploadFile>[];

    final obsRechazoCtrl = TextEditingController();
    String accion = 'APROBAR';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final h = MediaQuery.of(ctx).size.height * 0.90;

        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> pickCam() async {
              if (!_isMobile) {
                AppFeedback.showFromSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Cámara solo disponible en móvil.'),
                  ),
                );
                return;
              }
              final picker = ImagePicker();
              final x = await picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 85,
              );
              if (x == null) return;

              final bytes = await x.readAsBytes();
              setModal(() {
                archivos.add(
                  SelectedUploadFile(
                    name: x.name.isNotEmpty ? x.name : 'foto.jpg',
                    bytes: bytes,
                    mimeType: 'image/jpeg',
                  ),
                );
              });
            }

            Future<void> pickGallery() async {
              // ✅ Web: usar selector universal HTML (no image_picker)
              if (kIsWeb) {
                final picked = await UniversalFilePick.pick(
                  allowMultiple: true,
                  allowedExtensions: const ['jpg', 'jpeg', 'png'],
                );
                if (picked.isEmpty) return;
                setModal(() => archivos.addAll(picked));
                return;
              }

              // ✅ Desktop: selector universal (IO usa file_picker interno)
              if (_isDesktop) {
                final picked = await UniversalFilePick.pick(
                  allowMultiple: true,
                  allowedExtensions: const ['jpg', 'jpeg', 'png'],
                );
                if (picked.isEmpty) return;
                setModal(() => archivos.addAll(picked));
                return;
              }

              // ✅ Mobile: image_picker multi
              final picker = ImagePicker();
              final xs = await picker.pickMultiImage(imageQuality: 85);
              if (xs.isEmpty) return;

              final converted = <SelectedUploadFile>[];
              for (final xf in xs) {
                final bytes = await xf.readAsBytes();
                converted.add(
                  SelectedUploadFile(
                    name: xf.name.isNotEmpty ? xf.name : 'foto.jpg',
                    bytes: bytes,
                    mimeType: 'image/jpeg',
                  ),
                );
              }

              setModal(() => archivos.addAll(converted));
            }

            Future<void> pickFiles() async {
              // ✅ Web / Desktop / Mobile: selector universal
              final picked = await UniversalFilePick.pick(
                allowMultiple: true,
                allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
              );
              if (picked.isEmpty) return;
              setModal(() => archivos.addAll(picked));
            }

            void removeArchivo(int i) => setModal(() => archivos.removeAt(i));

            final evidencias = t.evidencias ?? const [];
            final ini = DateFormat(
              'dd/MM/yyyy HH:mm',
              'es',
            ).format(t.fechaInicio);
            final fin = DateFormat('dd/MM/yyyy HH:mm', 'es').format(t.fechaFin);

            final necesitaObsRechazo = accion == 'RECHAZAR';

            // Para preview: separamos imágenes vs otros
            bool isImageName(String name) {
              final n = name.toLowerCase();
              return n.endsWith('.jpg') ||
                  n.endsWith('.jpeg') ||
                  n.endsWith('.png');
            }

            return SizedBox(
              height: h,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Revisión de tarea',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.descripcion,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _kv('ID', t.id.toString()),
                          _kv(
                            'Conjunto',
                            t.conjuntoNombre ?? t.conjuntoId ?? '—',
                          ),
                          _kv('Ubicación', t.ubicacionNombre ?? '—'),
                          _kv('Elemento', t.elementoNombre ?? '—'),
                          _kv(
                            'Supervisor',
                            t.supervisorNombre ?? t.supervisorId ?? '—',
                          ),
                          _kv(
                            'Operarios',
                            t.operariosNombres.isEmpty
                                ? '—'
                                : t.operariosNombres.join(', '),
                          ),
                          _kv('Horario', '$ini  →  $fin'),
                          _kv('Estado', t.estado ?? '—'),
                          if ((t.observaciones ?? '').trim().isNotEmpty)
                            _kv('Observaciones', t.observaciones!.trim()),
                          const SizedBox(height: 14),

                          // Evidencias existentes
                          Row(
                            children: [
                              const Text(
                                'Evidencias enviadas',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              Text(
                                evidencias.isEmpty
                                    ? '0'
                                    : '${evidencias.length}',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (evidencias.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.20),
                                ),
                              ),
                              child: const Text(
                                'Esta tarea no tiene evidencias. Puedes adjuntarlas antes de aprobar.',
                                style: TextStyle(fontSize: 12),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: evidencias.map((url) {
                                final isImg =
                                    url.contains('drive.google.com') ||
                                    url.toLowerCase().endsWith('.jpg') ||
                                    url.toLowerCase().endsWith('.jpeg') ||
                                    url.toLowerCase().endsWith('.png');

                                return Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    color: Colors.grey.shade50,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: isImg
                                      ? Image.network(url, fit: BoxFit.cover)
                                      : Center(
                                          child: Text(
                                            'Archivo',
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                );
                              }).toList(),
                            ),

                          const SizedBox(height: 16),

                          const Text(
                            'Adjuntar evidencias (opcional)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: pickCam,
                                icon: const Icon(Icons.photo_camera),
                                label: Text(
                                  _isMobile ? 'Cámara' : 'Cámara (móvil)',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: pickGallery,
                                icon: const Icon(Icons.photo_library),
                                label: Text(
                                  _isMobile ? 'Galería' : 'Elegir fotos',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: pickFiles,
                                icon: const Icon(Icons.attach_file),
                                label: const Text('Archivos'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          if (archivos.isNotEmpty) ...[
                            const Text(
                              'Archivos seleccionados:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),

                            // Preview cuadritos (solo imágenes con bytes)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(archivos.length, (i) {
                                final f = archivos[i];
                                final isImg = isImageName(f.name);

                                Widget thumb;
                                if (isImg && f.hasBytes) {
                                  thumb = ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      f.bytes!,
                                      width: 92,
                                      height: 92,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                } else {
                                  thumb = Container(
                                    width: 92,
                                    height: 92,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      color: Colors.grey.shade50,
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      isImg
                                          ? Icons.image
                                          : Icons.insert_drive_file,
                                      color: Colors.grey.shade700,
                                    ),
                                  );
                                }

                                return Stack(
                                  children: [
                                    thumb,
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: InkWell(
                                        onTap: () => removeArchivo(i),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                            const SizedBox(height: 10),

                            // Lista por nombre
                            ...List.generate(archivos.length, (i) {
                              final f = archivos[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  isImageName(f.name)
                                      ? Icons.image
                                      : Icons.insert_drive_file,
                                ),
                                title: Text(
                                  f.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _archivoInfo(f),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],

                          const Divider(height: 22),

                          const Text(
                            'Decisión',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: accion,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'APROBAR',
                                child: Text('Aprobar'),
                              ),
                              DropdownMenuItem(
                                value: 'RECHAZAR',
                                child: Text('Rechazar'),
                              ),
                              DropdownMenuItem(
                                value: 'NO_COMPLETADA',
                                child: Text('Marcar No Completada'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setModal(() => accion = v);
                            },
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: obsRechazoCtrl,
                            minLines: 2,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText:
                                  'Observaciones (obligatorio si rechaza)',
                              border: const OutlineInputBorder(),
                              errorText:
                                  necesitaObsRechazo &&
                                      obsRechazoCtrl.text.trim().isEmpty
                                  ? 'Requerido para rechazar'
                                  : null,
                            ),
                            onChanged: (_) => setModal(() {}),
                          ),
                          const SizedBox(height: 18),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Confirmar'),
                              onPressed: () async {
                                if (accion == 'RECHAZAR' &&
                                    obsRechazoCtrl.text.trim().isEmpty) {
                                  setModal(() {});
                                  return;
                                }

                                final hasFiles = archivos.isNotEmpty;

                                try {
                                  Map<String, dynamic> out;

                                  if (hasFiles) {
                                    out = await _api.veredictoConEvidencias(
                                      tareaId: t.id,
                                      accion: accion,
                                      observacionesRechazo: obsRechazoCtrl.text,
                                      fechaVerificacion: DateTime.now(),
                                      archivos: archivos,
                                    );
                                  } else {
                                    out = await _api.veredicto(
                                      tareaId: t.id,
                                      accion: accion,
                                      observacionesRechazo: obsRechazoCtrl.text,
                                      fechaVerificacion: DateTime.now(),
                                    );
                                  }

                                  if (out['ok'] == false) {
                                    if (!mounted) return;
                                    AppFeedback.showFromSnackBar(
                                      context,
                                      SnackBar(
                                        content: Text(
                                          out['error']?.toString() ?? 'Error',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!mounted) return;
                                  Navigator.pop(ctx);
                                  await _cargar();

                                  AppFeedback.showFromSnackBar(
                                    context,
                                    SnackBar(
                                      content: Text(
                                        accion == 'APROBAR'
                                            ? 'Tarea aprobada'
                                            : accion == 'RECHAZAR'
                                            ? 'Tarea rechazada'
                                            : 'Tarea marcada No Completada',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  AppFeedback.showFromSnackBar(
                                    context,
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _archivoInfo(SelectedUploadFile f) {
    if (f.hasBytes) {
      final kb = f.bytes!.lengthInBytes / 1024;
      if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
      final mb = kb / 1024;
      return '${mb.toStringAsFixed(1)} MB';
    }
    if (f.hasPath) return f.path!;
    return '';
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$k:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
