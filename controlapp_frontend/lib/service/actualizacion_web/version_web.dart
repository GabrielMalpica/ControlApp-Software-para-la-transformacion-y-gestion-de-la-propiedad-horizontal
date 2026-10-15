import 'package:intl/intl.dart';

/// Fecha de un encabezado HTTP ("Wed, 14 Oct 2026 19:41:58 GMT"), en UTC.
/// null si no viene o no se entiende.
DateTime? fechaHttp(String? texto) {
  final limpio = (texto ?? '').trim().replaceFirst(RegExp(r'\s*GMT$'), '');
  if (limpio.isEmpty) return null;
  try {
    return DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US').parseUtc(limpio);
  } catch (_) {
    return null;
  }
}

/// "14 oct 2026, 2:41 p. m." en la hora del dispositivo.
String textoVersionWeb(DateTime fecha) =>
    DateFormat('d MMM y, h:mm a', 'es').format(fecha.toLocal());
