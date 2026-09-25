import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/notificacion_api.dart';
import 'package:flutter_application_1/model/notificacion_model.dart';
import 'package:flutter_application_1/service/session_service.dart';

class NotificacionesCenter with WidgetsBindingObserver {
  NotificacionesCenter._();
  static final NotificacionesCenter instance = NotificacionesCenter._();

  final NotificacionApi _api = NotificacionApi();
  final SessionService _session = SessionService();

  final ValueNotifier<int> totalNoLeidas = ValueNotifier<int>(0);
  final ValueNotifier<List<NotificacionModel>> items =
      ValueNotifier<List<NotificacionModel>>([]);

  /// Se actualiza cada vez que llega una notificación nueva de tipo
  /// INSUMO_STOCK_BAJO (no en el primer refresh de la sesión), para que un
  /// listener global la muestre como aviso flotante.
  final ValueNotifier<NotificacionModel?> stockBajoNueva =
      ValueNotifier<NotificacionModel?>(null);

  /// Última notificación nueva sobre un pedido (p. ej. `pedido_pagado`). La
  /// pantalla de detalle del pedido la escucha para recargarse sin polling
  /// propio.
  final ValueNotifier<NotificacionModel?> pedidoActualizado =
      ValueNotifier<NotificacionModel?>(null);

  Timer? _timer;
  bool _cargando = false;
  bool _observando = false;
  String? _usuarioActivo;
  Duration _interval = const Duration(seconds: 60);
  Set<int> _idsVistos = {};
  bool _primerRefresh = true;

  Future<void> start({Duration interval = const Duration(seconds: 60)}) async {
    final token = (await _session.getToken())?.trim();
    if (token == null || token.isEmpty) {
      stop();
      return;
    }

    final usuario = (await _session.getUserId())?.trim();
    if (usuario == null || usuario.isEmpty) return;

    if (_usuarioActivo != usuario) {
      _usuarioActivo = usuario;
      totalNoLeidas.value = 0;
      items.value = const [];
      _idsVistos = {};
      _primerRefresh = true;
    }

    _interval = interval;

    if (!_observando) {
      WidgetsBinding.instance.addObserver(this);
      _observando = true;
    }

    if (_timer != null) return;

    unawaited(refresh());
    _timer = Timer.periodic(_interval, (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pausa el polling con la app en segundo plano; al volver, refresca de
    // una vez y retoma el timer. Evita pegarle al backend sin que nadie mire.
    if (state == AppLifecycleState.resumed) {
      if (_usuarioActivo != null && _timer == null) {
        unawaited(refresh());
        _timer = Timer.periodic(_interval, (_) => refresh());
      }
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> refresh() async {
    if (_cargando) return;

    final token = (await _session.getToken())?.trim();
    if (token == null || token.isEmpty) {
      stop();
      return;
    }

    _cargando = true;

    try {
      final resultados = await Future.wait([
        _api.listar(limit: 50),
        _api.contarNoLeidas(),
      ]);
      final nuevaLista = resultados[0] as List<NotificacionModel>;

      if (_primerRefresh) {
        // No flotamos el historial que ya existía al abrir la app.
        _idsVistos = nuevaLista.map((n) => n.id).toSet();
        _primerRefresh = false;
      } else {
        for (final n in nuevaLista) {
          if (_idsVistos.contains(n.id)) continue;
          _idsVistos.add(n.id);
          if (n.tipo == 'INSUMO_STOCK_BAJO') {
            stockBajoNueva.value = n;
          } else if (n.tipo.startsWith('pedido_') &&
              n.referenciaTipo == 'PedidoApp') {
            pedidoActualizado.value = n;
          }
        }
      }

      items.value = nuevaLista;
      totalNoLeidas.value = resultados[1] as int;
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
    if (_observando) {
      WidgetsBinding.instance.removeObserver(this);
      _observando = false;
    }
    _usuarioActivo = null;
    totalNoLeidas.value = 0;
    items.value = const [];
    _idsVistos = {};
    _primerRefresh = true;
  }
}
