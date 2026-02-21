// lib/pages/gerente/crear_herramienta_page.dart
import 'package:flutter/material.dart';
import '../../api/herramienta_api.dart';
import '../../model/herramienta_model.dart';

import 'package:flutter_application_1/service/app_feedback.dart';
// Si ya tienes tu theme.dart y colores corporativos, puedes importar y usarlo.
// import '../../service/theme.dart';

class CrearHerramientaPage extends StatefulWidget {
  /// NIT de la empresa (o el id que uses en backend como empresaId)
  final String empresaId;

  const CrearHerramientaPage({super.key, required this.empresaId});

  @override
  State<CrearHerramientaPage> createState() => _CrearHerramientaPageState();
}

class _CrearHerramientaPageState extends State<CrearHerramientaPage> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _unidadCtrl = TextEditingController(text: "UNIDAD");
  final _vidaUtilCtrl = TextEditingController();
  final _umbralCtrl = TextEditingController();

  ModoControlHerramienta _modo = ModoControlHerramienta.PRESTAMO;

  bool _saving = false;
  final _api = HerramientaApi();

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _unidadCtrl.dispose();
    _vidaUtilCtrl.dispose();
    _umbralCtrl.dispose();
    super.dispose();
  }

  int? _parseIntNullable(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final req = HerramientaRequest(
        nombre: _nombreCtrl.text.trim(),
        unidad: _unidadCtrl.text.trim(),
        modoControl: _modo,
        vidaUtilDias: _parseIntNullable(_vidaUtilCtrl.text),
        umbralBajo: _parseIntNullable(_umbralCtrl.text),
      );

      // OJO: tu API pide empresaId en crearHerramienta
      await _api.crearHerramienta(
        empresaId: widget.empresaId,
        nombre: req.nombre,
        unidad: req.unidad,
        modoControl: req.modoControl.backendValue,
        vidaUtilDias: req.vidaUtilDias,
        umbralBajo: req.umbralBajo,
      );

      if (!mounted) return;

      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text("✅ Herramienta creada. A trabajar con estilo."),
        ),
      );

      Navigator.pop(
        context,
        true,
      ); // devuelve true para refrescar listado si quieres
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text("❌ ${e.toString()}")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = const SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(title: const Text("Crear herramienta")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // EmpresaId (solo lectura)
                _ReadOnlyField(label: "Empresa (NIT)", value: widget.empresaId),
                spacing,

                TextFormField(
                  controller: _nombreCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: "Nombre",
                    hintText: "Ej: Martillo, Alicate, Escoba...",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final s = (v ?? "").trim();
                    if (s.isEmpty) return "El nombre es obligatorio";
                    if (s.length < 2) return "Mínimo 2 caracteres";
                    return null;
                  },
                ),
                spacing,

                TextFormField(
                  controller: _unidadCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: "Unidad",
                    hintText: "UNIDAD",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final s = (v ?? "").trim();
                    if (s.isEmpty) return "La unidad es obligatoria";
                    return null;
                  },
                ),
                spacing,

                DropdownButtonFormField<ModoControlHerramienta>(
                  value: _modo,
                  decoration: const InputDecoration(
                    labelText: "Modo de control",
                    border: OutlineInputBorder(),
                  ),
                  items: ModoControlHerramienta.values.map((e) {
                    return DropdownMenuItem(value: e, child: Text(e.label));
                  }).toList(),
                  onChanged: (v) => setState(
                    () => _modo = v ?? ModoControlHerramienta.PRESTAMO,
                  ),
                ),
                spacing,

                // Campos opcionales en 2 columnas
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _vidaUtilCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: "Vida útil (días) (opcional)",
                          hintText: "Ej: 30",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = (v ?? "").trim();
                          if (s.isEmpty) return null;
                          final n = int.tryParse(s);
                          if (n == null) return "Debe ser un número";
                          if (n <= 0) return "Debe ser mayor a 0";
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _umbralCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: "Umbral bajo (opcional)",
                          hintText: "Ej: 2",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = (v ?? "").trim();
                          if (s.isEmpty) return null;
                          final n = int.tryParse(s);
                          if (n == null) return "Debe ser un número";
                          if (n < 0) return "No puede ser negativo";
                          return null;
                        },
                        onFieldSubmitted: (_) => _saving ? null : _guardar(),
                      ),
                    ),
                  ],
                ),
                spacing,

                // Nota/ayuda rápida
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Tip: Martillo/Alicate suelen ser “Préstamo”. Escoba/Trapeador va mejor como “Vida corta”.\n"
                    "Así tu inventario no se vuelve una novela de misterio cuando termine el contrato 😄",
                  ),
                ),
                spacing,

                ElevatedButton.icon(
                  onPressed: _saving ? null : _guardar,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? "Guardando..." : "Crear herramienta"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () {
            // Copiar sin dependencia extra (Clipboard está en services)
            // Si quieres, lo activamos con:
            // Clipboard.setData(ClipboardData(text: value));
            AppFeedback.showFromSnackBar(
              context,
              const SnackBar(
                content: Text("📋 Copia manual: Ctrl+C (modo pro)"),
              ),
            );
          },
        ),
      ),
    );
  }
}
