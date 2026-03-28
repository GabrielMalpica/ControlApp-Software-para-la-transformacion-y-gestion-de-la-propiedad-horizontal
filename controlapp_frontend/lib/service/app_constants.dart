class AppConstants {
  static const String _railwayBaseUrl =
      'https://controlapp-software-para-la-transformacion-y-ges-production.up.railway.app';

  /// Cambia en build/run con:
  /// --dart-define=API_BASE_URL=https://tu-api
  static const String _apiBaseFromEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Base URL efectiva en runtime.
  /// Si el build trae localhost pero la app NO corre en localhost (ej: producción web),
  /// forzamos Railway para evitar que apunte al backend local por error.
  static String get baseUrl {
    final env = _apiBaseFromEnv.trim();
    if (env.isEmpty) return _railwayBaseUrl;

    final host = Uri.base.host.toLowerCase();
    final runningOnLocalhost = host == 'localhost' || host == '127.0.0.1';

    final envLower = env.toLowerCase();
    final envPointsToLocal =
        envLower.contains('localhost') || envLower.contains('127.0.0.1');

    if (envPointsToLocal && !runningOnLocalhost) {
      return _railwayBaseUrl;
    }

    return env;
  }

  // 🔹 Prefijo de todo lo que maneja el GerenteController
  static String get gerenteBase => "$baseUrl/gerente";
  static const empresaNit = '901191875-4';

  static String get empresaBase => "$baseUrl/empresa";
  static String maquinariaEmpresa(String nit) => "$empresaBase/$nit/maquinaria";

  // 🔹 Usuarios
  static String get usuarios => "$gerenteBase/usuarios";

  // 🔹 Asignación de roles
  static String get operarios => "$gerenteBase/operarios";
  static String get supervisores => "$gerenteBase/supervisores";
  static String get supervisorBase => "$baseUrl/supervisor";
  static String get administradores => "$gerenteBase/administradores";
  static String get jefesOperaciones => "$gerenteBase/jefes-operaciones";
  static String get jefeOperacionesBase => "$baseUrl/jefe-operaciones";
  static String get reportesBase => "$baseUrl/reporte";

  // 🔹 Catálogo de enums para usuario
  static String get usuarioEnums => "$gerenteBase/enums-usuario";

  static String get conjuntosGerente => "$gerenteBase/conjuntos";

  static String get definicionPreventivaBase =>
      "$baseUrl/definicion-preventiva";

  static String get cronogramaBase => "$baseUrl/cronograma";
}
