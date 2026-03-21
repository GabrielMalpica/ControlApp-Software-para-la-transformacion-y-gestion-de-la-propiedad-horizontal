import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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
      child: Padding(
        padding: padding ?? const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null || trailing != null) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (title != null)
                          Text(title!, style: theme.textTheme.titleMedium),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
