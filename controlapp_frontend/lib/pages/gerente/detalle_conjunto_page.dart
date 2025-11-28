import 'package:flutter/material.dart';
import '../../service/theme.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';

class DetalleConjuntoPage extends StatefulWidget {
  final String conjuntoNit;
  final bool modoEdicionBasico; // si vienes desde el lápiz

  const DetalleConjuntoPage({
    super.key,
    required this.conjuntoNit,
    this.modoEdicionBasico = false,
  });

  @override
  State<DetalleConjuntoPage> createState() => _DetalleConjuntoPageState();
}

class _DetalleConjuntoPageState extends State<DetalleConjuntoPage> {
  final GerenteApi _api = GerenteApi();
  late Future<Conjunto> _futureConjunto;

  // para edición básica (nombre/dirección/correo/valorMensual/activo)
  final _nombreCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _valorMensualCtrl = TextEditingController();
  bool _activo = true;
  bool _editMode = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _editMode = widget.modoEdicionBasico;
    _loadConjunto();
  }

  void _loadConjunto() {
    _futureConjunto = _api.obtenerConjunto(widget.conjuntoNit);
  }

  void _inicializarForm(Conjunto c) {
    _nombreCtrl.text = c.nombre;
    _direccionCtrl.text = c.direccion;
    _correoCtrl.text = c.correo;
    _valorMensualCtrl.text = c.valorMensual != null
        ? c.valorMensual!.toStringAsFixed(0)
        : '';
    _activo = c.activo;
  }

  Future<void> _guardarCambios(Conjunto c) async {
    setState(() => _saving = true);
    try {
      double? valor;
      if (_valorMensualCtrl.text.trim().isNotEmpty) {
        valor = double.tryParse(_valorMensualCtrl.text.trim());
      }

      await _api.actualizarConjunto(
        c.nit,
        nombre: _nombreCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        correo: _correoCtrl.text.trim(),
        activo: _activo,
        valorMensual: valor,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Conjunto actualizado'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _editMode = false;
        _loadConjunto();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al actualizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _correoCtrl.dispose();
    _valorMensualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          'Detalle Conjunto ${widget.conjuntoNit}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _editMode ? Icons.close : Icons.edit,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _editMode = !_editMode;
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<Conjunto>(
        future: _futureConjunto,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final c = snapshot.data!;
          if (_editMode && _nombreCtrl.text.isEmpty) {
            // primer vez que entro en modo edición, lleno los campos
            _inicializarForm(c);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // DATOS BÁSICOS
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _editMode
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Datos generales',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'NIT: ${c.nit}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nombreCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _direccionCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Dirección',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _correoCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Correo',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _valorMensualCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Valor mensual',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                title: const Text('Activo'),
                                value: _activo,
                                onChanged: (v) => setState(() => _activo = v),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _saving
                                      ? null
                                      : () => _guardarCambios(c),
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save),
                                  label: Text(
                                    _saving ? 'Guardando...' : 'Guardar',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Datos generales',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('NIT: ${c.nit}'),
                              Text('Nombre: ${c.nombre}'),
                              Text('Dirección: ${c.direccion}'),
                              Text('Correo: ${c.correo}'),
                              const SizedBox(height: 6),
                              Text(
                                'Estado: ${c.activo ? 'Activo' : 'Inactivo'}',
                                style: TextStyle(
                                  color: c.activo
                                      ? Colors.green
                                      : Colors.redAccent,
                                ),
                              ),
                              if (c.valorMensual != null)
                                Text(
                                  'Valor mensual: \$${c.valorMensual!.toStringAsFixed(0)}',
                                ),
                              if (c.fechaInicioContrato != null)
                                Text(
                                  'Inicio contrato: '
                                  '${c.fechaInicioContrato!.day}/${c.fechaInicioContrato!.month}/${c.fechaInicioContrato!.year}',
                                ),
                              if (c.fechaFinContrato != null)
                                Text(
                                  'Fin contrato: '
                                  '${c.fechaFinContrato!.day}/${c.fechaFinContrato!.month}/${c.fechaFinContrato!.year}',
                                ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // ADMIN / OPERARIOS
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Equipo asignado',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Administrador: ${c.administradorNombre ?? 'No asignado'}',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Operarios:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        if (c.operarios.isEmpty)
                          const Text(
                            'Sin operarios asignados.',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          Column(
                            children: c.operarios
                                .map(
                                  (o) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.person),
                                    title: Text(o.nombre),
                                    subtitle: Text('CC: ${o.cedula}'),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // HORARIOS
                if (c.horarios.isNotEmpty)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Horarios',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children: c.horarios
                                .map(
                                  (h) => Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(h.dia),
                                      Text(
                                        '${h.horaApertura} - ${h.horaCierre}',
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // UBICACIONES
                if (c.ubicaciones.isNotEmpty)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'Ubicaciones y elementos',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          ...c.ubicaciones.map(
                            (u) => ExpansionTile(
                              title: Text(u.nombre),
                              children: u.elementos.isEmpty
                                  ? [
                                      const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text(
                                          'Sin elementos registrados.',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    ]
                                  : u.elementos
                                        .map(
                                          (e) => ListTile(
                                            dense: true,
                                            leading: const Icon(
                                              Icons.circle,
                                              size: 10,
                                            ),
                                            title: Text(e.nombre),
                                          ),
                                        )
                                        .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // CONSIGNAS / VALOR AGREGADO
                if (c.consignasEspeciales.isNotEmpty ||
                    c.valorAgregado.isNotEmpty)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (c.consignasEspeciales.isNotEmpty) ...[
                            const Text(
                              'Consignas especiales',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...c.consignasEspeciales.map(
                              (txt) => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• '),
                                  Expanded(child: Text(txt)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (c.valorAgregado.isNotEmpty) ...[
                            const Text(
                              'Valor agregado',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...c.valorAgregado.map(
                              (txt) => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• '),
                                  Expanded(child: Text(txt)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
