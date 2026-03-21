import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/animated_fade_slide.dart';

class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: AnimatedFadeSlide(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Colors.white, Color(0xFFF6FBF7)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.08)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x12084D31),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withValues(alpha: 0.10),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.08)),
                  ),
                  child: Icon(icon, size: 40, color: AppTheme.primary),
                ),
                const SizedBox(height: 18),
                Text(
                  'Aun no hay informacion',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
                if (onRetry != null) ...<Widget>[
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
