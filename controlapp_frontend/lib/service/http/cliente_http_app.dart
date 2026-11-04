import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../reloj_confiable.dart';
import '../session_service.dart';

/// Cliente HTTP de la app nativa. Se instala con `http.runWithClient` (ver
/// `ejecutarConClienteApp`), así que lo usan TODAS las peticiones de la app,
/// también las de las APIs que llaman `http.get` directamente:
///
/// - agrega `X-App-Version` (versionCode) y `X-App-Plataforma: android`;
/// - ante un 401 de una petición autenticada renueva la sesión una vez
///   (`/auth/refresh-app`) y la repite con el token nuevo (solo peticiones
///   que se pueden repetir; los multipart de cierre lo hacen en `OperarioApi`);
/// - guarda la hora del servidor (cabecera `Date`) para `RelojConfiable`;
/// - avisa un 426 `APP_DESACTUALIZADA` para obligar a actualizar;
/// - informa si hubo respuesta o falla de red (indicador "sin señal").
class ClienteHttpApp extends http.BaseClient {
  ClienteHttpApp(
    this._inner, {
    Future<ResultadoRenovacion> Function()? renovar,
    Future<String?> Function()? tokenActual,
    Future<Map<String, String>> Function()? cabecerasVersion,
    void Function(DateTime horaServidor)? alHoraServidor,
    void Function()? alAppDesactualizada,
    void Function(bool enLinea)? alEstadoRed,
  }) : _renovar = renovar ?? (() => SessionService().renovarSesionApp()),
       _tokenActual = tokenActual ?? (() => SessionService().getToken()),
       _cabecerasVersion = cabecerasVersion ?? AppInfo.cabeceras,
       _alHoraServidor =
           alHoraServidor ??
           ((h) => unawaited(RelojConfiable.instance.registrarHoraServidor(h))),
       _alAppDesactualizada = alAppDesactualizada ?? _avisoGlobal426,
       _alEstadoRed = alEstadoRed ?? _avisoGlobalRed;

  final http.Client _inner;
  final Future<ResultadoRenovacion> Function() _renovar;
  final Future<String?> Function() _tokenActual;
  final Future<Map<String, String>> Function() _cabecerasVersion;
  final void Function(DateTime) _alHoraServidor;
  final void Function() _alAppDesactualizada;
  final void Function(bool) _alEstadoRed;

  /// Lo registran `ActualizacionAppService` y `ConnectivityService` al
  /// arrancar (evita que este archivo dependa de ellos).
  static void Function()? alAppDesactualizadaGlobal;
  static void Function(bool enLinea)? alEstadoRedGlobal;

  static void _avisoGlobal426() => alAppDesactualizadaGlobal?.call();
  static void _avisoGlobalRed(bool enLinea) => alEstadoRedGlobal?.call(enLinea);

  /// Rutas de /auth que no se renuevan: un 401 ahí es "credenciales
  /// incorrectas" o la propia renovación, no un token vencido.
  static bool esRenovable(http.BaseRequest request) {
    final auth =
        request.headers['Authorization'] ??
        request.headers['authorization'] ??
        '';
    if (!auth.startsWith('Bearer ')) return false;
    final path = request.url.path;
    if (!path.contains('/auth/')) return true;
    return path.endsWith('/auth/me') || path.endsWith('/auth/perfil-resumen');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      request.headers.addAll(await _cabecerasVersion());
    } catch (_) {}

    final http.StreamedResponse resp;
    try {
      resp = await _inner.send(request);
    } catch (_) {
      _alEstadoRed(false);
      rethrow;
    }
    _alEstadoRed(true);
    _registrarHora(resp);

    if (resp.statusCode == 426) {
      final buffer = await _bufferizar(resp);
      if (_codigo(buffer) == 'APP_DESACTUALIZADA') _alAppDesactualizada();
      return buffer.respuesta;
    }

    if (resp.statusCode != 401 ||
        request is! http.Request ||
        !esRenovable(request)) {
      return resp;
    }

    final original = await _bufferizar(resp);
    final r = await _renovar();
    if (r != ResultadoRenovacion.renovada) return original.respuesta;
    final token = await _tokenActual();
    if (token == null || token.isEmpty) return original.respuesta;

    final repetida = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..headers['Authorization'] = 'Bearer $token'
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = request.bodyBytes;
    repetida.headers.remove('authorization');
    repetida.headers['Authorization'] = 'Bearer $token';

    final segunda = await _inner.send(repetida);
    _registrarHora(segunda);
    return segunda;
  }

  void _registrarHora(http.StreamedResponse resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 400) return;
    final hora = RelojConfiable.horaDeCabeceraDate(resp.headers['date']);
    if (hora != null) _alHoraServidor(hora);
  }

  static Future<_RespuestaEnMemoria> _bufferizar(
    http.StreamedResponse resp,
  ) async {
    final bytes = await resp.stream.toBytes();
    return _RespuestaEnMemoria(
      bytes,
      http.StreamedResponse(
        Stream.value(bytes),
        resp.statusCode,
        contentLength: bytes.length,
        request: resp.request,
        headers: resp.headers,
        isRedirect: resp.isRedirect,
        persistentConnection: resp.persistentConnection,
        reasonPhrase: resp.reasonPhrase,
      ),
    );
  }

  static String? _codigo(_RespuestaEnMemoria r) {
    try {
      final decoded = jsonDecode(utf8.decode(r.bytes, allowMalformed: true));
      if (decoded is Map) return decoded['code']?.toString();
    } catch (_) {}
    return null;
  }

  @override
  void close() => _inner.close();
}

class _RespuestaEnMemoria {
  final List<int> bytes;
  final http.StreamedResponse respuesta;

  _RespuestaEnMemoria(this.bytes, this.respuesta);
}
