import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';

String _normalizeException(Object e, {required String fallback}) {
  return AppError.messageOf(e, fallback: fallback);
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
              width: (MediaQuery.sizeOf(ctx).width * 0.9).clamp(0, 380),
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
                style: AppTheme.saveButtonStyle,
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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

/// La recuperacion con correo + cedula se desactivo por seguridad (cualquiera
/// que conociera esos dos datos tomaba la cuenta). Ahora la restablece un
/// gerente o jefe de operaciones y al entrar se pide crear una nueva.
Future<void> showRecoverPasswordDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Recuperar acceso'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(dialogContext).width * 0.9).clamp(0, 380),
          child: const Text(
            'Por seguridad, la contraseña ya no se recupera desde aquí. '
            'Pide a tu gerente o jefe de operaciones que la restablezca en '
            'ControlApp. Te dará una contraseña temporal y, al entrar, la app '
            'te pedirá crear una nueva.',
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      );
    },
  );
}

Future<void> showManagerResetPasswordDialog(
  BuildContext context, {
  required String userId,
  required String nombreUsuario,
}) async {
  final authApi = AuthApi();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  bool loading = false;
  bool showNew = false;
  bool showConfirm = false;
  String? formError;

  String? validate() {
    final newPass = newCtrl.text;
    final confirm = confirmCtrl.text;
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
              await authApi.cambiarContrasenaUsuario(
                userId: userId,
                nuevaContrasena: newCtrl.text,
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(true);
            } catch (e) {
              if (!dialogContext.mounted) return;
              setModalState(
                () => formError = _normalizeException(
                  e,
                  fallback: 'No se pudo actualizar la contrasena del usuario.',
                ),
              );
            } finally {
              if (dialogContext.mounted) {
                setModalState(() => loading = false);
              }
            }
          }

          return AlertDialog(
            title: const Text('Actualizar contrasena del usuario'),
            content: SizedBox(
              width: (MediaQuery.sizeOf(ctx).width * 0.9).clamp(0, 380),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Define una nueva contrasena para $nombreUsuario.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                style: AppTheme.saveButtonStyle,
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );

  newCtrl.dispose();
  confirmCtrl.dispose();

  if (ok == true && context.mounted) {
    AppFeedback.showInfo(
      context,
      message:
          'Contraseña temporal asignada a $nombreUsuario. Sus sesiones abiertas '
          'se cerraron y deberá crear una nueva al entrar.',
    );
  }
}
