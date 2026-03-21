import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/app_router.dart';
import 'package:flutter_application_1/service/theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Limpieza S.A.S.',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: AppRouter.splash,
      routes: AppRouter.routes,
    );
  }
}
