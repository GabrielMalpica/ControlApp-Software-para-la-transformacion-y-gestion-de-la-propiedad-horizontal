import 'package:flutter_application_1/service/session_service.dart';

import '../api/auth_api.dart';

class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();
  final SessionService _session = SessionService();
  final AuthApi _authApi = AuthApi();

  static const Map<String, Set<String>> _permissionsThatGrantAccess = {
    'tareas.ver': {'tareas.crear', 'tareas.cerrar', 'tareas.veredicto'},
    'cronograma.ver': {
      'cronograma.imprimir',
      'cronograma.publicar',
      'cronograma.eliminar_publicado',
      'cronograma.correctivas_programar',
      'cronograma.excluidas_ver',
    },
    'solicitudes.ver': {'solicitudes.crear', 'solicitudes.gestionar'},
    'inventario.ver': {'inventario.gestionar'},
    'maquinaria.ver': {'maquinaria.asignar'},
    'herramientas.ver': {'herramientas.gestionar'},
    'conjuntos.ver': {'conjuntos.gestionar'},
    'mapa_areas.ver': {'mapa_areas.gestionar'},
    'compromisos.ver': {'compromisos.gestionar'},
    'residentes.ver': {
      'residentes.crear',
      'residentes.editar',
      'residentes.eliminar',
      'residentes.cargar_masivo',
    },
    'plan_esperanza.acceso': {'plan_esperanza.configurar'},
  };

  static String normalize(String value) => value.trim().toLowerCase();

  bool can(String permission) {
    final role = normalize(_session.getRolSync() ?? '');
    if (role == 'gerente') return true;

    final wanted = normalize(permission);
    final current = _session.getPermissionsSync().map(normalize).toSet();
    if (current.contains(wanted)) return true;

    final accessGrants = _permissionsThatGrantAccess[wanted] ?? const {};
    return accessGrants.any(current.contains);
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
