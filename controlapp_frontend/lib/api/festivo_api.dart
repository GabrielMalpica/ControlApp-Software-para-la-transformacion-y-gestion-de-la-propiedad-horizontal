import 'dart:convert';

import '../service/api_client.dart';
import '../service/app_constants.dart';

class FestivoItem {
  final DateTime fecha; // local, start-of-day
  final String? nombre;

  FestivoItem({required this.fecha, this.nombre});

  factory FestivoItem.fromJson(Map<String, dynamic> json) {
    final raw = DateTime.parse(json['fecha']).toLocal();
    final d = DateTime(raw.year, raw.month, raw.day); // normalizado
    return FestivoItem(fecha: d, nombre: json['nombre']?.toString());
  }

  Map<String, dynamic> toJson() => {
    'fecha': _toYmd(fecha),
    if (nombre != null && nombre!.trim().isNotEmpty) 'nombre': nombre,
  };

  static String _toYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class FestivoApi {
  final ApiClient _client = ApiClient();

  String get _base => '${AppConstants.baseUrl}/empresa';

  static String _toYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<FestivoItem>> listarFestivosRango({
    required DateTime desde,
    required DateTime hasta,
    String pais = 'CO',
  }) async {
    final uri = Uri.parse('$_base/festivos').replace(
      queryParameters: {
        'desde': _toYmd(desde),
        'hasta': _toYmd(hasta),
        'pais': pais,
      },
    );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error listando festivos: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => FestivoItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Reemplaza TODO el rango [desde..hasta] con la lista de fechas enviada.
  /// Esto es perfecto para un calendario (guardar = dejar igual a lo seleccionado).
  Future<void> reemplazarFestivosEnRango({
    required DateTime desde,
    required DateTime hasta,
    required List<FestivoItem> fechas,
    String pais = 'CO',
  }) async {
    final body = {
      'pais': pais,
      'desde': _toYmd(desde),
      'hasta': _toYmd(hasta),
      'fechas': fechas.map((f) => f.toJson()).toList(),
    };

    // OJO: tu ApiClient debe tener put(). Si no, dime y te lo adapto a post con route alternativa.
    final resp = await _client.put('$_base/festivos/rango', body: body);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Error guardando festivos: ${resp.statusCode} ${resp.body}',
      );
    }
  }
}
