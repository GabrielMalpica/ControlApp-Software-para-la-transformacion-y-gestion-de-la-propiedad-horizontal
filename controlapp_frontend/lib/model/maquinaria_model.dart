enum EstadoMaquinaria { OPERATIVA, EN_REPARACION, FUERA_DE_SERVICIO }

extension EstadoMaquinariaExt on EstadoMaquinaria {
  String get label {
    switch (this) {
      case EstadoMaquinaria.OPERATIVA:
        return 'Operativa';
      case EstadoMaquinaria.EN_REPARACION:
        return 'En reparación';
      case EstadoMaquinaria.FUERA_DE_SERVICIO:
        return 'Fuera de servicio';
    }
  }
}

enum TipoMaquinariaFlutter {
  CORTASETOS_MANO,
  CORTASETOS_ALTURA,
  GUADANIA,
  PODADORA_CESPED,
  ESCALERA,
  SOPLADORA,
  FUMIGADORA_MOTOR,
  BOMBA_ESPALDA,
  MOTOSIERRA_MANO,
  MOTOSIERRA_ALTURA,
  HIDROLAVADORA_ELECTRICA,
  HIDROLAVADORA_GASOLINA,
  PULIDORA,
  TALADRO,
  ROTOMARTILLO,
  LAVABRILLADORA,
  COMPRESOR,
  PULVERIZADORA_PINTURA,
  EQUIPO_ALTURAS,
  MEDIA_LUNA,
  CAJA_HERRAMIENTAS,
  OTRO,
}

extension TipoMaquinariaExt on TipoMaquinariaFlutter {
  String get label {
    // Puedes ponerlo más bonito después
    return name.replaceAll('_', ' ').toLowerCase();
  }

  String get backendValue => name; // Debe coincidir con el enum Prisma
}

class MaquinariaRequest {
  final String nombre;
  final String marca;
  final TipoMaquinariaFlutter tipo;
  final EstadoMaquinaria? estado;
  final bool? disponible;

  MaquinariaRequest({
    required this.nombre,
    required this.marca,
    required this.tipo,
    this.estado,
    this.disponible,
  });

  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'marca': marca,
      'tipo': tipo.backendValue,
      if (estado != null) 'estado': estado!.name,
      if (disponible != null) 'disponible': disponible,
    };
  }
}

class MaquinariaResponse {
  final int id;
  final String nombre;
  final String marca;
  final TipoMaquinariaFlutter tipo;
  final EstadoMaquinaria estado;
  final bool disponible;
  final String? conjuntoId;
  final String? empresaId;
  final String? conjuntoNombre;   // 👈 nuevo
  final String? operarioNombre; 

  MaquinariaResponse({
    required this.id,
    required this.nombre,
    required this.marca,
    required this.tipo,
    required this.estado,
    required this.disponible,
    this.conjuntoId,
    this.empresaId,
    this.conjuntoNombre,
    this.operarioNombre,
  });

  factory MaquinariaResponse.fromJson(Map<String, dynamic> json) {
    final tipoStr = json['tipo'] as String;
    final estadoStr = json['estado'] as String;

    final tipo = TipoMaquinariaFlutter.values.firstWhere(
      (e) => e.name == tipoStr,
      orElse: () => TipoMaquinariaFlutter.OTRO,
    );

    final estado = EstadoMaquinaria.values.firstWhere(
      (e) => e.name == estadoStr,
      orElse: () => EstadoMaquinaria.OPERATIVA,
    );

    return MaquinariaResponse(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      marca: json['marca'] as String,
      tipo: tipo,
      estado: estado,
      disponible: json['disponible'] as bool,
      conjuntoId: json['conjuntoId'] as String?,
      empresaId: json['empresaId'] as String?,
      conjuntoNombre: json['conjuntoNombre'] as String?,
      operarioNombre: json['operarioNombre'] as String?,
    );
  }
}
