import 'dart:convert';

import 'package:flutter_application_1/model/saldo_servicio_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

/// Saldos de servicios pagados con anticipo (los del usuario) y la lista de
/// clientes en mora (gerente / jefe de operaciones).
class SaldosApi {
  final ApiClient _client = ApiClient();

  String get _base => AppConstants.commerceBase;

  Future<List<SaldoServicio>> listarMios() async {
    final response = await _client.get('$_base/saldos');
    _ensureSuccess(response.statusCode, response.body);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const <SaldoServicio>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SaldoServicio.fromJson)
        .toList();
  }

  Future<SaldoServicio> obtener(int saldoId) async {
    final response = await _client.get('$_base/saldos/$saldoId');
    _ensureSuccess(response.statusCode, response.body);
    return SaldoServicio.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Genera (o devuelve el vigente) el código para pagar lo que falta. El
  /// monto lo pone el servidor.
  Future<SaldoServicio> pagar(int saldoId) async {
    final response = await _client.post('$_base/saldos/$saldoId/pago');
    _ensureSuccess(response.statusCode, response.body);
    return SaldoServicio.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// "Ya pagué": consulta el pago ahora mismo.
  Future<SaldoServicio> verificar(int saldoId) async {
    final response = await _client.post(
      '$_base/saldos/$saldoId/pago/verificar',
    );
    _ensureSuccess(response.statusCode, response.body);
    return SaldoServicio.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<MoraListado> listarMora({
    String estado = 'PENDIENTE',
    String? q,
    int pagina = 1,
  }) async {
    final params = <String, String>{
      'estado': estado,
      'pagina': '$pagina',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };
    final query = Uri(queryParameters: params).query;
    final response = await _client.get('$_base/mora?$query');
    _ensureSuccess(response.statusCode, response.body);
    return MoraListado.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Registra que el saldo se pagó por fuera (efectivo, transferencia
  /// directa). Devuelve si había un código de pago vigente.
  Future<bool> registrarPagoPorFuera(int saldoId, String motivo) async {
    final response = await _client.post(
      '$_base/mora/$saldoId/resolver',
      body: {'motivo': motivo},
    );
    _ensureSuccess(response.statusCode, response.body);
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> &&
        decoded['habiaCodigoVigente'] == true;
  }

  void _ensureSuccess(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw Exception(
      AppError.fromResponseBody(
        body,
        fallback: 'No se pudo completar la acción del saldo.',
      ),
    );
  }
}
