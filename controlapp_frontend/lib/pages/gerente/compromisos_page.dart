import 'package:flutter/material.dart';

import '../../api/administrador_api.dart';
import '../../api/evidencias_multipart.dart' show maxEvidenciasCierre;
import '../../api/gerente_api.dart';
import '../../model/evidencia_adjunto_model.dart';
import '../../model/compromiso_model.dart';
import '../../service/evidencia_camara_service.dart';
import '../../service/app_error.dart';
import '../../service/app_feedback.dart';
import '../../service/permission_service.dart';
import '../../service/session_service.dart';
import '../../service/theme.dart';
import '../../utils/cronograma/cierre_utils.dart' show evidenciasDesdeArchivos;
import '../../utils/pickers/galeria_evidencias.dart';
import '../../utils/pickers/selected_upload_file.dart';
import '../../widgets/evidencia_gallery.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

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
    this.emptyMessage = 'Aún no hay compromisos.\nAgrega el primero.',
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
  _CompromisoFilter _filter = _CompromisoFilter.abiertos;

  bool get _canManage =>
      PermissionService.instance.can('compromisos.gestionar');
  bool get _canSeguimiento =>
      PermissionService.instance.can('compromisos.seguimiento.gestionar');

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

  Future<void> _registrarSeguimiento(CompromisoModel item) async {
    if (!_canSeguimiento || item.completado) return;
    final draft = await showDialog<_SeguimientoDraft>(
      context: context,
      builder: (_) => _SeguimientoDialog(estadoInicial: item.estado),
    );
    if (draft == null) return;
    try {
      final raw = await _api.agregarSeguimientoCompromiso(
        id: item.id,
        estado: draft.estado,
        observacion: draft.observacion,
        evidencias: draft.evidencias,
      );
      if (!mounted) return;
      setState(() => item.updateFrom(CompromisoModel.fromJson(raw)));
      _snack('Se guardó el avance de la PQRS.');
    } catch (e) {
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
      final raw = await _api.actualizarCompromiso(id: item.id, titulo: nuevo);
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
      await _api.eliminarCompromiso(item.id);
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
          ? const SkeletonList()
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
                  if (_canManage) ...[
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
                              border: const OutlineInputBorder(),
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
                  ],
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
                          label: 'Activos',
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
                          label: 'Completados',
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              12,
                                              4,
                                              0,
                                            ),
                                            child: Icon(
                                              item.completado
                                                  ? Icons.check_circle_rounded
                                                  : Icons.assignment_outlined,
                                              color: item.completado
                                                  ? Colors.green
                                                  : AppTheme.primary,
                                            ),
                                          ),
                                          Expanded(
                                            child: InkWell(
                                              onTap:
                                                  _canManage &&
                                                      !widget
                                                          .usarFlujoAdministrador
                                                  ? () => _editarTitulo(item)
                                                  : null,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.titulo,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      children: [
                                                        if (!widget
                                                            .usarFlujoAdministrador) ...[
                                                          _MetaChip(
                                                            icon: Icons
                                                                .schedule_rounded,
                                                            label: item
                                                                .antiguedadLabel,
                                                          ),
                                                          _MetaChip(
                                                            icon: Icons
                                                                .event_available_outlined,
                                                            label: item
                                                                .fechaCreacionLabel,
                                                          ),
                                                        ],
                                                        _MetaChip(
                                                          icon: Icons
                                                              .person_outline,
                                                          label:
                                                              item.autorLabel,
                                                        ),
                                                        _MetaChip(
                                                          icon: Icons
                                                              .track_changes_outlined,
                                                          label:
                                                              item.estadoLabel,
                                                          color: item.completado
                                                              ? Colors.green
                                                              : AppTheme
                                                                    .primary,
                                                        ),
                                                        _MetaChip(
                                                          icon: item.completado
                                                              ? Icons
                                                                    .task_alt_outlined
                                                              : Icons
                                                                    .timelapse_rounded,
                                                          label: item
                                                              .fechaCierreLabel,
                                                        ),
                                                        if (!widget
                                                            .usarFlujoAdministrador)
                                                          _MetaChip(
                                                            icon: Icons
                                                                .flag_outlined,
                                                            label:
                                                                item.ansLabel,
                                                            color: ansColor,
                                                          ),
                                                      ],
                                                    ),
                                                    if (item
                                                            .actualizaciones
                                                            .isNotEmpty &&
                                                        (item
                                                                    .actualizaciones
                                                                    .last
                                                                    .observacion ??
                                                                '')
                                                            .trim()
                                                            .isNotEmpty) ...[
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'Último avance: ${item.actualizaciones.last.observacion}',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                    ],
                                                    if (item
                                                            .actualizaciones
                                                            .isNotEmpty &&
                                                        item
                                                            .actualizaciones
                                                            .last
                                                            .evidencias
                                                            .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 4,
                                                            ),
                                                        child: Text(
                                                          '${item.actualizaciones.last.evidencias.length} evidencia(s) en el último avance',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .black54,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_canSeguimiento &&
                                              !item.completado)
                                            IconButton(
                                              tooltip: 'Registrar avance',
                                              onPressed: () =>
                                                  _registrarSeguimiento(item),
                                              icon: const Icon(
                                                Icons.add_comment_outlined,
                                              ),
                                            ),
                                          if (_canManage &&
                                              !widget
                                                  .usarFlujoAdministrador) ...[
                                            IconButton(
                                              tooltip: 'Editar',
                                              onPressed: () =>
                                                  _editarTitulo(item),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                            if (!item.completado)
                                              IconButton(
                                                tooltip: 'Eliminar',
                                                onPressed: () =>
                                                    _eliminar(item),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                              ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (item.actualizaciones.isNotEmpty)
                                      ExpansionTile(
                                        tilePadding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        title: Text(
                                          'Historial (${item.actualizaciones.length})',
                                        ),
                                        children: item.actualizaciones.map((
                                          actualizacion,
                                        ) {
                                          final fecha = actualizacion.creadaEn;
                                          final fechaLabel = fecha == null
                                              ? 'Fecha no disponible'
                                              : '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
                                          return ListTile(
                                            title: Text(
                                              actualizacion.estadoLabel,
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '$fechaLabel · ${actualizacion.actorLabel}',
                                                ),
                                                if ((actualizacion
                                                            .observacion ??
                                                        '')
                                                    .trim()
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    actualizacion.observacion!,
                                                  ),
                                                ],
                                                if (actualizacion
                                                    .evidencias
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  EvidenciaGallery(
                                                    evidencias: actualizacion
                                                        .evidencias,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        }).toList(),
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

class _SeguimientoDraft {
  const _SeguimientoDraft({
    required this.estado,
    required this.observacion,
    required this.evidencias,
  });

  final String estado;
  final String? observacion;
  final List<EvidenciaAdjunto> evidencias;
}

class _SeguimientoDialog extends StatefulWidget {
  const _SeguimientoDialog({required this.estadoInicial});

  final String estadoInicial;

  @override
  State<_SeguimientoDialog> createState() => _SeguimientoDialogState();
}

class _SeguimientoDialogState extends State<_SeguimientoDialog> {
  static const _estados = <String, String>{
    'RECIBIDO': 'Recibido',
    'EN_REVISION': 'En revisión',
    'EN_PROCESO': 'En proceso',
    'EN_ESPERA': 'En espera',
    'CERRADO': 'Cerrado',
  };

  final _observacion = TextEditingController();
  final List<EvidenciaAdjunto> _evidencias = [];
  late String _estado;
  bool _cargandoArchivo = false;

  @override
  void initState() {
    super.initState();
    _estado = _estados.containsKey(widget.estadoInicial)
        ? widget.estadoInicial
        : 'RECIBIDO';
  }

  @override
  void dispose() {
    _observacion.dispose();
    super.dispose();
  }

  void _agregarArchivos(List<SelectedUploadFile> archivos) {
    final nuevos = evidenciasDesdeArchivos(archivos);
    if (!mounted) return;
    setState(() {
      for (final evidencia in nuevos) {
        if (_evidencias.length >= maxEvidenciasCierre) break;
        _evidencias.add(evidencia);
      }
    });
  }

  Future<void> _tomarFoto() async {
    setState(() => _cargandoArchivo = true);
    try {
      final foto = await EvidenciaCamara.tomarFoto();
      if (foto != null) _agregarArchivos([foto]);
    } finally {
      if (mounted) setState(() => _cargandoArchivo = false);
    }
  }

  Future<void> _elegirFotos() async {
    final restantes = maxEvidenciasCierre - _evidencias.length;
    if (restantes <= 0) return;
    setState(() => _cargandoArchivo = true);
    try {
      final seleccionados = await GaleriaEvidencias.elegir(maximo: restantes);
      if (seleccionados.isEmpty) return;
      final preparados = await EvidenciaCamara.prepararDeGaleria(seleccionados);
      _agregarArchivos(preparados);
    } finally {
      if (mounted) setState(() => _cargandoArchivo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar avance'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: _estados.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: _cargandoArchivo
                    ? null
                    : (value) {
                        if (value != null) setState(() => _estado = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _observacion,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Observación (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _cargandoArchivo ||
                            _evidencias.length >= maxEvidenciasCierre
                        ? null
                        : _tomarFoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Tomar foto'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _cargandoArchivo ||
                            _evidencias.length >= maxEvidenciasCierre
                        ? null
                        : _elegirFotos,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Adjuntar'),
                  ),
                ],
              ),
              if (_cargandoArchivo) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              if (_evidencias.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._evidencias.asMap().entries.map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.image_outlined),
                    title: Text(
                      entry.value.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Quitar evidencia',
                      onPressed: _cargandoArchivo
                          ? null
                          : () =>
                                setState(() => _evidencias.removeAt(entry.key)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cargandoArchivo ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _cargandoArchivo
              ? null
              : () => Navigator.pop(
                  context,
                  _SeguimientoDraft(
                    estado: _estado,
                    observacion: _observacion.text.trim().isEmpty
                        ? null
                        : _observacion.text.trim(),
                    evidencias: List.unmodifiable(_evidencias),
                  ),
                ),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar avance'),
        ),
      ],
    );
  }
}
