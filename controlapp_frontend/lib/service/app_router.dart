import 'package:flutter/material.dart';

import 'package:flutter_application_1/pages/administrador_page.dart';
import 'package:flutter_application_1/pages/gerente/gerente_page.dart';
import 'package:flutter_application_1/pages/jefe_operaciones_page.dart';
import 'package:flutter_application_1/pages/login_page.dart';
import 'package:flutter_application_1/pages/operarios_page.dart';
import 'package:flutter_application_1/pages/splash_decider_page.dart';
import 'package:flutter_application_1/pages/supervisor_page.dart';
import 'package:flutter_application_1/service/app_constants.dart';

class AppRouter {
  static const splash = '/';
  static const login = '/login';
  static const homeGerente = '/home-gerente';
  static const homeSupervisor = '/home-supervisor';
  static const homeAdmin = '/home-admin';
  static const homeOperario = '/home-operario';
  static const homeJefeOperaciones = '/home-jefe-operaciones';
  static const dashboard = '/dashboard';

  static Map<String, WidgetBuilder> get routes => {
    splash: (_) => const SplashDeciderPage(),
    login: (_) => const LoginPage(),
    homeGerente: (_) => const GerenteDashboardPage(),
    homeSupervisor: (_) => const SupervisorPage(),
    homeAdmin: (_) => const AdministradorPage(),
    homeOperario: (_) =>
        const OperarioDashboardPage(nit: AppConstants.empresaNit),
    homeJefeOperaciones: (_) => const JefeOperacionesPage(),
    dashboard: (_) => const GerenteDashboardPage(),
  };

  static String routeForRole(String role) {
    switch (role) {
      case 'gerente':
        return homeGerente;
      case 'supervisor':
        return homeSupervisor;
      case 'administrador':
        return homeAdmin;
      case 'operario':
        return homeOperario;
      case 'jefe_operaciones':
        return homeJefeOperaciones;
      default:
        return login;
    }
  }

  static void goReplacementByRole(BuildContext context, String role) {
    Navigator.pushReplacementNamed(context, routeForRole(role));
  }
}
