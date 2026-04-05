import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';

class MapaConjuntoPage extends StatefulWidget {
  const MapaConjuntoPage({
    super.key,
    required this.conjuntoNit,
    this.conjuntoInicial,
  });

  final String conjuntoNit;
  final Conjunto? conjuntoInicial;

  @override
  State<MapaConjuntoPage> createState() => _MapaConjuntoPageState();
}

class _MapaConjuntoPageState extends State<MapaConjuntoPage> {
  final GerenteApi _api = GerenteApi();
  late Future<Conjunto> _futureConjunto;
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _futureConjunto = widget.conjuntoInicial != null
        ? Future<Conjunto>.value(widget.conjuntoInicial!)
        : _api.obtenerConjunto(widget.conjuntoNit);
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureConjunto = _api.obtenerConjunto(widget.conjuntoNit);
    });
    await _futureConjunto;
  }

  List<UbicacionConElementos> _filtrarUbicaciones(
    List<UbicacionConElementos> items,
  ) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return items;

    return items.where((ubicacion) {
      final buffer = StringBuffer(ubicacion.nombre);
      for (final zona in ubicacion.elementos) {
        buffer.write(' ${zona.nombre}');
        for (final area in zona.hijos) {
          buffer.write(' ${area.nombre}');
        }
      }
      return buffer.toString().toLowerCase().contains(q);
    }).toList();
  }

  int _countZonas(List<UbicacionConElementos> items) {
    return items.fold<int>(0, (sum, item) => sum + item.elementos.length);
  }

  int _countAreas(List<UbicacionConElementos> items) {
    return items.fold<int>(0, (sum, item) {
      return sum +
          item.elementos.fold<int>(
            0,
            (inner, zona) => inner + zona.hijos.length,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Mapa del conjunto'),
      ),
      body: FutureBuilder<Conjunto>(
        future: _futureConjunto,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error: ${AppError.messageOf(snapshot.error)}'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final conjunto = snapshot.data!;
          final ubicaciones = _filtrarUbicaciones(conjunto.ubicaciones);
          final totalUbicaciones = conjunto.ubicaciones.length;
          final totalZonas = _countZonas(conjunto.ubicaciones);
          final totalAreas = _countAreas(conjunto.ubicaciones);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _ResumenMapaCard(
                  conjunto: conjunto,
                  ubicaciones: totalUbicaciones,
                  zonas: totalZonas,
                  areas: totalAreas,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _busquedaCtrl,
                  decoration: InputDecoration(
                    labelText: 'Buscar ubicación, subzona o área',
                    hintText: 'Ej. Torre A, Piscina, Lobby...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _busqueda.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _busquedaCtrl.clear();
                              setState(() => _busqueda = '');
                            },
                            icon: const Icon(Icons.clear_rounded),
                          ),
                  ),
                  onChanged: (value) => setState(() => _busqueda = value),
                ),
                const SizedBox(height: 14),
                if (ubicaciones.isEmpty)
                  const _EmptyMapaState()
                else
                  ...ubicaciones.map(
                    (ubicacion) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _UbicacionMapaCard(ubicacion: ubicacion),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResumenMapaCard extends StatelessWidget {
  const _ResumenMapaCard({
    required this.conjunto,
    required this.ubicaciones,
    required this.zonas,
    required this.areas,
  });

  final Conjunto conjunto;
  final int ubicaciones;
  final int zonas;
  final int areas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12084D31),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mapa espacial del conjunto',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${conjunto.nombre} · NIT ${conjunto.nit}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Aquí puedes entender rápidamente cómo está organizado el conjunto desde las ubicaciones principales hasta las áreas finales.',
            style: TextStyle(color: AppTheme.textMuted, height: 1.35),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(label: 'Ubicaciones', value: '$ubicaciones'),
              _InfoPill(label: 'Subzonas', value: '$zonas'),
              _InfoPill(label: 'Áreas finales', value: '$areas'),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppTheme.primaryDark,
        ),
      ),
    );
  }
}

class _UbicacionMapaCard extends StatelessWidget {
  const _UbicacionMapaCard({required this.ubicacion});

  final UbicacionConElementos ubicacion;

  @override
  Widget build(BuildContext context) {
    final totalAreas = ubicacion.elementos.fold<int>(
      0,
      (sum, zona) => sum + zona.hijos.length,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.domain_rounded, color: AppTheme.primary),
          ),
          title: Text(
            ubicacion.nombre,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          subtitle: Text(
            '${ubicacion.elementos.length} subzonas · $totalAreas áreas finales',
            style: const TextStyle(color: Colors.black54),
          ),
          children: [
            if (ubicacion.elementos.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No hay subzonas registradas todavía.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              ...ubicacion.elementos.map((zona) => _ZonaMapaCard(zona: zona)),
          ],
        ),
      ),
    );
  }
}

class _ZonaMapaCard extends StatelessWidget {
  const _ZonaMapaCard({required this.zona});

  final Elemento zona;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0ECE5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: AppTheme.green,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  zona.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                zona.hijos.isEmpty
                    ? 'Sin áreas'
                    : zona.hijos.length == 1
                    ? '1 área'
                    : '${zona.hijos.length} áreas',
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (zona.hijos.isEmpty)
            const Text(
              'No hay áreas finales registradas en esta subzona.',
              style: TextStyle(color: Colors.black54),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: zona.hijos
                  .map(
                    (area) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            area.nombre,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _EmptyMapaState extends StatelessWidget {
  const _EmptyMapaState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black12),
      ),
      child: const Column(
        children: [
          Icon(Icons.map_outlined, size: 46, color: Colors.grey),
          SizedBox(height: 10),
          Text(
            'No hay resultados para esa búsqueda o no existen ubicaciones registradas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
