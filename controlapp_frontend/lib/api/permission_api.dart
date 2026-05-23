import 'dart:convert';

import 'package:flutter_application_1/model/permission_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

class PermissionApi {
  final ApiClient _client = ApiClient();

  Future<PermissionMatrixResponse> obtenerMatriz() async {
    final resp = await _client.get('${AppConstants.gerenteBase}/permisos');

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo cargar la matriz de permisos.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return PermissionMatrixResponse.fromJson(data);
  }

  Future<PermissionMatrixResponse> guardarMatriz(
    PermissionMatrixResponse matrix,
  ) async {
    final resp = await _client.put(
      '${AppConstants.gerenteBase}/permisos',
      body: matrix.toUpdatePayload(),
    );

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudieron guardar los permisos.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return PermissionMatrixResponse.fromJson(data);
  }
}
