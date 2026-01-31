import 'package:flutter_application_1/model/maquinaria_model.dart';

class AgendaGlobalResponse {
  final bool ok;
  final int anio;
  final int mes;
  final List<AgendaMaquinaBlock> data;

  AgendaGlobalResponse({
    required this.ok,
    required this.anio,
    required this.mes,
    required this.data,
  });

  factory AgendaGlobalResponse.fromJson(Map<String, dynamic> json) {
    final raw = (json['data'] as List? ?? []);
    return AgendaGlobalResponse(
      ok: json['ok'] == true,
      anio: (json['anio'] as num).toInt(),
      mes: (json['mes'] as num).toInt(),
      data: raw
          .map(
            (e) =>
                AgendaMaquinaBlock.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
    );
  }
}

class AgendaMaquinaBlock {
  final MaquinariaResponse maquinaria;
  final Map<int, Map<int, List<AgendaReservaItem>>>
  semanas; // semana -> grupo -> items
  final int reservasMes;

  AgendaMaquinaBlock({
    required this.maquinaria,
    required this.semanas,
    required this.reservasMes,
  });

  factory AgendaMaquinaBlock.fromJson(Map<String, dynamic> json) {
    final maq = MaquinariaResponse.fromJson(
      (json['maquinaria'] as Map).cast<String, dynamic>(),
    );
    final semanasRaw = (json['semanas'] as Map? ?? {});
    final semanas = <int, Map<int, List<AgendaReservaItem>>>{};

    semanasRaw.forEach((kSemana, v) {
      final semana = int.tryParse(kSemana.toString()) ?? 1;
      final gruposRaw = (v as Map).cast<String, dynamic>();
      final grupos = <int, List<AgendaReservaItem>>{};
      for (final g in [1, 2, 3, 4, 5, 6]) {
        final arr = (gruposRaw[g.toString()] as List? ?? []);
        grupos[g] = arr
            .map(
              (x) => AgendaReservaItem.fromJson(
                (x as Map).cast<String, dynamic>(),
              ),
            )
            .toList();
      }

      semanas[semana] = grupos;
    });

    final resumen = (json['resumen'] as Map?)?.cast<String, dynamic>() ?? {};
    return AgendaMaquinaBlock(
      maquinaria: maq,
      semanas: semanas,
      reservasMes: (resumen['reservasMes'] as num? ?? 0).toInt(),
    );
  }
}

class AgendaReservaItem {
  final int usoId;
  final int tareaId;
  final String? conjuntoNombre;
  final String? descripcion;
  final String entrega; // yyyy-mm-dd
  final String recogida; // yyyy-mm-dd
  final int grupo;
  final int semana;

  // ✅ NUEVO
  final List<String> grid; // 6 columnas L..S
  final String? observacion;

  AgendaReservaItem({
    required this.usoId,
    required this.tareaId,
    required this.entrega,
    required this.recogida,
    required this.grupo,
    required this.semana,
    this.conjuntoNombre,
    this.descripcion,

    required this.grid,
    this.observacion,
  });

  factory AgendaReservaItem.fromJson(Map<String, dynamic> json) {
    final rawGrid = (json['grid'] as List? ?? const []);
    final grid = rawGrid.map((x) => (x ?? '').toString()).toList();

    // blindaje: si no llega, crea 6 vacíos
    final safeGrid = (grid.length == 6) ? grid : List<String>.filled(6, '');

    return AgendaReservaItem(
      usoId: (json['usoId'] as num).toInt(),
      tareaId: (json['tareaId'] as num).toInt(),
      entrega: (json['entrega'] ?? '').toString(),
      recogida: (json['recogida'] ?? '').toString(),
      grupo: (json['grupo'] as num).toInt(),
      semana: (json['semana'] as num).toInt(),
      conjuntoNombre: json['conjuntoNombre']?.toString(),
      descripcion: json['descripcion']?.toString(),

      // ✅ NUEVO
      grid: safeGrid,
      observacion: json['observacion']?.toString(),
    );
  }
}
