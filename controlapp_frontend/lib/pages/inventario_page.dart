import 'package:flutter/material.dart';
import '../service/theme.dart';

class InventarioPage extends StatelessWidget {
  final String nit;
  const InventarioPage({super.key, required this.nit});

  @override
  Widget build(BuildContext context) {
    // 🔹 Datos simulados de inventario
    final List<Map<String, dynamic>> inventario = [
      {"item": "Detergente", "stock": 15, "estado": "Suficiente"},
      {"item": "Traperos", "stock": 4, "estado": "Bajo"},
      {"item": "Guantes", "stock": 30, "estado": "Suficiente"},
      {"item": "Escobas", "stock": 2, "estado": "Bajo"},
      {"item": "Lustradora", "stock": 1, "estado": "Suficiente"},
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        elevation: 0,
        title: Text(
          "Inventario - Proyecto $nit",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Listado de insumos",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: inventario.length,
                itemBuilder: (context, i) {
                  final inv = [i] as Map<String, dynamic>;
                  final item = inv['item']?.toString() ?? '';
                  final stock = inv['stock']?.toString() ?? '0';
                  final estado = inv['estado']?.toString() ?? '';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: Icon(Icons.inventory_2_outlined, color: AppTheme.primary),
                      title: Text(item, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text("Stock: $stock unidades"),
                      trailing: Text(
                        estado,
                        style: TextStyle(
                          color: estado == "Bajo" ? AppTheme.red : AppTheme.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
