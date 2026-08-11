import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;

class AppConstants {
  static const String _localBaseUrlWebDesktop = 'http://localhost:3000';
  static const String _localBaseUrlAndroid = 'http://10.0.2.2:3000';

  /// Cambia en build/run con:
  /// --dart-define=API_BASE_URL=https://tu-api
  static const String _apiBaseFromEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get _localBaseUrl {
    if (kIsWeb) return _localBaseUrlWebDesktop;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _localBaseUrlAndroid;
      case TargetPlatform.iOS:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return _localBaseUrlWebDesktop;
      case TargetPlatform.fuchsia:
        return _localBaseUrlWebDesktop;
    }
  }

  /// Base URL efectiva en runtime.
  /// Si el build trae localhost pero la app NO corre en localhost (ej: producción web),
  /// En produccion no existe fallback: API_BASE_URL debe declararse en el build.
  static String get baseUrl {
    final env = _apiBaseFromEnv.trim();
    if (env.isEmpty) {
      final host = kIsWeb ? Uri.base.host.toLowerCase() : '';
      final runningOnLocalhost =
          !kIsWeb || host == 'localhost' || host == '127.0.0.1';
      if (kReleaseMode || !runningOnLocalhost) {
        throw StateError(
          'API_BASE_URL es obligatorio en produccion. Usa '
          '--dart-define=API_BASE_URL=https://tu-api.',
        );
      }
      return _localBaseUrl;
    }

    if (!kIsWeb) {
      return env
          .replaceAll('localhost', '10.0.2.2')
          .replaceAll('127.0.0.1', '10.0.2.2');
    }

    final host = Uri.base.host.toLowerCase();
    final runningOnLocalhost = host == 'localhost' || host == '127.0.0.1';

    final envLower = env.toLowerCase();
    final envPointsToLocal =
        envLower.contains('localhost') || envLower.contains('127.0.0.1');

    if (envPointsToLocal && !runningOnLocalhost) {
      throw StateError(
        'API_BASE_URL no puede apuntar a localhost desde una app web desplegada.',
      );
    }

    return env;
  }

  // 🔹 Prefijo de todo lo que maneja el GerenteController
  static String get gerenteBase => "$baseUrl/gerente";
  static String get administradorBase => "$baseUrl/administrador";
  static const empresaNit = String.fromEnvironment(
    'EMPRESA_NIT',
    defaultValue: '',
  );

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
  static String get commerceBase => "$baseUrl/commerce";
}
