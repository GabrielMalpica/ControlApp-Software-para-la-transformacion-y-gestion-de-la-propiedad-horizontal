import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/notificacion_api.dart';
import 'package:flutter_application_1/model/notificacion_model.dart';
import 'package:flutter_application_1/service/session_service.dart';

class NotificacionesCenter {
  NotificacionesCenter._();
  static final NotificacionesCenter instance = NotificacionesCenter._();

  final NotificacionApi _api = NotificacionApi();
  final SessionService _session = SessionService();

  final ValueNotifier<int> totalNoLeidas = ValueNotifier<int>(0);
  final ValueNotifier<List<NotificacionModel>> items =
      ValueNotifier<List<NotificacionModel>>([]);

  Timer? _timer;
  bool _cargando = false;
  String? _usuarioActivo;

  Future<void> start({
    Duration interval = const Duration(seconds: 20),
  }) async {
    final usuario = (await _session.getUserId())?.trim();
    if (usuario == null || usuario.isEmpty) return;

    if (_usuarioActivo != usuario) {
      _usuarioActivo = usuario;
      totalNoLeidas.value = 0;
      items.value = const [];
    }

    if (_timer != null) return;

    await refresh();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  Future<void> refresh() async {
    if (_cargando) return;
    _cargando = true;

    try {
      final lista = await _api.listar(limit: 50);
      final noLeidas = await _api.contarNoLeidas();

      items.value = lista;
      totalNoLeidas.value = noLeidas;
    } catch (_) {
      // Silencioso para no interrumpir UX en caso de red.
    } finally {
      _cargando = false;
    }
  }

  Future<void> marcarLeida(int id) async {
    await _api.marcarLeida(id);
    await refresh();
  }

  Future<void> marcarTodasLeidas() async {
    await _api.marcarTodasLeidas();
    await refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _usuarioActivo = null;
    totalNoLeidas.value = 0;
    items.value = const [];
  }
}
