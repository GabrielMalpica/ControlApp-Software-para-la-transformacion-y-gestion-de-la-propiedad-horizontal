import 'dart:async';

import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/api/operario_api.dart';
import 'package:flutter_application_1/model/cierre_tarea_pendiente_model.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/offline/cierre_tarea_offline_store.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';

/// Sesión del operario necesaria para su agenda.
class SesionOperario {
  final String usuarioId;
  final int operarioId;
  final String rol;
  final String nombre;

  const SesionOperario({
    required this.usuarioId,
    required this.operarioId,
    required this.rol,
    required this.nombre,
  });

  String get primerNombre {
    final n = nombre.trim();
    if (n.isEmpty) return '';
    return n.split(RegExp(r'\s+')).first;
  }
}

class ActividadesCargadas {
  final List<TareaModel> tareas;

  /// Si no hubo conexión: fecha de la copia guardada que se está mostrando.
  final DateTime? copiaDel;

  const ActividadesCargadas(this.tareas, this.copiaDel);
}

/// Carga la agenda del operario (con copia local para trabajar sin señal)
/// y los cierres que siguen guardados en el teléfono.
class MisActividadesRepo {
  MisActividadesRepo({OperarioApi? api, InventarioApi? inventarioApi})
    : _api = api ?? OperarioApi(),
      _inventarioApi = inventarioApi ?? InventarioApi();

  final OperarioApi _api;
  final InventarioApi _inventarioApi;
  final SessionService _session = SessionService();

  static String _claveCache(String usuarioId) => 'mis_actividades:$usuarioId';

  Future<SesionOperario?> sesion() async {
    final results = await Future.wait<String?>([
      _session.getUserId(),
      _session.getRol(),
      _session.getNombre(),
    ]);
    final uid = results[0]?.trim() ?? '';
    final opId = int.tryParse(uid);
    if (uid.isEmpty || opId == null) return null;
    return SesionOperario(
      usuarioId: uid,
      operarioId: opId,
      rol: (results[1] ?? '').trim().toLowerCase(),
      nombre: (results[2] ?? '').trim(),
    );
  }

  /// Rango por defecto: dos semanas atrás (para lo que quedó sin cerrar) y
  /// dos adelante (para "otros días").
  static ({DateTime desde, DateTime hasta}) rangoPorDefecto(DateTime ahora) {
    final hoy = soloFecha(ahora);
    return (
      desde: hoy.subtract(const Duration(days: 14)),
      hasta: hoy.add(const Duration(days: 16)),
    );
  }

  Future<ActividadesCargadas> cargar(
    SesionOperario s, {
    DateTime? desde,
    DateTime? hasta,
    bool guardarCopia = true,
  }) async {
    final store = CierreTareaOfflineStore.instance;
    final clave = _claveCache(s.usuarioId);
    LecturaCacheada? copia;
    try {
      copia = await store.obtenerLecturaCacheada(clave);
    } catch (_) {
      copia = null;
    }
    try {
      // Con la copia guardada se manda su ETag: si la agenda no cambió, el
      // servidor responde 304 sin mandar nada (rápido con datos móviles).
      final r = await _api.listarTareasOperarioCondicional(
        operarioId: s.operarioId,
        desde: desde,
        hasta: hasta,
        etag: guardarCopia ? copia?.etag : null,
      );
      if (r.noModificado && copia != null) {
        unawaited(store.marcarLecturaVigente(clave));
        return ActividadesCargadas(
          copia.datos.map(TareaModel.fromJson).toList(),
          null,
        );
      }
      final normalizada = _conOperarioActual(r.datos ?? const [], s);
      if (guardarCopia) {
        // Sin await: guardar la copia no debe demorar la pantalla.
        unawaited(
          store.cachearLectura(
            clave,
            normalizada.map((t) => t.toJson()).toList(),
            etag: r.etag,
          ),
        );
      }
      return ActividadesCargadas(normalizada, null);
    } catch (e) {
      // Un 401/403/426 no es "sin señal": la sesión o la app se encargan.
      if (copia == null) rethrow;
      return ActividadesCargadas(
        copia.datos.map(TareaModel.fromJson).toList(),
        copia.actualizadoEn,
      );
    }
  }

  /// Ids de las actividades con un cierre guardado en el teléfono que aún no
  /// se ha enviado.
  Future<Set<int>> cierresSinEnviar(String usuarioId) async {
    final lista = await CierreTareaOfflineStore.instance.listarCierres(
      usuarioId: usuarioId,
    );
    return {
      for (final c in lista)
        if (c.estadoSync != CierreSyncEstado.sincronizado) c.tareaId,
    };
  }

  Future<int> cierresConError(String usuarioId) async {
    final lista = await CierreTareaOfflineStore.instance.listarCierres(
      usuarioId: usuarioId,
    );
    return lista.where((c) => c.estadoSync == CierreSyncEstado.error).length;
  }

  /// Inventario del conjunto para registrar insumos; sin señal usa la última
  /// copia (el servidor revalida el stock al sincronizar).
  Future<List<InventarioItemResponse>> inventario(String conjuntoNit) async {
    final store = CierreTareaOfflineStore.instance;
    final clave = CierreTareaOfflineStore.claveInventarioConjunto(conjuntoNit);
    LecturaCacheada? copia;
    try {
      copia = await store.obtenerLecturaCacheada(clave);
    } catch (_) {
      copia = null;
    }
    try {
      final r = await _inventarioApi.listarInventarioConjuntoCondicional(
        conjuntoNit,
        etag: copia?.etag,
      );
      if (r.noModificado && copia != null) {
        unawaited(store.marcarLecturaVigente(clave));
        return copia.datos.map(InventarioItemResponse.fromJson).toList();
      }
      final inv = r.datos ?? const <InventarioItemResponse>[];
      unawaited(
        store.cachearLectura(
          clave,
          inv.map((i) => i.toJson()).toList(),
          etag: r.etag,
        ),
      );
      return inv;
    } catch (_) {
      if (copia == null) return const [];
      return copia.datos.map(InventarioItemResponse.fromJson).toList();
    }
  }

  Future<void> iniciar(SesionOperario s, int tareaId) =>
      _api.iniciarTarea(operarioId: s.operarioId, tareaId: tareaId);

  /// El endpoint ya filtra por operario; si una respuesta antigua no trae
  /// los ids, se agrega el del operario para que las reglas de cierre
  /// ("solo lo asignado") funcionen.
  List<TareaModel> _conOperarioActual(
    List<TareaModel> lista,
    SesionOperario s,
  ) {
    return [
      for (final t in lista)
        t.operariosIds.contains(s.usuarioId)
            ? t
            : t.copyWith(
                operariosIds: [...t.operariosIds, s.usuarioId],
                operariosNombres:
                    t.operariosNombres.length == t.operariosIds.length
                    ? [...t.operariosNombres, s.nombre]
                    : t.operariosNombres,
              ),
    ];
  }
}
