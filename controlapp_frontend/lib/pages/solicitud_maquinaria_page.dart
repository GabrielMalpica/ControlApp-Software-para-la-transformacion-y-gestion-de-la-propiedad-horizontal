import 'package:flutter/material.dart';
import '../service/theme.dart';
import '../model/maquinaria_model.dart';

class SolicitudMaquinariaPage extends StatefulWidget {
  final String nit;
  const SolicitudMaquinariaPage({super.key, required this.nit});

  @override
  State<SolicitudMaquinariaPage> createState() => _SolicitudMaquinariaPageState();
}

class _SolicitudMaquinariaPageState extends State<SolicitudMaquinariaPage> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _marcaController = TextEditingController();
  final _tipoController = TextEditingController();
  final _estadoController = TextEditingController();

  DateTime? _fechaPrestamo;
  DateTime? _fechaDevolucion;

  Future<void> _seleccionarFecha(bool esPrestamo) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (esPrestamo) {
          _fechaPrestamo = picked;
        } else {
          _fechaDevolucion = picked;
        }
      });
    }
  }

  // void _guardarSolicitud() {
  //   if (!_formKey.currentState!.validate()) return;

  //   final maquinaria = Maquinaria(
  //     id: 1,
  //     nombre: _nombreController.text,
  //     marca: _marcaController.text,
  //     tipo: _tipoController.text,
  //     estado: _estadoController.text,
  //     disponible: true,
  //     conjuntoId: widget.nit,
  //     fechaPrestamo: _fechaPrestamo,
  //     fechaDevolucionEstimada: _fechaDevolucion,
  //   );

  //   showDialog(
  //     context: context,
  //     builder: (_) => AlertDialog(
  //       title: const Text("Solicitud creada"),
  //       content: Text(maquinaria.toJson().toString()),
  //       actions: [
  //         TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar")),
  //       ],
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Solicitud de Maquinaria"),
        backgroundColor: AppTheme.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: "Nombre de la maquinaria"),
                validator: (v) => v!.isEmpty ? "Campo requerido" : null,
              ),
              TextFormField(
                controller: _marcaController,
                decoration: const InputDecoration(labelText: "Marca"),
              ),
              TextFormField(
                controller: _tipoController,
                decoration: const InputDecoration(labelText: "Tipo"),
              ),
              TextFormField(
                controller: _estadoController,
                decoration: const InputDecoration(labelText: "Estado"),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: () => _seleccionarFecha(true),
                    child: Text(_fechaPrestamo == null
                        ? "Fecha préstamo"
                        : "Prestamo: ${_fechaPrestamo!.toLocal()}".split(' ')[0]),
                  ),
                  ElevatedButton(
                    onPressed: () => _seleccionarFecha(false),
                    child: Text(_fechaDevolucion == null
                        ? "Fecha devolución"
                        : "Devolución: ${_fechaDevolucion!.toLocal()}".split(' ')[0]),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ElevatedButton.icon(
              //   onPressed: _guardarSolicitud,
              //   icon: const Icon(Icons.save),
              //   label: const Text("Enviar Solicitud"),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
