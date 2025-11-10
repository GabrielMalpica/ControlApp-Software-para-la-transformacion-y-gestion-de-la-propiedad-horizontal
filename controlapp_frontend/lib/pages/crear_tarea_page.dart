import 'package:flutter/material.dart';
import '../service/theme.dart';

class CrearTareaPage extends StatefulWidget {
  final String nit;
  const CrearTareaPage({super.key, required this.nit});

  @override
  State<CrearTareaPage> createState() => _CrearTareaPageState();
}

class _CrearTareaPageState extends State<CrearTareaPage> {
  final _formKey = GlobalKey<FormState>();

  // 🔹 Controladores
  final _descripcionCtrl = TextEditingController();
  final _duracionCtrl = TextEditingController();

  // 🔹 Fechas
  DateTime? fechaInicio;
  DateTime? fechaFin;

  // 🔹 Dropdowns
  int? ubicacionId;
  int? elementoId;
  int? supervisorId;

  // 🔹 Listas quemadas (simuladas)
  final List<Map<String, dynamic>> ubicaciones = [
    {"id": 1, "nombre": "Edificio Central"},
    {"id": 2, "nombre": "Parqueadero"},
    {"id": 3, "nombre": "Zona Verde"},
    {"id": 4, "nombre": "Área Administrativa"},
  ];

  final List<Map<String, dynamic>> elementos = [
    {"id": 1, "nombre": "Aire acondicionado"},
    {"id": 2, "nombre": "Ascensor"},
    {"id": 3, "nombre": "Portón eléctrico"},
    {"id": 4, "nombre": "Planta eléctrica"},
  ];

  final List<Map<String, dynamic>> supervisores = [
    {"id": 1, "nombre": "Carlos Pérez"},
    {"id": 2, "nombre": "Ana Gómez"},
    {"id": 3, "nombre": "Luis Rodríguez"},
    {"id": 4, "nombre": "Marta Fernández"},
  ];

  // 🔹 Seleccionar fechas
  Future<void> _seleccionarFechaInicio(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaInicio ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => fechaInicio = picked);
  }

  Future<void> _seleccionarFechaFin(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaFin ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => fechaFin = picked);
  }

  // 🔹 Guardar tarea (simulado)
  void _guardarTarea() {
    if (_formKey.currentState!.validate()) {
      final nuevaTarea = {
        "descripcion": _descripcionCtrl.text,
        "fechaInicio": fechaInicio?.toIso8601String(),
        "fechaFin": fechaFin?.toIso8601String(),
        "duracionHoras": int.tryParse(_duracionCtrl.text) ?? 0,
        "ubicacionId": ubicacionId,
        "elementoId": elementoId,
        "supervisorId": supervisorId,
        "nitProyecto": widget.nit,
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Tarea creada para NIT ${widget.nit}"),
          backgroundColor: AppTheme.green,
        ),
      );

      print("🧾 Tarea creada (local): $nuevaTarea");

      _formKey.currentState!.reset();
      setState(() {
        ubicacionId = null;
        elementoId = null;
        supervisorId = null;
        fechaInicio = null;
        fechaFin = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          "Crear Tarea - Proyecto ${widget.nit}",
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
              const Text(
                "Detalles de la Tarea",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),

              // 🔹 Descripción
              TextFormField(
                controller: _descripcionCtrl,
                decoration: const InputDecoration(
                  labelText: "Descripción de la tarea",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese una descripción' : null,
              ),
              const SizedBox(height: 16),

              // 🔹 Fecha inicio
              InkWell(
                onTap: () => _seleccionarFechaInicio(context),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Fecha de inicio",
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    fechaInicio == null
                        ? "Seleccionar fecha"
                        : "${fechaInicio!.day}/${fechaInicio!.month}/${fechaInicio!.year}",
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 🔹 Fecha fin
              InkWell(
                onTap: () => _seleccionarFechaFin(context),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Fecha de fin",
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    fechaFin == null
                        ? "Seleccionar fecha"
                        : "${fechaFin!.day}/${fechaFin!.month}/${fechaFin!.year}",
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 🔹 Duración
              TextFormField(
                controller: _duracionCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Duración (horas)",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese la duración en horas' : null,
              ),
              const SizedBox(height: 16),

              // 🔹 Ubicación
              DropdownButtonFormField<int>(
                value: ubicacionId,
                items: ubicaciones
                    .map<DropdownMenuItem<int>>(
                      (u) => DropdownMenuItem<int>(
                        value: u["id"] as int,
                        child: Text(u["nombre"] as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => ubicacionId = v),
                decoration: const InputDecoration(
                  labelText: "Ubicación",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null ? 'Seleccione una ubicación' : null,
              ),
              const SizedBox(height: 16),

              // 🔹 Elemento
              DropdownButtonFormField<int>(
                value: elementoId,
                items: elementos
                    .map<DropdownMenuItem<int>>(
                      (e) => DropdownMenuItem<int>(
                        value: e["id"] as int,
                        child: Text(e["nombre"] as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => elementoId = v),
                decoration: const InputDecoration(
                  labelText: "Elemento",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null ? 'Seleccione un elemento' : null,
              ),
              const SizedBox(height: 16),

              // 🔹 Supervisor
              DropdownButtonFormField<int>(
                value: supervisorId,
                items: supervisores
                    .map<DropdownMenuItem<int>>(
                      (s) => DropdownMenuItem<int>(
                        value: s["id"] as int,
                        child: Text(s["nombre"] as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => supervisorId = v),
                decoration: const InputDecoration(
                  labelText: "Supervisor",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null ? 'Seleccione un supervisor' : null,
              ),
              const SizedBox(height: 32),

              // 🔹 Botón Guardar
              ElevatedButton.icon(
                onPressed: _guardarTarea,
                icon: const Icon(Icons.save),
                label: const Text("Guardar Tarea"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
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
