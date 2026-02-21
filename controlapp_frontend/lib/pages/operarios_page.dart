import 'package:flutter/material.dart';
import '../service/theme.dart';
import 'tareas_page.dart';
import 'solicitudes_page.dart';
import 'package:flutter_application_1/service/logout.dart';
import 'package:flutter_application_1/widgets/notificaciones_action.dart';

class OperarioDashboardPage extends StatefulWidget {
  final String nit;
  const OperarioDashboardPage({super.key, required this.nit});

  @override
  State<OperarioDashboardPage> createState() => _OperarioDashboardPageState();
}

class _OperarioDashboardPageState extends State<OperarioDashboardPage> {
  int _gridCountForWidth(double w) {
    if (w >= 1100) return 4;
    if (w >= 800) return 4;
    if (w >= 520) return 3;
    return 2;
  }

  /// 🔹 Tarjeta simple
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

              // ✅ franja con patrón
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

  /// 🔹 Sección de atajos (si quieres)
  Widget _atajos() {
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
        children: const [
          Text(
            "Atajos",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 10),
          Text(
            "• Aquí puedes poner accesos rápidos (ej: “Solicitar insumo”)",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
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

    if (ok == true && mounted) logout(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Panel del Operario",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          const NotificacionesAction(),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final cols = _gridCountForWidth(c.maxWidth);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cols, // ✅ ahora sí responsivo
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
                          MaterialPageRoute(
                            builder: (_) => TareasPage(nit: widget.nit),
                          ),
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
                            builder: (_) => SolicitudesPage(nit: widget.nit),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ✅ opcional
                _atajos(),
              ],
            ),
          );
        },
      ),
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

