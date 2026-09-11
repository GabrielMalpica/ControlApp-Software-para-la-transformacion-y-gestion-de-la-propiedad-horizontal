class ConceptoAsistencia {
  final int id;
  final String codigo;
  final String nombre;
  final bool cuentaComoTrabajado;
  final String colorHex;
  final bool activo;
  final int orden;

  ConceptoAsistencia({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.cuentaComoTrabajado,
    required this.colorHex,
    required this.activo,
    required this.orden,
  });

  factory ConceptoAsistencia.fromJson(Map<String, dynamic> json) {
    return ConceptoAsistencia(
      id: int.parse(json['id'].toString()),
      codigo: json['codigo']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      cuentaComoTrabajado: json['cuentaComoTrabajado'] == true,
      colorHex: json['colorHex']?.toString() ?? '#9E9E9E',
      activo: json['activo'] != false,
      orden: int.tryParse(json['orden']?.toString() ?? '') ?? 0,
    );
  }
}

class UbicacionAsistencia {
  final double lat;
  final double lng;

  UbicacionAsistencia({required this.lat, required this.lng});

  factory UbicacionAsistencia.fromJson(Map<String, dynamic> json) {
    return UbicacionAsistencia(
      lat: double.tryParse(json['lat'].toString()) ?? 0,
      lng: double.tryParse(json['lng'].toString()) ?? 0,
    );
  }

  String get googleMapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
}

class RegistroAsistenciaDia {
  final int id;
  final int conceptoId;
  final String conceptoCodigo;
  final String conceptoNombre;
  final String colorHex;
  final String origen; // QR | MANUAL
  final DateTime? horaEntrada;
  final DateTime? horaSalida;
  final UbicacionAsistencia? ubicacionEntrada;
  final UbicacionAsistencia? ubicacionSalida;
  final String? observacion;

  RegistroAsistenciaDia({
    required this.id,
    required this.conceptoId,
    required this.conceptoCodigo,
    required this.conceptoNombre,
    required this.colorHex,
    required this.origen,
    this.horaEntrada,
    this.horaSalida,
    this.ubicacionEntrada,
    this.ubicacionSalida,
    this.observacion,
  });

  factory RegistroAsistenciaDia.fromJson(Map<String, dynamic> json) {
    return RegistroAsistenciaDia(
      id: int.parse(json['id'].toString()),
      conceptoId: int.parse(json['conceptoId'].toString()),
      conceptoCodigo: json['conceptoCodigo']?.toString() ?? '',
      conceptoNombre: json['conceptoNombre']?.toString() ?? '',
      colorHex: json['colorHex']?.toString() ?? '#9E9E9E',
      origen: json['origen']?.toString() ?? 'MANUAL',
      horaEntrada: json['horaEntrada'] != null
          ? DateTime.tryParse(json['horaEntrada'].toString())
          : null,
      horaSalida: json['horaSalida'] != null
          ? DateTime.tryParse(json['horaSalida'].toString())
          : null,
      ubicacionEntrada: json['ubicacionEntrada'] != null
          ? UbicacionAsistencia.fromJson(
              json['ubicacionEntrada'] as Map<String, dynamic>,
            )
          : null,
      ubicacionSalida: json['ubicacionSalida'] != null
          ? UbicacionAsistencia.fromJson(
              json['ubicacionSalida'] as Map<String, dynamic>,
            )
          : null,
      observacion: json['observacion']?.toString(),
    );
  }

  bool get faltaSalida => horaEntrada != null && horaSalida == null;
}

class AsistenciaDiaCelda {
  final int dia;
  final String fecha; // yyyy-MM-dd
  final int diaSemana; // 0=domingo
  final bool pendiente;
  final bool incompleto;
  final RegistroAsistenciaDia? registro;

  AsistenciaDiaCelda({
    required this.dia,
    required this.fecha,
    required this.diaSemana,
    required this.pendiente,
    required this.incompleto,
    this.registro,
  });

