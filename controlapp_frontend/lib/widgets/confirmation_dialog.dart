// lib/widgets/confirmation_dialog.dart
import 'package:flutter/material.dart';
import 'custom_button.dart';

Future<bool?> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = "Confirmar",
  String cancelText = "Cancelar",
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelText),
        ),
        CustomButton(
          text: confirmText,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
}
