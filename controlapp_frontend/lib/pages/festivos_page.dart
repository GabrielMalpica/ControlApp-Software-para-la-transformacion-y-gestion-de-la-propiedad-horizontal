import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../api/festivo_api.dart';
import '../service/theme.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class FestivosPage extends StatefulWidget {
  const FestivosPage({super.key});

  @override
  State<FestivosPage> createState() => _FestivosPageState();
}

class _FestivosPageState extends State<FestivosPage> {
  final FestivoApi _api = FestivoApi();

  // Config
  String _pais = 'CO';

  // UI state
  bool _cargando = true;
  bool _guardando = false;

  // Calendario
  CalendarFormat _format = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Rango sobre el que guardamos (por defecto: mes actual)
  bool _modoAnioCompleto = false;
  DateTime get _rangoDesde {
    final d = DateTime(_focusedDay.year, _focusedDay.month, 1);
    return _modoAnioCompleto ? DateTime(_focusedDay.year, 1, 1) : d;
  }

  DateTime get _rangoHasta {
    if (_modoAnioCompleto) return DateTime(_focusedDay.year, 12, 31);

    final nextMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    return DateTime(lastDay.year, lastDay.month, lastDay.day);
  }

  // Selección (normalizada a start-of-day)
  final Map<String, FestivoItem> _seleccion = {}; // key = YYYY-MM-DD

  @override
  void initState() {
    super.initState();
    _cargarFestivos();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _cargarFestivos() async {
    setState(() => _cargando = true);
    try {
      final list = await _api.listarFestivosRango(
        desde: _rangoDesde,
        hasta: _rangoHasta,
        pais: _pais,
      );

      _seleccion.clear();
      for (final f in list) {
        _seleccion[_ymd(f.fecha)] = f;
      }

      if (!mounted) return;
      setState(() => _cargando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error cargando festivos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _isSelected(DateTime day) => _seleccion.containsKey(_ymd(day));

  void _toggleDay(DateTime day) async {
    final d = _startOfDay(day);
    final key = _ymd(d);

    // Si existe, lo quitamos
    if (_seleccion.containsKey(key)) {
      setState(() => _seleccion.remove(key));
      return;
    }

    // Si no existe, lo agregamos (opcional: pedir nombre)
    final nombre = await _pedirNombreFestivo(d);
    if (!mounted) return;

    setState(() {
      _seleccion[key] = FestivoItem(fecha: d, nombre: nombre);
    });
  }

  Future<String?> _pedirNombreFestivo(DateTime fecha) async {
    final ctrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del festivo (opcional)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Fecha: ${_ymd(fecha)}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Ej: Año Nuevo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok != true) return null;
    final t = ctrl.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final items = _seleccion.values.toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));

      await _api.reemplazarFestivosEnRango(
        desde: _rangoDesde,
        hasta: _rangoHasta,
        fechas: items,
        pais: _pais,
      );

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('✅ Festivos guardados'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error guardando festivos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Festivos (no laborables)',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargarFestivos,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Controles
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _pais,
                                  decoration: const InputDecoration(
                                    labelText: 'País',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'CO',
                                      child: Text('Colombia (CO)'),
                                    ),
                                  ],
                                  onChanged: (v) async {
                                    if (v == null) return;
                                    setState(() => _pais = v);
                                    await _cargarFestivos();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SwitchListTile.adaptive(
                                  value: _modoAnioCompleto,
                                  title: const Text('Año completo'),
                                  onChanged: (v) async {
                                    setState(() => _modoAnioCompleto = v);
                                    await _cargarFestivos();
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Rango: ${_ymd(_rangoDesde)} → ${_ymd(_rangoHasta)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _guardando ? null : _guardar,
                                icon: _guardando
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save),
                                label: Text(
                                  _guardando ? 'Guardando...' : 'Guardar',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Calendario
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TableCalendar(
                      firstDay: DateTime(2020, 1, 1),
                      lastDay: DateTime(2035, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: _format,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      rowHeight: 44,
                      daysOfWeekHeight: 28,
                      selectedDayPredicate: (day) =>
                          _selectedDay != null && isSameDay(_selectedDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                        _toggleDay(selectedDay);
                      },
                      onPageChanged: (focusedDay) async {
                        setState(() => _focusedDay = focusedDay);
                        // si estás en modo mes, recargamos cada vez que cambias de mes
                        if (!_modoAnioCompleto) {
                          await _cargarFestivos();
                        }
                      },
                      onFormatChanged: (f) {
                        setState(() => _format = f);
                      },
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          if (_isSelected(day)) {
                            return const Positioned(
                              right: 4,
                              bottom: 4,
                              child: Icon(Icons.flag, size: 16),
                            );
                          }
                          return null;
                        },
                        defaultBuilder: (context, day, focusedDay) {
                          final isFestivo = _isSelected(day);
                          final isSunday = day.weekday == DateTime.sunday;

                          // Festivo (tu selección) + Domingo (solo visual, el back también debe bloquearlo)
                          if (isFestivo || isSunday) {
                            return Center(
                              child: Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(width: 1),
                                ),
                                child: Text('${day.day}'),
                              ),
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                ),

                // Lista rápida del mes/año seleccionado
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Seleccionados: ${_seleccion.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 90,
                            child: ListView(
                              children: _seleccion.values
                                  .map(
                                    (f) => Text(
                                      '• ${f.fecha.day}/${f.fecha.month}/${f.fecha.year}'
                                      '${f.nombre != null ? " — ${f.nombre}" : ""}',
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
