import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/api/inventario_activo_api.dart';
import 'package:flutter_application_1/model/inventario_activo_model.dart';
import 'package:flutter_application_1/pdf/acta_inventario_pdf.dart';
import 'package:flutter_application_1/pdf/pdf_actions.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/permission_service.dart';
import 'package:flutter_application_1/utils/pickers/camera_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/clipboard_image_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';
import 'package:intl/intl.dart';

class InventarioActivosPage extends StatefulWidget {
  final String empresaId;
  final String? conjuntoId;
  final ClaseActivoInventario initialClase;
  final bool soloEmpresa;
  final bool soloPendientes;
  final bool abrirCreacionInicial;
  final bool claseFija;

  const InventarioActivosPage({
    super.key,
    required this.empresaId,
    this.conjuntoId,
    this.initialClase = ClaseActivoInventario.maquinaria,
    this.soloEmpresa = false,
    this.soloPendientes = false,
    this.abrirCreacionInicial = false,
    this.claseFija = false,
  });

  @override
  State<InventarioActivosPage> createState() => _InventarioActivosPageState();
}

class _InventarioActivosPageState extends State<InventarioActivosPage> {
  final _api = InventarioActivoApi();
  final _search = TextEditingController();
  late ClaseActivoInventario _clase;
  List<ActivoInventario> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _approval;
  int _total = 0;
  int _page = 1;
  bool _generatingActa = false;

  static const _pageSize = 50;

  bool get _approver =>
      PermissionService.instance.hasAnyRole(const [
        'gerente',
        'jefe_operaciones',
        'supervisor',
      ]) &&
      PermissionService.instance.canAny(const [
        'maquinaria.aprobar',
        'herramientas.aprobar',
      ]);

  String get _prefix => _clase == ClaseActivoInventario.maquinaria
      ? 'maquinaria'
      : 'herramientas';

  bool get _canCreate => PermissionService.instance.can('$_prefix.crear');

  bool get _canEdit =>
      PermissionService.instance.canAny(['$_prefix.editar', '$_prefix.crear']);

  bool get _canState =>
      _approver && PermissionService.instance.can('$_prefix.gestionar_estado');

  bool get _canLoan =>
      _approver && PermissionService.instance.can('$_prefix.prestar');

  bool get _canDelete =>
      PermissionService.instance.hasAnyRole(const ['gerente']);

  bool get _canDownloadActa =>
      widget.conjuntoId != null &&
      PermissionService.instance.hasAnyRole(const [
        'gerente',
        'jefe_operaciones',
      ]);

