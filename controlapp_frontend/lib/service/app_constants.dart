class AppConstants {
  /// Cambia en build/run con:
  /// --dart-define=API_BASE_URL=http://localhost:3000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        'https://controlapp-software-para-la-transformacion-y-ges-production.up.railway.app',
  );

  // 🔹 Prefijo de todo lo que maneja el GerenteController
  static const String gerenteBase = "$baseUrl/gerente";
  static const empresaNit = '901191875-4';

  static const String empresaBase = "$baseUrl/empresa";
  static String maquinariaEmpresa(String nit) => "$empresaBase/$nit/maquinaria";

  // 🔹 Usuarios
  static const String usuarios = "$gerenteBase/usuarios";

  // 🔹 Asignación de roles
  static const String operarios = "$gerenteBase/operarios";
  static const String supervisores = "$baseUrl/supervisores";
  static const String supervisorBase = "$baseUrl/supervisor";
  static const String administradores = "$gerenteBase/administradores";
  static const String jefeOperacionesBase = "$baseUrl/jefe-operaciones";
  static const String reportesBase = "$baseUrl/reporte";

  // 🔹 Catálogo de enums para usuario
  static const String usuarioEnums = "$gerenteBase/enums-usuario";

  static const String conjuntosGerente = "$gerenteBase/conjuntos";

  static const String definicionPreventivaBase =
      "$baseUrl/definicion-preventiva";

  static const String cronogramaBase = "$baseUrl/cronograma";
}
