import 'package:flutter/material.dart';
import '../service/theme.dart';

class TareasPage extends StatelessWidget {
  final String nit;
  const TareasPage({super.key, required this.nit});

  @override
  Widget build(BuildContext context) {
    // 🔹 Lista simulada de tareas (información quemada)
    final List<Map<String, dynamic>> tareas = [
      {
        "titulo": "Revisión de maquinaria pesada",
        "descripcion": "Verificar niveles de aceite y frenos.",
        "estado": "En proceso",
        "responsable": "Carlos Pérez"
      },
      {
        "titulo": "Limpieza de zona A",
        "descripcion": "Asegurar área libre de residuos.",
        "estado": "Pendiente",
        "responsable": "Laura Gómez"
      },
      {
        "titulo": "Mantenimiento eléctrico",
        "descripcion": "Revisar cableado y tableros.",
        "estado": "Completada",
        "responsable": "Andrés Ruiz"
      },
      {
        "titulo": "Instalación de señalización",
        "descripcion": "Colocar nuevas señales de seguridad.",
        "estado": "En proceso",
        "responsable": "Marta Torres"
      },
    ];

    Color _colorPorEstado(String estado) {
      switch (estado) {
        case "Pendiente":
          return Colors.orange;
        case "En proceso":
          return Colors.blue;
        case "Completada":
          return Colors.green;
        default:
          return Colors.grey;
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          "Tareas - Proyecto $nit",
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tareas.length,
        itemBuilder: (context, index) {
          final tarea = tareas[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 3,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Icon(
                Icons.assignment,
                color: _colorPorEstado(tarea["estado"]),
                size: 32,
              ),
              title: Text(
                tarea["titulo"],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tarea["descripcion"]),
                    const SizedBox(height: 4),
                    Text("👷 Responsable: ${tarea["responsable"]}"),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 10),
                        const SizedBox(width: 6),
                        Text(
                          tarea["estado"],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _colorPorEstado(tarea["estado"]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
