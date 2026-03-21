import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_router.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/animated_fade_slide.dart';
import 'package:flutter_application_1/widgets/password_dialogs.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _logoUrl =
      'https://controlsas.com.co/wp-content/uploads/2025/07/Mesa-de-trabajo-3@3x-1.png';

  final _correoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _authApi = AuthApi();
  final _session = SessionService();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _correoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await _authApi.login(
        correo: _correoCtrl.text.trim(),
        contrasena: _passCtrl.text,
      );

      await _session.saveSession(
        token: resp.token,
        rol: resp.user.rol,
        correo: resp.user.correo,
        nombre: resp.user.nombre,
        userId: resp.user.id,
      );
      unawaited(NotificacionesCenter.instance.start());
      _goByRol(resp.user.rol);
    } catch (e) {
      setState(() {
        _error = AppError.messageOf(e, fallback: 'No se pudo iniciar sesion.');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _goByRol(String rol) {
    AppRouter.goReplacementByRole(context, rol);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Stack(
          children: <Widget>[
            const Positioned(
              top: -80,
              right: -30,
              child: _AmbientCircle(size: 240, color: Color(0x1A0C6B43)),
            ),
            const Positioned(
              left: -60,
              bottom: -80,
              child: _AmbientCircle(size: 220, color: Color(0x18F2B84B)),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: AnimatedFadeSlide(
                      delay: const Duration(milliseconds: 110),
                      child: _buildLoginCard(context, theme),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginCard(BuildContext context, ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.10)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x16084D31),
                blurRadius: 36,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: RepaintBoundary(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x12084D31),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        height: 108,
                        child: Image.network(
                          _logoUrl,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          webHtmlElementStrategy: kIsWeb
                              ? WebHtmlElementStrategy.prefer
                              : WebHtmlElementStrategy.never,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          },
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text(
                              'No se pudo cargar el logo',
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Bienvenido',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _correoCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Contrasena',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  onSubmitted: (_) => _loading ? null : _submit(),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _loading
                        ? null
                        : () => showRecoverPasswordDialog(
                            context,
                            initialCorreo: _correoCtrl.text.trim(),
                            onSuccess:
                                ({
                                  required String correo,
                                  required String nuevaContrasena,
                                }) {
                                  _correoCtrl.text = correo;
                                  _passCtrl.text = nuevaContrasena;
                                },
                          ),
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: const Text('Recuperar acceso'),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _error == null
                      ? const SizedBox(height: 8)
                      : Container(
                          key: ValueKey<String>(_error!),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppTheme.red.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(
                                  Icons.error_outline_rounded,
                                  color: AppTheme.red,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(_loading ? 'Ingresando...' : 'Ingresar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AmbientCircle extends StatelessWidget {
  const _AmbientCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
