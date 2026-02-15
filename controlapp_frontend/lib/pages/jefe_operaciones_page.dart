import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/jefe_operaciones/jefe_operaciones_pendientes_page.dart';
import 'package:flutter_application_1/service/app_constants.dart';

import '../service/theme.dart';
import 'maquinaria_page.dart';
import 'inventario_page.dart';
import 'solicitudes_page.dart';
import 'cronograma_page.dart';

class JefeOperacionesPage extends StatefulWidget {
  const JefeOperacionesPage({super.key});

  @override
  State<JefeOperacionesPage> createState() => _JefeOperacionesPageState();
}

class _JefeOperacionesPageState extends State<JefeOperacionesPage> {
  final GerenteApi _api = GerenteApi();

  List<Conjunto> _conjuntos = [];
  String? _conjuntoSeleccionadoNit;

  bool _loading = true;
  String? _error;

  Conjunto? get _conjuntoSeleccionado {
    if (_conjuntoSeleccionadoNit == null) return null;
    try {
      return _conjuntos.firstWhere((c) => c.nit == _conjuntoSeleccionadoNit);
    } catch (_) {
      return _conjuntos.isNotEmpty ? _conjuntos.first : null;
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarConjuntos();
  }

  Future<void> _cargarConjuntos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final lista = await _api.listarConjuntos();
      setState(() {
        _conjuntos = lista;
        _conjuntoSeleccionadoNit = lista.isNotEmpty ? lista.first.nit : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 🔹 Tarjeta simple
  int _gridCountForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  Widget _simpleCard(
    String title,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.12),
                        ),
                        child: Icon(icon, size: 44, color: color),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 46, color: color.withOpacity(0.10)),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔹 Atajos (usa el NIT seleccionado)
  Widget _atajos(String nit) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12.withOpacity(0.05), blurRadius: 5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Atajos",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.12),
                        ),
                        child: Icon(icon, size: 44, color: color),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 46,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: color.withOpacity(0.10)),
                    CustomPaint(painter: _BubblePatternPainter(color)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔹 Atajos (usa el NIT seleccionado)
  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(child: Text("Error cargando conjuntos: $_error"));
    }

    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) {
      return const Center(
        child: Text(
          "No hay conjuntos disponibles.\nPide al gerente que registre/asigne conjuntos.",
          textAlign: TextAlign.center,
        ),
      );
    }

    final nit = conjunto.nit;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Selector tipo gerente (más bonito que el Row simple)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.apartment, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Conjunto seleccionado",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          conjunto.nombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text("NIT: $nit", style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  DropdownButton<String>(
                    value: _conjuntoSeleccionadoNit,
                    underline: const SizedBox.shrink(),
                    items: _conjuntos
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.nit,
                            child: Text(
                              c.nombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _conjuntoSeleccionadoNit = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: [
              _simpleCard(
                "Tareas",
                AppTheme.green,
                Icons.assignment,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => JefeOperacionesPendientesPage(conjuntoId: nit)),
                  );
                },
              ),
              _simpleCard(
                "Solicitudes",
                AppTheme.primary,
                Icons.pending_actions,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SolicitudesPage(nit: nit),
                    ),
                  );
                },
              ),
              _simpleCard(
                "Maquinaria",
                AppTheme.red,
                Icons.precision_manufacturing,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MaquinariaPage(nit: nit)),
                  );
                },
              ),
              _simpleCard(
                "Inventario",
                AppTheme.yellow,
                Icons.inventory,
                onTap: () {
                  // ✅ FIX: inventario usa NIT del conjunto + empresaId
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InventarioPage(
                        nit: nit,
                        empresaId: AppConstants.empresaNit,
                      ),
                    ),
                  );
                },
              ),
              _simpleCard(
                "Cronograma",
                Colors.purple,
                Icons.calendar_month,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CronogramaPage(nit: nit, )),
                  );
                },
              ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Panel Jefe de Operaciones",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: "Recargar conjuntos",
            onPressed: _cargarConjuntos,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}


class _BubblePatternPainter extends CustomPainter {
  final Color color;
  _BubblePatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    const xs = [0.04, 0.10, 0.22, 0.34, 0.48, 0.62, 0.74, 0.86, 0.92];
    const ys = [0.64, 0.32, 0.78, 0.40, 0.70, 0.36, 0.78, 0.52, 0.30];
    const rs = [3.5, 4.6, 2.8, 5.0, 3.8, 4.2, 3.0, 4.8, 3.2];

    for (var i = 0; i < xs.length; i++) {
      final c = Offset(size.width * xs[i], size.height * ys[i]);
      canvas.drawCircle(c, rs[i], paint);
      canvas.drawCircle(c.translate(18, -4), rs[i] * 0.55, paint);
      canvas.drawCircle(c.translate(-14, 6), rs[i] * 0.45, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
