// Kit de skeleton loading compartido: reemplaza los spinners bloqueantes
// (CircularProgressIndicator centrado en pantalla en blanco) por placeholders
// que imitan la forma del contenido real, con una animacion tipo "shimmer"
// propia (sin dependencias nuevas: solo AnimationController + LinearGradient
// animado, siguiendo AGENTS.md "prefer Flutter/Dart SDK facilities before
// new packages").
import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/theme.dart';

/// Controla una unica animacion de shimmer y la comparte con todos los
/// [Skeleton] descendientes via [InheritedWidget], para no crear un
/// [AnimationController] por cada caja skeleton de la pantalla.
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();

  static Animation<double>? _maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SkeletonShimmerScope>();
    return scope?.animation;
  }
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SkeletonShimmerScope(
      animation: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class _SkeletonShimmerScope extends InheritedWidget {
  const _SkeletonShimmerScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_SkeletonShimmerScope oldWidget) => false;
}

/// Caja base del skeleton: un rectangulo con esquinas redondeadas cuyo color
/// oscila suavemente entre [AppTheme.surfaceSoft] y blanco. Si no hay un
/// [SkeletonShimmer] ancestro, se auto-envuelve en uno (asi cada widget de
/// este archivo funciona de forma independiente).
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final animation = SkeletonShimmer._maybeOf(context);
    if (animation == null) {
      return SkeletonShimmer(
        child: Builder(builder: (context) => _box(context)),
      );
    }
    return _box(context);
  }

  Widget _box(BuildContext context) {
    final animation = SkeletonShimmer._maybeOf(context)!;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppTheme.surfaceSoft,
              Colors.white,
              animation.value,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        );
      },
    );
  }
}

/// Linea de texto placeholder. [widthFactor] la acorta respecto al ancho
/// disponible (1.0 = ancho completo) para que varias lineas no luzcan como
/// bloques identicos.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1.0, this.height = 14});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor.clamp(0.1, 1.0),
      alignment: Alignment.centerLeft,
      child: Skeleton(height: height, borderRadius: height / 2.5),
    );
  }
}

/// Placeholder circular (avatar / icono).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Skeleton(width: size, height: size, borderRadius: size / 2);
  }
}

/// Tarjeta placeholder con el mismo borde/sombra/radio que [SectionCard], asi
/// el layout no "salta" cuando el contenido real reemplaza al skeleton.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.lines = 3,
    this.showAvatar = false,
    this.height,
  });

  final int lines;
  final bool showAvatar;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.08)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12084D31),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar) ...[
            const SkeletonCircle(size: 44),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  SkeletonLine(widthFactor: i == 0 ? 0.55 : 1 - (i * 0.12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista vertical de filas placeholder, para reemplazar un `ListView` de
/// tarjetas/registros mientras carga.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.items = 4,
    this.lines = 2,
    this.showAvatar = false,
    this.padding = const EdgeInsets.all(16),
  });

  final int items;
  final int lines;
  final bool showAvatar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: items,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) =>
            SkeletonCard(lines: lines, showAvatar: showAvatar),
      ),
    );
  }
}

/// Grilla de tiles placeholder, para pantallas de inicio con accesos rapidos
/// (gerente, supervisor, administrador, jefe de operaciones).
class SkeletonDashboardGrid extends StatelessWidget {
  const SkeletonDashboardGrid({
    super.key,
    this.tiles = 6,
    this.crossAxisCount = 2,
    this.padding = const EdgeInsets.all(16),
  });

  final int tiles;
  final int crossAxisCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonLine(widthFactor: 0.4, height: 20),
            const SizedBox(height: 16),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: tiles,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (_, __) => Skeleton(borderRadius: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tabla placeholder para las matrices de cronograma (filas x dias).
class SkeletonTable extends StatelessWidget {
  const SkeletonTable({super.key, this.rows = 8, this.cols = 6});

  final int rows;
  final int cols;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(child: Skeleton(height: 16)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) const SizedBox(height: 10),
              Row(
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) const SizedBox(width: 10),
                    Expanded(child: Skeleton(height: 36, borderRadius: 10)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
