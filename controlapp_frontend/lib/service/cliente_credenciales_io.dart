import 'package:http/http.dart' as http;

/// Fuera del navegador no hay cookies de sesion: un cliente normal.
http.Client crearClienteConCredenciales() => http.Client();
