// lib/api/insumo_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../model/insumo_model.dart';

class InsumoApi {
  final String baseUrl;
  final String empresaNit;
  final String? authToken; // opcional si usas JWT

  InsumoApi({required this.baseUrl, required this.empresaNit, this.authToken});

  Uri _buildUri(String path) {
    return Uri.parse('$baseUrl$path');
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
    };
  }

  Future<InsumoResponse> crearInsumo(InsumoRequest request) async {
    final uri = _buildUri('/empresa/$empresaNit/catalogo/insumos');
    final resp = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(request.toJson()),
    );

    if (resp.statusCode != 201) {
      throw Exception('Error al crear insumo: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return InsumoResponse.fromJson(data);
  }
}
