import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/theme.dart';

/// Tokens exclusivos del marketplace. Mantienen la identidad verde de la app,
/// pero suman el contraste y la calidez propios de una experiencia de delivery.
abstract final class CommerceClayTokens {
  static const Color canvas = Color(0xFFF3F5EF);
  static const Color surface = Color(0xFFF9FAF6);
  static const Color surfaceStrong = Color(0xFFFFFFFF);
  static const Color mint = Color(0xFFE0F1E6);
  static const Color lime = Color(0xFFBDEB79);
  static const Color orange = Color(0xFFFF714B);
  static const Color orangeSoft = Color(0xFFFFE4DC);
  static const Color ink = Color(0xFF17251D);
  static const Color muted = Color(0xFF6F7C73);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF0A5E3D), Color(0xFF11835A), Color(0xFF39A66F)],
  );
}

class CommerceClayBackground extends StatelessWidget {
  const CommerceClayBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CommerceClayTokens.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Positioned(
            top: -90,
            right: -70,
            child: _AmbientOrb(size: 210, color: CommerceClayTokens.lime),
          ),
          const Positioned(
            bottom: 80,
            left: -100,
            child: _AmbientOrb(size: 230, color: CommerceClayTokens.mint),
          ),
          child,
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.26),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class CommerceClayCard extends StatelessWidget {
  const CommerceClayCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.onTap,
    this.color = CommerceClayTokens.surface,
    this.borderRadius = 24,
    this.depth = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color color;
  final double borderRadius;
  final double depth;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final shadowDepth = depth.clamp(0, 2).toDouble();
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
        boxShadow: shadowDepth == 0
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: const Color(
                    0xFF193C2C,
                  ).withValues(alpha: 0.08 * shadowDepth),
                  blurRadius: 18 * shadowDepth,
                  spreadRadius: -4,
                  offset: Offset(7 * shadowDepth, 10 * shadowDepth),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.92),
                  blurRadius: 12 * shadowDepth,
                  spreadRadius: -3,
                  offset: Offset(-5 * shadowDepth, -6 * shadowDepth),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class CommerceHeroCard extends StatelessWidget {
  const CommerceHeroCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: CommerceClayTokens.heroGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33084D31),
            blurRadius: 28,
            spreadRadius: -7,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            right: -28,
            top: -38,
            child: _AmbientOrb(size: 130, color: CommerceClayTokens.lime),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CommerceClayIcon(
                icon: icon,
                color: AppTheme.primaryDark,
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                size: 58,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      eyebrow.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: CommerceClayTokens.lime,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      style: textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing case final widget?) ...<Widget>[
                const SizedBox(width: 10),
                widget,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class CommerceClayIcon extends StatelessWidget {
  const CommerceClayIcon({
    super.key,
    required this.icon,
    this.color = AppTheme.primary,
    this.backgroundColor = CommerceClayTokens.mint,
    this.size = 48,
    this.iconSize = 24,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size * 0.34),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(4, 7),
          ),
          const BoxShadow(
            color: Color(0xCCFFFFFF),
            blurRadius: 8,
            offset: Offset(-3, -4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

class CommerceSectionHeader extends StatelessWidget {
  const CommerceSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
              if (subtitle case final value?) ...<Widget>[
                const SizedBox(height: 3),
                Text(value, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing case final widget?) widget,
      ],
    );
  }
}

class CommerceQuantityStepper extends StatelessWidget {
  const CommerceQuantityStepper({
    super.key,
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    this.compact = false,
  });

  final int quantity;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final buttonSize = compact ? 32.0 : 40.0;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: CommerceClayTokens.mint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepperButton(
            icon: Icons.remove_rounded,
            onPressed: onDecrease,
            size: buttonSize,
          ),
          SizedBox(
            width: compact ? 30 : 38,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            onPressed: onIncrease,
            size: buttonSize,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: IconButton.filled(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: filled ? AppTheme.primary : Colors.white,
          foregroundColor: filled ? Colors.white : AppTheme.primary,
          disabledBackgroundColor: Colors.white54,
          disabledForegroundColor: CommerceClayTokens.muted,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class CommerceCheckoutBar extends StatelessWidget {
  const CommerceCheckoutBar({
    super.key,
    required this.caption,
    required this.total,
    required this.actionLabel,
    required this.onPressed,
    this.loading = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String caption;
  final String total;
  final String actionLabel;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.fromLTRB(18, 13, 12, 13),
        decoration: BoxDecoration(
          color: CommerceClayTokens.surfaceStrong,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x24193C2C),
              blurRadius: 28,
              spreadRadius: -6,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(caption, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 1),
                  Text(
                    total,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: loading ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: CommerceClayTokens.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon),
              label: Text(loading ? 'Procesando...' : actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class CommerceStateView extends StatelessWidget {
  const CommerceStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: CommerceClayCard(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CommerceClayIcon(icon: icon, size: 68, iconSize: 34),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CommerceClayTokens.muted,
                ),
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CommerceNetworkImage extends StatelessWidget {
  const CommerceNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.inventory_2_outlined,
  });

  final String url;
  final BoxFit fit;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) return _fallback(fallbackIcon);

    return Image.network(
      url,
      fit: fit,
      webHtmlElementStrategy: kIsWeb
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return const ColoredBox(
          color: CommerceClayTokens.mint,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, __, ___) => _fallback(Icons.broken_image_outlined),
    );
  }

  Widget _fallback(IconData icon) {
    return ColoredBox(
      color: CommerceClayTokens.mint,
      child: Center(child: Icon(icon, color: AppTheme.primary, size: 30)),
    );
  }
}

class CommerceStatusPill extends StatelessWidget {
  const CommerceStatusPill({super.key, required this.status});

  final String status;

  String get _normalized => status.trim().toLowerCase();

  String get _label {
    switch (_normalized) {
      case 'pending':
      case 'pendiente_pago':
        return 'Pendiente de pago';
      case 'processing':
        return 'En proceso';
      case 'pagado':
        return 'Pagado';
      case 'pendiente_envio':
        return 'En preparación';
      case 'enviado':
        return 'En camino';
      case 'recibido':
        return 'Recibido';
      case 'on-hold':
        return 'En espera';
      case 'completed':
      case 'entregado':
        return 'Entregado';
      case 'cancelled':
      case 'canceled':
      case 'cancelado':
        return 'Cancelado';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color get _color {
    switch (_normalized) {
      case 'completed':
      case 'entregado':
      case 'recibido':
        return AppTheme.green;
      case 'cancelled':
      case 'canceled':
      case 'cancelado':
      case 'failed':
        return AppTheme.red;
      case 'processing':
      case 'pagado':
      case 'enviado':
        return AppTheme.secondary;
      case 'pendiente_envio':
        return AppTheme.primary;
      default:
        return const Color(0xFFAA6710);
    }
  }

  IconData get _icon {
    switch (_normalized) {
      case 'completed':
      case 'entregado':
      case 'recibido':
        return Icons.check_circle_rounded;
      case 'cancelled':
      case 'canceled':
      case 'cancelado':
      case 'failed':
        return Icons.cancel_rounded;
      case 'enviado':
        return Icons.delivery_dining_rounded;
      case 'processing':
      case 'pagado':
        return Icons.verified_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: 14, color: _color),
          const SizedBox(width: 5),
          Text(
            _label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
