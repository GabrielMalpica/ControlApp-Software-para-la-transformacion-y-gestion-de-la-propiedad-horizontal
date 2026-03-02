import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:flutter_application_1/service/session_service.dart';
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

  String _friendlyError(Object e) {
    var out = e.toString().trim();
    if (out.isEmpty) return 'No se pudo iniciar sesion.';

    final rx = RegExp(r'^[A-Za-z]*Exception:\s*', caseSensitive: false);
    while (rx.hasMatch(out)) {
      out = out.replaceFirst(rx, '').trim();
    }

    return out.isEmpty ? 'No se pudo iniciar sesion.' : out;
  }

  Future<void> _submit() async {
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
      await NotificacionesCenter.instance.start();

      _goByRol(resp.user.rol);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goByRol(String rol) {
    switch (rol) {
      case 'gerente':
        Navigator.pushReplacementNamed(context, '/home-gerente');
        break;
      case 'supervisor':
        Navigator.pushReplacementNamed(context, '/home-supervisor');
        break;
      case 'administrador':
        Navigator.pushReplacementNamed(context, '/home-admin');
        break;
      case 'operario':
        Navigator.pushReplacementNamed(context, '/home-operario');
        break;
      case 'jefe_operaciones':
        Navigator.pushReplacementNamed(context, '/home-jefe-operaciones');
        break;
      default:
        Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final logoWidth = (screenWidth - 48).clamp(220, 560).toDouble();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: logoWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE6EAF0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 120,
                    child: Image.network(
                      _logoUrl,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text(
                          'No se pudo cargar el logo',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              SizedBox(
                width: 300,
                child: TextField(
                  controller: _correoCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Correo',
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: 300,
                child: TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Contrasena',
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onSubmitted: (_) => _loading ? null : _submit(),
                ),
              ),
              const SizedBox(height: 6),

              SizedBox(
                width: 300,
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton(
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
                    child: const Text('Olvide mi contrasena'),
                  ),
                ),
              ),

              if (_error != null) ...[
                SizedBox(
                  width: 300,
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 10),
              ] else
                const SizedBox(height: 6),

              SizedBox(
                width: 170,
                height: 44,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006C3C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Ingresar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
