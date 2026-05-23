import 'package:flutter_application_1/service/session_service.dart';

class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();
  final SessionService _session = SessionService();

  static String normalize(String value) => value.trim().toLowerCase();

  bool can(String permission) {
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
    await _session.getPermissions();
  }
}
