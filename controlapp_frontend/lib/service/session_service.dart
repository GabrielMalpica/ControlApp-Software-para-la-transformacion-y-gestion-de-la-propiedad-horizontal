import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_constants.dart';
import 'cliente_credenciales_bridge.dart';

/// Sesion del usuario.
///
/// En web el token de acceso vive SOLO en memoria (no lo puede leer otra
/// pestana, una extension ni un agente que inspeccione el almacenamiento) y
/// dura poco: antes de que venza, o al recargar la pagina, se renueva con la
/// cookie HttpOnly que puso el backend al iniciar sesion (`/auth/refresh`).
/// En movil el token sigue en almacenamiento seguro.
class SessionService {
  /// Margen para renovar antes de que el token venza.
  static const _margenRenovacion = Duration(seconds: 60);
  static Future<bool>? _renovacionEnCurso;

  // Keys
  static const _kToken = 'auth_token';
  static const _kRol = 'auth_rol';
  static const _kCorreo = 'auth_correo';
  static const _kNombre = 'auth_nombre';
  static const _kUserId = 'auth_user_id';
  static const _kEmpresaId = 'auth_empresa_id';
  static const _kConjuntoId = 'auth_conjunto_id';
  static const _kPermissions = 'auth_permissions';
  static const _kRequirePasswordChange = 'auth_require_password_change';

  static const _secure = FlutterSecureStorage();

  // ✅ Cache en memoria (evita “no alcanzó a guardar / leer”)
  static String? _memToken;
  static String? _memUserId;
  static String? _memRol;
  static String? _memEmpresaId;
  static String? _memConjuntoId;
  static List<String>? _memPermissions;
  static bool? _memRequirePasswordChange;

  Future<void> saveSession({
    required String token,
    required String rol,
    required String correo,
    required String nombre,
    required String userId,
    required String empresaId,
    String conjuntoId = '',
    List<String> permissions = const [],
    bool requiereCambioContrasena = false,
  }) async {
    // ✅ cache inmediato
    _memToken = token;
    _memRol = rol;
    _memUserId = userId;
    _memEmpresaId = empresaId.trim();
    _memConjuntoId = conjuntoId.trim();
    AppConstants.setEmpresaNitFromSession(empresaId);
    _memPermissions = [...permissions];
    _memRequirePasswordChange = requiereCambioContrasena;

    final permissionsJson = jsonEncode(permissions);

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      // El token no se persiste en web: tras una recarga se renueva con la
      // cookie HttpOnly. Se borra el que dejaban versiones anteriores.
      await prefs.remove(_kToken);
      await prefs.setString(_kRol, rol);
      await prefs.setString(_kCorreo, correo);
      await prefs.setString(_kNombre, nombre);
      await prefs.setString(_kUserId, userId);
      await prefs.setString(_kEmpresaId, empresaId.trim());
      await prefs.setString(_kConjuntoId, conjuntoId.trim());
      await prefs.setString(_kPermissions, permissionsJson);
      await prefs.setBool(_kRequirePasswordChange, requiereCambioContrasena);
      return;
    }

