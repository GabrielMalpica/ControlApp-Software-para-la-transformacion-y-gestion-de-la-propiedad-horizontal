import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../app_constants.dart';

/// Detecta cuándo el dispositivo recupera una conexión *real* a internet.
///
/// `connectivity_plus` solo informa si hay una interfaz de red activa
/// (wifi/datos), no si esa red llega efectivamente al backend. Por eso toda
/// señal de conectividad se confirma con una llamada corta a `/ping`
/// (ya existente en el backend) antes de disparar una sincronización.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  final _restauradaController = StreamController<void>.broadcast();

  /// Emite cada vez que se detecta que volvió la conexión real a internet.
  Stream<void> get onConexionRestaurada => _restauradaController.stream;

  void iniciar() {
    _sub ??= Connectivity().onConnectivityChanged.listen((results) async {
      final hayInterfaz = results.any((r) => r != ConnectivityResult.none);
      if (!hayInterfaz) return;
      if (await hayInternetReal()) {
        _restauradaController.add(null);
      }
    });
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
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
