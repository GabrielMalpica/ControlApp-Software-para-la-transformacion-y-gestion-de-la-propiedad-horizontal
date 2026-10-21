import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// En web, la cookie HttpOnly de renovacion de sesion solo viaja (y solo se
/// guarda al iniciar sesion) si la peticion se hace con credenciales.
http.Client crearClienteConCredenciales() =>
    BrowserClient()..withCredentials = true;
