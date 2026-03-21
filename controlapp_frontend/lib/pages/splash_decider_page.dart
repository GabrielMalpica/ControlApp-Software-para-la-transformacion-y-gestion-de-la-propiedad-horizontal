import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/app_router.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/service/session_service.dart';

class SplashDeciderPage extends StatefulWidget {
  const SplashDeciderPage({super.key});

  @override
  State<SplashDeciderPage> createState() => _SplashDeciderPageState();
}

class _SplashDeciderPageState extends State<SplashDeciderPage> {
  final _session = SessionService();
  final _authApi = AuthApi();

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final token = await _session.getToken();

    if (token == null || token.isEmpty) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRouter.login);
      return;
    }

    try {
      final me = await _authApi.me();
      if (!mounted) return;
      AppRouter.goReplacementByRole(context, me.rol);
      unawaited(NotificacionesCenter.instance.start());
    } catch (_) {
      NotificacionesCenter.instance.stop();
      await _session.clear();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRouter.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
