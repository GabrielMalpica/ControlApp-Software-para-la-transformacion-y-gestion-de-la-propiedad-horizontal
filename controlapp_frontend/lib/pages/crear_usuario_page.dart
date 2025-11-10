import 'package:flutter/material.dart';
import '../service/theme.dart';
import '../model/usuario_model.dart';

class CrearUsuarioPage extends StatefulWidget {
  final String nit;
  const CrearUsuarioPage({super.key, required this.nit});

  @override
  State<CrearUsuarioPage> createState() => _CrearUsuarioPageState();
}

class _CrearUsuarioPageState extends State<CrearUsuarioPage> {
  final _formKey = GlobalKey<FormState>();

  // 🔹 Controladores
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  // 🔹 Variables
  String? rolSeleccionado;
  String? estadoCivilSeleccionado;
  DateTime? fechaNacimiento;
  bool padresVivos = true;
  int numeroHijos = 0;

  // 🔹 Listas simuladas
  final List<String> roles = ['Operario', 'Supervisor', 'Administrador'];
  final List<String> estadosCiviles = ['Soltero', 'Casado', 'Divorciado', 'Viudo'];
  final List<String> tiposSangre = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+'];
  final List<String> epsDisponibles = ['Sanitas', 'Sura', 'Coomeva', 'Compensar'];
  final List<String> fondosPensiones = ['Colpensiones', 'Protección', 'Porvenir'];
  final List<String> tiposContrato = ['Fijo', 'Indefinido', 'Por obra'];
  final List<String> jornadas = ['Diurna', 'Nocturna', 'Mixta'];

  // 🔹 Campos extra
  String? tipoSangre, eps, fondo, tipoContrato, jornada;
  String? tallaCamisa, tallaPantalon, tallaCalzado;

  // 🔹 Seleccionar fecha
  Future<void> _seleccionarFecha(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaNacimiento ?? DateTime(1990),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => fechaNacimiento = picked);
  }

  // 🔹 Guardar usuario (modo local)
  void _guardarUsuario() {
    if (_formKey.currentState!.validate()) {
      final nuevoUsuario = Usuario(
        id: DateTime.now().millisecondsSinceEpoch,
        nombre: _nombreCtrl.text,
        correo: _correoCtrl.text,
        rol: rolSeleccionado ?? 'Sin rol',
        telefono: BigInt.parse(_telefonoCtrl.text),
        fechaNacimiento: fechaNacimiento ?? DateTime.now(),
        direccion: _direccionCtrl.text,
        estadoCivil: estadoCivilSeleccionado,
        numeroHijos: numeroHijos,
        padresVivos: padresVivos,
        tipoSangre: tipoSangre,
        eps: eps,
        fondoPensiones: fondo,
        tallaCamisa: tallaCamisa,
        tallaPantalon: tallaPantalon,
        tallaCalzado: tallaCalzado,
        tipoContrato: tipoContrato,
        jornadaLaboral: jornada,
      );

      print("👤 Usuario creado (local): ${nuevoUsuario.toJson()}");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Usuario registrado correctamente"),
          backgroundColor: Colors.green,
        ),
      );

      // Limpieza
      _formKey.currentState!.reset();
      setState(() {
        rolSeleccionado = null;
        estadoCivilSeleccionado = null;
        fechaNacimiento = null;
        tipoSangre = null;
        eps = null;
        fondo = null;
        tipoContrato = null;
        jornada = null;
        tallaCamisa = null;
        tallaPantalon = null;
        tallaCalzado = null;
        padresVivos = true;
        numeroHijos = 0;
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
          "Crear Usuario - Proyecto ${widget.nit}",
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
              const Text("🧑‍💼 Registro de Nuevo Usuario",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),

              // Nombre
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: "Nombre completo",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese el nombre completo' : null,
              ),
              const SizedBox(height: 12),

              // Correo
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

              // Teléfono
              TextFormField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Teléfono",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese un teléfono' : null,
              ),
              const SizedBox(height: 12),

              // Rol
              DropdownButtonFormField<String>(
                value: rolSeleccionado,
                items: roles
                    .map((r) =>
                        DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() => rolSeleccionado = v),
                decoration: const InputDecoration(
                  labelText: "Rol",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null ? 'Seleccione un rol' : null,
              ),
              const SizedBox(height: 12),

              // Fecha nacimiento
              InkWell(
                onTap: () => _seleccionarFecha(context),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Fecha de nacimiento",
                    border: OutlineInputBorder(),
                  ),
                  child: Text(fechaNacimiento == null
                      ? "Seleccionar fecha"
                      : "${fechaNacimiento!.day}/${fechaNacimiento!.month}/${fechaNacimiento!.year}"),
                ),
              ),
              const SizedBox(height: 12),

              // Estado civil
              DropdownButtonFormField<String>(
                value: estadoCivilSeleccionado,
                items: estadosCiviles
                    .map((e) =>
                        DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => estadoCivilSeleccionado = v),
                decoration: const InputDecoration(
                  labelText: "Estado civil",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Número de hijos
              Row(
                children: [
                  const Text("Número de hijos: "),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        if (numeroHijos > 0) numeroHijos--;
                      });
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text("$numeroHijos"),
                  IconButton(
                    onPressed: () {
                      setState(() => numeroHijos++);
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Padres vivos
              SwitchListTile(
                title: const Text("¿Padres vivos?"),
                value: padresVivos,
                onChanged: (v) => setState(() => padresVivos = v),
              ),
              const SizedBox(height: 12),

              // Tipo de sangre
              DropdownButtonFormField<String>(
                value: tipoSangre,
                items: tiposSangre
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => tipoSangre = v),
                decoration: const InputDecoration(
                  labelText: "Tipo de sangre",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // EPS
              DropdownButtonFormField<String>(
                value: eps,
                items: epsDisponibles
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => eps = v),
                decoration: const InputDecoration(
                  labelText: "EPS",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Fondo pensiones
              DropdownButtonFormField<String>(
                value: fondo,
                items: fondosPensiones
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setState(() => fondo = v),
                decoration: const InputDecoration(
                  labelText: "Fondo de pensiones",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Tipo contrato
              DropdownButtonFormField<String>(
                value: tipoContrato,
                items: tiposContrato
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => tipoContrato = v),
                decoration: const InputDecoration(
                  labelText: "Tipo de contrato",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Jornada laboral
              DropdownButtonFormField<String>(
                value: jornada,
                items: jornadas
                    .map((j) => DropdownMenuItem(value: j, child: Text(j)))
                    .toList(),
                onChanged: (v) => setState(() => jornada = v),
                decoration: const InputDecoration(
                  labelText: "Jornada laboral",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // Guardar
              ElevatedButton.icon(
                onPressed: _guardarUsuario,
                icon: const Icon(Icons.save),
                label: const Text("Guardar Usuario"),
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
