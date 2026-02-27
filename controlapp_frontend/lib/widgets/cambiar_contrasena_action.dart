import 'package:flutter/material.dart';

import 'package:flutter_application_1/widgets/password_dialogs.dart';

class CambiarContrasenaAction extends StatelessWidget {
  final Color color;

  const CambiarContrasenaAction({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Cambiar contrasena',
      icon: Icon(Icons.lock_reset, color: color),
      onPressed: () => showChangePasswordDialog(context),
    );
  }
}
