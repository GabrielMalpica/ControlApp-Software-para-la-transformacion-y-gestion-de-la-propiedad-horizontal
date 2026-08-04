import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/app_router.dart';

class PerfilAction extends StatelessWidget {
  final Color color;

  const PerfilAction({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Mi perfil',
      icon: Icon(Icons.person_outline, color: color),
      onPressed: () => Navigator.pushNamed(context, AppRouter.perfil),
    );
  }
}
