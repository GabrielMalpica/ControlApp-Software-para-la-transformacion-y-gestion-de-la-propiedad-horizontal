import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'cliente_http_app.dart';

/// Tiempo máximo para abrir la conexión: con "señal" pero sin datos el
/// teléfono se quedaría esperando minutos.
const Duration tiempoMaximoConexion = Duration(seconds: 20);

/// Corre [cuerpo] con [ClienteHttpApp] como cliente de todas las peticiones
/// (`http.get`, `http.MultipartRequest.send`, `http.Client()`…) que se hagan
/// dentro, incluido el código asíncrono que arranque.
R ejecutarConClienteApp<R>(R Function() cuerpo) {
  return http.runWithClient(cuerpo, () {
    final base = HttpClient()..connectionTimeout = tiempoMaximoConexion;
    return ClienteHttpApp(IOClient(base));
  });
}