    await _secure.write(key: _kToken, value: token);
    await _secure.write(key: _kRol, value: rol);
    await _secure.write(key: _kCorreo, value: correo);
    await _secure.write(key: _kNombre, value: nombre);
    await _secure.write(key: _kUserId, value: userId);
    await _secure.write(key: _kEmpresaId, value: empresaId.trim());
    await _secure.write(key: _kConjuntoId, value: conjuntoId.trim());
    await _secure.write(key: _kPermissions, value: permissionsJson);
    await _secure.write(
      key: _kRequirePasswordChange,
      value: requiereCambioContrasena ? 'true' : 'false',
    );
  }

  Future<void> saveProfile({
    required String rol,
    required String correo,
    required String nombre,
    required String userId,
    required String empresaId,
    String conjuntoId = '',
    List<String> permissions = const [],
    bool requiereCambioContrasena = false,
  }) async {
    _memRol = rol;
    _memUserId = userId;
    _memEmpresaId = empresaId.trim();
    _memConjuntoId = conjuntoId.trim();
    AppConstants.setEmpresaNitFromSession(empresaId);
    _memPermissions = [...permissions];
    _memRequirePasswordChange = requiereCambioContrasena;

    final permissionsJson = jsonEncode(permissions);

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRol, rol);
      await prefs.setString(_kCorreo, correo);
      await prefs.setString(_kNombre, nombre);
      await prefs.setString(_kUserId, userId);
      await prefs.setString(_kEmpresaId, empresaId.trim());
      await prefs.setString(_kConjuntoId, conjuntoId.trim());
      await prefs.setString(_kPermissions, permissionsJson);
      await prefs.setBool(_kRequirePasswordChange, requiereCambioContrasena);
      return;
    }

    await _secure.write(key: _kRol, value: rol);
    await _secure.write(key: _kCorreo, value: correo);
    await _secure.write(key: _kNombre, value: nombre);
    await _secure.write(key: _kUserId, value: userId);
    await _secure.write(key: _kEmpresaId, value: empresaId.trim());
    await _secure.write(key: _kConjuntoId, value: conjuntoId.trim());
    await _secure.write(key: _kPermissions, value: permissionsJson);
    await _secure.write(
      key: _kRequirePasswordChange,
      value: requiereCambioContrasena ? 'true' : 'false',
    );
  }

  Future<bool> getRequirePasswordChange() async {
    if (_memRequirePasswordChange != null) return _memRequirePasswordChange!;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _memRequirePasswordChange =
          prefs.getBool(_kRequirePasswordChange) ?? false;
      return _memRequirePasswordChange!;
    }

    final raw = await _secure.read(key: _kRequirePasswordChange);
    _memRequirePasswordChange = raw == 'true';
    return _memRequirePasswordChange!;
  }

  Future<void> setRequirePasswordChange(bool value) async {
    _memRequirePasswordChange = value;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRequirePasswordChange, value);
      return;
    }

    await _secure.write(
      key: _kRequirePasswordChange,
      value: value ? 'true' : 'false',
    );
  }

  /// Se incrementa cuando una sesion web abierta no se pudo renovar: la app
  /// vuelve al login (ver MyApp) en vez de dejar fallar cada peticion.
  static final ValueNotifier<int> sesionExpirada = ValueNotifier<int>(0);

  Future<String?> getToken() async {
    if (kIsWeb) {
      if (_vigente(_memToken)) return _memToken;
      final teniaSesion = _memToken != null && _memToken!.isNotEmpty;
      final renovada = await renovarSesionWeb();
      if (!renovada && teniaSesion) sesionExpirada.value++;
      return _vigente(_memToken) ? _memToken : null;
    }

    if (_memToken != null && _memToken!.isNotEmpty) return _memToken;
    _memToken = await _secure.read(key: _kToken);
    return _memToken;
  }

  /// Guarda en memoria un token recien emitido (login, cambio de contrasena).
  Future<void> setToken(String token) async {
    _memToken = token;
    if (!kIsWeb) await _secure.write(key: _kToken, value: token);
  }

  /// Renueva la sesion web con la cookie HttpOnly. Varias llamadas a la vez
  /// comparten una sola renovacion. Devuelve false si no hay sesion que
  /// renovar (cookie vencida, revocada o bloqueada por el navegador).
  Future<bool> renovarSesionWeb() {
    if (!kIsWeb) return Future.value(false);
    return _renovacionEnCurso ??= _renovar().whenComplete(() {
      _renovacionEnCurso = null;
    });
  }

  Future<bool> _renovar({bool reintento = false}) async {
    final client = crearClienteConCredenciales();
    try {
      final resp = await client.post(
        Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
        headers: const {'Accept': 'application/json'},
      );
      // Otra pestana renovo con la misma cookie hace un instante: el
      // navegador ya tiene la nueva, basta con reintentar.
      if (resp.statusCode == 409 && !reintento) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return await _renovar(reintento: true);
      }
      if (resp.statusCode != 200) {
        _memToken = null;
        return false;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final token = data['token']?.toString() ?? '';
      final user = data['user'];
      if (token.isEmpty || user is! Map<String, dynamic>) {
        _memToken = null;
        return false;
      }
      _memToken = token;
      await saveProfile(
        rol: user['rol']?.toString() ?? '',
        correo: user['correo']?.toString() ?? '',
        nombre: user['nombre']?.toString() ?? '',
        userId: user['id']?.toString() ?? '',
        empresaId: user['empresaId']?.toString() ?? '',
        conjuntoId: user['conjuntoId']?.toString() ?? '',
        permissions: (user['permissions'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        requiereCambioContrasena: user['requiereCambioContrasena'] == true,
      );
      return true;
    } catch (_) {
      // Sin red: se conserva el token en memoria si aun sirve.
      return _vigente(_memToken);
    } finally {
      client.close();
    }
  }

  /// True si el JWT existe y no vence dentro del margen de renovacion.
  static bool _vigente(String? token) {
    if (token == null || token.isEmpty) return false;
    final exp = expiracionDeToken(token);
    if (exp == null) return true;
    return exp.isAfter(DateTime.now().add(_margenRenovacion));
  }

  /// Fecha `exp` de un JWT, o null si no se puede leer.
  @visibleForTesting
  static DateTime? expiracionDeToken(String token) {
    final partes = token.split('.');
    if (partes.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(partes[1])),
      );
      final exp = (jsonDecode(payload) as Map<String, dynamic>)['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    } catch (_) {
      return null;
    }
  }

  Future<String?> getUserId() async {
    if (_memUserId != null && _memUserId!.isNotEmpty) return _memUserId;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _memUserId = prefs.getString(_kUserId);
      return _memUserId;
    }

    _memUserId = await _secure.read(key: _kUserId);
    return _memUserId;
  }

  Future<String?> getEmpresaId() async {
    if (_memEmpresaId != null && _memEmpresaId!.isNotEmpty) {
      AppConstants.setEmpresaNitFromSession(_memEmpresaId!);
      return _memEmpresaId;
    }

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _memEmpresaId = prefs.getString(_kEmpresaId)?.trim();
      AppConstants.setEmpresaNitFromSession(_memEmpresaId ?? '');
      return _memEmpresaId;
    }

    _memEmpresaId = (await _secure.read(key: _kEmpresaId))?.trim();
    AppConstants.setEmpresaNitFromSession(_memEmpresaId ?? '');
    return _memEmpresaId;
  }

  String? getConjuntoIdSync() => _memConjuntoId;

  /// Nombre de la persona en sesión (para saludarla en su agenda).
  Future<String?> getNombre() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kNombre);
    }
    return _secure.read(key: _kNombre);
  }

  Future<String?> getRol() async {
    if (_memRol != null && _memRol!.isNotEmpty) return _memRol;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _memRol = prefs.getString(_kRol);
      return _memRol;
    }

    _memRol = await _secure.read(key: _kRol);
    return _memRol;
  }

  String? getRolSync() => _memRol;

  List<String> getPermissionsSync() =>
      List<String>.from(_memPermissions ?? const []);

  Future<List<String>> getPermissions() async {
    if (_memPermissions != null) return List<String>.from(_memPermissions!);

    final raw = await (() async {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_kPermissions);
      }

      return _secure.read(key: _kPermissions);
    })();

    if (raw == null || raw.trim().isEmpty) {
      _memPermissions = <String>[];
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _memPermissions = decoded.map((item) => item.toString()).toList();
      } else {
        _memPermissions = <String>[];
      }
    } catch (_) {
      _memPermissions = <String>[];
    }

    return List<String>.from(_memPermissions!);
  }

  Future<void> clear() async {
    _memToken = null;
    _memRol = null;
    _memUserId = null;
    _memEmpresaId = null;
    _memConjuntoId = null;
    AppConstants.setEmpresaNitFromSession('');
    _memPermissions = null;
    _memRequirePasswordChange = null;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kToken);
      await prefs.remove(_kRol);
      await prefs.remove(_kCorreo);
      await prefs.remove(_kNombre);
      await prefs.remove(_kUserId);
      await prefs.remove(_kEmpresaId);
      await prefs.remove(_kConjuntoId);
      await prefs.remove(_kPermissions);
      await prefs.remove(_kRequirePasswordChange);
      return;
    }

    await _secure.delete(key: _kToken);
    await _secure.delete(key: _kRol);
    await _secure.delete(key: _kCorreo);
    await _secure.delete(key: _kNombre);
    await _secure.delete(key: _kUserId);
    await _secure.delete(key: _kEmpresaId);
    await _secure.delete(key: _kConjuntoId);
    await _secure.delete(key: _kPermissions);
    await _secure.delete(key: _kRequirePasswordChange);
  }
}
