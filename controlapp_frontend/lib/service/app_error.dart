import 'dart:convert';

class AppError {
  static const String _defaultFallback = 'No se pudo completar la solicitud.';

  static String messageOf(Object? error, {String fallback = _defaultFallback}) {
    if (error == null) return fallback;

    final structured = _messageFromStructured(error, fallback: fallback);
    if (structured != null) return structured;

    return _messageFromText(error.toString(), fallback: fallback);
  }

  static String fromResponseBody(String body, {required String fallback}) {
    final structured = _messageFromStructured(_tryDecodeJson(body));
    if (structured != null) return structured;
    return _messageFromText(body, fallback: fallback);
  }

  static String _messageFromText(String raw, {required String fallback}) {
    var text = _fixMojibake(raw).trim();
    if (text.isEmpty) return fallback;

    final embeddedJson = _extractEmbeddedJson(text);
    if (embeddedJson != null) {
      final structured = _messageFromStructured(_tryDecodeJson(embeddedJson));
      if (structured != null) return structured;
    }

    text = text
        .replaceFirst(
          RegExp(
            r'^(?:[A-Za-z_][A-Za-z0-9_]*Exception:\s*)+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'^ApiError\(\d+\):\s*'), '')
        .replaceFirst(RegExp(r'^Error:\s*', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'^[\u2705\u274c\u26a0\ufe0f\s]+', unicode: true),
          '',
        )
        .trim();

    final mappedCode = _mapKnownCode(text);
    if (mappedCode != null) return mappedCode;

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? fallback : text;
  }

  static String? _messageFromStructured(
    dynamic value, {
    String fallback = _defaultFallback,
  }) {
    if (value == null) return null;

    if (value is String) {
      final text = _messageFromText(value, fallback: '');
      return text.isEmpty ? null : text;
    }

    if (value is List) {
      final details = _collectDetailMessages(value);
      if (details.isEmpty) return null;
      return details.join('\n');
    }

    if (value is Map) {
      final details = _collectDetailMessages(
        value['details'] ?? value['issues'] ?? value['errors'],
      );

      final directMessage = _firstNonEmptyString([
        value['message'],
        value['error'],
        value['detail'],
        value['title'],
        value['reason'],
        value['code'],
      ]);

      if (directMessage != null) {
        final parsed = _messageFromText(directMessage, fallback: fallback);
        if (_isGenericMessage(parsed) && details.isNotEmpty) {
          return details.join('\n');
        }
        return parsed;
      }

      if (details.isNotEmpty) return details.join('\n');
    }

    return null;
  }

  static List<String> _collectDetailMessages(dynamic value) {
    final out = <String>[];

    void collect(dynamic entry) {
      if (entry == null) return;

      if (entry is String) {
        final message = _messageFromText(entry, fallback: '');
        if (message.isNotEmpty) out.add(message);
        return;
      }

      if (entry is List) {
        for (final item in entry) {
          collect(item);
        }
        return;
      }

      if (entry is Map) {
        final field = _fieldNameOf(entry['field'] ?? entry['path']);
        final directMessage = _firstNonEmptyString([
          entry['message'],
          entry['error'],
          entry['detail'],
          entry['reason'],
          entry['code'],
        ]);

        if (directMessage != null) {
          final message = _messageFromText(directMessage, fallback: '');
          if (message.isNotEmpty) {
            if (field != null && !_containsFieldName(message, field)) {
              out.add('$field: $message');
            } else {
              out.add(message);
            }
          }
        }

        collect(entry['details']);
        collect(entry['issues']);
        collect(entry['errors']);
      }
    }

    collect(value);

    final unique = <String>[];
    for (final item in out) {
      final normalized = item.trim();
      if (normalized.isEmpty) continue;
      if (!unique.contains(normalized)) {
        unique.add(normalized);
      }
      if (unique.length == 3) break;
    }
    return unique;
  }

  static String? _extractEmbeddedJson(String text) {
    final objectStart = text.indexOf('{');
    final arrayStart = text.indexOf('[');

    var start = -1;
    if (objectStart >= 0 && arrayStart >= 0) {
      start = objectStart < arrayStart ? objectStart : arrayStart;
    } else if (objectStart >= 0) {
      start = objectStart;
    } else if (arrayStart >= 0) {
      start = arrayStart;
    }

    if (start < 0) return null;

    final candidate = text.substring(start).trim();
    return _tryDecodeJson(candidate) != null ? candidate : null;
  }

  static dynamic _tryDecodeJson(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return null;
    }

    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  static String? _firstNonEmptyString(List<dynamic> candidates) {
    for (final candidate in candidates) {
      if (candidate is String) {
        final text = _fixMojibake(candidate).trim();
        if (text.isNotEmpty) return text;
      }

      if (candidate is List && candidate.isNotEmpty) {
        final nested = _firstNonEmptyString(candidate);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static String? _fieldNameOf(dynamic field) {
    if (field == null) return null;

    if (field is List) {
      final parts = field
          .map((part) => _fixMojibake(part.toString()).trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) return null;
      return parts.join('.');
    }

    final text = _fixMojibake(field.toString()).trim();
    return text.isEmpty ? null : text;
  }

  static bool _containsFieldName(String message, String field) {
    return message.toLowerCase().contains(field.toLowerCase());
  }

  static bool _isGenericMessage(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized == 'no se pudo completar la solicitud.' ||
        normalized == 'no se pudo completar la solicitud' ||
        normalized == 'ocurrio un error.' ||
        normalized == 'ocurrio una novedad.' ||
        normalized == 'revisa la informacion ingresada.' ||
        normalized == 'datos invalidos.' ||
        normalized == 'solicitud invalida.';
  }

  static String? _mapKnownCode(String message) {
    final normalized = _fixMojibake(message).trim();
    if (normalized.isEmpty) return null;

    if (RegExp(
      r'^MAQUINARIA_OCUPADA_\d+$',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return 'La maquinaria seleccionada ya esta ocupada en ese horario.';
    }

    switch (normalized.toUpperCase()) {
      case 'EMAIL_YA_REGISTRADO':
        return 'Ya existe un usuario con ese correo.';
      case 'NO_ES_CORRECTIVA':
        return 'Solo aplica para tareas correctivas.';
      case 'MOTIVO_REQUERIDO':
        return 'Debes indicar un motivo para continuar.';
      case 'ACCION_REEMPLAZO_REQUERIDA':
        return 'Debes elegir como reemplazar las tareas afectadas.';
      case 'REEMPLAZO_NO_VALIDO':
        return 'La seleccion no permite realizar ese reemplazo.';
      case 'REEMPLAZO_SOLO_PREVENTIVA':
        return 'Solo se pueden reemplazar tareas preventivas.';
      default:
        return null;
    }
  }

  static String _fixMojibake(String text) {
    return text
        .replaceAll('Ã¡', 'a')
        .replaceAll('Ã©', 'e')
        .replaceAll('Ã­', 'i')
        .replaceAll('Ã³', 'o')
        .replaceAll('Ãº', 'u')
        .replaceAll('Ã±', 'n')
        .replaceAll('Ã¼', 'u')
        .replaceAll('Â¿', '')
        .replaceAll('Â¡', '')
        .replaceAll('âœ…', '')
        .replaceAll('âŒ', '')
        .replaceAll('âš ', '')
        .replaceAll('â€¦', '...')
        .replaceAll('â€“', '-')
        .replaceAll('â€”', '-')
        .replaceAll('â€˜', "'")
        .replaceAll('â€™', "'")
        .replaceAll('â€œ', '"')
        .replaceAll('â€', '"')
        .replaceAll('\u00a0', ' ');
  }
}
