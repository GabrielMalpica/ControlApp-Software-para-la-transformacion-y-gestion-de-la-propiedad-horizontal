import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/gerente_api.dart';
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
        final compromiso = _CompromisoResumen.fromJson(item);
        final nit = (item['conjuntoNit'] ?? item['conjuntoId'] ?? '').toString();
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

  @override
  Widget build(BuildContext context) {
    final filtered = _groups.where((group) {
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      final haystack = [
        group.nombre,
        group.nit,
        ...group.items.map((item) => item.titulo),
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Compromisos por conjunto'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
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
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar conjunto o compromiso',
                      hintText: 'Nombre del conjunto, NIT o compromiso',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setState(() => _query = value),
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
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                    child: Text(
                      item.titulo,
                      style: TextStyle(
                        color: item.completado ? Colors.black54 : Colors.black87,
                        decoration: item.completado
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
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
  final List<_CompromisoResumen> items;

  int get pendingCount => items.where((item) => !item.completado).length;
  int get completedCount => items.where((item) => item.completado).length;
}

class _CompromisoResumen {
  const _CompromisoResumen({required this.titulo, required this.completado});

  final String titulo;
  final bool completado;

  factory _CompromisoResumen.fromJson(Map<String, dynamic> json) {
    return _CompromisoResumen(
      titulo: (json['titulo'] ?? '').toString(),
      completado: json['completado'] == true,
    );
  }
}
