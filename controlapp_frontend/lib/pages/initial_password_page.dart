import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_router.dart';
import 'package:flutter_application_1/service/theme.dart';

class InitialPasswordPage extends StatefulWidget {
  const InitialPasswordPage({super.key});

  @override
  State<InitialPasswordPage> createState() => _InitialPasswordPageState();
}

class _InitialPasswordPageState extends State<InitialPasswordPage> {
  final _authApi = AuthApi();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final nueva = _newCtrl.text.trim();
    final confirmar = _confirmCtrl.text.trim();

    if (nueva.length < 8) {
      setState(
        () => _error = 'La nueva contrasena debe tener minimo 8 caracteres.',
      );
      return;
    }
    if (nueva != confirmar) {
      setState(
        () => _error = 'La confirmacion no coincide con la nueva contrasena.',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _authApi.cambiarContrasenaInicial(nuevaContrasena: nueva);
      final me = await _authApi.me();
      if (!mounted) return;
      AppRouter.goReplacementAfterAuth(
        context,
        rol: me.rol,
        requiereCambioContrasena: me.requiereCambioContrasena,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(
          e,
          fallback: 'No se pudo actualizar la contrasena inicial.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Activa tu cuenta',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Antes de seguir debes cambiar la contrasena temporal por una segura.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _newCtrl,
                        obscureText: true,
                        enabled: !_loading,
                        decoration: const InputDecoration(
                          labelText: 'Nueva contrasena',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: true,
                        enabled: !_loading,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar nueva contrasena',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: Text(
                          _loading ? 'Actualizando...' : 'Guardar y continuar',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
