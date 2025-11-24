import 'package:flutter/material.dart';
import '../../service/theme.dart';
import '../../model/conjunto_model.dart';

class CrearConjuntoPage extends StatefulWidget {
  final String nit;
  const CrearConjuntoPage({super.key, required this.nit});

  @override
  State<CrearConjuntoPage> createState() => _CrearConjuntoPageState();
}

class _CrearConjuntoPageState extends State<CrearConjuntoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _valorMensualCtrl = TextEditingController();

  List<TipoServicio> _serviciosSeleccionados = [];
  DateTime? _inicioContrato;
  DateTime? _finContrato;

  Future<void> _seleccionarFecha(BuildContext context, bool inicio) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (inicio) {
          _inicioContrato = picked;
        } else {
          _finContrato = picked;
        }
      });
    }
  }

  void _guardarConjunto() {
    if (!_formKey.currentState!.validate()) return;

    final conjunto = ConjuntoModel(
      nit: widget.nit,
      nombre: _nombreCtrl.text,
      direccion: _direccionCtrl.text,
      correo: _correoCtrl.text,
      fechaInicioContrato: _inicioContrato,
      fechaFinContrato: _finContrato,
      tipoServicio: _serviciosSeleccionados,
      valorMensual: double.tryParse(_valorMensualCtrl.text),
      activo: true,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✅ Conjunto creado correctamente"),
        backgroundColor: Colors.green,
      ),
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Conjunto creado"),
        content: Text(conjunto.toRawJson()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  Widget _checkboxServicio(TipoServicio tipo) {
    final isSelected = _serviciosSeleccionados.contains(tipo);
    return CheckboxListTile(
      title: Text(tipo.name),
      value: isSelected,
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _serviciosSeleccionados.add(tipo);
          } else {
            _serviciosSeleccionados.remove(tipo);
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          "Crear Conjunto - Proyecto ${widget.nit}",
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
              const Text("🏢 Registro de Nuevo Conjunto",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: "Nombre del conjunto",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese el nombre del conjunto' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _direccionCtrl,
                decoration: const InputDecoration(
                  labelText: "Dirección",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese la dirección' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _correoCtrl,
                decoration: const InputDecoration(
                  labelText: "Correo electrónico",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || !v.contains('@') ? 'Correo inválido' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _valorMensualCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Valor mensual del contrato",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _seleccionarFecha(context, true),
                    icon: const Icon(Icons.date_range),
                    label: Text(_inicioContrato == null
                        ? "Fecha inicio"
                        : "Inicio: ${_inicioContrato!.day}/${_inicioContrato!.month}/${_inicioContrato!.year}"),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _seleccionarFecha(context, false),
                    icon: const Icon(Icons.event),
                    label: Text(_finContrato == null
                        ? "Fecha fin"
                        : "Fin: ${_finContrato!.day}/${_finContrato!.month}/${_finContrato!.year}"),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text("🧩 Tipos de servicio contratados",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...TipoServicio.values.map(_checkboxServicio).toList(),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _guardarConjunto,
                icon: const Icon(Icons.save),
                label: const Text("Guardar Conjunto"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
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
