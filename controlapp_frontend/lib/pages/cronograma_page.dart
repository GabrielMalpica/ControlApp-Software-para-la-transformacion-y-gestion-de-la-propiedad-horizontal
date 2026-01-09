import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/cronograma_api.dart';
import '../model/tarea_model.dart';
import '../service/theme.dart';

class CronogramaPage extends StatefulWidget {
  final String nit;

  const CronogramaPage({super.key, required this.nit});

  @override
  State<CronogramaPage> createState() => _CronogramaPageState();
}

class _CronogramaPageState extends State<CronogramaPage> {
  final _api = CronogramaApi();

  DateTime _mesActual = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  ); // primer día del mes
  bool _cargando = false;
  String? _error;

  List<TareaModel> _tareas = [];
  Map<int, List<TareaModel>> _tareasPorDia = {};

  // Filtros
  String _filtroTipo = 'TODAS'; // TODAS / PREVENTIVA / CORRECTIVA
  String _filtroEstado = 'TODOS'; // TODOS o EstadoTarea.*

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
      final tareas = await _api.listarPorConjuntoYMes(
        nit: widget.nit,
        anio: _mesActual.year,
        mes: _mesActual.month,
      );

      _tareas = tareas;
      _reconstruirMapa();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _cargando = false;
      });
    }
  }

  void _reconstruirMapa() {
    final mapa = <int, List<TareaModel>>{};

    for (final t in _tareas) {
      // Filtrar por tipo (si tu campo tipo viene del enum TipoTarea)
      if (_filtroTipo != 'TODAS') {
        final tipo = (t.tipo ?? '').toUpperCase();
        if (tipo != _filtroTipo) continue;
      }

      // Filtrar por estado
      if (_filtroEstado != 'TODOS' && t.estado != null) {
        if (t.estado != _filtroEstado) continue;
      }

      final f = t.fechaInicio;
      if (f.year != _mesActual.year || f.month != _mesActual.month) continue;

      final dia = f.day;
      mapa.putIfAbsent(dia, () => []).add(t);
    }

    setState(() {
      _tareasPorDia = mapa;
    });
  }

  void _cambiarMes(int delta) {
    setState(() {
      _mesActual = DateTime(_mesActual.year, _mesActual.month + delta);
    });
    _cargar();
  }

  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'ASIGNADA':
        return Colors.blueGrey;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'COMPLETADA':
        return Colors.green;
      case 'APROBADA':
        return Colors.teal;
      case 'PENDIENTE_APROBACION':
        return Colors.orange;
      case 'RECHAZADA':
        return Colors.red;
      case 'NO_COMPLETADA':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  Color _colorCuadrado(int dia) {
    final hoy = DateTime.now();
    final fechaDia = DateTime(_mesActual.year, _mesActual.month, dia);

    final tareas = _tareasPorDia[dia] ?? [];
    final hayTareas = tareas.isNotEmpty;
    final hayPendientes = tareas.any(
      (t) =>
          t.estado == 'ASIGNADA' ||
          t.estado == 'EN_PROCESO' ||
          t.estado == 'PENDIENTE_APROBACION' ||
          t.estado == 'NO_COMPLETADA' ||
          t.estado == 'RECHAZADA',
    );

    final esHoy =
        fechaDia.year == hoy.year &&
        fechaDia.month == hoy.month &&
        fechaDia.day == hoy.day;

    // Primero: siempre resaltar el día de hoy
    if (esHoy) {
      if (!hayTareas) {
        return Colors.blue.withOpacity(0.25); // hoy sin tareas
      }
      if (hayPendientes) {
        return Colors.orange.shade300; // hoy con problemas
      }
      return Colors.green.shade400; // hoy todo ok
    }

    // Días sin tareas
    if (!hayTareas) {
      return Colors.grey.shade200;
    }

    // Días pasados con tareas
    if (fechaDia.isBefore(DateTime(hoy.year, hoy.month, hoy.day))) {
      // Si hay alguna pendiente / problemática → naranja
      if (hayPendientes) {
        return Colors.orange.shade300;
      }
      // Todas completadas/aprobadas
      return Colors.green.shade400;
    }

    // Días futuros con tareas
    return Colors.deepPurple.withOpacity(0.15);
  }

  Color _bordeCuadrado(int dia) {
    final hoy = DateTime.now();
    final fechaDia = DateTime(_mesActual.year, _mesActual.month, dia);

    if (fechaDia.year == hoy.year &&
        fechaDia.month == hoy.month &&
        fechaDia.day == hoy.day) {
      return Colors.blueAccent;
    }

    final tareas = _tareasPorDia[dia] ?? [];
    if (tareas.isEmpty) {
      return Colors.grey.shade300;
    }
    return Colors.deepPurple;
  }

  void _abrirDia(int dia) {
    final tareas = _tareasPorDia[dia] ?? [];
    if (tareas.isEmpty) return;

    final fecha = DateTime(
      _mesActual.year,
      _mesActual.month,
      dia,
    ); // para título
    final mesNombre = DateFormat.MMMM(
      'es',
    ).format(fecha); // "enero", "febrero"...

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tareas del $dia de ${mesNombre.toUpperCase()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conjunto: ${widget.nit}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: tareas.length,
                      itemBuilder: (_, index) {
                        final t = tareas[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            onTap: () {
                              // Aquí podrías navegar a la pantalla de detalle/edición:
                              // Navigator.push(...);
                              // Por ahora solo cerramos:
                              // Navigator.of(context).pop();
                            },
                            leading: CircleAvatar(
                              backgroundColor: _colorEstado(
                                t.estado,
                              ).withOpacity(0.2),
                              child: Icon(
                                Icons.assignment,
                                color: _colorEstado(t.estado),
                              ),
                            ),
                            title: Text(
                              t.descripcion,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Estado: ${t.estado ?? 'SIN_ESTADO'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _colorEstado(t.estado),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tipo: ${t.tipo ?? 'SIN_TIPO'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Inicio: ${DateFormat('dd/MM/yyyy HH:mm').format(t.fechaInicio)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalDias = DateUtils.getDaysInMonth(
      _mesActual.year,
      _mesActual.month,
    );
    final mesNombre = DateFormat.MMMM(
      'es',
    ).format(_mesActual).toUpperCase(); // "ENERO"
    final year = _mesActual.year;

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth < 600
        ? 7
        : screenWidth < 1000
        ? 10
        : 14;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Cronograma', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔹 Cabecera mes + cambio de mes
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _cambiarMes(-1),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tareas cargadas: ${_tareas.length}  |  Días con tareas: ${_tareasPorDia.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Center(
                        child: Text(
                          '$mesNombre $year',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _cambiarMes(1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 🔹 Leyenda + filtros (en columna para evitar overflow)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leyenda
                    Row(
                      children: [
                        _buildLegend(
                          Colors.grey.shade200,
                          'Sin tareas',
                          Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        _buildLegend(
                          Colors.deepPurple.withOpacity(0.15),
                          'Futuro con tareas',
                          Colors.deepPurple,
                        ),
                        const SizedBox(width: 6),
                        _buildLegend(
                          Colors.green.shade400,
                          'Cumplidas',
                          Colors.green,
                        ),
                        const SizedBox(width: 6),
                        _buildLegend(
                          Colors.orange.shade300,
                          'Alertas',
                          Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Filtros',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Filtro tipo de tarea
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de tarea',
                        border: OutlineInputBorder(),
                      ),
                      value: _filtroTipo,
                      items: const [
                        DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
                        DropdownMenuItem(
                          value: 'PREVENTIVA',
                          child: Text('Preventivas'),
                        ),
                        DropdownMenuItem(
                          value: 'CORRECTIVA',
                          child: Text('Correctivas'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _filtroTipo = v;
                        });
                        _reconstruirMapa();
                      },
                    ),
                    const SizedBox(height: 8),

                    // Filtro estado
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        border: OutlineInputBorder(),
                      ),
                      value: _filtroEstado,
                      items: const [
                        DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
                        DropdownMenuItem(
                          value: 'ASIGNADA',
                          child: Text('Asignada'),
                        ),
                        DropdownMenuItem(
                          value: 'EN_PROCESO',
                          child: Text('En proceso'),
                        ),
                        DropdownMenuItem(
                          value: 'COMPLETADA',
                          child: Text('Completada'),
                        ),
                        DropdownMenuItem(
                          value: 'APROBADA',
                          child: Text('Aprobada'),
                        ),
                        DropdownMenuItem(
                          value: 'PENDIENTE_APROBACION',
                          child: Text('Pendiente aprobación'),
                        ),
                        DropdownMenuItem(
                          value: 'RECHAZADA',
                          child: Text('Rechazada'),
                        ),
                        DropdownMenuItem(
                          value: 'NO_COMPLETADA',
                          child: Text('No completada'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _filtroEstado = v;
                        });
                        _reconstruirMapa();
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            if (_cargando)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    'Error: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else
              // 🔹 Calendario
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemCount: totalDias,
                  itemBuilder: (_, index) {
                    final dia = index + 1;
                    final tareas = _tareasPorDia[dia];

                    return GestureDetector(
                      onTap: () => _abrirDia(dia),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _colorCuadrado(dia),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _bordeCuadrado(dia),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dia.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (tareas != null && tareas.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${tareas.length} tareas',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(Color fillColor, String label, Color borderColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
