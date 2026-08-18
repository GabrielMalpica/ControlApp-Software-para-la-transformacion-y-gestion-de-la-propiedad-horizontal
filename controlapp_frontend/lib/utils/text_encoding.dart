import 'dart:convert';

const Map<int, int> _windows1252Bytes = <int, int>{
  0x20AC: 0x80,
  0x201A: 0x82,
  0x0192: 0x83,
  0x201E: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02C6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8A,
  0x2039: 0x8B,
  0x0152: 0x8C,
  0x017D: 0x8E,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201C: 0x93,
  0x201D: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02DC: 0x98,
  0x2122: 0x99,
  0x0161: 0x9A,
  0x203A: 0x9B,
  0x0153: 0x9C,
  0x017E: 0x9E,
  0x0178: 0x9F,
};

/// Repara texto UTF-8 interpretado accidentalmente como Windows-1252.
///
/// Se permiten varias pasadas porque algunos datos históricos fueron
/// recodificados más de una vez. Si el texto ya es válido, se devuelve igual.
String repairMojibake(Object? raw) {
  var value = raw?.toString() ?? '';
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!value.contains(RegExp(r'[ÃÂâ]'))) break;

    final bytes = <int>[];
    var encodable = true;
    for (final rune in value.runes) {
      final byte = rune <= 0xff ? rune : _windows1252Bytes[rune];
      if (byte == null) {
        encodable = false;
        break;
      }
      bytes.add(byte);
    }
    if (!encodable) break;

    try {
      final repaired = utf8.decode(bytes, allowMalformed: false);
      if (repaired == value) break;
      value = repaired;
    } on FormatException {
      break;
    }
  }
  return value;
}
