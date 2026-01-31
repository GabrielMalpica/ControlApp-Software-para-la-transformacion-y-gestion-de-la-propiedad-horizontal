// agenda_maquinaria_page.dart (SIN GRUPOS + más linda)
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/agenda_api.dart';
import 'package:flutter_application_1/api/empresa_api.dart';
import 'package:flutter_application_1/model/agenda_maquinaria_model.dart';
import 'package:flutter_application_1/model/maquinaria_model.dart';

class AgendaMaquinariaPage extends StatefulWidget {
  final String conjuntoId; // NIT del conjunto
  const AgendaMaquinariaPage({super.key, required this.conjuntoId});

  @override
  State<AgendaMaquinariaPage> createState() => _AgendaMaquinariaPageState();
}

class _AgendaMaquinariaPageState extends State<AgendaMaquinariaPage> {
  final _empresaApi = EmpresaApi();
  final _agendaApi = AgendaApi();

  late Future<List<MaquinariaResponse>> _fMaquinas;

  MaquinariaResponse? _seleccionada;

  /// Agenda SOLO de la máquina seleccionada
  AgendaMaquinaria? _agendaSeleccionada;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  bool _cargandoAgenda = false;
  String? _errorAgenda;

  @override
  void initState() {
    super.initState();
    _fMaquinas = _empresaApi.listarMaquinaria();
  }

