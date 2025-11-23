class AppConstants {
  static const String baseUrl = "http://localhost:3000";

  // 🔹 Prefijo de todo lo que maneja el GerenteController
  static const String gerenteBase = "$baseUrl/gerente";

  // 🔹 Usuarios
  static const String usuarios = "$gerenteBase/usuarios";

  // 🔹 Asignación de roles
  static const String operarios = "$gerenteBase/operarios";
  static const String supervisores = "$gerenteBase/supervisores";
  static const String administradores = "$gerenteBase/administradores";
  static const String jefesOperaciones = "$gerenteBase/jefes-operaciones";

  // 🔹 Catálogo de enums para usuario
  static const String usuarioEnums = "$gerenteBase/enums-usuario";
}
