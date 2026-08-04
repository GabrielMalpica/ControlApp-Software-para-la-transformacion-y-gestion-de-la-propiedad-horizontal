class CargaConjuntoResumen {
  const CargaConjuntoResumen({
    required this.horarios,
    required this.ubicaciones,
    required this.operariosCreados,
    required this.operariosReutilizados,
    required this.preventivasTotal,
    required this.preventivasCreadas,
    required this.preventivasFallidas,
  });

  final int horarios;
  final int ubicaciones;
  final int operariosCreados;
  final int operariosReutilizados;
  final int preventivasTotal;
  final int preventivasCreadas;
  final int preventivasFallidas;

  factory CargaConjuntoResumen.fromJson(Map<String, dynamic> json) {
    int value(String key) => (json[key] as num?)?.toInt() ?? 0;
    return CargaConjuntoResumen(
      horarios: value('horarios'),
      ubicaciones: value('ubicaciones'),
      operariosCreados: value('operariosCreados'),
      operariosReutilizados: value('operariosReutilizados'),
      preventivasTotal: value('preventivasTotal'),
      preventivasCreadas: value('preventivasCreadas'),
      preventivasFallidas: value('preventivasFallidas'),
    );
  }
}

class CargaConjuntoError {
  const CargaConjuntoError({
    required this.fila,
    required this.seccion,
    required this.motivo,
  });

  final int fila;
  final String seccion;
  final String motivo;

  factory CargaConjuntoError.fromJson(Map<String, dynamic> json) {
    return CargaConjuntoError(
      fila: (json['fila'] as num?)?.toInt() ?? 0,
      seccion: json['seccion']?.toString() ?? '',
      motivo: json['motivo']?.toString() ?? 'Error sin detalle',
    );
  }
}

class CargaConjuntoResult {
  const CargaConjuntoResult({
    required this.creado,
    required this.conjuntoNit,
    required this.conjuntoNombre,
    required this.resumen,
    required this.errores,
    required this.columnasEsperadas,
  });

  final bool creado;
  final String conjuntoNit;
  final String conjuntoNombre;
  final CargaConjuntoResumen resumen;
  final List<CargaConjuntoError> errores;
  final Map<String, List<String>> columnasEsperadas;

  factory CargaConjuntoResult.fromJson(Map<String, dynamic> json) {
    final conjunto = Map<String, dynamic>.from(
      json['conjunto'] as Map? ?? const <String, dynamic>{},
    );
    final rawColumns = json['columnasEsperadas'] as Map? ?? const {};
    return CargaConjuntoResult(
      creado: json['creado'] == true,
      conjuntoNit: conjunto['nit']?.toString() ?? '',
      conjuntoNombre: conjunto['nombre']?.toString() ?? '',
      resumen: CargaConjuntoResumen.fromJson(
        Map<String, dynamic>.from(
          json['resumen'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      errores: (json['errores'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CargaConjuntoError.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      columnasEsperadas: rawColumns.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List? ?? const []).map((item) => item.toString()).toList(),
        ),
      ),
    );
  }
}
