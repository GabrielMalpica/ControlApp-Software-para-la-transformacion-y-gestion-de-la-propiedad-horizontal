import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/animated_fade_slide.dart';
import 'package:flutter_application_1/widgets/empty_state.dart';
import 'package:flutter_application_1/widgets/searchable_select_field.dart';

class DashboardScaffold extends StatelessWidget {
  const DashboardScaffold({
    super.key,
    required this.title,
    required this.headline,
    required this.description,
    required this.child,
    this.leadingBadge,
    this.trailing,
  });

  final String title;
  final String headline;
  final String description;
  final Widget child;
  final String? leadingBadge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
      child: Stack(
        children: <Widget>[
          const Positioned(
            top: -110,
            right: -40,
            child: _AmbientCircle(size: 260, color: Color(0x140C6B43)),
          ),
          const Positioned(
            left: -80,
            bottom: -100,
            child: _AmbientCircle(size: 240, color: Color(0x14F2B84B)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AnimatedFadeSlide(
                        child: _DashboardHero(
                          title: title,
                          headline: headline,
                          description: description,
                          leadingBadge: leadingBadge,
                          trailing: trailing,
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedFadeSlide(
                        delay: const Duration(milliseconds: 80),
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardSurface extends StatelessWidget {
  const DashboardSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.08)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12084D31),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DashboardSection extends StatelessWidget {
  const DashboardSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class DashboardGrid extends StatelessWidget {
  const DashboardGrid({
    super.key,
    required this.children,
    this.minTileWidth = 220,
    this.childAspectRatio = 1.05,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final count = width >= 1120
            ? 4
            : width >= 820
            ? 3
            : width >= 560
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (_, index) => children[index],
        );
      },
    );
  }
}

class ConjuntoSelectorCard extends StatelessWidget {
  const ConjuntoSelectorCard({
    super.key,
    required this.conjuntoActual,
    required this.conjuntos,
    required this.selectedNit,
    required this.onChanged,
  });

  final Conjunto conjuntoActual;
  final List<Conjunto> conjuntos;
  final String? selectedNit;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardSurface(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final info = <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.apartment_rounded,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 14, height: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Conjunto activo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conjuntoActual.nombre,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'NIT: ${conjuntoActual.nit}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ];

          final selector = ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: compact ? 0 : 220,
              maxWidth: compact ? constraints.maxWidth : 320,
            ),
            child: SearchableSelectField<String>(
              label: 'Cambiar conjunto',
              value: selectedNit,
              prefixIcon: const Icon(Icons.swap_horiz_rounded),
              searchHint: 'Buscar conjunto o NIT',
              options: conjuntos
                  .map(
                    (conjunto) => SearchableSelectOption<String>(
                      value: conjunto.nit,
                      label: conjunto.nombre,
                      subtitle: 'NIT: ${conjunto.nit}',
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: info),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: selector),
              ],
            );
          }

          return Row(
            children: <Widget>[
              Expanded(child: Row(children: info)),
              const SizedBox(width: 16),
              selector,
            ],
          );
        },
      ),
    );
  }
}

class DashboardStatusCard extends StatelessWidget {
  const DashboardStatusCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppTheme.primary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(value, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardEmptyStateCard extends StatelessWidget {
  const DashboardEmptyStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DashboardSurface(
      child: EmptyState(icon: icon, message: '$title. $message'),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.title,
    required this.headline,
    required this.description,
    this.leadingBadge,
    this.trailing,
  });

  final String title;
  final String headline;
  final String description;
  final String? leadingBadge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final hasBadge =
              leadingBadge != null && leadingBadge!.trim().isNotEmpty;
          final hasHeadline = headline.trim().isNotEmpty;
          final hasDescription = description.trim().isNotEmpty;
          final hasDetails = hasBadge || hasHeadline || hasDescription;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (hasBadge) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    leadingBadge!,
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppTheme.primaryDark,
                ),
              ),
              if (hasHeadline) ...<Widget>[
                const SizedBox(height: 10),
                Text(headline, style: theme.textTheme.headlineMedium),
              ],
              if (hasDescription) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ],
          );

          if (compact || trailing == null || !hasDetails) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                summary,
                if (trailing != null) ...<Widget>[
                  const SizedBox(height: 18),
                  trailing!,
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 5, child: summary),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: trailing!),
            ],
          );
        },
      ),
    );
  }
}

class _AmbientCircle extends StatelessWidget {
  const _AmbientCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