  factory AsistenciaDiaCelda.fromJson(Map<String, dynamic> json) {
    return AsistenciaDiaCelda(
      dia: int.parse(json['dia'].toString()),
      fecha: json['fecha']?.toString() ?? '',
      diaSemana: int.tryParse(json['diaSemana']?.toString() ?? '') ?? 0,
      pendiente: json['pendiente'] == true,
      incompleto: json['incompleto'] == true,
      registro: json['registro'] != null
          ? RegistroAsistenciaDia.fromJson(json['registro'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AsistenciaOperarioFila {
  final String operarioId;
  final String nombre;
  final String cedula;
  final String cargo;
  final List<AsistenciaDiaCelda> dias;

  AsistenciaOperarioFila({
    required this.operarioId,
    required this.nombre,
    required this.cedula,
    required this.cargo,
    required this.dias,
  });

  factory AsistenciaOperarioFila.fromJson(Map<String, dynamic> json) {
    final diasJson = (json['dias'] as List<dynamic>? ?? []);
    return AsistenciaOperarioFila(
      operarioId: json['operarioId']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      cedula: json['cedula']?.toString() ?? '',
      cargo: json['cargo']?.toString() ?? '',
      dias: diasJson
          .map((e) => AsistenciaDiaCelda.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AsistenciaGrupoConjunto {
  final String conjuntoId;
  final String conjuntoNombre;
  final List<AsistenciaOperarioFila> operarios;

  AsistenciaGrupoConjunto({
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.operarios,
  });

  factory AsistenciaGrupoConjunto.fromJson(Map<String, dynamic> json) {
    final operariosJson = (json['operarios'] as List<dynamic>? ?? []);
    return AsistenciaGrupoConjunto(
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      operarios: operariosJson
          .map((e) => AsistenciaOperarioFila.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AsistenciaGrid {
  final int anio;
  final int mes;
  final int totalDias;
  final List<AsistenciaOperarioFila> operarios;
  final List<AsistenciaGrupoConjunto>? gruposPorConjunto;

  AsistenciaGrid({
    required this.anio,
    required this.mes,
    required this.totalDias,
    required this.operarios,
    this.gruposPorConjunto,
  });

  factory AsistenciaGrid.fromJson(Map<String, dynamic> json) {
    final operariosJson = (json['operarios'] as List<dynamic>? ?? []);
    final gruposJson = json['gruposPorConjunto'] as List<dynamic>?;
    return AsistenciaGrid(
      anio: int.parse(json['anio'].toString()),
      mes: int.parse(json['mes'].toString()),
      totalDias: int.parse(json['totalDias'].toString()),
      operarios: operariosJson
          .map((e) => AsistenciaOperarioFila.fromJson(e as Map<String, dynamic>))
          .toList(),
      gruposPorConjunto: gruposJson
          ?.map((e) => AsistenciaGrupoConjunto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TurnoExtra {
  final int id;
  final String fecha;
  final String operarioId;
  final String operarioNombre;
  final String? conjuntoId;
  final String? conjuntoNombre;
  final String tipo;
  final bool esReemplazo;
  final String? reemplazadoNombre;
  final String? motivo;
  final double? valorNegociado;
  final int turnosOrdinarios;
  final int turnosDominicales;
  final String estado;

  TurnoExtra({
    required this.id,
    required this.fecha,
    required this.operarioId,
    required this.operarioNombre,
    this.conjuntoId,
    this.conjuntoNombre,
    required this.tipo,
    required this.esReemplazo,
    this.reemplazadoNombre,
    this.motivo,
    this.valorNegociado,
    required this.turnosOrdinarios,
    required this.turnosDominicales,
    required this.estado,
  });

  factory TurnoExtra.fromJson(Map<String, dynamic> json) {
    final operario = json['operario'] as Map<String, dynamic>?;
    final reemplazado = json['operarioReemplazado'] as Map<String, dynamic>?;
    final conjunto = json['conjunto'] as Map<String, dynamic>?;

    return TurnoExtra(
      id: int.parse(json['id'].toString()),
      fecha: (json['fecha']?.toString() ?? '').substring(
        0,
        (json['fecha']?.toString() ?? '').length >= 10
            ? 10
            : (json['fecha']?.toString() ?? '').length,
      ),
      operarioId: json['operarioId']?.toString() ?? '',
      operarioNombre:
          json['operarioNombre']?.toString() ??
          operario?['usuario']?['nombre']?.toString() ??
          '',
      conjuntoId: json['conjuntoId']?.toString() ?? conjunto?['nit']?.toString(),
      conjuntoNombre: conjunto?['nombre']?.toString(),
      tipo: json['tipo']?.toString() ?? 'TURNO',
      esReemplazo: json['esReemplazo'] == true,
      reemplazadoNombre:
          json['reemplazadoNombre']?.toString() ??
          reemplazado?['usuario']?['nombre']?.toString() ??
          json['reemplazadoNombreLibre']?.toString(),
      motivo: json['motivo']?.toString(),
      valorNegociado: json['valorNegociado'] != null
          ? double.tryParse(json['valorNegociado'].toString())
          : null,
      turnosOrdinarios: int.tryParse(json['turnosOrdinarios']?.toString() ?? '') ?? 0,
      turnosDominicales: int.tryParse(json['turnosDominicales']?.toString() ?? '') ?? 0,
      estado: json['estado']?.toString() ?? 'PENDIENTE',
    );
  }
}

class AsistenciaResumenOperario {
  final String operarioId;
  final String nombre;
  final String cedula;
  final String cargo;
  final int pendientes;
  final Map<String, int> conteoPorConcepto;

  AsistenciaResumenOperario({
    required this.operarioId,
    required this.nombre,
    required this.cedula,
    required this.cargo,
    required this.pendientes,
    required this.conteoPorConcepto,
  });

  factory AsistenciaResumenOperario.fromJson(Map<String, dynamic> json) {
    final conteo = (json['conteoPorConcepto'] as Map<String, dynamic>? ?? {});
    return AsistenciaResumenOperario(
      operarioId: json['operarioId']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      cedula: json['cedula']?.toString() ?? '',
      cargo: json['cargo']?.toString() ?? '',
      pendientes: int.tryParse(json['pendientes']?.toString() ?? '') ?? 0,
      conteoPorConcepto: conteo.map(
        (key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0),
      ),
    );
  }
}

class AsistenciaResumenGrupoConjunto {
  final String conjuntoId;
  final String conjuntoNombre;
  final List<AsistenciaResumenOperario> operarios;

  AsistenciaResumenGrupoConjunto({
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.operarios,
  });

  factory AsistenciaResumenGrupoConjunto.fromJson(Map<String, dynamic> json) {
    final operariosJson = (json['operarios'] as List<dynamic>? ?? []);
    return AsistenciaResumenGrupoConjunto(
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      operarios: operariosJson
          .map((e) => AsistenciaResumenOperario.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AsistenciaResumen {
  final int anio;
  final int mes;
  final List<AsistenciaResumenOperario> operarios;
  final List<AsistenciaResumenGrupoConjunto>? gruposPorConjunto;
  final List<TurnoExtra> turnosExtra;

  AsistenciaResumen({
    required this.anio,
    required this.mes,
    required this.operarios,
    this.gruposPorConjunto,
    required this.turnosExtra,
  });

  factory AsistenciaResumen.fromJson(Map<String, dynamic> json) {
    final operariosJson = (json['operarios'] as List<dynamic>? ?? []);
    final gruposJson = json['gruposPorConjunto'] as List<dynamic>?;
    final turnosJson = (json['turnosExtra'] as List<dynamic>? ?? []);
    return AsistenciaResumen(
      anio: int.parse(json['anio'].toString()),
      mes: int.parse(json['mes'].toString()),
      operarios: operariosJson
          .map((e) => AsistenciaResumenOperario.fromJson(e as Map<String, dynamic>))
          .toList(),
      gruposPorConjunto: gruposJson
          ?.map((e) => AsistenciaResumenGrupoConjunto.fromJson(e as Map<String, dynamic>))
          .toList(),
      turnosExtra: turnosJson
          .map((e) => TurnoExtra.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AsistenciaQr {
  final String conjuntoId;
  final String conjuntoNombre;
  final String token;
  final String payload;
  final DateTime? actualizadoEn;

  AsistenciaQr({
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.token,
    required this.payload,
    this.actualizadoEn,
  });

  factory AsistenciaQr.fromJson(Map<String, dynamic> json) {
    return AsistenciaQr(
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      payload: json['payload']?.toString() ?? '',
      actualizadoEn: json['actualizadoEn'] != null
          ? DateTime.tryParse(json['actualizadoEn'].toString())
          : null,
    );
  }
}

class AsistenciaCheckinResultado {
  final String tipo; // ENTRADA | SALIDA
  final String conjuntoNombre;
  final RegistroAsistenciaDia registro;

  AsistenciaCheckinResultado({
    required this.tipo,
    required this.conjuntoNombre,
    required this.registro,
  });

  factory AsistenciaCheckinResultado.fromJson(Map<String, dynamic> json) {
    return AsistenciaCheckinResultado(
      tipo: json['tipo']?.toString() ?? 'ENTRADA',
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      registro: RegistroAsistenciaDia.fromJson(
        json['registro'] as Map<String, dynamic>,
      ),
    );
  }
}
