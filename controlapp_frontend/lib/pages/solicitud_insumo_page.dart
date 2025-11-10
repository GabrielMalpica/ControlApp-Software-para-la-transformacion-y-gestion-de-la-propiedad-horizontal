import 'package:flutter/material.dart';
import '../service/theme.dart';
import '../model/solicitud_insumo_model.dart';

class SolicitudInsumoPage extends StatefulWidget {
  final String nit;
  const SolicitudInsumoPage({super.key, required this.nit});

  @override
  State<SolicitudInsumoPage> createState() => _SolicitudInsumoPageState();
}

class _SolicitudInsumoPageState extends State<SolicitudInsumoPage> {
  final _formKey = GlobalKey<FormState>();
  final _motivoCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController();

  int? insumoSeleccionado;

  final List<Map<String, dynamic>> insumosDisponibles = [
    {"id": 1, "nombre": "Guantes de seguridad"},
    {"id": 2, "nombre": "Cascos protectores"},
    {"id": 3, "nombre": "Lámparas portátiles"},
    {"id": 4, "nombre": "Extintores"},
    {"id": 5, "nombre": "Chalecos reflectivos"},
  ];

  List<SolicitudInsumoItem> items = [];

  void _agregarItem() {
    if (insumoSeleccionado == null ||
        _cantidadCtrl.text.isEmpty ||
        int.tryParse(_cantidadCtrl.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Seleccione un insumo y cantidad válida."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      items.add(SolicitudInsumoItem(
        insumoId: insumoSeleccionado!,
        cantidad: int.parse(_cantidadCtrl.text),
      ));
      insumoSeleccionado = null;
      _cantidadCtrl.clear();
    });
  }

  void _enviarSolicitud() {
    if (_formKey.currentState!.validate() && items.isNotEmpty) {
      final solicitud = SolicitudInsumoModel(
        conjuntoId: widget.nit,
        empresaId: "EMPRESA123",
        items: items,
        fechaCreacion: DateTime.now(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Solicitud enviada (${solicitud.items.length} insumos)"),
          backgroundColor: AppTheme.green,
        ),
      );

      setState(() {
        items.clear();
        insumoSeleccionado = null;
        _cantidadCtrl.clear();
        _motivoCtrl.clear();
      });
    } else if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Agregue al menos un insumo a la solicitud."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          "Solicitud de Insumos - ${widget.nit}",
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("🧾 Nueva Solicitud de Insumos",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: insumoSeleccionado,
                items: insumosDisponibles
                    .map(
                      (i) => DropdownMenuItem<int>(
                        value: i["id"],
                        child: Text(i["nombre"]),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => insumoSeleccionado = v),
                decoration: const InputDecoration(
                  labelText: "Seleccione un insumo",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _cantidadCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Cantidad",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: _agregarItem,
                icon: const Icon(Icons.add),
                label: const Text("Agregar insumo a la lista"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),

              if (items.isNotEmpty)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 3,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                        ),
                        child: const Text(
                          "🧰 Insumos agregados",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...items.map((item) {
                        final insumo = insumosDisponibles
                            .firstWhere((i) => i["id"] == item.insumoId);
                        return ListTile(
                          title: Text(insumo["nombre"]),
                          subtitle: Text("Cantidad: ${item.cantidad}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                setState(() => items.remove(item)),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _motivoCtrl,
                decoration: const InputDecoration(
                  labelText: "Motivo de la solicitud",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese el motivo' : null,
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _enviarSolicitud,
                icon: const Icon(Icons.send),
                label: const Text("Enviar Solicitud"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
