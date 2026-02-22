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
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goByRol(String rol) {
    // Ajusta nombres de rutas a las tuyas reales
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ✅ Placeholder para poner tu logo por URL cuando lo tengas
              SizedBox(
                width: 560,
                child: AspectRatio(
                  aspectRatio: 3.2,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Text(
                      'Aquí va el logo (Image.network con URL)',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: 280,
                child: TextField(
                  controller: _correoCtrl,
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
              const SizedBox(height: 14),

              SizedBox(
                width: 280,
                child: TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
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
              const SizedBox(height: 8),

              SizedBox(
                width: 280,
                child: Align(
                  alignment: Alignment.centerRight,
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
              const SizedBox(height: 16),

              if (_error != null)
                SizedBox(
                  width: 280,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              const SizedBox(height: 12),

              SizedBox(
                width: 160,
                height: 42,
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
