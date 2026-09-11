import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/theme.dart';

class DashboardTile extends StatefulWidget {
  const DashboardTile({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    this.onTap,
  });

  final String title;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<DashboardTile> createState() => _DashboardTileState();
}

class _DashboardTileState extends State<DashboardTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: RepaintBoundary(
        child: AnimatedScale(
          scale: _hovered ? 1.015 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white,
              border: Border.all(
                color: _hovered
                    ? baseColor.withValues(alpha: 0.28)
                    : AppTheme.primary.withValues(alpha: 0.08),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(
                    0x12084D31,
                  ).withValues(alpha: _hovered ? 0.95 : 0.72),
                  blurRadius: _hovered ? 28 : 18,
                  offset: Offset(0, _hovered ? 14 : 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // El contenido (icono + título) tiene un tamaño
                      // "ideal" fijo, pero la tarjeta puede volverse muy
                      // baja en móviles con grillas de 2-3 columnas. En vez
                      // de dejar que el Column desborde (RenderFlex
                      // overflow), lo escalamos hacia abajo con FittedBox
                      // para que siempre quepa, sin importar la resolución.
                      final barHeight = constraints.maxHeight < 170
                          ? 40.0
                          : 52.0;
                      final iconSize = constraints.maxHeight < 170
                          ? 60.0
                          : 82.0;

                      return Column(
                        children: <Widget>[
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth - 20,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        width: iconSize,
                                        height: iconSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            colors: <Color>[
                                              baseColor.withValues(
                                                alpha: _hovered ? 0.24 : 0.18,
                                              ),
                                              baseColor.withValues(alpha: 0.06),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: baseColor.withValues(
                                              alpha: 0.10,
                                            ),
                                          ),
                                        ),
                                        child: Icon(
                                          widget.icon,
                                          size: iconSize * 0.51,
                                          color: baseColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        widget.title,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: barHeight,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: <Color>[
                                        baseColor.withValues(alpha: 0.88),
                                        baseColor.withValues(alpha: 0.68),
                                      ],
                                    ),
                                  ),
                                ),
                                CustomPaint(
                                  painter: _BubblePatternPainter(baseColor),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 14),
                                    child: Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePatternPainter extends CustomPainter {
  const _BubblePatternPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paintA = Paint()..color = color.withValues(alpha: 0.18);
    final paintB = Paint()..color = color.withValues(alpha: 0.10);
    final random = math.Random((size.width * 19 + size.height * 11).round());

    for (var i = 0; i < 22; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final radius = 2.2 + random.nextDouble() * 6.0;
      canvas.drawCircle(Offset(dx, dy), radius, i.isEven ? paintA : paintB);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePatternPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
