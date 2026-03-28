// agenda_maquinaria_page.dart (SIN GRUPOS + más linda)
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/agenda_api.dart';
import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/model/agenda_model.dart';
import 'package:flutter_application_1/model/agenda_maquinaria_model.dart';
import 'package:flutter_application_1/model/maquinaria_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_constants.dart';

class AgendaMaquinariaPage extends StatefulWidget {
  final String conjuntoId; // NIT del conjunto
  const AgendaMaquinariaPage({super.key, required this.conjuntoId});

  @override
  State<AgendaMaquinariaPage> createState() => _AgendaMaquinariaPageState();
}

class _AgendaMaquinariaPageState extends State<AgendaMaquinariaPage> {
  final _conjuntoApi = ConjuntoApi();
  final _agendaApi = AgendaApi();

  late Future<List<MaquinariaResponse>> _fMaquinas;
  final Map<int, AgendaMaquinaBlock> _bloquesAgendaPorMaquina = {};

  MaquinariaResponse? _seleccionada;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  bool _cargandoAgenda = false;
  String? _errorAgenda;
  String _maquinariaQuery = '';

  @override
  void initState() {
    super.initState();
    _fMaquinas = _cargarCatalogoAgendaConjunto();
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _fMaquinas = _cargarCatalogoAgendaConjunto();
      _errorAgenda = null;
      _cargandoAgenda = false;
    });
  }

  bool _esPropiaDelConjunto(MaquinariaResponse m) {
    return m.propietarioTipo == PropietarioMaquinaria.CONJUNTO &&
        (m.conjuntoPropietarioId?.trim() ?? '') == widget.conjuntoId.trim();
  }

  bool _bloqueTieneAgendaDelConjunto(AgendaMaquinaBlock block) {
    for (final grupos in block.semanas.values) {
      for (final items in grupos.values) {
        for (final item in items) {
          if ((item.conjuntoId?.trim() ?? '') == widget.conjuntoId.trim()) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _itemEsDelConjunto(AgendaReservaItem item) {
    return (item.conjuntoId?.trim() ?? '') == widget.conjuntoId.trim();
  }

  Map<int, List<AgendaReservaItem>> _gruposVacios() {
    return {
      for (int grupo = 1; grupo <= 6; grupo++) grupo: <AgendaReservaItem>[],
    };
  }

  Map<int, Map<int, List<AgendaReservaItem>>> _semanasVacias() {
    return {
      for (int semana = 1; semana <= 6; semana++) semana: _gruposVacios(),
    };
  }

  AgendaMaquinaBlock _bloqueVacioPara(MaquinariaResponse maquinaria) {
    return AgendaMaquinaBlock(
      maquinaria: maquinaria,
      semanas: _semanasVacias(),
      reservasMes: 0,
    );
  }

  AgendaMaquinaBlock _filtrarBloqueParaConjunto(
    AgendaMaquinaBlock block, {
    MaquinariaResponse? maquinaria,
  }) {
    final semanas = <int, Map<int, List<AgendaReservaItem>>>{};
    final usoIds = <int>{};

    for (int semana = 1; semana <= 6; semana++) {
      final gruposSemana = <int, List<AgendaReservaItem>>{};
      final gruposBase = block.semanas[semana];

      for (int grupo = 1; grupo <= 6; grupo++) {
        final items = (gruposBase?[grupo] ?? const <AgendaReservaItem>[])
            .where(_itemEsDelConjunto)
            .toList();
        gruposSemana[grupo] = items;
        for (final item in items) {
          usoIds.add(item.usoId);
        }
      }

      semanas[semana] = gruposSemana;
    }

    return AgendaMaquinaBlock(
      maquinaria: maquinaria ?? block.maquinaria,
      semanas: semanas,
      reservasMes: usoIds.length,
    );
  }

  Future<List<MaquinariaResponse>> _cargarCatalogoAgendaConjunto() async {
    final results = await Future.wait([
      _conjuntoApi.listarMaquinariaConjunto(widget.conjuntoId),
      _agendaApi.agendaGlobalMaquinaria(
        empresaNit: AppConstants.empresaNit,
        anio: _month.year,
        mes: _month.month,
      ),
    ]);

    final maquinariaConjunto = results[0] as List<MaquinariaResponse>;
    final agendaGlobal = results[1] as AgendaGlobalResponse;
    final bloquesGlobales = {
      for (final block in agendaGlobal.data) block.maquinaria.id: block,
    };

    final idsConAgenda = agendaGlobal.data
        .where(_bloqueTieneAgendaDelConjunto)
        .map((b) => b.maquinaria.id)
        .toSet();

    final byId = <int, MaquinariaResponse>{};
    final bloquesPorId = <int, AgendaMaquinaBlock>{};

    for (final m in maquinariaConjunto) {
      if (_esPropiaDelConjunto(m)) {
        byId[m.id] = m;
        final block = bloquesGlobales[m.id];
        bloquesPorId[m.id] = block == null
            ? _bloqueVacioPara(m)
            : _filtrarBloqueParaConjunto(block, maquinaria: m);
      }
    }

    for (final b in agendaGlobal.data) {
      if (!idsConAgenda.contains(b.maquinaria.id)) continue;
      final filtrado = _filtrarBloqueParaConjunto(b);
      if (filtrado.reservasMes == 0) continue;
      byId.putIfAbsent(b.maquinaria.id, () => b.maquinaria);
      bloquesPorId[b.maquinaria.id] = filtrado;
    }

    final salida = byId.values.toList()
      ..sort((a, b) {
        final rankA = _esPropiaDelConjunto(a) ? 0 : 1;
        final rankB = _esPropiaDelConjunto(b) ? 0 : 1;
        if (rankA != rankB) return rankA.compareTo(rankB);
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });

    _bloquesAgendaPorMaquina
      ..clear()
      ..addAll(bloquesPorId);

    return salida;
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

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

  Widget _buildDetalleAgenda(String mesLabel) {
    if (_seleccionada == null) {
      return const Center(
        child: Text('Selecciona una maquina para ver su programacion'),
      );
    }

    return _buildPlanilla(mesLabel);
  }

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
            onPressed: () {
              setState(() {
                _fMaquinas = _cargarCatalogoAgendaConjunto();
                _errorAgenda = null;
                _cargandoAgenda = false;
              });
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
            return Center(
              child: Text('Error catalogo: ${AppError.messageOf(snap.error)}'),
            );
          }

          final maquinas = snap.data ?? const <MaquinariaResponse>[];
          final filteredMaquinas = maquinas.where((m) {
            final query = _maquinariaQuery.trim().toLowerCase();
            if (query.isEmpty) return true;
            return [
              m.nombre,
              m.marca,
              m.tipo.label,
              m.conjuntoNombre ?? '',
            ].join(' ').toLowerCase().contains(query);
          }).toList();
          final selectedVisible = _seleccionada == null
              ? true
              : filteredMaquinas.any((m) => m.id == _seleccionada!.id) ||
                    maquinas.any((m) => m.id == _seleccionada!.id);

          if (!selectedVisible) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _seleccionada = null;
                _errorAgenda = null;
              });
            });
          }

          Widget catalogo() => Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Máquinas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Propias del conjunto + con agenda del conjunto',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar maquinaria',
                    hintText: 'Nombre, marca o tipo',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) =>
                      setState(() => _maquinariaQuery = value),
                ),
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Colors.black12.withValues(alpha: .08),
                    ),
                  ),
                  child: ListView.separated(
                    itemCount: filteredMaquinas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = filteredMaquinas[i];
                      final selected = _seleccionada?.id == m.id;
                      final esPropia = _esPropiaDelConjunto(m);

                      final subtitle =
                          [
                                m.marca,
                                m.tipo.label,
                                esPropia ? 'Propia' : 'Con agenda',
                                if (m.propietarioTipo != null)
                                  m.propietarioTipo!.label,
                                if (m.conjuntoPropietarioId != null)
                                  'Conjunto: ${m.conjuntoPropietarioId}',
                              ]
                              .where((x) => x.toString().trim().isNotEmpty)
                              .join(' • ');

                      return ListTile(
                        selected: selected,
                        selectedTileColor: Colors.green.withValues(alpha: .08),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              (selected ? Colors.green : Colors.black12)
                                  .withValues(alpha: .12),
                          child: Icon(
                            Icons.precision_manufacturing,
                            size: 18,
                            color: selected ? Colors.green : Colors.black54,
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
                            color: Colors.black12.withValues(alpha: .08),
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
                        onTap: () {
                          setState(() {
                            _seleccionada = m;
                            _errorAgenda = null;
                            _cargandoAgenda = false;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );

          Widget detalle() => _seleccionada == null
              ? const Center(
                  child: Text(
                    'Selecciona una máquina para ver su programación',
                  ),
                )
              : _cargandoAgenda
              ? const Center(child: CircularProgressIndicator())
              : _errorAgenda != null
              ? Center(child: Text('Error agenda: $_errorAgenda'))
              : _buildPlanilla(mesLabel);

          return LayoutBuilder(
            builder: (context, c) {
              final mobile = c.maxWidth < 980;
              if (!mobile) {
                return Row(
                  children: [
                    SizedBox(width: 360, child: catalogo()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildDetalleAgenda(mesLabel)),
                  ],
                );
              }

              return Column(
                children: [
                  SizedBox(height: 260, child: catalogo()),
                  const Divider(height: 1),
                  Expanded(child: _buildDetalleAgenda(mesLabel)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPlanilla(String mesLabel) {
    final block =
        _bloquesAgendaPorMaquina[_seleccionada!.id] ??
        _bloqueVacioPara(_seleccionada!);

    return _PlanillaProgramacionFiltrada(
      titulo: _seleccionada!.nombre.toUpperCase(),
      subTitulo: 'Periodo: $mesLabel',
      anio: _month.year,
      mes: _month.month,
      block: block,
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
              side: BorderSide(color: Colors.black12.withValues(alpha: .08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: .10),
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
    final visibleEndExclusive = week.start.add(Duration(days: _dias.length));
    final inWeek = reservas.where((r) {
      final ini = r.fechaInicio.toLocal();
      final fin = r.fechaFin.toLocal();
      return ini.isBefore(visibleEndExclusive) && fin.isAfter(week.start);
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
    final obsText = (obsWeekSet.toList()..sort()).join('\n');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black12.withValues(alpha: .08)),
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
                      color: Colors.black12.withValues(alpha: .08),
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
                      '${_fmt(week.start)} -> ${_fmt(visibleEndExclusive.subtract(const Duration(days: 1)))}',
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

      for (final r in matches) {
        final code = codeForDate(date, r);
        if (code == 'E') return 'E';
        if (code == 'R') return 'R';
        if (code == 'A') hasA = true;
        if (code == 'P') hasP = true;
      }

      if (hasA) return 'A';
      if (hasP) return 'P';
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

    for (int i = 0; i < 6; i++) {
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
          color: Colors.green.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: .18)),
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
          border: Border.all(color: Colors.black12.withValues(alpha: .10)),
        ),
        child: Text(
          text,
          softWrap: true,
          overflow: TextOverflow.clip,
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
        bg = Colors.blue.withValues(alpha: .14);
        fg = Colors.blue.shade800;
        break;

      case 'A': // ✅ Actividad (verde)
        bg = Colors.green.withValues(alpha: .16);
        fg = Colors.green.shade800;
        break;

      case 'P': // ✅ Instancia (beige)
        bg = Colors.amber.withValues(alpha: .18);
        fg = Colors.brown.shade800;
        break;

      case 'R':
        bg = Colors.red.withValues(alpha: .14);
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
          border: Border.all(color: Colors.black12.withValues(alpha: .10)),
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
        color: Colors.black12.withValues(alpha: .08),
        border: Border.all(color: Colors.black12.withValues(alpha: .10)),
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

class _PlanillaProgramacionFiltrada extends StatelessWidget {
  final String titulo;
  final String subTitulo;
  final int anio;
  final int mes;
  final AgendaMaquinaBlock block;

  const _PlanillaProgramacionFiltrada({
    required this.titulo,
    required this.subTitulo,
    required this.anio,
    required this.mes,
    required this.block,
  });

  @override
  Widget build(BuildContext context) {
    final semanas = block.semanas.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.black12.withValues(alpha: .08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: .10),
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
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      'Reservas: ${block.reservasMes}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _ChipLeyenda(texto: 'E = Entrega'),
              _ChipLeyenda(texto: 'A = Actividad'),
              _ChipLeyenda(texto: 'P = En sitio'),
              _ChipLeyenda(texto: 'R = Retorno'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: semanas
                    .map(
                      (e) => _ExcelSemanaFiltrada(
                        anio: anio,
                        mes: mes,
                        semana: e.key,
                        grupos: e.value,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExcelSemanaFiltrada extends StatelessWidget {
  final int anio;
  final int mes;
  final int semana;
  final Map<int, List<AgendaReservaItem>> grupos;

  const _ExcelSemanaFiltrada({
    required this.anio,
    required this.mes,
    required this.semana,
    required this.grupos,
  });

  static const _days = ['L', 'M', 'M', 'J', 'V', 'S'];
  static const double _wProg = 220;
  static const double _wDay = 42;
  static const double _wGroup = 160;
  static const double _tableWidth = _wProg + (6 * _wDay) + (6 * _wGroup);

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _firstMondayOfGrid(int anio, int mes) {
    final first = DateTime(anio, mes, 1);
    final back = first.weekday - DateTime.monday;
    return _startOfDay(first.subtract(Duration(days: back)));
  }

  DateTime _weekStart(int anio, int mes, int semana) {
    final base = _firstMondayOfGrid(anio, mes);
    return base.add(Duration(days: (semana - 1) * 7));
  }

  List<String> _dayNumbers(int anio, int mes, int semana) {
    final start = _weekStart(anio, mes, semana);
    return List.generate(6, (i) {
      final d = start.add(Duration(days: i));
      if (d.month != mes) return '';
      return '${d.day}';
    });
  }

  List<_ExcelRowFiltrada> _buildRows() {
    final allItems = <AgendaReservaItem>[];
    for (final entry in grupos.entries) {
      allItems.addAll(entry.value);
    }

    final byConjunto = <String, List<AgendaReservaItem>>{};
    for (final it in allItems) {
      final nombre = (it.conjuntoNombre ?? '').trim();
      final id = (it.conjuntoId ?? '').trim();
      final label = nombre.isNotEmpty
          ? nombre
          : (id.isNotEmpty ? id : 'Conjunto seleccionado');
      byConjunto.putIfAbsent(label, () => []).add(it);
    }

    final nombres = byConjunto.keys.toList()..sort();
    if (nombres.isEmpty) {
      return [
        _ExcelRowFiltrada(
          programacion: '-',
          grid: List.filled(6, ''),
          groupCells: List.filled(6, ''),
        ),
      ];
    }

    final out = <_ExcelRowFiltrada>[];
    for (final nombre in nombres) {
      final items = byConjunto[nombre] ?? const <AgendaReservaItem>[];
      final mergedGrid = _mergeGrids(items);

      int grupoMayor = 1;
      if (items.isNotEmpty) {
        grupoMayor = items
            .map((it) => it.grupo)
            .reduce((a, b) => a > b ? a : b)
            .clamp(1, 6);
      }

      final groupCells = List<String>.generate(6, (index) {
        final grupo = index + 1;
        return grupo == grupoMayor ? nombre : '';
      });

      out.add(
        _ExcelRowFiltrada(
          programacion: nombre,
          grid: mergedGrid,
          groupCells: groupCells,
        ),
      );
    }

    return out;
  }

  List<String> _mergeGrids(List<AgendaReservaItem> items) {
    List<String> ensure6(List<String> grid) =>
        grid.length == 6 ? grid : List.filled(6, '');

    int priority(String value) {
      switch (value) {
        case 'E':
        case 'R':
          return 4;
        case 'A':
          return 3;
        case 'P':
          return 2;
        default:
          return 1;
      }
    }

    final merged = List<String>.filled(6, '');
    for (final item in items) {
      final grid = ensure6(item.grid);
      for (int i = 0; i < 6; i++) {
        if (priority(grid[i]) > priority(merged[i])) {
          merged[i] = grid[i];
        }
      }
    }
    return merged;
  }

  Widget _hdr(String text, double width) {
    return Container(
      width: width,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        color: Colors.amber.shade300,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _hdrMultiline(String text, double width) {
    return Container(
      width: width,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        color: Colors.amber.shade300,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }

  Widget _cellText(String text, double width, {bool alignLeft = false}) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        color: Colors.white,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _cellCode(String code, double width) {
    Color bg = Colors.white;
    Color fg = Colors.black87;

    switch (code) {
      case 'E':
        bg = Colors.blue.withValues(alpha: .15);
        fg = Colors.blue.shade800;
        break;
      case 'A':
        bg = Colors.green.withValues(alpha: .18);
        fg = Colors.green.shade800;
        break;
      case 'P':
        bg = Colors.amber.withValues(alpha: .20);
        fg = Colors.brown.shade800;
        break;
      case 'R':
        bg = Colors.red.withValues(alpha: .15);
        fg = Colors.red.shade800;
        break;
    }

    return Container(
      width: width,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        color: bg,
      ),
      child: Text(
        code,
        style: TextStyle(fontWeight: FontWeight.w900, color: fg),
      ),
    );
  }

  Widget _headerRow() {
    final numeros = _dayNumbers(anio, mes, semana);

    return Row(
      children: [
        _hdr('PROGRAMACION', _wProg),
        ...List.generate(
          6,
          (index) => _hdrMultiline('${_days[index]}\n${numeros[index]}', _wDay),
        ),
        for (int grupo = 1; grupo <= 6; grupo++) _hdr('GRUPO $grupo', _wGroup),
      ],
    );
  }

  Widget _rowWidget(_ExcelRowFiltrada row) {
    return Row(
      children: [
        _cellText(row.programacion, _wProg, alignLeft: true),
        ...List.generate(6, (index) => _cellCode(row.grid[index], _wDay)),
        ...List.generate(
          6,
          (index) => _cellText(row.groupCells[index], _wGroup),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.lightGreen.shade300,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Text(
              'SEMANA $semana',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _tableWidth,
              child: Column(children: [_headerRow(), ...rows.map(_rowWidget)]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExcelRowFiltrada {
  final String programacion;
  final List<String> grid;
  final List<String> groupCells;

  _ExcelRowFiltrada({
    required this.programacion,
    required this.grid,
    required this.groupCells,
  });
}
