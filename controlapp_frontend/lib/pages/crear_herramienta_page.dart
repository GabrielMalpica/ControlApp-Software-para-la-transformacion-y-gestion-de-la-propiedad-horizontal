import 'package:flutter/material.dart';

import '../api/herramienta_api.dart';
import '../model/herramienta_model.dart';
import '../service/app_constants.dart';
import '../service/theme.dart';
import 'package:flutter_application_1/service/app_feedback.dart';

class CrearHerramientaPage extends StatefulWidget {
  final String? empresaId;

  const CrearHerramientaPage({super.key, this.empresaId});

  @override
  State<CrearHerramientaPage> createState() => _CrearHerramientaPageState();
}

class _CrearHerramientaPageState extends State<CrearHerramientaPage> {
  static const List<String> _unidadesHerramienta = [
    'unidad',
    'juego',
    'kit',
    'set',
    'par',
    'caja',
    'paquete',
    'rollo',
    'metro',
  ];

  final _formKey = GlobalKey<FormState>();
  final _api = HerramientaApi();

  final _nombreCtrl = TextEditingController();
  final _vidaUtilCtrl = TextEditingController();
  final _umbralCtrl = TextEditingController();
  final _stockInicialCtrl = TextEditingController(text: '0');

  ModoControlHerramienta _modo = ModoControlHerramienta.PRESTAMO;
  CategoriaHerramienta _categoria = CategoriaHerramienta.OTROS;
  String _unidad = 'unidad';
  bool _saving = false;

  String get _empresaId => widget.empresaId ?? AppConstants.empresaNit;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _vidaUtilCtrl.dispose();
    _umbralCtrl.dispose();
    _stockInicialCtrl.dispose();
    super.dispose();
  }

  int? _parseIntNullable(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  num _parseNum(String value) => num.tryParse(value.trim()) ?? 0;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final creada = await _api.crearHerramienta(
        empresaId: _empresaId,
        nombre: _nombreCtrl.text.trim(),
        unidad: _unidad,
        categoria: _categoria.backendValue,
        modoControl: _modo.backendValue,
        vidaUtilDias: _parseIntNullable(_vidaUtilCtrl.text),
        umbralBajo: _parseIntNullable(_umbralCtrl.text),
      );

      final stockInicial = _parseNum(_stockInicialCtrl.text);
      final herramientaId = (creada['id'] as num?)?.toInt();

      if (herramientaId != null && stockInicial > 0) {
        await _api.upsertStockEmpresa(
          empresaId: _empresaId,
          herramientaId: herramientaId,
          cantidad: stockInicial,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Herramienta creada en el catalogo.')),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('No se pudo crear la herramienta: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva herramienta de empresa'),
        backgroundColor: AppTheme.primary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionCard(
                  title: 'Catalogo base',
                  subtitle:
                      'Aqui registras el tipo de herramienta para la empresa. Luego decides si queda en stock de empresa o como herramienta propia del conjunto.',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          hintText: 'Ej: Martillo, escoba, taladro',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return 'El nombre es obligatorio';
                          if (text.length < 2) return 'Minimo 2 caracteres';
                          return null;
                        },
                      ),
                      gap,
                      DropdownButtonFormField<String>(
                        initialValue: _unidad,
                        decoration: const InputDecoration(
                          labelText: 'Unidad de medida',
                          helperText:
                              'Es la forma estandar en que se contara esta herramienta.',
                          border: OutlineInputBorder(),
                        ),
                        items: _unidadesHerramienta
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _unidad = value);
                        },
                      ),
                      gap,
                      DropdownButtonFormField<CategoriaHerramienta>(
                        initialValue: _categoria,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          border: OutlineInputBorder(),
                        ),
                        items: CategoriaHerramienta.values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _categoria = value ?? _categoria),
                      ),
                    ],
                  ),
                ),
                gap,
                _SectionCard(
                  title: 'Comportamiento',
                  subtitle:
                      'Define si la herramienta se presta y vuelve, o si solo se controla por cantidad.',
                  child: Column(
                    children: [
                      DropdownButtonFormField<ModoControlHerramienta>(
                        initialValue: _modo,
                        decoration: const InputDecoration(
                          labelText: 'Como se controla',
                          border: OutlineInputBorder(),
                        ),
                        items: ModoControlHerramienta.values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(
                          () => _modo = value ?? ModoControlHerramienta.PRESTAMO,
                        ),
                      ),
                      gap,
                      _ModeSummary(mode: _modo),
                    ],
                  ),
                ),
                gap,
                _SectionCard(
                  title: 'Stock inicial de empresa',
                  subtitle:
                      'Este stock queda en la empresa. Los conjuntos reciben herramientas despues, como propias o prestadas.',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _stockInicialCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cantidad inicial en empresa',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = num.tryParse((value ?? '').trim());
                          if (parsed == null) return 'Ingresa un numero valido';
                          if (parsed < 0) return 'No puede ser negativo';
                          return null;
                        },
                      ),
                      gap,
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _vidaUtilCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Vida util en dias',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) return null;
                                final parsed = int.tryParse(text);
                                if (parsed == null || parsed <= 0) {
                                  return 'Numero invalido';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _umbralCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Alerta de stock bajo',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) return null;
                                final parsed = int.tryParse(text);
                                if (parsed == null || parsed < 0) {
                                  return 'Numero invalido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                gap,
                FilledButton.icon(
                  onPressed: _saving ? null : _guardar,
                  style: AppTheme.saveButtonStyle,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving ? 'Guardando...' : 'Crear herramienta en empresa',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ModeSummary extends StatelessWidget {
  final ModoControlHerramienta mode;

  const _ModeSummary({required this.mode});

  @override
  Widget build(BuildContext context) {
    final examples = switch (mode) {
      ModoControlHerramienta.PRESTAMO =>
        'Ejemplos: taladro, pulidora, guadana manual.',
      ModoControlHerramienta.CONSUMO =>
        'Ejemplos: bolsas, guantes desechables, repuestos por cantidad.',
      ModoControlHerramienta.VIDA_CORTA =>
        'Ejemplos: escoba, trapeador, cepillos o elementos que se reemplazan por desgaste.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mode.label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(mode.descripcion),
          const SizedBox(height: 6),
          Text(examples, style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
