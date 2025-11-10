import 'package:flutter/material.dart';
import '../service/theme.dart';

class SolicitudesPage extends StatefulWidget {
  final String nit;
  const SolicitudesPage({super.key, required this.nit});

  @override
  State<SolicitudesPage> createState() => _SolicitudesPageState();
}

class _SolicitudesPageState extends State<SolicitudesPage> {
  final List<Map<String, dynamic>> solicitudes = [
    {
      'id': 'SOL-001',
      'tipo': 'Insumos',
      'descripcion': 'Solicitud de cemento y arena',
      'estado': 'Pendiente',
      'fecha': '2025-10-20'
    },
    {
      'id': 'SOL-002',
      'tipo': 'Maquinaria',
      'descripcion': 'Petición de retroexcavadora',
      'estado': 'Aprobada',
      'fecha': '2025-10-21'
    },
    {
      'id': 'SOL-003',
      'tipo': 'Insumos',
      'descripcion': 'Pintura y brochas para muro sur',
      'estado': 'Rechazada',
      'fecha': '2025-10-25'
    },
  ];

  Color _estadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'pendiente':
        return Colors.orange;
      case 'aprobada':
        return Colors.green;
      case 'rechazada':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          "Solicitudes - Proyecto ${widget.nit}",
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: solicitudes.length,
        itemBuilder: (context, index) {
          final s = solicitudes[index];
          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            child: ListTile(
              leading: Icon(
                s['tipo'] == 'Insumos'
                    ? Icons.shopping_cart
                    : Icons.precision_manufacturing,
                color: AppTheme.primary,
              ),
              title: Text(s['descripcion']),
              subtitle: Text("Fecha: ${s['fecha']}  |  Tipo: ${s['tipo']}"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _estadoColor(s['estado']).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s['estado'],
                  style: TextStyle(
                    color: _estadoColor(s['estado']),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              onTap: () {
                _mostrarDetallesSolicitud(s);
              },
            ),
          );
        },
      ),
    );
  }

  void _mostrarDetallesSolicitud(Map<String, dynamic> solicitud) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Detalles de ${solicitud['id']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Tipo: ${solicitud['tipo']}"),
            Text("Descripción: ${solicitud['descripcion']}"),
            Text("Estado: ${solicitud['estado']}"),
            Text("Fecha: ${solicitud['fecha']}"),
          ],
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
}
