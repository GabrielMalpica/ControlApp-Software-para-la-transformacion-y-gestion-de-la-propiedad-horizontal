import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/app_feedback.dart';

typedef RecoverPasswordSuccess =
    void Function({required String correo, required String nuevaContrasena});

String _normalizeException(Object e, {required String fallback}) {
  final raw = e.toString().trim();
  if (raw.startsWith('Exception:')) {
    final msg = raw.substring('Exception:'.length).trim();
    if (msg.isNotEmpty) return msg;
  }
  return raw.isEmpty ? fallback : raw;
}

Future<void> showChangePasswordDialog(BuildContext context) async {
  final authApi = AuthApi();
  final currentCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  bool loading = false;
  bool showCurrent = false;
  bool showNew = false;
  bool showConfirm = false;
  String? formError;

  String? validate() {
    final current = currentCtrl.text.trim();
    final newPass = newCtrl.text;
    final confirm = confirmCtrl.text;

    if (current.isEmpty) return 'Ingresa tu contrasena actual.';
    if (newPass.length < 8) {
      return 'La nueva contrasena debe tener minimo 8 caracteres.';
    }
    if (newPass != confirm) return 'La confirmacion no coincide.';
    return null;
  }

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> submit() async {
            if (loading) return;

            final err = validate();
            if (err != null) {
              setModalState(() => formError = err);
              return;
            }

            setModalState(() {
              loading = true;
              formError = null;
            });

            try {
              await authApi.cambiarContrasena(
                contrasenaActual: currentCtrl.text.trim(),
                nuevaContrasena: newCtrl.text,
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(true);
            } catch (e) {
              if (!dialogContext.mounted) return;
              setModalState(
                () => formError = _normalizeException(
                  e,
                  fallback: 'No se pudo cambiar la contrasena.',
                ),
              );
            } finally {
              if (dialogContext.mounted) {
                setModalState(() => loading = false);
              }
            }
          }

          return AlertDialog(
            title: const Text('Cambiar contrasena'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Actualiza tu clave de acceso.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: currentCtrl,
                      obscureText: !showCurrent,
                      decoration: InputDecoration(
                        labelText: 'Contrasena actual',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setModalState(() => showCurrent = !showCurrent),
                          icon: Icon(
                            showCurrent
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newCtrl,
                      obscureText: !showNew,
                      decoration: InputDecoration(
                        labelText: 'Nueva contrasena',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setModalState(() => showNew = !showNew),
                          icon: Icon(
                            showNew ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmCtrl,
                      obscureText: !showConfirm,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirmar nueva contrasena',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setModalState(() => showConfirm = !showConfirm),
                          icon: Icon(
                            showConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        formError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: loading ? null : submit,
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );

  currentCtrl.dispose();
  newCtrl.dispose();
  confirmCtrl.dispose();

  if (ok == true && context.mounted) {
    AppFeedback.showInfo(
      context,
      message: 'Contrasena actualizada correctamente.',
    );
  }
}

Future<void> showRecoverPasswordDialog(
  BuildContext context, {
  String? initialCorreo,
  RecoverPasswordSuccess? onSuccess,
}) async {
  final authApi = AuthApi();
  final correoCtrl = TextEditingController(text: initialCorreo ?? '');
  final cedulaCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  bool loading = false;
  bool showNew = false;
  bool showConfirm = false;
  String? formError;

  String? validate() {
    final correo = correoCtrl.text.trim();
    final cedula = cedulaCtrl.text.trim();
    final newPass = newCtrl.text;
    final confirm = confirmCtrl.text;

    if (correo.isEmpty || !correo.contains('@')) {
      return 'Ingresa un correo valido.';
    }
    if (cedula.length < 5) return 'Ingresa tu cedula.';
    if (newPass.length < 8) {
      return 'La nueva contrasena debe tener minimo 8 caracteres.';
    }
    if (newPass != confirm) return 'La confirmacion no coincide.';
    return null;
  }

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> submit() async {
            if (loading) return;

            final err = validate();
            if (err != null) {
              setModalState(() => formError = err);
              return;
            }

            setModalState(() {
              loading = true;
              formError = null;
            });

            try {
              await authApi.recuperarContrasena(
                correo: correoCtrl.text.trim(),
                cedula: cedulaCtrl.text.trim(),
                nuevaContrasena: newCtrl.text,
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(true);
            } catch (e) {
              if (!dialogContext.mounted) return;
              setModalState(
                () => formError = _normalizeException(
                  e,
                  fallback: 'No se pudo recuperar la contrasena.',
                ),
              );
            } finally {
              if (dialogContext.mounted) {
                setModalState(() => loading = false);
              }
            }
          }

          return AlertDialog(
            title: const Text('Recuperar contrasena'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Valida correo y cedula para restablecer tu acceso.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: correoCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: cedulaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cedula',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newCtrl,
                      obscureText: !showNew,
                      decoration: InputDecoration(
                        labelText: 'Nueva contrasena',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setModalState(() => showNew = !showNew),
                          icon: Icon(
                            showNew ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmCtrl,
                      obscureText: !showConfirm,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirmar nueva contrasena',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setModalState(() => showConfirm = !showConfirm),
                          icon: Icon(
                            showConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        formError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: loading ? null : submit,
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Restablecer'),
              ),
            ],
          );
        },
      );
    },
  );

  final correo = correoCtrl.text.trim();
  final nueva = newCtrl.text;
  correoCtrl.dispose();
  cedulaCtrl.dispose();
  newCtrl.dispose();
  confirmCtrl.dispose();

  if (ok == true && context.mounted) {
    AppFeedback.showInfo(
      context,
      message: 'Contrasena restablecida. Ya puedes iniciar sesion.',
    );
    onSuccess?.call(correo: correo, nuevaContrasena: nueva);
  }
}
