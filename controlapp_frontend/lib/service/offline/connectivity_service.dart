import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_constants.dart';
import '../http/cliente_http_app.dart';

/// Detecta cuándo el dispositivo recupera una conexión *real* a internet.
///
/// `connectivity_plus` solo informa si hay una interfaz de red activa
/// (wifi/datos), no si esa red llega efectivamente al backend. Por eso toda
/// señal de conectividad se confirma con una llamada corta a `/ping`
/// (ya existente en el backend) antes de disparar una sincronización.
///
/// En la app nativa además cada petición informa si hubo respuesta o falla
/// de red ([enLinea]): con eso la pantalla deshabilita lo que solo funciona
/// con señal ("Iniciar") sin esperar a que falle.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  final _restauradaController = StreamController<void>.broadcast();

  /// false desde que una petición falla por red o el teléfono queda sin
  /// interfaz de red; true con la primera respuesta del servidor.
  final ValueNotifier<bool> enLinea = ValueNotifier<bool>(true);

  /// Emite cada vez que se detecta que volvió la conexión real a internet.
  Stream<void> get onConexionRestaurada => _restauradaController.stream;

  void iniciar() {
    ClienteHttpApp.alEstadoRedGlobal ??= _reportarEstado;
    _sub ??= Connectivity().onConnectivityChanged.listen((results) async {
      final hayInterfaz = results.any((r) => r != ConnectivityResult.none);
      if (!hayInterfaz) {
        enLinea.value = false;
        return;
      }
      if (await hayInternetReal()) {
        _reportarEstado(true);
      }
    });
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
  }

  void _reportarEstado(bool hayRespuesta) {
    final antes = enLinea.value;
    enLinea.value = hayRespuesta;
    if (hayRespuesta && !antes) _restauradaController.add(null);
  }

  Future<bool> hayInternetReal({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.baseUrl}/ping');
      final resp = await http.get(uri).timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
