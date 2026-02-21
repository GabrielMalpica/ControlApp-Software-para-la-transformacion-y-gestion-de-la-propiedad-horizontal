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

enum PropietarioMaquinaria { EMPRESA, CONJUNTO }

extension PropietarioMaquinariaExt on PropietarioMaquinaria {
  String get backendValue => name;
  String get label =>
      this == PropietarioMaquinaria.EMPRESA ? "Empresa" : "Conjunto";
}

class MaquinariaRequest {
  final String nombre;
  final String marca;
  final TipoMaquinariaFlutter tipo;
  final EstadoMaquinaria? estado;

  final PropietarioMaquinaria propietarioTipo;
  final String? conjuntoPropietarioId; // NIT

  MaquinariaRequest({
    required this.nombre,
    required this.marca,
    required this.tipo,
    this.estado,
    this.propietarioTipo = PropietarioMaquinaria.EMPRESA,
    this.conjuntoPropietarioId,
  });

  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'marca': marca,
      'tipo': tipo.backendValue,
      if (estado != null) 'estado': estado!.name,

      'propietarioTipo': propietarioTipo.backendValue,
      if (propietarioTipo == PropietarioMaquinaria.CONJUNTO)
        'conjuntoPropietarioId': conjuntoPropietarioId,
    };
  }
}

class MaquinariaResponse {
  final int id;
  final String nombre;
  final String marca;
  final TipoMaquinariaFlutter tipo;
  final EstadoMaquinaria estado;

  final bool? disponible; // si aún lo usas en catálogo
  final String? conjuntoNombre; // “Prestada a …” (si backend lo envía)
  final String? operarioNombre;

  final PropietarioMaquinaria? propietarioTipo; // nuevo
  final String? conjuntoPropietarioId; // nuevo

  MaquinariaResponse({
    required this.id,
    required this.nombre,
    required this.marca,
    required this.tipo,
    required this.estado,
    this.disponible,
    this.conjuntoNombre,
    this.operarioNombre,
    this.propietarioTipo,
    this.conjuntoPropietarioId,
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

    final propStr = json['propietarioTipo'] as String?;
    PropietarioMaquinaria? prop;
    if (propStr != null) {
      prop = PropietarioMaquinaria.values.firstWhere(
        (e) => e.name == propStr,
        orElse: () => PropietarioMaquinaria.EMPRESA,
      );
    }

    return MaquinariaResponse(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      marca: json['marca'] as String,
      tipo: tipo,
      estado: estado,
      disponible: json['disponible'] as bool?,
      conjuntoNombre: json['conjuntoNombre'] as String?,
      operarioNombre: json['operarioNombre'] as String?,
      propietarioTipo: prop,
      conjuntoPropietarioId: json['conjuntoPropietarioId'] as String?,
    );
  }
}

class MaquinariaDisponibleItem {
  final int id;
  final String nombre;
  final String tipo;
  final String marca;
  final String origen; // "CONJUNTO" | "EMPRESA"

  MaquinariaDisponibleItem({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.marca,
    required this.origen,
  });

  factory MaquinariaDisponibleItem.fromJson(Map<String, dynamic> json) {
    final origenRaw = (json['origen'] ?? 'EMPRESA').toString();
    final origen = origenRaw.trim().toUpperCase();

    return MaquinariaDisponibleItem(
      id: (json['id'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
      tipo: (json['tipo'] ?? '').toString(),
      marca: (json['marca'] ?? '').toString(),
      origen: origen,
    );
  }
}

class MaquinariaOcupadaItem {
  final int maquinariaId;
  final DateTime ini;
  final DateTime fin;
  final int? tareaId;
  final String? conjuntoId;
  final String? descripcion;
  final String? fuente; // RESERVA_PUBLICADA | BORRADOR_PREVENTIVA

  MaquinariaOcupadaItem({
    required this.maquinariaId,
    required this.ini,
    required this.fin,
    this.tareaId,
    this.conjuntoId,
    this.descripcion,
    this.fuente,
  });

  factory MaquinariaOcupadaItem.fromJson(Map<String, dynamic> json) {
    return MaquinariaOcupadaItem(
      maquinariaId: (json['maquinariaId'] as num).toInt(),
      ini: DateTime.parse(json['ini'].toString()),
      fin: DateTime.parse(json['fin'].toString()),
      tareaId: (json['tareaId'] as num?)?.toInt(),
      conjuntoId: json['conjuntoId']?.toString(),
      descripcion: json['descripcion']?.toString(),
      fuente: json['fuente']?.toString(),
    );
  }
}

class DisponibilidadMaquinariaResponse {
  final bool ok;
  final List<MaquinariaDisponibleItem> propiasDisponibles;
  final List<MaquinariaDisponibleItem> empresaDisponibles;
  final List<MaquinariaOcupadaItem> ocupadas;

  DisponibilidadMaquinariaResponse({
    required this.ok,
    required this.propiasDisponibles,
    required this.empresaDisponibles,
    required this.ocupadas,
  });

  factory DisponibilidadMaquinariaResponse.fromJson(Map<String, dynamic> json) {
    final propias = (json['propiasDisponibles'] as List?) ?? [];
    final empresa = (json['empresaDisponibles'] as List?) ?? [];
    final ocup = (json['ocupadas'] as List?) ?? [];

    return DisponibilidadMaquinariaResponse(
      ok: json['ok'] == true,
      propiasDisponibles: propias
          .map(
            (e) => MaquinariaDisponibleItem.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      empresaDisponibles: empresa
          .map(
            (e) => MaquinariaDisponibleItem.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      ocupadas: ocup
          .map(
            (e) => MaquinariaOcupadaItem.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }
}
