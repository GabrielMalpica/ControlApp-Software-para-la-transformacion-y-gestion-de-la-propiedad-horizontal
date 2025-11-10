import 'package:flutter/material.dart';
import '../service/theme.dart';
import 'crear_tarea_page.dart';
import 'solicitud_insumo_page.dart';
import 'tareas_page.dart';
import 'solicitudes_page.dart';
import 'cronograma_page.dart';
import 'crear_cronograma_page.dart';

class SupervisorPage extends StatefulWidget {
  const SupervisorPage({super.key});

  @override
  State<SupervisorPage> createState() => _SupervisorPageState();
}

class _SupervisorPageState extends State<SupervisorPage> {
  final List<String> proyectos = ['Proyecto 1', 'Proyecto 2', 'Proyecto 3'];
  String proyectoSeleccionado = 'Proyecto 1';

  final Map<String, dynamic> dataPorProyecto = {
    'Proyecto 1': {'nit': '1111'},
    'Proyecto 2': {'nit': '2222'},
    'Proyecto 3': {'nit': '3333'},
  };

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

  /// 🔹 Sección de atajos (crear tarea, solicitud y cronograma)
  Widget _atajos() {
    final nit = dataPorProyecto[proyectoSeleccionado]['nit'];
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CrearTareaPage(nit: nit)));
                },
                icon: const Icon(Icons.assignment_add),
                label: const Text("Crear Tarea"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SolicitudInsumoPage(nit: nit)));
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text("Solicitud Insumo"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CrearCronogramaPage(nit: nit)));
                },
                icon: const Icon(Icons.calendar_today),
                label: const Text("Crear Cronograma"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nit = dataPorProyecto[proyectoSeleccionado]['nit'];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text("Panel Supervisor", style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Selector de proyecto
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Seleccionar proyecto:", style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: proyectoSeleccionado,
                  items: proyectos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: (v) => setState(() => proyectoSeleccionado = v!),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 🔹 Paneles principales (sin maquinaria ni inventario)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _simpleCard("Tareas", AppTheme.green, Icons.assignment, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TareasPage(nit: nit)));
                }),
                _simpleCard("Solicitudes", AppTheme.primary, Icons.pending_actions, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SolicitudesPage(nit: nit)));
                }),
                _simpleCard("Cronograma", Colors.purple, Icons.calendar_month, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CronogramaPage(nit: nit)));
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
