import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/notificacion_model.dart';
import 'package:flutter_application_1/service/app_router.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/aviso_version_nueva.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  /// Global: permite mostrar avisos flotantes (ej. stock bajo) sin depender
  /// del context de la página que esté abierta en ese momento.
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Global: permite volver al login cuando la sesion vence fuera de una
  /// pagina concreta (renovacion fallida de la sesion web).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    NotificacionesCenter.instance.stockBajoNueva.addListener(_onStockBajoNueva);
    SessionService.sesionExpirada.addListener(_onSesionExpirada);
  }

  @override
  void dispose() {
    NotificacionesCenter.instance.stockBajoNueva.removeListener(
      _onStockBajoNueva,
    );
    SessionService.sesionExpirada.removeListener(_onSesionExpirada);
    super.dispose();
  }

  Future<void> _onSesionExpirada() async {
    NotificacionesCenter.instance.stop();
    await SessionService().clear();
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushNamedAndRemoveUntil(AppRouter.login, (route) => false);
    MyApp.scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Tu sesión expiró. Inicia sesión de nuevo.'),
      ),
    );
  }

  void _onStockBajoNueva() {
    final n = NotificacionesCenter.instance.stockBajoNueva.value;
    if (n == null) return;
    _mostrarFlotante(n);
  }

  void _mostrarFlotante(NotificacionModel n) {
    final messenger = MyApp.scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFB8860B),
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                n.mensaje,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Limpieza S.A.S.',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: MyApp.scaffoldMessengerKey,
      navigatorKey: MyApp.navigatorKey,
      initialRoute: AppRouter.splash,
      routes: AppRouter.routes,
      builder: (context, child) =>
          AvisoVersionNueva(child: child ?? const SizedBox.shrink()),
    );
  }
}
