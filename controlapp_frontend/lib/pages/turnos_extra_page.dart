import 'package:flutter/material.dart';

import '../api/asistencia_api.dart';
import '../model/asistencia_model.dart';
import '../service/app_error.dart';
import '../service/app_feedback.dart';
import '../service/theme.dart';

class TurnosExtraPage extends StatefulWidget {
  final String? conjuntoId;
  final String? conjuntoNombre;

  const TurnosExtraPage({super.key, this.conjuntoId, this.conjuntoNombre});

  @override
  State<TurnosExtraPage> createState() => _TurnosExtraPageState();
}

class _TurnosExtraPageState extends State<TurnosExtraPage> {
  final AsistenciaApi _api = AsistenciaApi();

  bool _cargando = true;
  String? _error;
  List<TurnoExtra> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final items = await _api.listarTurnosExtra(conjuntoId: widget.conjuntoId);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppError.messageOf(e, fallback: 'No se pudo cargar los turnos extra.'),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _crear() async {
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TurnoExtraSheet(
        conjuntoId: widget.conjuntoId,
        api: _api,
      ),
    );
    if (creado == true) _cargar();
  }

  Future<void> _eliminar(TurnoExtra t) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar turno extra'),
        content: Text('¿Eliminar el turno de ${t.operarioNombre} del ${t.fecha}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _api.eliminarTurnoExtra(t.id);
      if (!mounted) return;
      AppFeedback.showInfo(context, message: 'Turno extra eliminado.');
      _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo eliminar.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.conjuntoNombre != null
        ? 'Turnos extra · ${widget.conjuntoNombre}'
        : 'Turnos extra · Toda la empresa';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crear,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo turno'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _items.isEmpty
          ? const Center(child: Text('Sin turnos extra registrados.'))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final t = _items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text('${t.operarioNombre} · ${t.fecha}'),
                      subtitle: Text(
                        [
                          t.tipo,
                          if (t.conjuntoNombre != null) t.conjuntoNombre!,
                          if (t.esReemplazo) 'Reemplazo de ${t.reemplazadoNombre ?? "?"}',
                          if (t.motivo != null && t.motivo!.isNotEmpty) t.motivo!,
                          'Estado: ${t.estado}',
                        ].join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (t.valorNegociado != null)
                            Text('\$${t.valorNegociado!.toStringAsFixed(0)}'),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _eliminar(t),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _TurnoExtraSheet extends StatefulWidget {
  final String? conjuntoId;
  final AsistenciaApi api;

  const _TurnoExtraSheet({required this.conjuntoId, required this.api});

  @override
  State<_TurnoExtraSheet> createState() => _TurnoExtraSheetState();
}

class _TurnoExtraSheetState extends State<_TurnoExtraSheet> {
  final _operarioIdCtrl = TextEditingController();
  final _reemplazadoNombreCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  final _valorCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  String _tipo = 'TURNO';
  bool _esReemplazo = false;
  bool _guardando = false;

  @override
  void dispose() {
    _operarioIdCtrl.dispose();
    _reemplazadoNombreCtrl.dispose();
    _motivoCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (fecha != null) setState(() => _fecha = fecha);
  }

  Future<void> _guardar() async {
    if (_operarioIdCtrl.text.trim().isEmpty) {
      AppFeedback.showError(
        context,
        message: 'Ingresa la cedula del operario que hizo el turno.',
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      await widget.api.crearTurnoExtra(
        operarioId: _operarioIdCtrl.text.trim(),
        conjuntoId: widget.conjuntoId,
        fecha: _ymd(_fecha),
        tipo: _tipo,
        esReemplazo: _esReemplazo,
        reemplazadoNombreLibre: _esReemplazo && _reemplazadoNombreCtrl.text.trim().isNotEmpty
            ? _reemplazadoNombreCtrl.text.trim()
            : null,
        motivo: _motivoCtrl.text.trim().isEmpty ? null : _motivoCtrl.text.trim(),
        valorNegociado: double.tryParse(_valorCtrl.text.trim()),
      );
      if (!mounted) return;
      AppFeedback.showInfo(context, message: 'Turno extra registrado.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo registrar el turno.'),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nuevo turno extra / reemplazo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _operarioIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Cedula del operario',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _seleccionarFecha,
              child: Text('Fecha: ${_ymd(_fecha)}'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['TURNO', 'NOVENA', 'OTRO'].map((t) {
                return ChoiceChip(
                  label: Text(t),
                  selected: _tipo == t,
                  onSelected: (_) => setState(() => _tipo = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Es reemplazo de alguien'),
              value: _esReemplazo,
              onChanged: (v) => setState(() => _esReemplazo = v),
            ),
            if (_esReemplazo)
              TextField(
                controller: _reemplazadoNombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre de quien reemplaza (si no esta en el sistema)',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo (ej: salvavidas, apoyo pintura)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor negociado (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
