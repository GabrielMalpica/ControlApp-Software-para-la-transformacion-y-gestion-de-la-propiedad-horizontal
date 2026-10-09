import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/theme.dart';

/// Desplazamientos horizontales que se mueven juntos: el encabezado fijo de
/// una tabla y cada una de sus filas. Las filas que se vuelven a construir al
/// recorrer la página arrancan en la misma posición que las demás.
class DesplazamientoEnlazado {
  final Map<int, ScrollController> _controladores = {};
  double _offset = 0;
  bool _moviendo = false;

  double get offset => _offset;

  /// Controlador de la fila [clave] (0 = encabezado).
  ScrollController controlador(int clave) =>
      _controladores.putIfAbsent(clave, () => _ControladorEnlazado(this));

  /// Se conecta a un `NotificationListener` que envuelva directamente el
  /// desplazamiento horizontal de cada fila.
  bool alDesplazar(ScrollNotification n) {
    if (_moviendo ||
        n.depth != 0 ||
        n.metrics.axis != Axis.horizontal ||
        n is! ScrollUpdateNotification) {
      return false;
    }
    _moverA(n.metrics.pixels);
    return false;
  }

  void _moverA(double pixels) {
    _offset = pixels;
    _moviendo = true;
    for (final c in _controladores.values) {
      for (final p in c.positions) {
        final destino = pixels.clamp(0.0, p.maxScrollExtent);
        if ((p.pixels - destino).abs() > 0.5) p.jumpTo(destino);
      }
    }
    _moviendo = false;
  }

  /// Mueve la tabla [delta] píxeles (negativo = hacia la izquierda).
  void desplazar(double delta) {
    for (final c in _controladores.values) {
      if (!c.hasClients) continue;
      final p = c.positions.first;
      final destino = (p.pixels + delta).clamp(0.0, p.maxScrollExtent);
      c.animateTo(
        destino,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
  }

  void dispose() {
    for (final c in _controladores.values) {
      c.dispose();
    }
    _controladores.clear();
  }
}

class _ControladorEnlazado extends ScrollController {
  final DesplazamientoEnlazado _grupo;

  _ControladorEnlazado(this._grupo) : super(keepScrollOffset: false);

  @override
  double get initialScrollOffset => _grupo.offset;
}

/// Aviso "la tabla sigue hacia los lados" con flechas grandes para moverla
/// sin tener que deslizar (con mouse no siempre es obvio cómo hacerlo).
class AvisoDesplazarLados extends StatelessWidget {
  final String texto;
  final VoidCallback onIzquierda;
  final VoidCallback onDerecha;

  const AvisoDesplazarLados({
    super.key,
    required this.texto,
    required this.onIzquierda,
    required this.onDerecha,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFBF0D6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, color: AppTheme.text),
            ),
          ),
          IconButton(
            tooltip: 'Ver días anteriores',
            onPressed: onIzquierda,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Ver días siguientes',
            onPressed: onDerecha,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// Encabezado fijo de altura conocida para `SliverPersistentHeader`.
class EncabezadoFijoDelegate extends SliverPersistentHeaderDelegate {
  final double alto;
  final Widget child;

  const EncabezadoFijoDelegate({required this.alto, required this.child});

  @override
  double get minExtent => alto;

  @override
  double get maxExtent => alto;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: alto,
      child: Material(
        color: Colors.white,
        elevation: overlapsContent ? 2 : 0,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(EncabezadoFijoDelegate oldDelegate) => true;
}
