import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CronogramaPage extends StatelessWidget {
  final String nit;
  const CronogramaPage({super.key, required this.nit});

  // 🔹 Datos de ejemplo
  Map<int, List<String>> getTareasEjemplo() {
    return {
      1: ["Inspección general", "Reunión operativa"],
      3: ["Mantenimiento de ascensores"],
      5: ["Limpieza de fachada", "Cambio de luminarias"],
      8: ["Revisión cámaras de seguridad"],
      10: ["Capacitación de operarios"],
      12: ["Visita del supervisor"],
      15: ["Informe de avances"],
      18: ["Reparación de portón"],
      20: ["Reunión con proveedor de aseo"],
      22: ["Inspección zonas verdes"],
      25: ["Revisión de bombas de agua"],
      28: ["Cierre mensual", "Entrega de reportes"],
    };
  }

  @override
  Widget build(BuildContext context) {
    final tareasPorDia = getTareasEjemplo();
    final now = DateTime.now();
    final mes = DateFormat.MMMM('es').format(now).toUpperCase();
    final year = now.year;
    final totalDias = DateUtils.getDaysInMonth(now.year, now.month);

    // 🔹 Detectar tamaño de pantalla (móvil, tablet o web)
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth < 600
        ? 7 // teléfonos
        : screenWidth < 1000
            ? 10 // tablets
            : 14; // web / escritorio

    return Scaffold(
      appBar: AppBar(
        title: Text("Cronograma - $mes $year"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // 🔹 Cabecera con mes y leyenda
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Tareas del mes",
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      _buildLegend(Colors.deepPurple.withOpacity(0.2), "Con tareas"),
                      const SizedBox(width: 8),
                      _buildLegend(Colors.grey.shade200, "Sin tareas"),
                    ],
                  ),
                ],
              ),
            ),

            // 🔹 Contenedor del calendario
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 1, // cuadrado
                ),
                itemCount: totalDias,
                itemBuilder: (context, index) {
                  final dia = index + 1;
                  final tareas = tareasPorDia[dia];

                  return GestureDetector(
                    onTap: () {
                      if (tareas != null) {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text("Tareas del $dia de $mes"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: tareas
                                  .map((t) => ListTile(
                                        leading: const Icon(Icons.task_alt,
                                            color: Colors.green),
                                        title: Text(t),
                                      ))
                                  .toList(),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Cerrar"),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: tareas != null
                            ? Colors.deepPurple.withOpacity(0.15)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: tareas != null
                              ? Colors.deepPurple
                              : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dia.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (tareas != null)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(Icons.event_note,
                                  size: 18, color: Colors.deepPurple),
                            ),
                        ],
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

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
