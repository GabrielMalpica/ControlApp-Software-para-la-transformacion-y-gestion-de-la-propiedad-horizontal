import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:http/http.dart' as http;

import '../service/app_constants.dart';
import '../api/tarea_api.dart';
import '../model/cierre_tarea_pendiente_model.dart';
import '../model/inventario_item_model.dart';
import '../model/tarea_model.dart';
import '../service/offline/cierre_tarea_offline_store.dart';
import '../service/offline/tarea_sync_engine.dart';
import '../service/session_service.dart';
import '../service/tarea_cierre_service.dart';
import '../service/theme.dart';
import '../service/permission_service.dart';
import 'package:flutter_application_1/service/app_error.dart';
import '../widgets/cerrar_tarea_sheet.dart';
import '../widgets/cierres_pendientes_sheet.dart';
import '../widgets/corregir_cierre_sheet.dart';
import 'crear_tarea_page.dart';
import 'editar_tarea_page.dart';

import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

class TareasPage extends StatefulWidget {
  final String nit;

  const TareasPage({super.key, required this.nit});

  @override
  State<TareasPage> createState() => _TareasPageState();
}

class _TareasPageState extends State<TareasPage> {
  final TareaApi _tareaApi = TareaApi();
  final InventarioApi _inventarioApi = InventarioApi();
  final SessionService _session = SessionService();
  final TareaCierreService _tareaCierreService = TareaCierreService();

  bool _cargando = true;
  String? _error;
  List<TareaModel> _tareas = [];
  DateTime? _tareasDesdeCache;

  // sesión
  String? _rol;
  String? _usuarioId;
  int? _operarioId;

  // cola offline de cierres del operario
  List<CierreTareaPendiente> _cierresPendientes = [];
  StreamSubscription<void>? _syncSub;

  bool get _canViewTasks => PermissionService.instance.can('tareas.ver');
  bool get _canManageTasks => PermissionService.instance.can('tareas.crear');

