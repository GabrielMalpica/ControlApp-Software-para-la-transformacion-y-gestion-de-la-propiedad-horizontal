import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/app_error.dart';

enum AppFeedbackType { info, error }

class AppFeedback {
  static bool _dialogOpen = false;

  static void showInfo(
    BuildContext context, {
    required String message,
    String title = 'Informacion',
  }) {
    _show(context, type: AppFeedbackType.info, title: title, message: message);
  }

  static void showError(
    BuildContext context, {
    required String message,
    String title = 'Error',
  }) {
    _show(context, type: AppFeedbackType.error, title: title, message: message);
  }

  static void showFromSnackBar(BuildContext context, SnackBar snackBar) {
    final rawMessage = _extractMessage(snackBar.content);
    final message = AppError.messageOf(
      rawMessage,
      fallback: 'Ocurrio una novedad.',
    );
    final isError = _looksLikeError(rawMessage, snackBar.backgroundColor);

    if (isError) {
      showError(context, message: message);
    } else {
      showInfo(context, message: message);
    }
  }

  static void _show(
    BuildContext context, {
    required AppFeedbackType type,
    required String title,
    required String message,
  }) {
    if (!context.mounted) return;

    final cleanMessage = message.trim().isEmpty
        ? 'Ocurrio una novedad.'
        : AppError.messageOf(message, fallback: 'Ocurrio una novedad.');

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _showBlockingDialog(
        context,
        type: type,
        title: title,
        message: cleanMessage,
      );
      return;
    }

    final isError = type == AppFeedbackType.error;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFF8D2C21)
              : const Color(0xFF114232),
          content: Row(
            children: <Widget>[
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$title: $cleanMessage',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
  }

  static void _showBlockingDialog(
    BuildContext context, {
    required AppFeedbackType type,
    required String title,
    required String message,
  }) {
    if (_dialogOpen || !context.mounted) return;
    _dialogOpen = true;

    final icon = type == AppFeedbackType.error
        ? Icons.error_outline
        : Icons.info_outline;
    final iconColor = type == AppFeedbackType.error
        ? Colors.redAccent
        : Colors.blueAccent;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: <Widget>[
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      ).whenComplete(() {
        _dialogOpen = false;
      }),
    );
  }

  static bool _looksLikeError(String message, Color? backgroundColor) {
    final m = _normalize(message);

    if (backgroundColor != null) {
      final red = (backgroundColor.r * 255.0).round().clamp(0, 255);
      final green = (backgroundColor.g * 255.0).round().clamp(0, 255);
      final blue = (backgroundColor.b * 255.0).round().clamp(0, 255);
      if (red > 160 && green < 120 && blue < 120) {
        return true;
      }
    }

    const infoWords = <String>[
      'correctamente',
      'cread',
      'actualiz',
      'eliminad',
      'enviad',
      'aprobad',
      'rechazad',
      'guardad',
      'registrad',
      'completad',
      'exito',
      'ok',
      'sugerencia aplicada',
      '✅',
    ];
    if (infoWords.any(m.contains)) return false;

    const errorWords = <String>[
      'error',
      '❌',
      'fall',
      'inval',
      'no se pudo',
      'no pude',
      'sin',
      'no hay',
      'debe ',
      'debes ',
      'seleccion',
      'cancelada',
      'cancelado',
      'falta',
      '⚠',
      'invalid',
    ];
    return errorWords.any(m.contains);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .trim();
  }

  static String _extractMessage(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText() ?? '';
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is Row) {
      return widget.children
          .map(_extractMessage)
          .where((t) => t.isNotEmpty)
          .join(' ');
    }
    if (widget is Column) {
      return widget.children
          .map(_extractMessage)
          .where((t) => t.isNotEmpty)
          .join(' ');
    }
    if (widget is Wrap) {
      return widget.children
          .map(_extractMessage)
          .where((t) => t.isNotEmpty)
          .join(' ');
    }
    if (widget is Padding && widget.child != null) {
      return _extractMessage(widget.child!);
    }
    if (widget is Align && widget.child != null) {
      return _extractMessage(widget.child!);
    }
    if (widget is Center && widget.child != null) {
      return _extractMessage(widget.child!);
    }
    if (widget is SizedBox && widget.child != null) {
      return _extractMessage(widget.child!);
    }
    if (widget is Expanded) {
      return _extractMessage(widget.child);
    }
    if (widget is Flexible) {
      return _extractMessage(widget.child);
    }
    return '';
  }
}
