import 'package:flutter/material.dart';
import '../service/theme.dart';
import 'inventario_page.dart';
import 'solicitud_insumo_page.dart';

class AdministradorPage extends StatefulWidget {
  final String nit;
  const AdministradorPage({super.key, required this.nit});

  @override
  State<AdministradorPage> createState() => _AdministradorPageState();
}

class _AdministradorPageState extends State<AdministradorPage> {
  /// 🔹 Tarjeta simple (solo Inventario)
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

  /// 🔹 Atajo (solo solicitud de insumo)
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
          // ElevatedButton.icon(
          //   onPressed: () {
          //     Navigator.push(
          //       context,
          //       MaterialPageRoute(builder: (_) => SolicitudInsumoPage(nit: widget.nit)),
          //     );
          //   },
          //   icon: const Icon(Icons.add_shopping_cart),
          //   label: const Text("Solicitud Insumo"),
          // ),
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
        title: Text("Panel Administrador - Proyecto ${widget.nit}",
            style: const TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Solo Inventario
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _simpleCard("Inventario", AppTheme.yellow, Icons.inventory, onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => InventarioPage(nit: widget.nit)));
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
