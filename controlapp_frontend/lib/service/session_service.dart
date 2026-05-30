import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  // Keys
  static const _kToken = 'auth_token';
  static const _kRol = 'auth_rol';
  static const _kCorreo = 'auth_correo';
  static const _kNombre = 'auth_nombre';
  static const _kUserId = 'auth_user_id';
  static const _kPermissions = 'auth_permissions';

  static const _secure = FlutterSecureStorage();

  // ✅ Cache en memoria (evita “no alcanzó a guardar / leer”)
  static String? _memToken;
  static String? _memUserId;
  static String? _memRol;
  static List<String>? _memPermissions;

  Future<void> saveSession({
    required String token,
    required String rol,
    required String correo,
    required String nombre,
    required String userId,
    List<String> permissions = const [],
  }) async {
    // ✅ cache inmediato
    _memToken = token;
    _memRol = rol;
    _memUserId = userId;
    _memPermissions = [...permissions];

    final permissionsJson = jsonEncode(permissions);

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kToken, token);
      await prefs.setString(_kRol, rol);
      await prefs.setString(_kCorreo, correo);
      await prefs.setString(_kNombre, nombre);
      await prefs.setString(_kUserId, userId);
      await prefs.setString(_kPermissions, permissionsJson);
      return;
    }

    await _secure.write(key: _kToken, value: token);
    await _secure.write(key: _kRol, value: rol);
    await _secure.write(key: _kCorreo, value: correo);
    await _secure.write(key: _kNombre, value: nombre);
    await _secure.write(key: _kUserId, value: userId);
    await _secure.write(key: _kPermissions, value: permissionsJson);
  }

  Future<void> saveProfile({
    required String rol,
    required String correo,
    required String nombre,
    required String userId,
    List<String> permissions = const [],
  }) async {
    _memRol = rol;
    _memUserId = userId;
    _memPermissions = [...permissions];

    final permissionsJson = jsonEncode(permissions);

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRol, rol);
      await prefs.setString(_kCorreo, correo);
      await prefs.setString(_kNombre, nombre);
      await prefs.setString(_kUserId, userId);
      await prefs.setString(_kPermissions, permissionsJson);
      return;
    }

    await _secure.write(key: _kRol, value: rol);
    await _secure.write(key: _kCorreo, value: correo);
    await _secure.write(key: _kNombre, value: nombre);
    await _secure.write(key: _kUserId, value: userId);
    await _secure.write(key: _kPermissions, value: permissionsJson);
  }

  Future<String?> getToken() async {
    if (_memToken != null && _memToken!.isNotEmpty) return _memToken;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _memToken = prefs.getString(_kToken);
      return _memToken;
    }

    _memToken = await _secure.read(key: _kToken);
    return _memToken;
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
    _memPermissions = null;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kToken);
      await prefs.remove(_kRol);
      await prefs.remove(_kCorreo);
      await prefs.remove(_kNombre);
      await prefs.remove(_kUserId);
      await prefs.remove(_kPermissions);
      return;
    }

    await _secure.delete(key: _kToken);
    await _secure.delete(key: _kRol);
    await _secure.delete(key: _kCorreo);
    await _secure.delete(key: _kNombre);
    await _secure.delete(key: _kUserId);
    await _secure.delete(key: _kPermissions);
  }
}
