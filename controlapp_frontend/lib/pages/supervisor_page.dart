import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/pages/supervisor/supervisor_tareas_page.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/widgets/cambiar_contrasena_action.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';

import '../service/theme.dart';

import 'solicitudes_page.dart';
import 'maquinaria_page.dart';
import 'inventario_page.dart';
import 'cronograma_page.dart';
import 'reportes_page.dart';
import 'preventivas_page.dart';
import '../service/app_constants.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class SupervisorPage extends StatefulWidget {
  const SupervisorPage({super.key});

  @override
  State<SupervisorPage> createState() => _SupervisorPageState();
}

class _SupervisorPageState extends State<SupervisorPage> {
  final GerenteApi _api = GerenteApi();

  List<Conjunto> _conjuntos = [];
  String? _conjuntoSeleccionadoNit;

  bool _cargandoConjuntos = true;
  String? _errorConjuntos;

  Conjunto? get _conjuntoSeleccionado {
    final nit = _conjuntoSeleccionadoNit;
    if (nit == null) return null;

    try {
      return _conjuntos.firstWhere((c) => c.nit == nit);
    } catch (_) {
      return _conjuntos.isNotEmpty ? _conjuntos.first : null;
    }
  }

  bool get _hayConjunto => _conjuntoSeleccionado != null;

  @override
  void initState() {
    super.initState();
    _cargarConjuntos();
  }

  Future<void> _cargarConjuntos() async {
    setState(() {
      _cargandoConjuntos = true;
      _errorConjuntos = null;
    });

    try {
      final lista = await _api.listarConjuntos();
      setState(() {
        _conjuntos = lista;
        _conjuntoSeleccionadoNit = lista.isNotEmpty ? lista.first.nit : null;
        _cargandoConjuntos = false;
      });
    } catch (e) {
      setState(() {
        _errorConjuntos = e.toString();
        _cargandoConjuntos = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(msg)));
  }

  void _go(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  bool _requiereConjuntoOrWarn() {
    if (_hayConjunto) return true;
    _snack("Primero selecciona un conjunto para continuar.");
    return false;
  }

  int _gridCountForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  /// Tarjeta pequeña tipo gerente
  Widget _smallCard(
    String title,
    IconData icon,
    Color color, {
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
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

  Widget _buildSelectorConjuntoCard(Conjunto conjunto) {
    final nit = conjunto.nit;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _conjuntoSeleccionadoNit = v);

                // 🔹 Hook para cargas futuras por conjunto (si las agregas)
                // await _cargarResumenSupervisor(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_cargandoConjuntos) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorConjuntos != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text("Error cargando conjuntos: $_errorConjuntos"),
        ),
      );
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
          _buildSelectorConjuntoCard(conjunto),
          const SizedBox(height: 20),
          const Text(
            "Panel general",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),

          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4, // ✅ cuadritos pequeños como gerente
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _smallCard(
                "Tareas",
                Icons.assignment,
                AppTheme.green,
                onTap: () {
                  if (!_requiereConjuntoOrWarn()) return;
                  _go(SupervisorTareasPage(nit: nit));
                },
              ),
              _smallCard(
                "Solicitudes",
                Icons.pending_actions,
                AppTheme.primary,
                onTap: () {
                  if (!_requiereConjuntoOrWarn()) return;
                  _go(SolicitudesPage(nit: nit));
                },
              ),
              _smallCard(
                "Cronograma",
                Icons.calendar_month,
                Colors.purple,
                onTap: () {
                  if (!_requiereConjuntoOrWarn()) return;
                  _go(CronogramaPage(nit: nit));
                },
              ),
              _smallCard(
                "Inventario",
                Icons.inventory_2_outlined,
                AppTheme.yellow,
                onTap: () {
                  if (!_requiereConjuntoOrWarn()) return;
                  _go(
                    InventarioPage(
                      nit: nit,
                      empresaId: AppConstants.empresaNit,
                    ),
                  );
                },
              ),
              _smallCard(
                "Maquinaria",
                Icons.precision_manufacturing,
                AppTheme.red,
                onTap: () {
                  if (!_requiereConjuntoOrWarn()) return;
                  _go(MaquinariaPage(nit: nit));
                },
              ),
              _smallCard(
                "Reportes",
                Icons.bar_chart,
                Colors.teal,
                onTap: () {
                  if (!_requiereConjuntoOrWarn()) return;
                  _go(ReportesPage(nit: nit));
                },
              ),
              _smallCard(
                "Preventivas",
                Icons.build_circle_outlined,
                Colors.deepOrange,
                onTap: () {
                  if (!_requiereConjuntoOrWarn()) return;
                  _go(PreventivasPage(nit: nit));
                },
              ),
              _smallCard(
                "Recargar",
                Icons.refresh,
                Colors.blueGrey,
                onTap: _cargarConjuntos,
              ),
            ],
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
          "Panel del Supervisor",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          const NotificacionesAction(),
          const CambiarContrasenaAction(),
          IconButton(
            tooltip: "Recargar conjuntos",
            onPressed: _cargarConjuntos,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Seguro que quieres salir?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              );

              if (ok == true) logout(context);
            },
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
