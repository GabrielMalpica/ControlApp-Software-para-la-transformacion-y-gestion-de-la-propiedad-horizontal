import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/compromiso_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';

class CompromisosPorConjuntoPage extends StatefulWidget {
  const CompromisosPorConjuntoPage({super.key});

  @override
  State<CompromisosPorConjuntoPage> createState() =>
      _CompromisosPorConjuntoPageState();
}

class _CompromisosPorConjuntoPageState
    extends State<CompromisosPorConjuntoPage> {
  final GerenteApi _gerenteApi = GerenteApi();

  bool _loading = true;
  String _query = '';
  String? _error;
  List<_CompromisoConjuntoGroup> _groups = [];
  _CompromisoFilter _filter = _CompromisoFilter.todos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _gerenteApi.listarCompromisosGlobales();
      final byConjunto = <String, _CompromisoConjuntoGroup>{};

      for (final item in raw) {
        final compromiso = CompromisoModel.fromJson(item);
        final nit = (item['conjuntoNit'] ?? item['conjuntoId'] ?? '')
            .toString();
        final nombre = (item['conjuntoNombre'] ?? 'Conjunto $nit').toString();
        byConjunto.putIfAbsent(
          nit,
          () => _CompromisoConjuntoGroup(nit: nit, nombre: nombre, items: []),
        );
        byConjunto[nit]!.items.add(compromiso);
      }

      final groups = byConjunto.values.toList()
        ..sort((a, b) {
          final pendingCompare = b.pendingCount.compareTo(a.pendingCount);
          if (pendingCompare != 0) return pendingCompare;
          return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
        });

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e);
        _loading = false;
      });
    }
  }

  bool _matchesFilter(CompromisoModel item) {
    switch (_filter) {
      case _CompromisoFilter.todos:
        return true;
      case _CompromisoFilter.abiertos:
        return !item.completado;
      case _CompromisoFilter.criticos:
        return !item.completado && item.ansColor == 'red';
      case _CompromisoFilter.verdes:
        return !item.completado && item.ansColor == 'green';
      case _CompromisoFilter.naranjas:
        return !item.completado && item.ansColor == 'orange';
      case _CompromisoFilter.rojos:
        return !item.completado && item.ansColor == 'red';
      case _CompromisoFilter.cerrados:
        return item.completado;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _groups
        .map(
          (group) => _CompromisoConjuntoGroup(
            nit: group.nit,
            nombre: group.nombre,
            items: group.items.where(_matchesFilter).toList(),
          ),
        )
        .where((group) => group.items.isNotEmpty)
        .where((group) {
          final q = _query.trim().toLowerCase();
          if (q.isEmpty) return true;
          final haystack = [
            group.nombre,
            group.nit,
            ...group.items.map((item) => item.titulo),
          ].join(' ').toLowerCase();
          return haystack.contains(q);
        })
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Compromisos por conjunto'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Buscar conjunto o compromiso',
                          hintText: 'Nombre del conjunto, NIT o compromiso',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _FilterChipButton(
                              label: 'Todos',
                              selected: _filter == _CompromisoFilter.todos,
                              onTap: () => setState(
                                () => _filter = _CompromisoFilter.todos,
                              ),
                            ),
                            _FilterChipButton(
                              label: 'Abiertos',
                              selected: _filter == _CompromisoFilter.abiertos,
                              onTap: () => setState(
                                () => _filter = _CompromisoFilter.abiertos,
                              ),
                            ),
                            _FilterChipButton(
                              label: 'Criticos',
                              selected: _filter == _CompromisoFilter.criticos,
                              onTap: () => setState(
                                () => _filter = _CompromisoFilter.criticos,
                              ),
                            ),
                            _FilterChipButton(
                              label: 'Verdes',
                              selected: _filter == _CompromisoFilter.verdes,
                              onTap: () => setState(
                                () => _filter = _CompromisoFilter.verdes,
                              ),
                            ),
                            _FilterChipButton(
                              label: 'Naranjas',
                              selected: _filter == _CompromisoFilter.naranjas,
                              onTap: () => setState(
                                () => _filter = _CompromisoFilter.naranjas,
                              ),
                            ),
                            _FilterChipButton(
                              label: 'Rojos',
                              selected: _filter == _CompromisoFilter.rojos,
                              onTap: () => setState(
                                () => _filter = _CompromisoFilter.rojos,
                              ),
                            ),
                            _FilterChipButton(
                              label: 'Cerrados',
                              selected: _filter == _CompromisoFilter.cerrados,
                              onTap: () => setState(
                                () => _filter = _CompromisoFilter.cerrados,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay compromisos registrados para mostrar.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final group = filtered[index];
                            return _ConjuntoCompromisoCard(group: group);
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _ConjuntoCompromisoCard extends StatelessWidget {
  const _ConjuntoCompromisoCard({required this.group});

  final _CompromisoConjuntoGroup group;

  Color _ansColor(String color) {
    switch (color) {
      case 'green':
        return const Color(0xFF2E7D32);
      case 'orange':
        return const Color(0xFFEF6C00);
      case 'red':
        return const Color(0xFFC62828);
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NIT: ${group.nit}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountPill(
                    label: 'Pendientes',
                    value: group.pendingCount.toString(),
                    color: Colors.orange,
                  ),
                  _CountPill(
                    label: 'Cumplidos',
                    value: group.completedCount.toString(),
                    color: Colors.green,
                  ),
                  _CountPill(
                    label: 'Verdes',
                    value: group.greenCount.toString(),
                    color: const Color(0xFF2E7D32),
                  ),
                  _CountPill(
                    label: 'Naranjas',
                    value: group.orangeCount.toString(),
                    color: const Color(0xFFEF6C00),
                  ),
                  _CountPill(
                    label: 'Rojos',
                    value: group.redCount.toString(),
                    color: const Color(0xFFC62828),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...group.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.completado
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: item.completado ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.titulo,
                          style: TextStyle(
                            color: item.completado
                                ? Colors.black54
                                : Colors.black87,
                            decoration: item.completado
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaChip(
                              icon: Icons.person_outline,
                              label: item.autorLabel,
                            ),
                            _MetaChip(
                              icon: Icons.schedule_rounded,
                              label: item.antiguedadLabel,
                            ),
                            _MetaChip(
                              icon: Icons.event_available_outlined,
                              label: item.fechaCreacionLabel,
                            ),
                            _MetaChip(
                              icon: item.completado
                                  ? Icons.task_alt_outlined
                                  : Icons.timelapse_rounded,
                              label: item.fechaCierreLabel,
                            ),
                            _MetaChip(
                              icon: Icons.flag_outlined,
                              label: item.ansLabel,
                              color: _ansColor(item.ansColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _CompromisoConjuntoGroup {
  _CompromisoConjuntoGroup({
    required this.nit,
    required this.nombre,
    required this.items,
  });

  final String nit;
  final String nombre;
  final List<CompromisoModel> items;

  int get pendingCount => items.where((item) => !item.completado).length;
  int get completedCount => items.where((item) => item.completado).length;
  int get greenCount => items
      .where((item) => !item.completado && item.ansColor == 'green')
      .length;
  int get orangeCount => items
      .where((item) => !item.completado && item.ansColor == 'orange')
      .length;
  int get redCount =>
      items.where((item) => !item.completado && item.ansColor == 'red').length;
}

enum _CompromisoFilter {
  todos,
  abiertos,
  criticos,
  verdes,
  naranjas,
  rojos,
  cerrados,
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppTheme.primary : Colors.black12,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: chipColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
