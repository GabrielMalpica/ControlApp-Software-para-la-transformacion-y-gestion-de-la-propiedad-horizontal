import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/theme.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isLoading;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isPrimary = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: onPressed == null && !isLoading ? 0.72 : 1,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: (isPrimary
                ? theme.elevatedButtonTheme.style
                : theme.outlinedButtonTheme.style)
            ?.copyWith(
              backgroundColor: isPrimary
                  ? WidgetStatePropertyAll<Color>(AppTheme.primary)
                  : const WidgetStatePropertyAll<Color>(Colors.white),
              foregroundColor: WidgetStatePropertyAll<Color>(
                isPrimary ? Colors.white : AppTheme.primary,
              ),
              side: isPrimary
                  ? const WidgetStatePropertyAll<BorderSide>(BorderSide.none)
                  : WidgetStatePropertyAll<BorderSide>(
                      BorderSide(color: AppTheme.primary.withValues(alpha: 0.16)),
                    ),
              padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  text,
                  key: ValueKey(text),
                  style: TextStyle(
                    color: isPrimary ? Colors.white : AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
