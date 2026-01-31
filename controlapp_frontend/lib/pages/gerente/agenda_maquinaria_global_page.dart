import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/agenda_api.dart';
import 'package:flutter_application_1/model/agenda_model.dart';
import 'package:flutter_application_1/model/maquinaria_model.dart';

class AgendaMaquinariaGlobalExcelPage extends StatefulWidget {
  final String empresaNit;
  const AgendaMaquinariaGlobalExcelPage({super.key, required this.empresaNit});

  @override
  State<AgendaMaquinariaGlobalExcelPage> createState() =>
      _AgendaMaquinariaGlobalExcelPageState();
}

class _AgendaMaquinariaGlobalExcelPageState
    extends State<AgendaMaquinariaGlobalExcelPage> {
  final _api = AgendaApi();

  late int _anio;
  late int _mes;

  bool _loading = false;
  AgendaGlobalResponse? _data;

  int _selectedIndex = 0;

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
      final r = await _api.agendaGlobalMaquinaria(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _data?.data ?? const <AgendaMaquinaBlock>[];

    if (_selectedIndex >= blocks.length) _selectedIndex = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda global de maquinaria')),
      body: Column(
        children: [
          _filtros(),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: blocks.isEmpty
                ? const Center(child: Text('Sin datos para este mes'))
                : Row(
                    children: [
                      SizedBox(width: 340, child: _panelListaMaquinas(blocks)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _panelExcel(blocks[_selectedIndex])),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // =========================
  // Filtros
  // =========================
  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _mes,
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
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _anio,
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
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
        ],
      ),
    );
  }

  // =========================
  // Panel izquierdo
  // =========================
  Widget _panelListaMaquinas(List<AgendaMaquinaBlock> blocks) {
    return ListView.separated(
      itemCount: blocks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final b = blocks[i];
        final m = b.maquinaria;
        final selected = i == _selectedIndex;

        return ListTile(
          selected: selected,
          selectedTileColor: Colors.green.withOpacity(.08),
          title: Text(
            m.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '${m.tipo.label} • ${m.marca}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              '${b.reservasMes}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          onTap: () => setState(() => _selectedIndex = i),
        );
      },
    );
  }

  // =========================
  // Panel derecho: Excel
  // =========================
  Widget _panelExcel(AgendaMaquinaBlock block) {
    final m = block.maquinaria;
    final semanas = block.semanas.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header grande
          Row(
            children: [
              Expanded(
                child: Text(
                  '${m.nombre.toUpperCase()} • ${m.marca}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
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
                  'Reservas mes: ${block.reservasMes}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: semanas.map((e) {
                  return _ExcelSemana(
                    anio: _anio,
                    mes: _mes,
                    semana: e.key,
                    grupos: e.value,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ======================================================
///  EXCEL SEMANA (sin infinito)
///  Columnas: Programación | L..S | Grupo1..Grupo6
/// ======================================================
class _ExcelSemana extends StatelessWidget {
  final int anio;
  final int mes;
  final int semana;
  final Map<int, List<AgendaReservaItem>> grupos;

  const _ExcelSemana({
    required this.anio,
    required this.mes,
    required this.semana,
    required this.grupos,
  });

  static const _days = ['L', 'M', 'M', 'J', 'V', 'S'];

  static const double _wProg = 220;
  static const double _wDay = 42;
  static const double _wGroup = 160;
  static const double _gap = 0;

  static const double _tableWidth = _wProg + (6 * _wDay) + (6 * _wGroup) + _gap;

  // =========================
  // Helpers calendario (igual lógica que backend)
  // =========================
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _firstMondayOfGrid(int anio, int mes) {
    final first = DateTime(anio, mes, 1);
    final dow = first.weekday; // 1=Lun..7=Dom
    final back = dow - DateTime.monday; // 0 si ya es lunes
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
      if (d.month != mes) return ""; // fuera del mes
      return "${d.day}";
    });
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

  // =========================
  // Construye filas
  // =========================
  List<_ExcelRow> _buildRows() {
    final allItems = <AgendaReservaItem>[];
    for (final entry in grupos.entries) {
      allItems.addAll(entry.value);
    }

    final byConjunto = <String, List<AgendaReservaItem>>{};
    for (final it in allItems) {
      final name = (it.conjuntoNombre ?? '').trim();
      if (name.isEmpty) continue;
      byConjunto.putIfAbsent(name, () => []).add(it);
    }

    final nombres = byConjunto.keys.toList()..sort();

    if (nombres.isEmpty) {
      return [
        _ExcelRow(
          programacion: '—',
          grid: List.filled(6, ''),
          groupCells: List.filled(6, ''),
        ),
      ];
    }

    final out = <_ExcelRow>[];

    for (final c in nombres) {
      final items = byConjunto[c] ?? const [];

      // 1) merge del grid (E/R > A > P > '')
      final mergedGrid = _mergeGrids(items);

      // 2) grupo por backend (máximo dentro de esa semana)
      int g = 1;
      if (items.isNotEmpty) {
        g = items.map((it) => it.grupo).reduce((a, b) => a > b ? a : b);
      }
      g = g.clamp(1, 6);

      final groupCells = List<String>.generate(6, (idx) {
        final gg = idx + 1;
        return (gg == g) ? c : '';
      });

      out.add(
        _ExcelRow(programacion: c, grid: mergedGrid, groupCells: groupCells),
      );
    }

    return out;
  }

  List<String> _mergeGrids(List<AgendaReservaItem> items) {
    List<String> ensure6(List<String> g) =>
        (g.length == 6) ? g : List.filled(6, '');

    int priority(String v) {
      switch (v) {
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

    for (final it in items) {
      final g = ensure6(it.grid);
      for (int i = 0; i < 6; i++) {
        final cur = merged[i];
        final nxt = g[i];
        if (priority(nxt) > priority(cur)) merged[i] = nxt;
      }
    }

    return merged;
  }

  // =========================
  // Header con números
  // =========================
  Widget _headerRow() {
    final nums = _dayNumbers(anio, mes, semana);

    return Row(
      children: [
        _hdr('PROGRAMACIÓN', _wProg),
        ...List.generate(
          6,
          (i) => _hdrMultiline('${_days[i]}\n${nums[i]}', _wDay),
        ),
        for (int g = 1; g <= 6; g++) _hdr('GRUPO $g', _wGroup),
      ],
    );
  }

  // =========================
  // Fila
  // =========================
  Widget _rowWidget(_ExcelRow r) {
    return Row(
      children: [
        _cellText(r.programacion, _wProg, alignLeft: true),
        ...List.generate(6, (i) => _cellCode(r.grid[i], _wDay)),
        ...List.generate(6, (i) => _cellText(r.groupCells[i], _wGroup)),
      ],
    );
  }

  // =========================
  // Celdas
  // =========================
  Widget _hdr(String t, double w) => Container(
    width: w,
    height: 38,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black12),
      color: Colors.amber.shade300,
    ),
    child: Text(
      t,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w900),
    ),
  );

  Widget _hdrMultiline(String t, double w) => Container(
    width: w,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black12),
      color: Colors.amber.shade300,
    ),
    child: Text(
      t,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
    ),
  );

  Widget _cellText(String t, double w, {bool alignLeft = false}) => Container(
    width: w,
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black12),
      color: Colors.white,
    ),
    child: Text(
      t,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );

  Widget _cellCode(String code, double w) {
    Color bg = Colors.white;
    Color fg = Colors.black87;

    switch (code) {
      case 'E':
        bg = Colors.blue.withOpacity(.15);
        fg = Colors.blue.shade800;
        break;
      case 'A':
        bg = Colors.green.withOpacity(.18);
        fg = Colors.green.shade800;
        break;
      case 'P':
        bg = Colors.amber.withOpacity(.20);
        fg = Colors.brown.shade800;
        break;
      case 'R':
        bg = Colors.red.withOpacity(.15);
        fg = Colors.red.shade800;
        break;
      default:
        bg = Colors.white;
        fg = Colors.black87;
    }

    return Container(
      width: w,
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
}

class _ExcelRow {
  final String programacion; // conjunto
  final List<String> grid; // 6 (L..S)
  final List<String> groupCells; // 6 grupos

  _ExcelRow({
    required this.programacion,
    required this.grid,
    required this.groupCells,
  });
}
