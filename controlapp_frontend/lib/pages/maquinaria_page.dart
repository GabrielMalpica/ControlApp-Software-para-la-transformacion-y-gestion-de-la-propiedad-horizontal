import 'package:flutter/material.dart';
import '../service/theme.dart';

class MaquinariaPage extends StatelessWidget {
  final String nit;
  const MaquinariaPage({super.key, required this.nit});

  @override
  Widget build(BuildContext context) {
    final maquinas = [
      {"nombre": "Aspiradora Industrial", "estado": "Operativa", "uso": "Zona A"},
      {"nombre": "Pulidora", "estado": "En reparación", "uso": "Zona B"},
      {"nombre": "Hidrolavadora", "estado": "Operativa", "uso": "Exteriores"},
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text("Maquinaria - Proyecto $nit", style: const TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView.builder(
          itemCount: maquinas.length,
          itemBuilder: (context, i) {
            final m = maquinas[i];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: Icon(Icons.precision_manufacturing, color: AppTheme.primary),
                title: Text(m['nombre']!),
                subtitle: Text("Uso actual: ${m['uso']}"),
                trailing: Text(
                  m['estado']!,
                  style: TextStyle(
                    color: m['estado'] == "Operativa" ? AppTheme.green : AppTheme.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
