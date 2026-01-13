import 'package:flutter/material.dart';

import '../api/tarea_api.dart';
import '../model/tarea_model.dart';
import '../service/theme.dart';
import 'editar_tarea_page.dart';

class TareasPage extends StatefulWidget {
  final String nit; // NIT del conjunto

  const TareasPage({super.key, required this.nit});

  @override
  State<TareasPage> createState() => _TareasPageState();
}

class _TareasPageState extends State<TareasPage> {
  final TareaApi _tareaApi = TareaApi();

  bool _cargando = true;
  String? _error;
  List<TareaModel> _tareas = [];

  @override
  void initState() {
    super.initState();
    _cargarTareas();
  }

  Future<void> _cargarTareas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final lista = await _tareaApi.listarTareasPorConjunto(widget.nit);
      if (!mounted) return;
      setState(() {
        _tareas = lista;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // 🔹 Eliminar tarea (con confirmación)
  Future<void> _eliminarTarea(TareaModel tarea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text(
          '¿Seguro que deseas eliminar la tarea:\n\n"${tarea.descripcion}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // Ajusta el método según tu TareaApi
      await _tareaApi.eliminarTarea(tarea.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea eliminada correctamente')),
      );

      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar tarea: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------- Helpers de UI ----------

  Color _colorPorEstado(String? estado) {
    switch (estado) {
      case 'ASIGNADA':
        return Colors.orange;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'PENDIENTE_APROBACION':
        return Colors.deepPurple;
      case 'COMPLETADA':
        return Colors.green;
      case 'RECHAZADA':
      case 'CANCELADA':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _labelEstado(String? estado) {
    switch (estado) {
      case 'ASIGNADA':
        return 'Asignada';
      case 'EN_PROCESO':
        return 'En proceso';
      case 'PENDIENTE_APROBACION':
        return 'Pendiente aprobación';
      case 'COMPLETADA':
        return 'Completada';
      case 'RECHAZADA':
        return 'Rechazada';
      case 'CANCELADA':
        return 'Cancelada';
      default:
        return 'Sin estado';
    }
  }

  String _formatearFecha(DateTime f) {
    final d = f.day.toString().padLeft(2, '0');
    final m = f.month.toString().padLeft(2, '0');
    final y = f.year.toString();
    return '$d/$m/$y';
  }

  String _resumenOperarios(TareaModel t) {
    if (t.operariosIds != null && t.operariosIds!.isNotEmpty) {
      if (t.operariosIds!.length == 1) return '1 operario';
      return '${t.operariosIds!.length} operarios';
    }
    return 'Sin operarios asignados';
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: primary,
        title: Text(
          "Tareas - Conjunto ${widget.nit}",
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargarTareas, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text(
                'Error al cargar tareas:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarTareas,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tareas.isEmpty) {
      return const Center(
        child: Text(
          'No hay tareas asignadas para este conjunto.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarTareas,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _tareas.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final tarea = _tareas[index];
          final colorEstado = _colorPorEstado(tarea.estado);
          final labelEstado = _labelEstado(tarea.estado);

          return Card(
            margin: const EdgeInsets.only(bottom: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 3,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: colorEstado.withOpacity(0.15),
                child: Icon(Icons.assignment, color: colorEstado, size: 24),
              ),
              title: Text(
                tarea.descripcion,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "📅 ${_formatearFecha(tarea.fechaInicio)}"
                      " → ${_formatearFecha(tarea.fechaFin)}  "
                      "• ⏱ ${tarea.duracionMinutos} h",
                    ),
                    const SizedBox(height: 4),
                    Text("👷 Operarios: ${_resumenOperarios(tarea)}"),
                    if (tarea.supervisorNombre != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "🧑‍💼 Supervisor: ${tarea.supervisorNombre}",
                        ),
                      ),
                    if (tarea.observaciones != null &&
                        tarea.observaciones!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "📝 ${tarea.observaciones}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: colorEstado),
                        const SizedBox(width: 6),
                        Text(
                          labelEstado,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorEstado,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 👉 Botón de borrar a la derecha
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Eliminar tarea',
                onPressed: () => _eliminarTarea(tarea),
              ),
              // Tap para editar
              onTap: () async {
                final actualizado = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditarTareaPage(nit: widget.nit, tarea: tarea),
                  ),
                );

                if (actualizado == true) {
                  _cargarTareas();
                }
              },
            ),
          );
        },
      ),
    );
  }
}
