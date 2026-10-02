import 'package:flutter_application_1/service/permission_service.dart';

/// El rol administrador ve las tareas CORRECTIVA como "actividad especial".
/// El resto de roles (gerente, supervisor, jefe de operaciones, etc.) sigue
/// viendo "correctiva". El backend y la base de datos no cambian: el tipo
/// sigue siendo el enum `CORRECTIVA`, esto es solo una etiqueta de UI.
bool get esVistaAdministrador =>
    PermissionService.instance.hasAnyRole(const ['administrador']);

/// Etiqueta para el tipo de tarea `CORRECTIVA`, en singular o plural.
String etiquetaCorrectiva({bool plural = false, bool minuscula = false}) {
  final String texto;
  if (esVistaAdministrador) {
    texto = plural ? 'Actividades especiales' : 'Actividad especial';
  } else {
    texto = plural ? 'Correctivas' : 'Correctiva';
  }
  if (!minuscula) return texto;
  return texto[0].toLowerCase() + texto.substring(1);
}

/// Etiqueta para un `tipo` de tarea crudo ('CORRECTIVA' | 'PREVENTIVA').
String etiquetaTipoTarea(String? tipo, {bool plural = false}) {
  final normalizado = (tipo ?? '').trim().toUpperCase();
  if (normalizado == 'CORRECTIVA') {
    return etiquetaCorrectiva(plural: plural);
  }
  return plural ? 'Preventivas' : 'Preventiva';
}
