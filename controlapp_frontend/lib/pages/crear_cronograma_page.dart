// crear_cronograma_page.dart
import 'package:flutter/material.dart';

class CrearCronogramaPage extends StatelessWidget {
  final String nit;
  const CrearCronogramaPage({super.key, required this.nit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Crear Cronograma")),
      body: Center(child: Text("Formulario para crear cronograma del proyecto $nit")),
    );
  }
}