  // filtros para vista operario
  String _filtroOperario = 'HOY';
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _init();
    _syncSub = TareaSyncEngine.instance.onCambios.listen((_) {
      _cargarCierresPendientes();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _cargarSesion();
    await _cargarTareas();
    if (_esOperario()) {
      await _cargarCierresPendientes();
      unawaited(TareaSyncEngine.instance.sincronizarAhora());
    }
  }

  Future<void> _cargarCierresPendientes() async {
    final uid = _usuarioId;
    if (uid == null || uid.isEmpty) return;
    final lista = await CierreTareaOfflineStore.instance.listarCierres(
      usuarioId: uid,
    );
    if (!mounted) return;
    setState(() => _cierresPendientes = lista);
  }

  bool _tieneCierrePendiente(int tareaId) {
    return _cierresPendientes.any(
      (c) => c.tareaId == tareaId && c.estadoSync != CierreSyncEstado.sincronizado,
    );
  }

  Future<void> _cargarSesion() async {
    final rol = await _session.getRol();
    final userId = await _session.getUserId();

    if (!mounted) return;
    setState(() {
      _rol = rol;
      _usuarioId = userId?.trim();
      _operarioId = int.tryParse(_usuarioId ?? '');
    });
  }

  bool _esOperario() => (_rol ?? '').toLowerCase() == 'operario';

  Future<void> _cargarTareas() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      List<TareaModel> lista;

      if (_esOperario()) {
        if (_operarioId == null) {
          throw Exception('No se pudo identificar el operario en sesión.');
        }
        lista = await _listarTareasOperarioDirecto(_operarioId!);
        final uid = _usuarioId;
        if (uid != null && uid.isNotEmpty) {
          unawaited(
            CierreTareaOfflineStore.instance.cachearLectura(
              CierreTareaOfflineStore.claveTareasOperario(uid),
              lista.map((t) => t.toJson()).toList(),
            ),
          );
        }
      } else {
        lista = await _tareaApi.listarTareasPorConjunto(widget.nit);
      }

      if (!mounted) return;
      setState(() {
        _tareas = lista;
        _tareasDesdeCache = null;
      });
    } catch (e) {
      // Sin conexión: si es el operario, intenta mostrar la última lista
      // de sus actividades que se guardó localmente en vez de dejarlo sin
      // poder ver (y por lo tanto cerrar) ninguna tarea.
      final uid = _usuarioId;
      if (_esOperario() && uid != null && uid.isNotEmpty) {
        final cache = await CierreTareaOfflineStore.instance
            .obtenerLecturaCacheada(
              CierreTareaOfflineStore.claveTareasOperario(uid),
            );
        if (cache != null) {
          if (!mounted) return;
          setState(() {
            _tareas = cache.datos.map(TareaModel.fromJson).toList();
            _tareasDesdeCache = cache.actualizadoEn;
            _error = null;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  Future<List<TareaModel>> _listarTareasOperarioDirecto(int operarioId) async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido (no hay sesión guardada)');
    }

    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas',
    );

    final resp = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al listar actividades del operario: ${resp.statusCode} - ${resp.body}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];

    final operarioIdStr = operarioId.toString();

    return decoded
        .map((e) => TareaModel.fromJson((e as Map).cast<String, dynamic>()))
        .where((t) => !t.borrador)
        // El endpoint de "mis actividades" ya filtra por operario pero no
        // siempre trae operariosIds en el payload; sin ese dato la
        // validación de "tarea asignada a mí" (TareaCierreService) falla
        // siempre y el operario nunca puede cerrar sus propias tareas.
        .map(
          (t) => t.operariosIds.contains(operarioIdStr)
              ? t
              : t.copyWith(operariosIds: [...t.operariosIds, operarioIdStr]),
        )
        .toList();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _esVencida(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    if (e == 'APROBADA' || e == 'COMPLETADA') return false;
    return t.fechaFin.isBefore(DateTime.now());
  }

  bool _esPendiente(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    return e == 'ASIGNADA' || e == 'EN_PROCESO';
  }

  List<TareaModel> get _tareasFiltradasOperario {
    final hoy = _dayOnly(DateTime.now());

    final out = _tareas.where((t) {
      if (!_coincideBusqueda(t)) return false;
      switch (_filtroOperario) {
        case 'HOY':
          return _dayOnly(t.fechaInicio) == hoy || _dayOnly(t.fechaFin) == hoy;
        case 'PENDIENTES':
          return _esPendiente(t);
        case 'VENCIDAS':
          return _esVencida(t);
        case 'RECHAZADAS':
          return (t.estado ?? '').toUpperCase() == 'RECHAZADA';
        case 'PENDIENTE_APROBACION':
          return (t.estado ?? '').toUpperCase() == 'PENDIENTE_APROBACION';
        case 'TODAS':
        default:
          return true;
      }
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    return out;
  }

  bool _coincideBusqueda(TareaModel t) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;

    return t.id.toString().contains(q) ||
        t.descripcion.toLowerCase().contains(q) ||
        (t.ubicacionNombre ?? '').toLowerCase().contains(q) ||
        (t.elementoNombre ?? '').toLowerCase().contains(q);
  }

  Map<DateTime, List<TareaModel>> _agruparPorDia(List<TareaModel> items) {
    final map = <DateTime, List<TareaModel>>{};
    for (final t in items) {
      final key = _dayOnly(t.fechaInicio);
      map.putIfAbsent(key, () => []).add(t);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {for (final e in entries) e.key: e.value};
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  String _fmtDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '${_fmtDate(d)} $hh:$mi';
  }

  Color _estadoColor(String? estado) {
    switch ((estado ?? '').toUpperCase()) {
      case 'ASIGNADA':
        return Colors.orange;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'PENDIENTE_APROBACION':
        return Colors.deepPurple;
      case 'COMPLETADA':
      case 'APROBADA':
        return Colors.green;
      case 'RECHAZADA':
      case 'NO_COMPLETADA':
      case 'CANCELADA':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool _puedeCerrar(TareaModel t) {
    if (!PermissionService.instance.can('tareas.cerrar')) return false;
    if (_esOperario() && _tieneCierrePendiente(t.id)) return false;
    return _tareaCierreService.puedeCerrar(
      rol: _rol,
      usuarioId: _usuarioId,
      tarea: t,
    );
  }

  Future<List<InventarioItemResponse>> _inventarioParaCierre(
    String inventarioNit,
  ) async {
    try {
      final inventario = await _inventarioApi.listarInventarioConjunto(
        inventarioNit,
      );
      unawaited(
        CierreTareaOfflineStore.instance.cachearLectura(
          CierreTareaOfflineStore.claveInventarioConjunto(inventarioNit),
          inventario.map((i) => i.toJson()).toList(),
        ),
      );
      return inventario;
    } catch (_) {
      // Sin conexión: usa el último inventario conocido para que el
      // operario pueda seguir registrando insumos. El stock puede estar
      // desactualizado; el backend valida el stock real al sincronizar.
      final cache = await CierreTareaOfflineStore.instance
          .obtenerLecturaCacheada(
            CierreTareaOfflineStore.claveInventarioConjunto(inventarioNit),
          );
      if (cache == null) return [];
      return cache.datos.map(InventarioItemResponse.fromJson).toList();
    }
  }

  Future<void> _cerrarComoOperario(TareaModel t) async {
    final motivo = _tareaCierreService.motivoNoPuedeCerrar(
      rol: _rol,
      usuarioId: _usuarioId,
      tarea: t,
    );
    if (motivo != null) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('No se pudo resolver el operario de sesión.')),
      );
      return;
    }

    final inventarioNit = (t.conjuntoId != null && t.conjuntoId!.isNotEmpty)
        ? t.conjuntoId!
        : widget.nit;

    final inventario = await _inventarioParaCierre(inventarioNit);

    if (!mounted) return;
    final result = await showModalBottomSheet<CerrarTareaResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CerrarTareaSheet(tarea: t, inventario: inventario),
    );

    if (result == null) return;

    try {
      final resultado = await _tareaCierreService.cerrarTarea(
        rol: _rol,
        usuarioId: _usuarioId,
        tarea: t,
        accion: result.accion,
        observaciones: result.observaciones,
        insumosUsados: result.insumosUsados,
        evidencias: result.evidencias, // ✅ correcto
      );

      if (!mounted) return;
      final mensaje = resultado == CierreTareaResultado.guardadoLocalPendiente
          ? '📶 Sin conexión: la tarea se guardó en este dispositivo y se enviará sola cuando vuelva la señal.'
          : (result.accion == 'NO_COMPLETADA'
                ? '✅ Tarea marcada como no completada.'
                : '✅ Tarea cerrada. Quedó pendiente aprobación.');
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text(mensaje)));
      await _cargarCierresPendientes();
      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('❌ Error cerrando tarea: $e')),
      );
    }
  }

  Widget _infoRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color ?? Colors.black54),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: color != null ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskTile(TareaModel t) {
    final c = _estadoColor(t.estado);
    final estado = (t.estado ?? 'SIN_ESTADO').replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.10)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        title: Text(
          t.descripcion,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(
              Icons.access_time,
              '${_fmtDateTime(t.fechaInicio)} → ${_fmtDateTime(t.fechaFin)}',
            ),
            if (t.ubicacionNombre != null || t.elementoNombre != null)
              _infoRow(
                Icons.place_outlined,
                '${t.ubicacionNombre ?? '-'} / ${t.elementoNombre ?? '-'}',
              ),
            if (_esVencida(t))
              _infoRow(
                Icons.warning_amber_rounded,
                'Vencida',
                color: Colors.red,
              ),
            if (_esOperario() && _tieneCierrePendiente(t.id))
              _infoRow(
                Icons.cloud_off,
                'Cierre pendiente de sincronizar',
                color: Colors.orange.shade800,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 9, color: c),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      estado,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: _esOperario()
            ? (_puedeCerrar(t)
                  ? IconButton(
                      tooltip: 'Cerrar tarea',
                      icon: const Icon(Icons.task_alt, color: Colors.green),
                      onPressed: () => _cerrarComoOperario(t),
                    )
                  : const Icon(Icons.chevron_right, color: Colors.black38))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (puedeCorregirCierre(t))
                    IconButton(
                      tooltip: 'Corregir cierre',
                      icon: const Icon(Icons.edit_note),
                      onPressed: () async {
                        final corregido = await abrirCorregirCierre(
                          context,
                          tareaId: t.id,
                        );
                        if (corregido) _cargarTareas();
                      },
                    ),
                  if (_canManageTasks)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _eliminarTarea(t),
                    ),
                ],
              ),
        onTap: _esOperario()
            ? () => _abrirDetalleTarea(t)
            : (_canManageTasks
                  ? () async {
                      final updated = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              EditarTareaPage(nit: widget.nit, tarea: t),
                        ),
                      );
                      if (updated == true) _cargarTareas();
                    }
                  : null),
      ),
    );
  }

  Future<void> _abrirDetalleTarea(TareaModel t) async {
    final c = _estadoColor(t.estado);
    final estado = (t.estado ?? 'SIN_ESTADO').replaceAll('_', ' ');
    final puedeCerrar = _puedeCerrar(t);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Text(
                    t.descripcion,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: c),
                      const SizedBox(width: 6),
                      Text(
                        estado,
                        style: TextStyle(color: c, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  _detalleRow(
                    Icons.play_circle_outline,
                    'Inicio',
                    _fmtDateTime(t.fechaInicio),
                  ),
                  _detalleRow(
                    Icons.flag_outlined,
                    'Fin',
                    _fmtDateTime(t.fechaFin),
                  ),
                  if (t.ubicacionNombre != null)
                    _detalleRow(
                      Icons.location_on_outlined,
                      'Ubicación',
                      t.ubicacionNombre!,
                    ),
                  if (t.elementoNombre != null)
                    _detalleRow(
                      Icons.category_outlined,
                      'Elemento',
                      t.elementoNombre!,
                    ),
                  if (t.tipo != null && t.tipo!.trim().isNotEmpty)
                    _detalleRow(Icons.label_outline, 'Tipo', t.tipo!),
                  if (t.observaciones != null &&
                      t.observaciones!.trim().isNotEmpty)
                    _detalleRow(
                      Icons.notes_outlined,
                      'Observaciones',
                      t.observaciones!,
                    ),
                  if (t.observacionesRechazo != null &&
                      t.observacionesRechazo!.trim().isNotEmpty)
                    _detalleRow(
                      Icons.report_gmailerrorred_outlined,
                      'Motivo de rechazo',
                      t.observacionesRechazo!,
                      color: Colors.red,
                    ),
                  if (_esVencida(t))
                    _detalleRow(
                      Icons.warning_amber_rounded,
                      'Estado de tiempo',
                      'Vencida',
                      color: Colors.red,
                    ),
                  const SizedBox(height: 20),
                  if (puedeCerrar)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _cerrarComoOperario(t);
                        },
                        icon: const Icon(Icons.task_alt),
                        label: const Text('Cerrar tarea'),
                      ),
                    )
                  else
                    Text(
                      _esOperario() && _tieneCierrePendiente(t.id)
                          ? 'Ya registraste el cierre de esta tarea y quedó guardado en este dispositivo. Se enviará solo cuando haya conexión.'
                          : (_tareaCierreService.motivoNoPuedeCerrar(
                                  rol: _rol,
                                  usuarioId: _usuarioId,
                                  tarea: t,
                                ) ??
                                'Esta tarea no está disponible para cierre.'),
                      style: const TextStyle(color: Colors.black54),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detalleRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarTarea(TareaModel tarea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Seguro que deseas eliminar "${tarea.descripcion}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _tareaApi.eliminarTarea(tarea.id);
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Tarea eliminada correctamente')),
      );
      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Error al eliminar tarea: $e')),
      );
    }
  }

  Widget _filters() {
    const opts = [
      'HOY',
      'PENDIENTES',
      'VENCIDAS',
      'RECHAZADAS',
      'PENDIENTE_APROBACION',
      'TODAS',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final f in opts)
              ChoiceChip(
                label: Text(f.replaceAll('_', ' ')),
                selected: _filtroOperario == f,
                onSelected: (_) => setState(() => _filtroOperario = f),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchBox() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: 'Buscar por ID o nombre de tarea',
            border: const OutlineInputBorder(),
            suffixIcon: _busqueda.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(() => _busqueda = ''),
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onChanged: (value) => setState(() => _busqueda = value),
        ),
      ),
    );
  }

  List<Widget> _bannersOfflineOperario() {
    final banners = <Widget>[];

    if (_tareasDesdeCache != null) {
      banners.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blueGrey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, size: 18, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sin conexión: mostrando tus actividades guardadas de '
                  '${_fmtDateTime(_tareasDesdeCache!)}.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pendientes = _cierresPendientes
        .where((c) => c.estadoSync != CierreSyncEstado.sincronizado)
        .toList();
    if (pendientes.isNotEmpty) {
      final conError = pendientes
          .where((c) => c.estadoSync == CierreSyncEstado.error)
          .length;
      banners.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (conError > 0 ? Colors.red : Colors.orange).withValues(
              alpha: 0.08,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                conError > 0 ? Icons.error_outline : Icons.cloud_upload,
                size: 18,
                color: conError > 0 ? Colors.red : Colors.orange.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conError > 0
                      ? '${pendientes.length} cierre(s) guardado(s) sin enviar, $conError con error.'
                      : '${pendientes.length} cierre(s) guardado(s) esperando conexión para enviarse.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: _abrirCierresPendientes,
                child: const Text('Ver'),
              ),
            ],
          ),
        ),
      );
    }

    return banners;
  }

  Future<void> _abrirCierresPendientes() async {
    if (_usuarioId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CierresPendientesSheet(usuarioId: _usuarioId!),
    );
    await _cargarCierresPendientes();
  }

  Widget _buildOperarioBody() {
    final list = _tareasFiltradasOperario;
    final banners = _bannersOfflineOperario();

    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          ...banners,
          _filters(),
          const SizedBox(height: 10),
          _searchBox(),
          const SizedBox(height: 16),
          const Text('No hay actividades para este filtro.'),
        ],
      );
    }

    final grouped = _agruparPorDia(list);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        ...banners,
        _filters(),
        const SizedBox(height: 10),
        _searchBox(),
        const SizedBox(height: 10),
        const Text(
          'TODO por día',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 10),
        ...grouped.entries.map((e) {
          final day = e.key;
          final tasks = e.value;

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text('${_fmtDate(day)} • ${tasks.length} actividad(es)'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(children: tasks.map(_taskTile).toList()),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGeneralBody() {
    final tareas = _tareas.where(_coincideBusqueda).toList();

    if (tareas.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _searchBox(),
          const SizedBox(height: 16),
          Text(
            _busqueda.trim().isEmpty
                ? 'No hay tareas asignadas para este conjunto.'
                : 'No hay coincidencias para la búsqueda actual.',
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: tareas.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i == 0) return _searchBox();
        return _taskTile(tareas[i - 1]);
      },
    );
  }

  Widget _body() {
    if (_cargando) return const SkeletonList();

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text(
                'Error al cargar actividades:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarTareas,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarTareas,
      child: _esOperario() ? _buildOperarioBody() : _buildGeneralBody(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canViewTasks) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tareas')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tu rol no tiene acceso a esta pantalla. Pidele al gerente que habilite el permiso de tareas.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          _esOperario() ? 'Mis actividades' : 'Tareas - Conjunto ${widget.nit}',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargarTareas, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _body(),
      floatingActionButton: _canManageTasks
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CrearTareaPage(nit: widget.nit),
                  ),
                );
                if (created == true) await _cargarTareas();
              },
              icon: const Icon(Icons.add_task),
              label: const Text('Crear tarea'),
            )
          : null,
    );
  }
}