  @override
  void initState() {
    super.initState();
    _clase = widget.initialClase;
    _approval = widget.soloPendientes ? 'PENDIENTE' : null;
    _load();
    if (widget.abrirCreacionInicial && !widget.soloPendientes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canCreate) _create();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append && (_loadingMore || _items.length >= _total)) return;
    final requestedPage = append ? _page + 1 : 1;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final result = await _api.listar(
        empresaId: widget.empresaId,
        conjuntoId: widget.conjuntoId,
        clase: _clase,
        busqueda: _search.text,
        aprobacion: _approval,
        propietario: widget.soloEmpresa ? 'EMPRESA' : null,
        page: requestedPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = append ? [..._items, ...result.data] : result.data;
        _total = result.total;
        _page = result.page;
      });
    } catch (error) {
      if (mounted) setState(() => _error = AppError.messageOf(error));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _changeClass(ClaseActivoInventario value) {
    setState(() {
      _clase = value;
      _items = const [];
    });
    _load();
  }

  String _label(String value) => value
      .toLowerCase()
      .split('_')
      .map(
        (word) => word.isEmpty
            ? word
            : word.substring(0, 1).toUpperCase() + word.substring(1),
      )
      .join(' ');

  Map<String, List<ActivoInventario>> get _groups {
    final result = <String, List<ActivoInventario>>{};
    for (final item in _items) {
      result.putIfAbsent(item.nombreCatalogo, () => []).add(item);
    }
    return Map.fromEntries(
      result.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
  }

  Future<String?> _ask(String title, String label, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 2) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _action(Future<void> Function() callback, String success) async {
    try {
      await callback();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text(success)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(error))),
      );
    }
  }

  Future<void> _approve(ActivoInventario item) {
    final loteId = item.clase == ClaseActivoInventario.herramienta
        ? item.registroLoteId
        : null;
    if (loteId != null && loteId.isNotEmpty) {
      return _action(
        () => _api.aprobarLoteHerramientas(loteId),
        'Lote de herramientas aprobado.',
      );
    }
    return _action(
      () => _api.aprobar(item.clase, item.id),
      'Registro aprobado.',
    );
  }

  Future<void> _reject(ActivoInventario item) async {
    final reason = await _ask('Rechazar registro', 'Motivo del rechazo');
    if (reason == null) return;
    final loteId = item.clase == ClaseActivoInventario.herramienta
        ? item.registroLoteId
        : null;
    await _action(
      () => loteId != null && loteId.isNotEmpty
          ? _api.rechazarLoteHerramientas(loteId, reason)
          : _api.rechazar(item.clase, item.id, reason),
      loteId != null && loteId.isNotEmpty
          ? 'Lote de herramientas rechazado.'
          : 'Registro rechazado.',
    );
  }

  Future<void> _editAsset(ActivoInventario item) async {
    final alias = TextEditingController(text: item.alias ?? '');
    final brand = TextEditingController(text: item.marca ?? '');
    final model = TextEditingController(text: item.modelo ?? '');
    final serial = TextEditingController(text: item.serial ?? '');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar información'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: alias,
                decoration: const InputDecoration(labelText: 'Alias'),
              ),
              TextField(
                controller: brand,
                decoration: const InputDecoration(labelText: 'Marca'),
              ),
              TextField(
                controller: model,
                decoration: const InputDecoration(labelText: 'Modelo'),
              ),
              TextField(
                controller: serial,
                decoration: const InputDecoration(labelText: 'Serial'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'alias': alias.text.trim().isEmpty ? null : alias.text.trim(),
              'marca': brand.text.trim().isEmpty ? null : brand.text.trim(),
              'modelo': model.text.trim().isEmpty ? null : model.text.trim(),
              'serial': serial.text.trim().isEmpty ? null : serial.text.trim(),
            }),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    alias.dispose();
    brand.dispose();
    model.dispose();
    serial.dispose();
    if (result == null) return;
    await _action(
      () => _api.editar(item.clase, item.id, result),
      'Información actualizada.',
    );
  }

  Future<void> _photo(ActivoInventario item) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return;
    if (file.size > 5 * 1024 * 1024) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('La fotografía no puede superar 5 MB.')),
      );
      return;
    }
    final selected = SelectedUploadFile(
      name: file.name,
      path: file.path,
      bytes: file.bytes,
      mimeType: file.extension?.toLowerCase() == 'png'
          ? 'image/png'
          : 'image/jpeg',
    );
    await _action(
      () => _api.subirFoto(item.clase, item.id, selected),
      'Fotografía actualizada.',
    );
  }

  Future<void> _deletePhoto(ActivoInventario item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar fotografía'),
        content: const Text(
          'Se quitará la fotografía del activo. Esta acción queda auditada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _action(
      () => _api.eliminarFoto(item.clase, item.id),
      'Fotografía eliminada.',
    );
  }

  Future<void> _deleteAsset(ActivoInventario item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar del inventario'),
        content: Text(
          'Se eliminará "${item.alias?.isNotEmpty == true ? item.alias! : item.codigoInterno}" '
          'del inventario. Esta acción no se puede deshacer y solo debe usarse '
          'si el registro se creó por error.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _action(
      () => _api.eliminar(item.clase, item.id),
      'Activo eliminado del inventario.',
    );
  }

  void _showPhoto(ActivoInventario item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.nombreCatalogo),
        content: FutureBuilder<Uint8List>(
          future: _api.foto(item.clase, item.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                width: 320,
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshot.hasData) {
              return const Text('No se pudo cargar la fotografía.');
            }
            return Image.memory(snapshot.data!, fit: BoxFit.contain);
          },
        ),
      ),
    );
  }

  Future<void> _changeStatus(ActivoInventario item) async {
    final states = item.clase == ClaseActivoInventario.maquinaria
        ? const [
            'OPERATIVA',
            'EN_MANTENIMIENTO',
            'EN_REPARACION',
            'DANADA',
            'FUERA_DE_SERVICIO',
            'PERDIDA',
            'RETIRADA',
          ]
        : const [
            'OPERATIVA',
            'EN_MANTENIMIENTO',
            'DANADA',
            'PERDIDA',
            'FUERA_DE_SERVICIO',
            'BAJA',
            'RETIRADA',
          ];
    final state = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Cambiar estado'),
        children: states
            .map(
              (state) => ListTile(
                selected: state == item.estado,
                leading: Icon(
                  state == item.estado
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(_label(state)),
                onTap: () => Navigator.pop(dialogContext, state),
              ),
            )
            .toList(),
      ),
    );
    if (state == null) return;
    String? condicion;
    if (state == 'OPERATIVA') {
      condicion = await _askCondicion();
      if (condicion == null) return;
    }
    final reason = await _ask('Justificación', 'Motivo del cambio');
    if (reason == null) return;
    await _action(
      () => _api.cambiarEstado(
        item.clase,
        item.id,
        state,
        reason,
        condicion: condicion,
      ),
      'Estado actualizado.',
    );
  }

  Future<String?> _askCondicion() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('¿Nueva o usada?'),
        children: [
          ListTile(
            leading: const Icon(Icons.fiber_new_outlined),
            title: const Text('Nueva'),
            onTap: () => Navigator.pop(dialogContext, 'NUEVA'),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('Usada'),
            onTap: () => Navigator.pop(dialogContext, 'USADA'),
          ),
        ],
      ),
    );
  }

  Future<void> _loan(ActivoInventario item) async {
    final nit = await _ask('Prestar activo', 'NIT del conjunto');
    if (nit == null) return;
    await _action(
      () => _api.prestar(
        clase: item.clase,
        id: item.id,
        conjuntoId: nit,
        fechaDevolucion: DateTime.now().add(const Duration(days: 30)),
      ),
      'Préstamo registrado por 30 días.',
    );
  }

  Future<void> _create() async {
    try {
      final catalog = await _api.catalogo(
        empresaId: widget.empresaId,
        clase: _clase,
      );
      if (!mounted) return;
      final choice = await showModalBottomSheet<_CreateChoice>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _CreateAssetSheet(clase: _clase, catalog: catalog),
      );
      if (choice == null) return;
      final body = <String, dynamic>{
        if (choice.catalogId != null &&
            _clase == ClaseActivoInventario.maquinaria)
          'tipoCatalogoId': choice.catalogId,
        if (choice.catalogId != null &&
            _clase == ClaseActivoInventario.herramienta)
          'herramientaId': choice.catalogId,
        if (choice.catalogId == null)
          'tipoPropuesto': _clase == ClaseActivoInventario.maquinaria
              ? {'nombre': choice.proposedName, 'tipoLegacy': 'OTRO'}
              : {
                  'nombre': choice.proposedName,
                  'unidad': 'UNIDAD',
                  'categoria': 'OTROS',
                  'modoControl': 'PRESTAMO',
                },
        if (_clase == ClaseActivoInventario.maquinaria)
          'marca': choice.brand.isEmpty ? 'Sin especificar' : choice.brand,
        if (_clase == ClaseActivoInventario.herramienta)
          'cantidad': choice.quantity,
        if (choice.brand.isNotEmpty &&
            _clase == ClaseActivoInventario.herramienta)
          'marca': choice.brand,
        if (choice.model.isNotEmpty) 'modelo': choice.model,
        if (choice.serial.isNotEmpty) 'serial': choice.serial,
        if (choice.alias.isNotEmpty) 'alias': choice.alias,
        'condicion': choice.condicion,
      };
      final created = await _api.crear(
        empresaId: widget.empresaId,
        conjuntoId: widget.conjuntoId,
        clase: _clase,
        body: body,
      );
      if (choice.photo != null && created.length == 1) {
        await _api.subirFoto(_clase, created.first.id, choice.photo!);
      }
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            created.first.estadoAprobacion == 'PENDIENTE'
                ? 'Registro enviado para aprobación.'
                : 'Activo registrado correctamente.',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(error))),
      );
    }
  }

  Future<List<ActivoInventario>> _listarTodo(
    String conjuntoId,
    ClaseActivoInventario clase,
  ) async {
    const pageSize = 100;
    final items = <ActivoInventario>[];
    var page = 1;
    while (true) {
      final result = await _api.listar(
        empresaId: widget.empresaId,
        clase: clase,
        conjuntoId: conjuntoId,
        propietario: 'CONJUNTO',
        aprobacion: 'APROBADA',
        page: page,
        pageSize: pageSize,
      );
      items.addAll(result.data);
      if (items.length >= result.total || result.data.isEmpty) break;
      page++;
    }
    return items;
  }

  Future<void> _downloadActa() async {
    final conjuntoId = widget.conjuntoId;
    if (conjuntoId == null || _generatingActa) return;
    setState(() => _generatingActa = true);
    try {
      final conjunto = await GerenteApi().obtenerConjunto(conjuntoId);
      final maquinaria = await _listarTodo(
        conjuntoId,
        ClaseActivoInventario.maquinaria,
      );
      final herramientas = await _listarTodo(
        conjuntoId,
        ClaseActivoInventario.herramienta,
      );
      final bytes = await buildActaInventarioPdf(
        empresaNit: widget.empresaId,
        conjuntoNombre: conjunto.nombre,
        conjuntoNit: conjunto.nit,
        administradorNombre: conjunto.administradorNombre,
        maquinaria: maquinaria,
        herramientas: herramientas,
      );
      await openOrDownloadPdf(bytes, 'acta_inventario_${conjunto.nit}.pdf');
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(error))),
      );
    } finally {
      if (mounted) setState(() => _generatingActa = false);
    }
  }

  Color _color(String value) {
    if (value == 'APROBADA' || value == 'OPERATIVA') return Colors.green;
    if (value == 'PENDIENTE' ||
        value == 'EN_MANTENIMIENTO' ||
        value == 'EN_REPARACION') {
      return Colors.orange;
    }
    if (value == 'RECHAZADA' ||
        value == 'DANADA' ||
        value == 'PERDIDA' ||
        value == 'FUERA_DE_SERVICIO' ||
        value == 'BAJA' ||
        value == 'RETIRADA') {
      return Colors.red;
    }
    return Colors.blueGrey;
  }

  Widget _tag(String value) {
    final color = _color(value);
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(_label(value)),
      backgroundColor: color.withValues(alpha: .1),
      side: BorderSide(color: color.withValues(alpha: .4)),
    );
  }

  Widget _unit(ActivoInventario item) {
    final editable =
        _canEdit && (_approver || item.estadoAprobacion == 'PENDIENTE');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: item.fotoUrl == null
                      ? 'Sin fotografía'
                      : 'Ver fotografía',
                  onPressed: item.fotoUrl == null
                      ? null
                      : () => _showPhoto(item),
                  icon: Icon(
                    item.fotoUrl == null
                        ? Icons.image_not_supported_outlined
                        : Icons.photo_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.alias?.isNotEmpty == true
                            ? item.alias!
                            : item.codigoInterno,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          if (item.marca?.isNotEmpty == true) item.marca!,
                          if (item.modelo?.isNotEmpty == true) item.modelo!,
                          if (item.serial?.isNotEmpty == true)
                            'Serial ${item.serial!}',
                        ].join(' · '),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') _editAsset(item);
                    if (action == 'photo') _photo(item);
                    if (action == 'delete_photo') _deletePhoto(item);
                    if (action == 'state') _changeStatus(item);
                    if (action == 'loan') _loan(item);
                    if (action == 'return') {
                      _action(
                        () => _api.devolver(item.clase, item.id),
                        'Devolución registrada.',
                      );
                    }
                    if (action == 'delete') _deleteAsset(item);
                  },
                  itemBuilder: (_) => [
                    if (editable)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Editar información'),
                      ),
                    if (editable)
                      const PopupMenuItem(
                        value: 'photo',
                        child: Text('Subir o reemplazar foto'),
                      ),
                    if (editable && item.fotoUrl != null)
                      const PopupMenuItem(
                        value: 'delete_photo',
                        child: Text('Eliminar foto'),
                      ),
                    if (_canState && item.estadoAprobacion == 'APROBADA')
                      const PopupMenuItem(
                        value: 'state',
                        child: Text('Cambiar estado'),
                      ),
                    if (_canLoan &&
                        item.propietarioTipo == 'EMPRESA' &&
                        item.disponible)
                      const PopupMenuItem(
                        value: 'loan',
                        child: Text('Prestar a conjunto'),
                      ),
                    if (_canLoan && item.prestada)
                      const PopupMenuItem(
                        value: 'return',
                        child: Text('Registrar devolución'),
                      ),
                    if (_canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Eliminar del inventario',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _tag(item.estado),
                if (item.condicion != null) _tag(item.condicion!),
                _tag(item.estadoAprobacion),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    item.propietarioTipo == 'EMPRESA'
                        ? 'Propiedad empresa'
                        : 'Propiedad conjunto',
                  ),
                ),
                if (item.prestada)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      'En ${item.ubicacionActual?.nombre ?? 'conjunto'}',
                    ),
                  ),
              ],
            ),
            Text(
              'Registró: ${item.creadoPorNombre ?? item.creadoPorId ?? 'Migración'}${item.creadoEn == null ? '' : ' · ${DateFormat('dd/MM/yyyy HH:mm').format(item.creadoEn!)}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (item.aprobadoPorNombre != null)
              Text(
                'Aprobó: ${item.aprobadoPorNombre!}${item.aprobadoEn == null ? '' : ' · ${DateFormat('dd/MM/yyyy HH:mm').format(item.aprobadoEn!)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (item.estadoAprobacion == 'RECHAZADA' &&
                item.motivoRechazo?.isNotEmpty == true)
              Text(
                'Motivo: ${item.motivoRechazo!}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.red.shade700),
              ),
            if (_approver && item.estadoAprobacion == 'PENDIENTE')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _approve(item),
                      icon: const Icon(Icons.check),
                      label: const Text('Aprobar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _reject(item),
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _group(MapEntry<String, List<ActivoInventario>> entry) {
    final pending = entry.value
        .where((item) => item.estadoAprobacion == 'PENDIENTE')
        .length;
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            _clase == ClaseActivoInventario.maquinaria
                ? Icons.precision_manufacturing_outlined
                : Icons.handyman_outlined,
          ),
        ),
        title: Text(entry.key),
        subtitle: Text(
          entry.value.length.toString() +
              (entry.value.length == 1 ? ' unidad' : ' unidades') +
              (pending == 0 ? '' : ' · $pending pendientes'),
        ),
        children: entry.value.map(_unit).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _groups.entries.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.soloPendientes
              ? 'Aprobaciones de inventario'
              : widget.claseFija
              ? _clase == ClaseActivoInventario.maquinaria
                    ? 'Inventario de maquinaria'
                    : 'Inventario de herramientas'
              : widget.conjuntoId == null
              ? 'Inventario general de empresa'
              : 'Inventario del conjunto',
        ),
        actions: [
          if (_canDownloadActa)
            IconButton(
              tooltip: 'Descargar acta de entrega de inventario',
              onPressed: _generatingActa ? null : _downloadActa,
              icon: _generatingActa
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      floatingActionButton: _canCreate && !widget.soloPendientes
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Registrar'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                if (!widget.claseFija) ...[
                  SegmentedButton<ClaseActivoInventario>(
                    segments: const [
                      ButtonSegment(
                        value: ClaseActivoInventario.maquinaria,
                        icon: Icon(Icons.precision_manufacturing_outlined),
                        label: Text('Maquinaria'),
                      ),
                      ButtonSegment(
                        value: ClaseActivoInventario.herramienta,
                        icon: Icon(Icons.handyman_outlined),
                        label: Text('Herramientas'),
                      ),
                    ],
                    selected: {_clase},
                    onSelectionChanged: (values) => _changeClass(values.first),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar por tipo, código, marca o serial',
                    suffixIcon: IconButton(
                      tooltip: 'Buscar',
                      onPressed: _load,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (!widget.soloPendientes)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _approval == null,
                          onSelected: (_) {
                            setState(() => _approval = null);
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Pendientes'),
                          selected: _approval == 'PENDIENTE',
                          onSelected: (_) {
                            setState(() => _approval = 'PENDIENTE');
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Aprobados'),
                          selected: _approval == 'APROBADA',
                          onSelected: (_) {
                            setState(() => _approval = 'APROBADA');
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Rechazados'),
                          selected: _approval == 'RECHAZADA',
                          onSelected: (_) {
                            setState(() => _approval = 'RECHAZADA');
                            _load();
                          },
                        ),
                        const SizedBox(width: 12),
                        Text('$_total unidades'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(_error!),
                    ),
                  )
                : entries.isEmpty
                ? const Center(child: Text('No hay unidades para mostrar.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      itemCount:
                          entries.length + (_items.length < _total ? 1 : 0),
                      itemBuilder: (_, index) {
                        if (index < entries.length) {
                          return _group(entries[index]);
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: _loadingMore
                                  ? null
                                  : () => _load(append: true),
                              icon: _loadingMore
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.expand_more),
                              label: Text(
                                _loadingMore
                                    ? 'Cargando…'
                                    : 'Cargar más (${_items.length} de $_total)',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreateChoice {
  final int? catalogId;
  final String proposedName;
  final String brand;
  final String model;
  final String serial;
  final String alias;
  final int quantity;
  final SelectedUploadFile? photo;
  final String condicion;

  const _CreateChoice({
    required this.catalogId,
    required this.proposedName,
    required this.brand,
    required this.model,
    required this.serial,
    required this.alias,
    required this.quantity,
    required this.photo,
    required this.condicion,
  });
}

class _CreateAssetSheet extends StatefulWidget {
  final ClaseActivoInventario clase;
  final List<CatalogoActivo> catalog;

  const _CreateAssetSheet({required this.clase, required this.catalog});

  @override
  State<_CreateAssetSheet> createState() => _CreateAssetSheetState();
}

class _CreateAssetSheetState extends State<_CreateAssetSheet> {
  final _proposed = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _alias = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  late bool _newType;
  int? _catalogId;
  SelectedUploadFile? _photo;
  String _condicion = 'NUEVA';

  bool get _puedePegarImagen => kIsWeb && ClipboardImageCapture.isSupported;
  ClipboardImageDispose? _disposeClipboardListener;
  bool _esperandoPegado = false;

  bool get _esMovil =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // En web (celular/tablet abriendo la app desde el navegador) usamos un
  // <input type="file" capture="environment"> que abre la cámara trasera
  // directamente; no podemos confiar solo en `defaultTargetPlatform` porque
  // iPadOS reporta un user-agent de escritorio y se detecta como macOS.
  bool get _puedeTomarFoto => kIsWeb || _esMovil;

  @override
  void initState() {
    super.initState();
    _newType = widget.catalog.isEmpty;
    _catalogId = widget.catalog.isEmpty ? null : widget.catalog.first.id;
    if (_puedePegarImagen) {
      _disposeClipboardListener = ClipboardImageCapture.registerPasteListener(
        _onClipboardImagePasted,
      );
    }
  }

  @override
  void dispose() {
    _proposed.dispose();
    _brand.dispose();
    _model.dispose();
    _serial.dispose();
    _alias.dispose();
    _quantity.dispose();
    _disposeClipboardListener?.call();
    super.dispose();
  }

  void _activarPegado() {
    setState(() => _esperandoPegado = true);
    AppFeedback.showFromSnackBar(
      context,
      const SnackBar(
        content: Text(
          'Copia la imagen y presiona Ctrl+V dentro de esta ventana para adjuntarla.',
        ),
      ),
    );
  }

  void _onClipboardImagePasted(SelectedUploadFile file) {
    if (!mounted) return;
    setState(() {
      _photo = file;
      _esperandoPegado = false;
    });
    AppFeedback.showFromSnackBar(
      context,
      const SnackBar(content: Text('Imagen pegada desde el portapapeles.')),
    );
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return;
    if (file.size > 5 * 1024 * 1024) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('La fotografía no puede superar 5 MB.')),
      );
      return;
    }
    setState(() {
      _photo = SelectedUploadFile(
        name: file.name,
        path: file.path,
        bytes: file.bytes,
        mimeType: file.extension?.toLowerCase() == 'png'
            ? 'image/png'
            : 'image/jpeg',
      );
    });
  }

  Future<void> _tomarFoto() async {
    if (!_puedeTomarFoto) return;
    try {
      final captura = await CameraCapture.pickPhoto();
      if (captura == null) return;
      if (!mounted) return;
      setState(() => _photo = captura);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('No se pudo abrir la cámara: $e')),
      );
    }
  }

  void _submit() {
    final quantity = int.tryParse(_quantity.text) ?? 0;
    if (_newType && _proposed.text.trim().length < 2) return;
    if (!_newType && _catalogId == null) return;
    if (widget.clase == ClaseActivoInventario.herramienta &&
        (quantity < 1 || quantity > 500)) {
      return;
    }
    Navigator.pop(
      context,
      _CreateChoice(
        catalogId: _newType ? null : _catalogId,
        proposedName: _proposed.text.trim(),
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        serial: _serial.text.trim(),
        alias: _alias.text.trim(),
        quantity: widget.clase == ClaseActivoInventario.herramienta
            ? quantity
            : 1,
        photo: _photo,
        condicion: _condicion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTool = widget.clase == ClaseActivoInventario.herramienta;
    final quantity = int.tryParse(_quantity.text) ?? 1;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      isTool
                          ? 'Registrar herramientas'
                          : 'Registrar maquinaria',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Proponer un tipo nuevo'),
                subtitle: const Text(
                  'Primero busca el nombre en el catálogo para evitar duplicados.',
                ),
                value: _newType,
                onChanged: (value) => setState(() => _newType = value),
              ),
              if (_newType)
                TextField(
                  controller: _proposed,
                  decoration: const InputDecoration(
                    labelText: 'Nombre canónico del tipo',
                    hintText: 'Ej. Cortasetos',
                  ),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _catalogId,
                  decoration: const InputDecoration(
                    labelText: 'Tipo del catálogo',
                  ),
                  items: widget.catalog
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => _catalogId = value,
                ),
              if (isTool)
                TextField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad de unidades',
                    helperText: 'Cada unidad recibirá un código individual.',
                  ),
                ),
              TextField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'Marca'),
              ),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Modelo'),
              ),
              TextField(
                controller: _serial,
                enabled: quantity == 1,
                decoration: InputDecoration(
                  labelText: 'Serial',
                  helperText: quantity > 1
                      ? 'Edita luego el serial de cada unidad.'
                      : null,
                ),
              ),
              TextField(
                controller: _alias,
                decoration: const InputDecoration(labelText: 'Alias'),
              ),
              const SizedBox(height: 12),
              const Text('Condición'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'NUEVA', label: Text('Nueva')),
                  ButtonSegment(value: 'USADA', label: Text('Usada')),
                ],
                selected: {_condicion},
                onSelectionChanged: (value) {
                  setState(() => _condicion = value.first);
                },
              ),
              const SizedBox(height: 12),
              if (_puedePegarImagen && _esperandoPegado) ...[
                Container(
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
                    'Modo pegado activo: copia la imagen y presiona Ctrl+V mientras este panel siga abierto.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: quantity == 1 ? _pickPhoto : null,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                      _photo?.name ?? 'Adjuntar desde el dispositivo',
                    ),
                  ),
                  if (_puedeTomarFoto)
                    OutlinedButton.icon(
                      onPressed: quantity == 1 ? _tomarFoto : null,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Tomar foto'),
                    ),
                  if (_puedePegarImagen)
                    OutlinedButton.icon(
                      onPressed: quantity == 1 ? _activarPegado : null,
                      icon: const Icon(Icons.content_paste_rounded),
                      label: Text(
                        _esperandoPegado ? 'Esperando Ctrl+V' : 'Pegar imagen',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
