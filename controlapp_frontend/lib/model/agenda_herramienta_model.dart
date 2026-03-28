class AgendaHerramientaResponse {
  final bool ok;
  final int anio;
  final int mes;
  final List<AgendaHerramientaBlock> data;

  AgendaHerramientaResponse({
    required this.ok,
    required this.anio,
    required this.mes,
    required this.data,
  });

  factory AgendaHerramientaResponse.fromJson(Map<String, dynamic> json) {
    final raw = (json['data'] as List? ?? []);
    return AgendaHerramientaResponse(
      ok: json['ok'] == true,
      anio: (json['anio'] as num).toInt(),
      mes: (json['mes'] as num).toInt(),
      data: raw
          .map(
            (e) => AgendaHerramientaBlock.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }
}

class AgendaHerramientaBlock {
  final AgendaHerramientaLite herramienta;
  final Map<int, Map<int, List<AgendaHerramientaItem>>> semanas;
  final int reservasMes;

  AgendaHerramientaBlock({
    required this.herramienta,
    required this.semanas,
    required this.reservasMes,
  });

  factory AgendaHerramientaBlock.fromJson(Map<String, dynamic> json) {
    final herramienta = AgendaHerramientaLite.fromJson(
      (json['herramienta'] as Map).cast<String, dynamic>(),
    );
    final semanasRaw = (json['semanas'] as Map? ?? {});
    final semanas = <int, Map<int, List<AgendaHerramientaItem>>>{};

    semanasRaw.forEach((kSemana, v) {
      final semana = int.tryParse(kSemana.toString()) ?? 1;
      final gruposRaw = (v as Map).cast<String, dynamic>();
      final grupos = <int, List<AgendaHerramientaItem>>{};
      for (final g in [1, 2, 3, 4, 5, 6]) {
        final arr = (gruposRaw[g.toString()] as List? ?? []);
        grupos[g] = arr
            .map(
              (x) => AgendaHerramientaItem.fromJson(
                (x as Map).cast<String, dynamic>(),
              ),
            )
            .toList();
      }
      semanas[semana] = grupos;
    });

    final resumen = (json['resumen'] as Map?)?.cast<String, dynamic>() ?? {};
    return AgendaHerramientaBlock(
      herramienta: herramienta,
      semanas: semanas,
      reservasMes: (resumen['reservasMes'] as num? ?? 0).toInt(),
    );
  }
}

class AgendaHerramientaLite {
  final int id;
  final String nombre;
  final String unidad;
  final String categoria;
  final String modoControl;

  AgendaHerramientaLite({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    required this.modoControl,
  });

  factory AgendaHerramientaLite.fromJson(Map<String, dynamic> json) {
    return AgendaHerramientaLite(
      id: (json['id'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
      unidad: (json['unidad'] ?? 'unidad').toString(),
      categoria: (json['categoria'] ?? 'OTROS').toString(),
      modoControl: (json['modoControl'] ?? 'PRESTAMO').toString(),
    );
  }
}

class AgendaHerramientaItem {
  final int usoId;
  final int tareaId;
  final String? conjuntoId;
  final String? conjuntoNombre;
  final String? descripcion;
  final String entrega;
  final String recogida;
  final int grupo;
  final int semana;
  final num cantidad;
  final String origenStock;
  final List<String> grid;

  AgendaHerramientaItem({
    required this.usoId,
    required this.tareaId,
    this.conjuntoId,
    this.conjuntoNombre,
    this.descripcion,
    required this.entrega,
    required this.recogida,
    required this.grupo,
    required this.semana,
    required this.cantidad,
    required this.origenStock,
    required this.grid,
  });

  factory AgendaHerramientaItem.fromJson(Map<String, dynamic> json) {
    final rawGrid = (json['grid'] as List? ?? const []);
    final grid = rawGrid.map((x) => (x ?? '').toString()).toList();

    return AgendaHerramientaItem(
      usoId: (json['usoId'] as num).toInt(),
      tareaId: (json['tareaId'] as num).toInt(),
      conjuntoId: json['conjuntoId']?.toString(),
      conjuntoNombre: json['conjuntoNombre']?.toString(),
      descripcion: json['descripcion']?.toString(),
      entrega: (json['entrega'] ?? '').toString(),
      recogida: (json['recogida'] ?? '').toString(),
      grupo: (json['grupo'] as num).toInt(),
      semana: (json['semana'] as num).toInt(),
      cantidad: json['cantidad'] is num
          ? json['cantidad'] as num
          : num.tryParse('${json['cantidad']}') ?? 0,
      origenStock: (json['origenStock'] ?? 'CONJUNTO').toString(),
      grid: grid.length == 6 ? grid : List<String>.filled(6, ''),
    );
  }
}
