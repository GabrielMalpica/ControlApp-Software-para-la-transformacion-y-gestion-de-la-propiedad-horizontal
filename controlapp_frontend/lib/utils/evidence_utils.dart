import 'dart:convert';

import 'package:flutter_application_1/service/app_constants.dart';

final RegExp _httpUrlRx = RegExp(r'https?:\/\/[^\s<>"\]\[)]+');

String normalizeEvidenceRaw(String raw) {
  var value = raw.trim();
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    value = value.substring(1, value.length - 1).trim();
  }
  return value
      .replaceAll(r'\u003d', '=')
      .replaceAll(r'\u0026', '&')
      .replaceAll('&amp;', '&')
      .replaceAll('\\/', '/')
      .replaceAll(RegExp(r'[,.;]+$'), '');
}

String? _absoluteEvidenceUrl(String raw) {
  final value = normalizeEvidenceRaw(raw);
  if (value.isEmpty) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  if (value.startsWith('www.')) return 'https://$value';
  if (value.startsWith('/')) return '${AppConstants.baseUrl}$value';

  final looksRelative =
      value.startsWith('uploads/') ||
      value.startsWith('storage/') ||
      value.startsWith('files/') ||
      value.startsWith('evidencias/');
  if (looksRelative) return '${AppConstants.baseUrl}/$value';

  return null;
}

String? _urlFromEvidenceMap(Map<dynamic, dynamic> map) {
  const keys = [
    'url',
    'downloadUrl',
    'secureUrl',
    'fileUrl',
    'evidenciaUrl',
    'archivoUrl',
    'src',
    'href',
    'path',
  ];

  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = normalizeEvidenceRaw(value.toString());
    if (text.isNotEmpty) return text;
  }
  return null;
}

void _collectEvidence(dynamic raw, Set<String> out) {
  if (raw == null) return;

  if (raw is List) {
    for (final item in raw) {
      _collectEvidence(item, out);
    }
    return;
  }

  if (raw is Map) {
    final direct = _urlFromEvidenceMap(raw);
    if (direct != null) _collectEvidence(direct, out);
    if (raw['urls'] is List) _collectEvidence(raw['urls'], out);
    if (raw['evidencias'] is List) _collectEvidence(raw['evidencias'], out);
    for (final value in raw.values) {
      if (value is Map || value is List) _collectEvidence(value, out);
    }
    return;
  }

  final value = normalizeEvidenceRaw(raw.toString());
  if (value.isEmpty) return;

  if ((value.startsWith('{') && value.endsWith('}')) ||
      (value.startsWith('[') && value.endsWith(']'))) {
    try {
      _collectEvidence(jsonDecode(value), out);
      return;
    } catch (_) {
      // seguimos con parseo plano
    }
  }

  final matches = _httpUrlRx
      .allMatches(value)
      .map((m) => value.substring(m.start, m.end));
  if (matches.isNotEmpty) {
    for (final match in matches) {
      final absolute = _absoluteEvidenceUrl(match);
      if (absolute != null && absolute.isNotEmpty) out.add(absolute);
    }
    return;
  }

  final absolute = _absoluteEvidenceUrl(value);
  if (absolute != null && absolute.isNotEmpty) {
    out.add(absolute);
    return;
  }

  if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(value)) {
    out.add(value);
  }
}

List<String> extractEvidenceUrls(dynamic raw) {
  final out = <String>{};
  _collectEvidence(raw, out);
  return out.toList();
}

String? extractDriveId(String input) {
  final value = normalizeEvidenceRaw(input);
  final directId = RegExp(r'^[a-zA-Z0-9_-]{20,}$').firstMatch(value);
  if (directId != null) return directId.group(0);

  final uri = Uri.tryParse(value);
  final queryId = uri?.queryParameters['id'];
  if (queryId != null && queryId.trim().isNotEmpty) return queryId.trim();

  final patterns = [
    RegExp(r'/d/([a-zA-Z0-9_-]{20,})'),
    RegExp(r'id=([a-zA-Z0-9_-]{20,})'),
    RegExp(r'file/d/([a-zA-Z0-9_-]{20,})'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(value);
    if (match != null && match.groupCount >= 1) return match.group(1);
  }
  return null;
}

List<String> evidenceUrlCandidates(String raw) {
  final clean = normalizeEvidenceRaw(raw);
  final out = <String>[];
  final seen = <String>{};

  void add(String? value) {
    if (value == null) return;
    final normalized = normalizeEvidenceRaw(value);
    if (normalized.isEmpty || seen.contains(normalized)) return;
    seen.add(normalized);
    out.add(normalized);
  }

  for (final url in extractEvidenceUrls(clean)) {
    final absolute = _absoluteEvidenceUrl(url);
    if (absolute != null) {
      add(absolute);
      continue;
    }
    if (extractDriveId(url) == null) add(url);
  }

  final absolute = _absoluteEvidenceUrl(clean);
  add(absolute);

  final driveId = extractDriveId(clean);
  if (driveId != null) {
    add('https://drive.google.com/thumbnail?id=$driveId&sz=w2000');
    add('https://drive.google.com/uc?export=view&id=$driveId');
    add('https://drive.google.com/uc?export=download&id=$driveId');
    add('https://lh3.googleusercontent.com/d/$driveId=w2000');
    add('https://lh3.googleusercontent.com/d/$driveId=s2000');
    add(
      'https://drive.usercontent.google.com/download?id=$driveId&export=view',
    );
    add(
      'https://drive.usercontent.google.com/download?id=$driveId&export=download',
    );
  }

  return out;
}

bool isLikelyImageEvidence(String raw) {
  final lower = normalizeEvidenceRaw(raw).toLowerCase();
  if (lower.startsWith('data:image/')) return true;
  if (extractDriveId(raw) != null) return true;

  bool hasImageExt(String value) {
    final clean = value.toLowerCase();
    return clean.endsWith('.jpg') ||
        clean.endsWith('.jpeg') ||
        clean.endsWith('.png') ||
        clean.endsWith('.webp') ||
        clean.endsWith('.gif') ||
        clean.contains('.jpg?') ||
        clean.contains('.jpeg?') ||
        clean.contains('.png?') ||
        clean.contains('.webp?') ||
        clean.contains('.gif?');
  }

  if (hasImageExt(lower)) return true;

  for (final candidate in evidenceUrlCandidates(raw)) {
    final clean = candidate.toLowerCase();
    if (hasImageExt(clean) ||
        clean.contains('drive.google.com/thumbnail') ||
        clean.contains('googleusercontent.com')) {
      return true;
    }
  }

  return false;
}
