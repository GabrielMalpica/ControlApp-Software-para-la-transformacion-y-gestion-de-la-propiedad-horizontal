import 'package:flutter/material.dart';
import '../service/theme.dart';
import 'tareas_page.dart';
import 'solicitudes_page.dart';
import 'solicitud_insumo_page.dart';

class OperarioDashboardPage extends StatefulWidget {
  final String nit;
  const OperarioDashboardPage({super.key, required this.nit});

  @override
  State<OperarioDashboardPage> createState() => _OperarioDashboardPageState();
}

class _OperarioDashboardPageState extends State<OperarioDashboardPage> {
  /// 🔹 Tarjeta simple
  Widget _simpleCard(String title, Color color, IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black12.withOpacity(0.05), blurRadius: 5),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 Sección de atajos (sin crear tarea, solo solicitud insumo)
  Widget _atajos() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12.withOpacity(0.05), blurRadius: 5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Atajos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => SolicitudInsumoPage(nit: widget.nit),
              ));
            },
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text("Solicitud Insumo"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text("Panel Operario - Proyecto ${widget.nit}",
            style: const TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Paneles principales (solo tareas y solicitudes)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _simpleCard("Tareas", AppTheme.green, Icons.assignment, onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => TareasPage(nit: widget.nit)));
                }),
                _simpleCard("Solicitudes", AppTheme.primary, Icons.pending_actions, onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SolicitudesPage(nit: widget.nit)));
                }),
              ],
            ),

            const SizedBox(height: 20),
            _atajos(),
          ],
        ),
      ),
    );
  }
}
