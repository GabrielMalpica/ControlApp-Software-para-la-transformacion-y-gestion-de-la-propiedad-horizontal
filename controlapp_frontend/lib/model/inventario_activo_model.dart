enum ClaseActivoInventario { maquinaria, herramienta }

class CatalogoActivo {
  final int id;
  final String nombre;
  final String? unidad;
  final String? categoria;
  final String? tipoLegacy;

  const CatalogoActivo({
    required this.id,
    required this.nombre,
    this.unidad,
    this.categoria,
    this.tipoLegacy,
  });

  factory CatalogoActivo.fromJson(Map<String, dynamic> json) {
    return CatalogoActivo(
      id: (json['id'] as num).toInt(),
      nombre: (json['nombre'] ?? '').toString(),
      unidad: json['unidad']?.toString(),
      categoria: json['categoria']?.toString(),
      tipoLegacy: json['tipoLegacy']?.toString(),
    );
  }
}

class UbicacionActivo {
  final String nit;
  final String nombre;

  const UbicacionActivo({required this.nit, required this.nombre});

  factory UbicacionActivo.fromJson(Map<String, dynamic> json) {
    return UbicacionActivo(
      nit: (json['nit'] ?? '').toString(),
      nombre: (json['nombre'] ?? json['nit'] ?? '').toString(),
    );
  }
}

class ActivoInventario {
  final int id;
  final ClaseActivoInventario clase;
  final String codigoInterno;
  final int catalogoId;
  final String nombreCatalogo;
  final String? alias;
  final String? marca;
  final String? modelo;
  final String? serial;
  final String estado;
  final String? condicion;
  final String estadoAprobacion;
  final String propietarioTipo;
  final UbicacionActivo? conjuntoPropietario;
  final UbicacionActivo? ubicacionActual;
  final bool prestada;
  final bool disponible;
  final String? fotoUrl;
  final String? creadoPorId;
  final String? creadoPorNombre;
  final String? aprobadoPorNombre;
  final String? motivoRechazo;
  final DateTime? creadoEn;
  final DateTime? aprobadoEn;
  final DateTime? actualizadoEn;
  final String? registroLoteId;

  const ActivoInventario({
    required this.id,
    required this.clase,
    required this.codigoInterno,
    required this.catalogoId,
    required this.nombreCatalogo,
    required this.estado,
    this.condicion,
    required this.estadoAprobacion,
    required this.propietarioTipo,
    required this.prestada,
    required this.disponible,
    this.alias,
    this.marca,
    this.modelo,
    this.serial,
    this.conjuntoPropietario,
    this.ubicacionActual,
    this.fotoUrl,
    this.creadoPorId,
    this.creadoPorNombre,
    this.aprobadoPorNombre,
    this.motivoRechazo,
    this.creadoEn,
    this.aprobadoEn,
    this.actualizadoEn,
    this.registroLoteId,
  });

  factory ActivoInventario.fromJson(
    Map<String, dynamic> json,
    ClaseActivoInventario clase,
  ) {
    final rawCatalogo = clase == ClaseActivoInventario.maquinaria
        ? json['tipoCatalogo']
        : json['herramienta'];
    final catalogo = rawCatalogo is Map
        ? rawCatalogo.cast<String, dynamic>()
        : const <String, dynamic>{};
    final rawPropietario = json['conjuntoPropietario'];
    final rawUbicacion = json['ubicacionActual'];
    final catalogIdValue =
        catalogo['id'] ??
        json[clase == ClaseActivoInventario.maquinaria
            ? 'tipoCatalogoId'
            : 'herramientaId'];

    return ActivoInventario(
      id: (json['id'] as num).toInt(),
      clase: clase,
      codigoInterno: (json['codigoInterno'] ?? '').toString(),
      catalogoId: (catalogIdValue as num?)?.toInt() ?? 0,
      nombreCatalogo: (catalogo['nombre'] ?? json['nombre'] ?? '').toString(),
      alias: json['alias']?.toString(),
      marca: json['marca']?.toString(),
      modelo: json['modelo']?.toString(),
      serial: json['serial']?.toString(),
      estado: (json['estado'] ?? '').toString(),
      condicion: json['condicion']?.toString(),
      estadoAprobacion: (json['estadoAprobacion'] ?? '').toString(),
      propietarioTipo: (json['propietarioTipo'] ?? '').toString(),
      conjuntoPropietario: rawPropietario is Map
          ? UbicacionActivo.fromJson(rawPropietario.cast<String, dynamic>())
          : null,
      ubicacionActual: rawUbicacion is Map
          ? UbicacionActivo.fromJson(rawUbicacion.cast<String, dynamic>())
          : null,
      prestada: json['prestada'] == true,
      disponible: json['disponible'] == true,
      fotoUrl: json['fotoUrl']?.toString(),
      creadoPorId: json['creadoPorId']?.toString(),
      creadoPorNombre: json['creadoPorNombre']?.toString(),
      aprobadoPorNombre: json['aprobadoPorNombre']?.toString(),
      motivoRechazo: json['motivoRechazo']?.toString(),
      creadoEn: DateTime.tryParse((json['creadoEn'] ?? '').toString()),
      aprobadoEn: DateTime.tryParse((json['aprobadoEn'] ?? '').toString()),
      actualizadoEn: DateTime.tryParse(
        (json['actualizadoEn'] ?? '').toString(),
      ),
      registroLoteId: json['registroLoteId']?.toString(),
    );
  }
}

class PaginaActivos {
  final List<ActivoInventario> data;
  final int total;
  final int page;
  final int pageSize;

  const PaginaActivos({
    required this.data,
    required this.total,
    required this.page,
    required this.pageSize,
  });
}

class ResumenInventarioActivos {
  final int maquinaria;
  final int herramientas;
  final int pendientes;

  const ResumenInventarioActivos({
    required this.maquinaria,
    required this.herramientas,
    required this.pendientes,
  });

  factory ResumenInventarioActivos.fromJson(Map<String, dynamic> json) {
    return ResumenInventarioActivos(
      maquinaria: (json['maquinaria'] as num?)?.toInt() ?? 0,
      herramientas: (json['herramientas'] as num?)?.toInt() ?? 0,
      pendientes: (json['pendientes'] as num?)?.toInt() ?? 0,
    );
  }
}
