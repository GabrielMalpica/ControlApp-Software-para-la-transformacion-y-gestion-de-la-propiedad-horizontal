
// reportes_page.dart
import 'package:flutter/material.dart';

class ReportesPage extends StatelessWidget {
  final String nit;
  const ReportesPage({super.key, required this.nit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reportes")),
      body: Center(child: Text("Reportes del proyecto con NIT: $nit")),
    );
  }
}