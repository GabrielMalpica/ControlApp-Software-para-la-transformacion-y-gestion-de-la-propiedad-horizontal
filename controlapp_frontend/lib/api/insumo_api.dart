// lib/api/insumo_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../model/insumo_model.dart';
import '../service/app_constants.dart';
import '../service/session_service.dart';

class InsumoApi {
  final String baseUrl;
  final String empresaNit;
  final String? authToken; // opcional si usas JWT
  final SessionService _session = SessionService();

  InsumoApi({required this.baseUrl, required this.empresaNit, this.authToken});

  Uri _buildUri(String path) {
    return Uri.parse('$baseUrl$path');
  }

  Future<Map<String, String>> _headers() async {
    final sessionToken = (await _session.getToken())?.trim();
    final token = authToken?.trim().isNotEmpty == true
        ? authToken!.trim()
        : sessionToken;

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-empresa-id': AppConstants.empresaNit,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<InsumoResponse> crearInsumo(InsumoRequest request) async {
    final uri = _buildUri('/empresa/$empresaNit/catalogo/insumos');
    final resp = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode(request.toJson()),
    );

    if (resp.statusCode != 201) {
      throw Exception('Error al crear insumo: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return InsumoResponse.fromJson(data);
  }
}
