import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/theme.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool obscureText;
  final TextInputType keyboardType;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.98, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          prefixIcon: icon != null
              ? Icon(icon, color: AppTheme.primary.withValues(alpha: 0.9))
              : null,
          labelText: label,
          labelStyle: theme.inputDecorationTheme.labelStyle,
          hintText: label,
          fillColor: Colors.white.withValues(alpha: 0.96),
          suffixIcon: obscureText
              ? const Icon(Icons.lock_outline_rounded, size: 18)
              : null,
        ),
      ),
    );
  }
}
