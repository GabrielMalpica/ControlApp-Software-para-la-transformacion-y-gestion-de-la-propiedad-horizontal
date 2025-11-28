import 'package:flutter/material.dart';
import 'service/theme.dart';
import 'pages/login_page.dart';
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
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginPage(),
        '/dashboard': (_) => const GerenteDashboardPage(),
      },
    );
  }
}