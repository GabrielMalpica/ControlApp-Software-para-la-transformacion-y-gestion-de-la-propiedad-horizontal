import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/actualizacion_app_service.dart';
import 'package:flutter_application_1/service/app_router.dart';
import 'package:flutter_application_1/service/arranque_sesion.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/service/offline/precarga_sin_senal.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

class SplashDeciderPage extends StatefulWidget {
  const SplashDeciderPage({super.key});

  @override
  State<SplashDeciderPage> createState() => _SplashDeciderPageState();
}

class _SplashDeciderPageState extends State<SplashDeciderPage> {
  final _session = SessionService();
  final _authApi = AuthApi();

  /// Sin señal real el operario no debe quedarse mirando el logo: pasado esto
  /// entra con lo guardado.
  static const _esperaPerfil = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final decision = await decidirArranque(
      tieneSesion: _session.tieneSesionGuardada,
      consultarPerfil: () => _authApi.me(timeout: _esperaPerfil),
      perfilGuardado: _session.perfilGuardado,
      esWeb: kIsWeb,
    );
    if (!mounted) return;

    switch (decision.destino) {
      case DestinoArranque.login:
        NotificacionesCenter.instance.stop();
        if (decision.borrarSesion) await _session.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRouter.login);
      case DestinoArranque.actualizarApp:
        // La pantalla de "Actualiza la app" (AvisoActualizacionApp) queda
        // encima; si hay perfil guardado se deja la app lista detrás.
        ActualizacionAppService.instance.marcarObligatoriaPorServidor();
        final u = decision.usuario;
        if (u != null) AppRouter.goReplacementAfterLogin(context, u);
      case DestinoArranque.inicio:
        final u = decision.usuario!;
        AppRouter.goReplacementAfterLogin(context, u);
        unawaited(NotificacionesCenter.instance.start());
        // Con señal: deja guardada la agenda y el inventario para cuando no
        // haya.
        if (!decision.sinSenal) unawaited(PrecargaSinSenal.ejecutar(u));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 120, height: 120),
            const SizedBox(height: 24),
            const SizedBox(
              width: 120,
              child: SkeletonLine(widthFactor: 1, height: 6),
            ),
          ],
        ),
      ),
    );
  }
}
