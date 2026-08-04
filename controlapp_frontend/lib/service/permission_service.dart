import 'package:flutter_application_1/service/session_service.dart';

import '../api/auth_api.dart';

class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();
  final SessionService _session = SessionService();
  final AuthApi _authApi = AuthApi();

  static String normalize(String value) => value.trim().toLowerCase();

  bool can(String permission) {
    final role = normalize(_session.getRolSync() ?? '');
    if (role == 'gerente') return true;

    final wanted = normalize(permission);
    final current = _session.getPermissionsSync().map(normalize).toSet();
    return current.contains(wanted);
  }

  bool canAny(Iterable<String> permissions) {
    for (final permission in permissions) {
      if (can(permission)) return true;
    }
    return false;
  }

  Future<void> refresh() async {
    await _authApi.me();
  }
}
