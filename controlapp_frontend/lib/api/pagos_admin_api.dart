import 'dart:convert';

import 'package:flutter_application_1/model/pago_admin_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

/// Panel de pagos del equipo (gerente / jefe de operaciones): rutas
/// /commerce/pagos del backend.
class PagosAdminApi {
  final ApiClient _client = ApiClient();

  Future<PagoAdminPagina> listar({
    String? estado,
    String? canal,
    bool soloRequierenAccion = false,
    String? busqueda,
    int pagina = 1,
  }) async {
    final query = <String, String>{
      'pagina': '$pagina',
      if (estado != null) 'estado': estado,
      if (canal != null) 'canal': canal,
      if (soloRequierenAccion) 'requierenAccion': 'true',
      if (busqueda != null && busqueda.trim().isNotEmpty) 'q': busqueda.trim(),
    };
    final response = await _client.get(
      '${AppConstants.commerceBase}/pagos?${Uri(queryParameters: query).query}',
    );
    _ensureSuccess(response.statusCode, response.body);
    return PagoAdminPagina.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<int> contarRequierenAccion() async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/pagos/conteo',
    );
    _ensureSuccess(response.statusCode, response.body);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['requierenAccion'] as num?)?.toInt() ?? 0;
  }

  Future<PagoAdminDetalle> detalle(int cobroId) async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/pagos/$cobroId',
    );
    _ensureSuccess(response.statusCode, response.body);
    return PagoAdminDetalle.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// [accion]: `DEVUELTO` (se devolvió el dinero) o `RESUELTO` (se resolvió
  /// por otra vía). Solo deja constancia; no mueve dinero ni reactiva pedidos.
  Future<PagoAdminDetalle> resolver(
    int cobroId, {
    required String accion,
    required String motivo,
  }) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/pagos/$cobroId/resolver',
      body: {'accion': accion, 'motivo': motivo},
    );
    _ensureSuccess(response.statusCode, response.body);
    return PagoAdminDetalle.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ConciliacionReporte?> ultimaConciliacion() async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/pagos/conciliacion',
    );
    _ensureSuccess(response.statusCode, response.body);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final reporte = json['reporte'];
    return reporte is Map<String, dynamic>
        ? ConciliacionReporte.fromJson(reporte)
        : null;
  }

  Future<ConciliacionReporte> conciliar() async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/pagos/conciliacion',
    );
    _ensureSuccess(response.statusCode, response.body);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ConciliacionReporte.fromJson(json['reporte'] as Map<String, dynamic>);
  }

  void _ensureSuccess(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw Exception(
      AppError.fromResponseBody(
        body,
        fallback: 'No se pudo completar la consulta de pagos.',
      ),
    );
  }
}