  DateTime get _desdeMes => DateTime(_month.year, _month.month, 1);
  DateTime get _hastaMes => DateTime(_month.year, _month.month + 1, 1);

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });

    if (_seleccionada != null) {
      await _cargarAgendaMaquinaSeleccionada();
    }
  }

  Future<void> _cargarAgendaMaquinaSeleccionada() async {
    if (_seleccionada == null) return;

    setState(() {
      _cargandoAgenda = true;
      _errorAgenda = null;
      _agendaSeleccionada = null;
    });

    try {
      final agenda = await _agendaApi.obtenerAgenda(
        conjuntoId: widget.conjuntoId,
        maquinariaId: _seleccionada!.id,
        desde: _desdeMes,
        hasta: _hastaMes,
      );

      setState(() {
        _agendaSeleccionada = agenda;
      });
    } catch (e) {
      setState(() {
        _errorAgenda = e.toString();
        _agendaSeleccionada = null;
      });
    } finally {
      if (!mounted) return;
      setState(() => _cargandoAgenda = false);
    }
  }

  List<ReservaMaquinaria> _reservasDeSeleccionada() =>
      _agendaSeleccionada?.reservas ?? const [];

  List<String> _ubicaciones(List<ReservaMaquinaria> reservas) {
    final set = <String>{};
    for (final r in reservas) {
      final u = (r.tarea?.ubicacion ?? 'SIN UBICACIÓN').trim();
      if (u.isNotEmpty) set.add(u);
    }
    if (set.isEmpty) return const ['—'];
    final list = set.toList()..sort();
    return list;
  }

  List<String> _observaciones(List<ReservaMaquinaria> reservas) {
    final set = <String>{};
    for (final r in reservas) {
      final o = r.observacion?.trim();
      if (o != null && o.isNotEmpty) set.add(o);
    }
    final list = set.toList()..sort();
    return list;
  }

  // Días logísticos: Lunes, Miércoles, Sábado
  bool _isDiaLogistico(DateTime d) {
    final wd = d.weekday; // 1=Lun ... 7=Dom
    return wd == DateTime.monday ||
        wd == DateTime.wednesday ||
        wd == DateTime.saturday;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _prevDiaLogistico(DateTime base) {
    // último día logístico ANTES de base
    var d = _dayOnly(base).subtract(const Duration(days: 1));
    while (!_isDiaLogistico(d)) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  DateTime _nextDiaLogistico(DateTime base) {
    // primer día logístico DESPUÉS de base
    var d = _dayOnly(base).add(const Duration(days: 1));
    while (!_isDiaLogistico(d)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  // ✅ lógica E/P/R basada en la fecha real de la TAREA
  String _codeForDate(DateTime date, ReservaMaquinaria r) {
    final d = _dayOnly(date);

    // ✅ SIEMPRE normaliza a local (Bogotá)
    final reservaIni = _dayOnly(r.fechaInicio.toLocal());
    final reservaFin = _dayOnly(r.fechaFin.toLocal());

    final tareaIni = _dayOnly(
      (r.tarea?.fechaInicio ?? r.fechaInicio).toLocal(),
    );
    final tareaFin = _dayOnly((r.tarea?.fechaFin ?? r.fechaFin).toLocal());

    // 1) E y R mandan (según la reserva REAL del backend)
    if (_isSameDay(d, reservaIni)) return 'E';
    if (_isSameDay(d, reservaFin)) return 'R';

    // 2) Si está por fuera de la reserva, no pintes nada
    final inReserva = !d.isBefore(reservaIni) && !d.isAfter(reservaFin);
    if (!inReserva) return '';

    // 3) Actividad real
    final inUso = !d.isBefore(tareaIni) && !d.isAfter(tareaFin);
    if (inUso) return 'A';

    // 4) Días en sitio (entre E y R pero no actividad)
    return 'P';
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final mesLabel =
        '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda de maquinaria'),
        actions: [
          IconButton(
            tooltip: 'Mes anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _changeMonth(-1),
          ),
          SizedBox(
            width: 110,
            child: Center(
              child: Text(
                mesLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _changeMonth(1),
          ),
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (_seleccionada != null) {
                await _cargarAgendaMaquinaSeleccionada();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<MaquinariaResponse>>(
        future: _fMaquinas,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error catálogo: ${snap.error}'));
          }

          final maquinas = snap.data ?? const <MaquinariaResponse>[];

          return Row(
            children: [
              // ======= IZQUIERDA: CATÁLOGO =======
              SizedBox(
                width: 360,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Máquinas',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Empresa + Conjuntos',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.black12.withOpacity(.08),
                          ),
                        ),
                        child: ListView.separated(
                          itemCount: maquinas.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final m = maquinas[i];
                            final selected = _seleccionada?.id == m.id;

                            final subtitle =
                                [
                                      m.marca,
                                      m.tipo.label,
                                      if (m.propietarioTipo != null)
                                        m.propietarioTipo!.label,
                                      if (m.conjuntoPropietarioId != null)
                                        'Conjunto: ${m.conjuntoPropietarioId}',
                                    ]
                                    .where(
                                      (x) => x.toString().trim().isNotEmpty,
                                    )
                                    .join(' • ');

                            return ListTile(
                              selected: selected,
                              selectedTileColor: Colors.green.withOpacity(.08),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    (selected ? Colors.green : Colors.black12)
                                        .withOpacity(.12),
                                child: Icon(
                                  Icons.precision_manufacturing,
                                  size: 18,
                                  color: selected
                                      ? Colors.green
                                      : Colors.black54,
                                ),
                              ),
                              title: Text(
                                m.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black12.withOpacity(.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  m.estado.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              onTap: () async {
                                setState(() {
                                  _seleccionada = m;
                                  _agendaSeleccionada = null;
                                  _errorAgenda = null;
                                });
                                await _cargarAgendaMaquinaSeleccionada();
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const VerticalDivider(width: 1),

              // ======= DERECHA: TABLA =======
              Expanded(
                child: _seleccionada == null
                    ? const Center(
                        child: Text(
                          'Selecciona una máquina para ver su programación',
                        ),
                      )
                    : _cargandoAgenda
                    ? const Center(child: CircularProgressIndicator())
                    : _errorAgenda != null
                    ? Center(child: Text('Error agenda: $_errorAgenda'))
                    : _buildPlanilla(mesLabel),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlanilla(String mesLabel) {
    final reservas = _reservasDeSeleccionada();
    final ubicaciones = _ubicaciones(reservas);
    final observaciones = _observaciones(reservas);

    return _PlanillaProgramacion(
      titulo: _seleccionada!.nombre.toUpperCase(),
      subTitulo: 'Periodo: $mesLabel',
      reservas: reservas,
      month: _month,
      ubicaciones: ubicaciones,
      observaciones: observaciones,
      codeForDate: _codeForDate,
    );
  }
}

/// ===============================
/// PLANILLA TIPO EXCEL (E/P/R)
/// SIN GRUPOS 1-4 + UI más linda
/// ===============================
class _PlanillaProgramacion extends StatelessWidget {
  final String titulo;
  final String subTitulo;

  final List<ReservaMaquinaria> reservas;
  final DateTime month;

  final List<String> ubicaciones;
  final List<String> observaciones;

  final String Function(DateTime, ReservaMaquinaria) codeForDate;

  const _PlanillaProgramacion({
    required this.titulo,
    required this.subTitulo,
    required this.reservas,
    required this.month,
    required this.ubicaciones,
    required this.observaciones,
    required this.codeForDate,
  });

  static const _dias = ['L', 'M', 'M', 'J', 'V', 'S'];

  // anchos
  static const double _wProg = 300;
  static const double _wDia = 56;
  static const double _wObs = 320;

  // gap entre columnas
  static const double _gap = 6;

  // total columnas: prog + 6 dias + obs
  static const int _cols = 1 + 6 + 1;

  // ancho exacto
  static const double _tableWidth =
      _wProg + (6 * _wDia) + _wObs + ((_cols - 1) * _gap);

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks(month);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bonito
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.black12.withOpacity(.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.calendar_month,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subTitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _ChipLeyenda(texto: 'E = Entrega'),
              _ChipLeyenda(texto: 'A = Actividad'),
              _ChipLeyenda(texto: 'P = En sitio (instancia)'),
              _ChipLeyenda(texto: 'R = Retorno'),
            ],
          ),

          const SizedBox(height: 12),

          // Tabla
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _tableWidth,
                child: Column(
                  children: [
                    _headerRow(),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: weeks.length,
                        itemBuilder: (context, index) {
                          final w = weeks[index];
                          return _weekBlock(semanaN: index + 1, week: w);
                        },
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

  List<Widget> _withGaps(List<Widget> cells) {
    final out = <Widget>[];
    for (int i = 0; i < cells.length; i++) {
      out.add(cells[i]);
      if (i != cells.length - 1) out.add(const SizedBox(width: _gap));
    }
    return out;
  }

  Widget _headerRow() {
    final cells = <Widget>[
      _hdrCell('PROGRAMACIÓN', width: _wProg),
      ..._dias.map((d) => _hdrCell(d, width: _wDia, center: true)),
      _hdrCell('OBSERVACIONES', width: _wObs),
    ];
    return Row(children: _withGaps(cells));
  }

  Widget _weekBlock({required int semanaN, required _WeekRange week}) {
    final inWeek = reservas.where((r) {
      final ini = r.fechaInicio.toLocal();
      final fin = r.fechaFin.toLocal();
      return ini.isBefore(week.end) && fin.isAfter(week.start);
    }).toList();

    final ubicWeekSet = <String>{};
    for (final r in inWeek) {
      final u = (r.tarea?.ubicacion ?? 'SIN UBICACIÓN').trim();
      if (u.isNotEmpty) ubicWeekSet.add(u);
    }
    final rows = ubicWeekSet.isEmpty ? ['—'] : (ubicWeekSet.toList()..sort());

    final obsWeekSet = <String>{};
    for (final r in inWeek) {
      final o = r.observacion?.trim();
      if (o != null && o.isNotEmpty) obsWeekSet.add(o);
    }
    final obsText = (obsWeekSet.toList()..sort()).take(3).join('\n');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black12.withOpacity(.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado semana
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black12.withOpacity(.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'SEMANA $semanaN',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_fmt(week.start)} → ${_fmt(week.end.subtract(const Duration(days: 1)))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Filas
            Column(
              children: rows.map((ubic) {
                final codes = _codesByDay(week, ubic, inWeek);

                final cells = <Widget>[
                  _cell(ubic, width: _wProg),
                  ...codes.map((c) => _codeCell(c, width: _wDia)),
                  _cell(obsText, width: _wObs),
                ];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: _withGaps(cells)),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _codesByDay(
    _WeekRange week,
    String ubicacion,
    List<ReservaMaquinaria> inWeek,
  ) {
    final dayStart = week.start;
    final ubicKey = ubicacion.trim().toUpperCase();

    String pickCodeForDate(DateTime date) {
      final matches = inWeek.where((r) {
        final u = (r.tarea?.ubicacion ?? '—').trim().toUpperCase();
        return u == ubicKey;
      }).toList();

      if (matches.isEmpty) return '';

      // Prioridad: E > P > R
      var hasA = false;
      var hasP = false;
      var hasR = false;

      for (final r in matches) {
        final code = codeForDate(date, r);
        if (code == 'E') return 'E';
        if (code == 'R') return 'R';
        if (code == 'A') hasA = true;
        if (code == 'P') hasP = true;
      }

      if (hasA) return 'A';
      if (hasP) return 'P';
      if (hasR) return 'R';
      return '';
    }

    final out = <String>[];
    for (int i = 0; i < 6; i++) {
      final d = dayStart.add(Duration(days: i));
      out.add(pickCodeForDate(d));
    }
    return out;
  }

  List<_WeekRange> _buildWeeks(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final firstMonday = firstOfMonth.subtract(
      Duration(days: (firstOfMonth.weekday + 6) % 7),
    );

    final weeks = <_WeekRange>[];
    DateTime start = firstMonday;

    for (int i = 0; i < 4; i++) {
      final end = start.add(const Duration(days: 7));
      weeks.add(_WeekRange(start: start, end: end));
      start = end;
    }
    return weeks;
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // --- estilos de celda bonitos ---
  Widget _hdrCell(String text, {required double width, bool center = false}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(.18)),
        ),
        child: Text(
          text,
          textAlign: center ? TextAlign.center : TextAlign.left,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _cell(String text, {required double width}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12.withOpacity(.10)),
        ),
        child: Text(
          text,
          softWrap: true,
          overflow: TextOverflow.clip,
          maxLines: 6,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2),
        ),
      ),
    );
  }

  Widget _codeCell(String code, {required double width}) {
    Color bg;
    Color fg;

    switch (code) {
      case 'E':
        bg = Colors.blue.withOpacity(.14);
        fg = Colors.blue.shade800;
        break;

      case 'A': // ✅ Actividad (verde)
        bg = Colors.green.withOpacity(.16);
        fg = Colors.green.shade800;
        break;

      case 'P': // ✅ Instancia (beige)
        bg = Colors.amber.withOpacity(.18);
        fg = Colors.brown.shade800;
        break;

      case 'R':
        bg = Colors.red.withOpacity(.14);
        fg = Colors.red.shade800;
        break;

      default:
        bg = Colors.white;
        fg = Colors.black87;
    }

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12.withOpacity(.10)),
        ),
        child: Center(
          child: Text(
            code,
            style: TextStyle(fontWeight: FontWeight.w900, color: fg),
          ),
        ),
      ),
    );
  }
}

class _WeekRange {
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  const _WeekRange({required this.start, required this.end});
}

class _ChipLeyenda extends StatelessWidget {
  final String texto;
  const _ChipLeyenda({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black12.withOpacity(.08),
        border: Border.all(color: Colors.black12.withOpacity(.10)),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
