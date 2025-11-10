// lib/widgets/error_dialog.dart
import 'package:flutter/material.dart';
import 'custom_button.dart';

Future<void> showErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.error_outline, color: Colors.redAccent),
          SizedBox(width: 8),
          Text("Error"),
        ],
      ),
      content: Text(message),
      actions: [
        CustomButton(
          text: "Aceptar",
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}
