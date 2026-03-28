import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/agenda_api.dart';
import 'package:flutter_application_1/model/agenda_herramienta_model.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class AgendaHerramientasGlobalPage extends StatefulWidget {
  final String empresaNit;

  const AgendaHerramientasGlobalPage({super.key, required this.empresaNit});

  @override
  State<AgendaHerramientasGlobalPage> createState() =>
      _AgendaHerramientasGlobalPageState();
}

class _AgendaHerramientasGlobalPageState
    extends State<AgendaHerramientasGlobalPage> {
  final _api = AgendaApi();

  late int _anio;
  late int _mes;
  bool _loading = false;
  AgendaHerramientaResponse? _data;
  int _selectedIndex = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anio = now.year;
    _mes = now.month;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final r = await _api.agendaGlobalHerramientas(
        empresaNit: widget.empresaNit,
        anio: _anio,
        mes: _mes,
      );
      if (!mounted) return;
      setState(() {
        _data = r;
        _selectedIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allBlocks = _data?.data ?? const <AgendaHerramientaBlock>[];
    final blocks = allBlocks.where((block) {
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      final h = block.herramienta;
      return [h.nombre, h.unidad, h.categoria, h.modoControl]
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();

    if (_selectedIndex >= blocks.length) _selectedIndex = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda global de herramientas')),
      body: Column(
        children: [
          _filtros(),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: blocks.isEmpty
                ? const Center(child: Text('Sin datos para este mes'))
                : LayoutBuilder(
                    builder: (context, c) {
                      final mobile = c.maxWidth < 980;
                      if (!mobile) {
                        return Row(
                          children: [
                            SizedBox(width: 340, child: _panelLista(blocks)),
                            const VerticalDivider(width: 1),
                            Expanded(child: _panelAgenda(blocks[_selectedIndex])),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          SizedBox(height: 240, child: _panelLista(blocks)),
                          const Divider(height: 1),
                          Expanded(child: _panelAgenda(blocks[_selectedIndex])),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<int>(
                  initialValue: _mes,
                  decoration: const InputDecoration(
                    labelText: 'Mes',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                      .toList(),
                  onChanged: (v) => setState(() => _mes = v ?? _mes),
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<int>(
                  initialValue: _anio,
                  decoration: const InputDecoration(
                    labelText: 'Año',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(5, (i) => DateTime.now().year - 1 + i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: (v) => setState(() => _anio = v ?? _anio),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _cargar,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar herramienta',
              hintText: 'Nombre, unidad, categoria o control',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ],
      ),
    );
  }

  Widget _panelLista(List<AgendaHerramientaBlock> blocks) {
    return ListView.separated(
      itemCount: blocks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final b = blocks[i];
        final h = b.herramienta;
        final selected = i == _selectedIndex;
        return ListTile(
          selected: selected,
          selectedTileColor: Colors.green.withValues(alpha: .08),
          title: Text(
            h.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: selected ? FontWeight.w900 : FontWeight.w700),
          ),
          subtitle: Text('${h.categoria} • ${h.unidad} • ${h.modoControl}'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text('${b.reservasMes}', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          onTap: () => setState(() => _selectedIndex = i),
        );
      },
    );
  }

  Widget _panelAgenda(AgendaHerramientaBlock block) {
    final h = block.herramienta;
    final semanas = block.semanas.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${h.nombre.toUpperCase()} • ${h.unidad}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text('Reservas mes: ${block.reservasMes}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${h.categoria} • ${h.modoControl}'),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: semanas
                    .map((e) => _AgendaSemanaHerramienta(anio: _anio, mes: _mes, semana: e.key, grupos: e.value))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaSemanaHerramienta extends StatelessWidget {
  final int anio;
  final int mes;
  final int semana;
  final Map<int, List<AgendaHerramientaItem>> grupos;

  const _AgendaSemanaHerramienta({
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
                  DataCell(
                    Text(
                      '${item.conjuntoNombre ?? item.conjuntoId ?? '-'} · cant: ${item.cantidad} · ${item.origenStock}',
                    ),
                  ),
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
