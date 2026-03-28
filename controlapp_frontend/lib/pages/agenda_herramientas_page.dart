import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/agenda_api.dart';
import 'package:flutter_application_1/api/herramienta_api.dart';
import 'package:flutter_application_1/model/agenda_herramienta_model.dart';
import 'package:flutter_application_1/model/herramienta_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

class AgendaHerramientasPage extends StatefulWidget {
  final String conjuntoId;

  const AgendaHerramientasPage({super.key, required this.conjuntoId});

  @override
  State<AgendaHerramientasPage> createState() => _AgendaHerramientasPageState();
}

class _AgendaHerramientasPageState extends State<AgendaHerramientasPage> {
  final _herrApi = HerramientaApi();
  final _agendaApi = AgendaApi();

  late Future<List<AgendaHerramientaLite>> _future;
  final Map<int, AgendaHerramientaBlock> _blocks = {};
  AgendaHerramientaLite? _seleccionada;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _cargarCatalogo();
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _future = _cargarCatalogo();
      _seleccionada = null;
    });
  }

  Future<List<AgendaHerramientaLite>> _cargarCatalogo() async {
    final results = await Future.wait([
      _herrApi.listarStockConjunto(nitConjunto: widget.conjuntoId),
      _agendaApi.agendaGlobalHerramientas(
        empresaNit: AppConstants.empresaNit,
        anio: _month.year,
        mes: _month.month,
      ),
    ]);

    final stockRaw = results[0] as List<dynamic>;
    final agenda = results[1] as AgendaHerramientaResponse;

    final stock = stockRaw
        .whereType<Map>()
        .map((e) => HerramientaStockResponse.fromJson(e.cast<String, dynamic>()))
        .toList();

    final byId = <int, AgendaHerramientaLite>{};
    final bloques = <int, AgendaHerramientaBlock>{};

    for (final s in stock) {
      byId[s.herramientaId] = AgendaHerramientaLite(
        id: s.herramientaId,
        nombre: s.nombre,
        unidad: s.unidad,
        categoria: s.categoria.name,
        modoControl: s.modoControl.name,
      );
    }

    for (final block in agenda.data) {
      final filtrado = _filtrarBloqueConjunto(block);
      final yaEnStock = byId.containsKey(block.herramienta.id);
      if (filtrado.reservasMes > 0 || yaEnStock) {
        byId.putIfAbsent(block.herramienta.id, () => block.herramienta);
        bloques[block.herramienta.id] = filtrado;
      }
    }

    for (final item in byId.values) {
      bloques.putIfAbsent(
        item.id,
        () => AgendaHerramientaBlock(
          herramienta: item,
          semanas: {for (int s = 1; s <= 6; s++) s: {for (int g = 1; g <= 6; g++) g: <AgendaHerramientaItem>[]}},
          reservasMes: 0,
        ),
      );
    }

    _blocks
      ..clear()
      ..addAll(bloques);

    final salida = byId.values.toList()
      ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return salida;
  }

  AgendaHerramientaBlock _filtrarBloqueConjunto(AgendaHerramientaBlock block) {
    final semanas = <int, Map<int, List<AgendaHerramientaItem>>>{};
    final usoIds = <int>{};
    for (int semana = 1; semana <= 6; semana++) {
      final grupos = <int, List<AgendaHerramientaItem>>{};
      for (int grupo = 1; grupo <= 6; grupo++) {
        final items = (block.semanas[semana]?[grupo] ?? const <AgendaHerramientaItem>[])
            .where((item) => (item.conjuntoId?.trim() ?? '') == widget.conjuntoId.trim())
            .toList();
        grupos[grupo] = items;
        for (final item in items) {
          usoIds.add(item.usoId);
        }
      }
      semanas[semana] = grupos;
    }

    return AgendaHerramientaBlock(
      herramienta: block.herramienta,
      semanas: semanas,
      reservasMes: usoIds.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mesLabel = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda de herramientas'),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
          SizedBox(width: 110, child: Center(child: Text(mesLabel, style: const TextStyle(fontWeight: FontWeight.w600)))),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _future = _cargarCatalogo();
                _seleccionada = null;
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<AgendaHerramientaLite>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error catalogo: ${AppError.messageOf(snap.error)}'));
          }

          final items = (snap.data ?? const <AgendaHerramientaLite>[])
              .where((h) {
                final q = _query.trim().toLowerCase();
                if (q.isEmpty) return true;
                return [h.nombre, h.unidad, h.categoria, h.modoControl]
                    .join(' ')
                    .toLowerCase()
                    .contains(q);
              })
              .toList();

          return Row(
            children: [
              SizedBox(
                width: 320,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Buscar herramienta',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, index) {
                          final h = items[index];
                          final block = _blocks[h.id];
                          final selected = _seleccionada?.id == h.id;
                          return ListTile(
                            selected: selected,
                            title: Text(h.nombre),
                            subtitle: Text('${h.unidad} • ${h.categoria}'),
                            trailing: Text('${block?.reservasMes ?? 0}'),
                            onTap: () => setState(() => _seleccionada = h),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _buildDetalle()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetalle() {
    if (_seleccionada == null) {
      return const Center(child: Text('Selecciona una herramienta para ver su programacion'));
    }

    final block = _blocks[_seleccionada!.id];
    if (block == null) {
      return const Center(child: Text('Sin datos'));
    }

    final semanas = block.semanas.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${block.herramienta.nombre.toUpperCase()} • ${block.herramienta.unidad}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text('${block.herramienta.categoria} • ${block.herramienta.modoControl}'),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: semanas
                    .map((e) => _AgendaSemanaHerramientaConjunto(anio: _month.year, mes: _month.month, semana: e.key, grupos: e.value))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaSemanaHerramientaConjunto extends StatelessWidget {
  final int anio;
  final int mes;
  final int semana;
  final Map<int, List<AgendaHerramientaItem>> grupos;

  const _AgendaSemanaHerramientaConjunto({
    required this.anio,
    required this.mes,
    required this.semana,
    required this.grupos,
  });

  static const _days = ['L', 'M', 'M', 'J', 'V', 'S'];

  @override
  Widget build(BuildContext context) {
    final monday = _mondayForWeek(anio, mes, semana);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Programacion')),
            ..._days.map((d) => DataColumn(label: Text(d))),
            const DataColumn(label: Text('Detalle')),
          ],
          rows: [
            for (int grupo = 1; grupo <= 6; grupo++)
              ...grupos[grupo]!.map(
                (item) => DataRow(cells: [
                  DataCell(Text('Semana $semana · Grupo $grupo')),
                  ...List.generate(6, (i) {
                    final day = monday.add(Duration(days: i));
                    return DataCell(Text('${_days[i]} ${day.day}\n${item.grid[i]}'));
                  }),
                  DataCell(Text('cant: ${item.cantidad} · ${item.origenStock}')),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  DateTime _mondayForWeek(int anio, int mes, int semana) {
    final first = DateTime(anio, mes, 1);
    final back = (first.weekday + 6) % 7;
    final monday = first.subtract(Duration(days: back));
    return monday.add(Duration(days: (semana - 1) * 7));
  }
}
