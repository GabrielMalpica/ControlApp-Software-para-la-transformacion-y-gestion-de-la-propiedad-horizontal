import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/administrador_page.dart';
import 'package:flutter_application_1/pages/jefe_operaciones_page.dart';
import 'package:flutter_application_1/pages/operarios_page.dart';
import 'package:flutter_application_1/pages/supervisor_page.dart';
import 'service/theme.dart';

import 'pages/login_page.dart';
import 'pages/splash_decider_page.dart';

import 'pages/gerente/gerente_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Limpieza S.A.S.',
      theme: ThemeData(
        scaffoldBackgroundColor: AppTheme.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.primary),
      ),
      debugShowCheckedModeBanner: false,

      // ✅ portero
      initialRoute: '/',

      routes: {
        '/': (_) => const SplashDeciderPage(),
        '/login': (_) => const LoginPage(),

        '/home-gerente': (_) => const GerenteDashboardPage(),
        '/home-supervisor': (_) => const SupervisorPage(),
        '/home-admin': (_) => const AdministradorPage(),
        '/home-operario': (_) => const OperarioDashboardPage(nit: '901191875-4',),
        '/home-jefe-operaciones': (_) => const JefeOperacionesPage(),

        '/dashboard': (_) => const GerenteDashboardPage(),
      },
    );
  }
}
