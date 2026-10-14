import 'package:flutter_application_1/model/reporte_model.dart';

/// Opciones del informe detallado en PDF. Los nombres de campo del JSON son
/// los mismos que valida el backend (`InformeMensualOpciones.ts`).

enum OrganizacionInforme {
  actividad('ACTIVIDAD', 'Por actividad'),
  ubicacion('UBICACION', 'Por ubicación'),
  cronologico('CRONOLOGICO', 'Tarea por tarea (cronológico)');

  const OrganizacionInforme(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static OrganizacionInforme desdeApi(Object? v) => values.firstWhere(
    (o) => o.api == '$v',
    orElse: () => OrganizacionInforme.actividad,
  );
}

enum RegistrosConFoto {
  auto('AUTO', 'Automático'),
  tres('3', '3 por actividad'),
  cinco('5', '5 por actividad'),
  diez('10', '10 por actividad'),
  todos('TODOS', 'Todos');

  const RegistrosConFoto(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  /// El backend recibe 'AUTO', 'TODOS' o un número.
  Object get json => int.tryParse(api) ?? api;

  static RegistrosConFoto desdeApi(Object? v) => values.firstWhere(
    (o) => o.api == '$v',
    orElse: () => RegistrosConFoto.auto,
  );
}

enum TamanoFoto {
  auto('AUTO', 'Automático'),
  grande('GRANDE', 'Grande (2 por fila)'),
  mediana('MEDIANA', 'Mediana (3 por fila)'),
  pequena('PEQUENA', 'Pequeña (4 por fila)');

  const TamanoFoto(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static TamanoFoto desdeApi(Object? v) =>
      values.firstWhere((o) => o.api == '$v', orElse: () => TamanoFoto.auto);
}

enum CalidadFoto {
  liviana('LIVIANA', 'Liviana', 40, 0.08),
  estandar('ESTANDAR', 'Estándar', 70, 0.12),
  alta('ALTA', 'Alta', 170, 0.2);

  const CalidadFoto(this.api, this.etiqueta, this.kbPorFoto, this.segPorFoto);
  final String api;
  final String etiqueta;

  /// Peso y tiempo aproximados por foto dentro del PDF (medidos con datos reales).
  final int kbPorFoto;
  final double segPorFoto;

  /// Tope de fotos por informe; el backend aplica el mismo.
  int get limiteFotos => this == CalidadFoto.alta ? 250 : 400;

  static CalidadFoto desdeApi(Object? v) => values.firstWhere(
    (o) => o.api == '$v',
    orElse: () => CalidadFoto.estandar,
  );
}

enum PlantillaInforme {
  estandar('Estándar', 'El informe de siempre: actividades con sus fotos.'),
  auditoria(
    'Auditoría',
    'Todo lo que pide una revisión: cumplimiento, novedades, puntualidad y anexo.',
  ),
  fotografico(
    'Fotográfico',
    'Fotos grandes de todos los registros y poco texto.',
  ),
  ejecutivo(
    'Ejecutivo (sin fotos)',
    'Resumen, cumplimiento, novedades y recursos en pocas páginas.',
  ),
  personalizado('Personalizado', 'Elegiste tus propias opciones.');

  const PlantillaInforme(this.etiqueta, this.descripcion);
  final String etiqueta;
  final String descripcion;
}

/// Una casilla del panel: sección del informe o dato de cada tarea.
class OpcionCasilla {
  final String clave;
  final String titulo;
  final String descripcion;

  /// Solo roles internos: el administrador del conjunto nunca la ve.
  final bool interna;

  const OpcionCasilla(
    this.clave,
    this.titulo,
    this.descripcion, {
    this.interna = false,
  });
}

const seccionesInforme = <OpcionCasilla>[
  OpcionCasilla(
    'resumen',
    'Resumen y cifras',
    'Tarjetas de previstas, programadas, realizadas y estados.',
  ),
  OpcionCasilla(
    'cumplimiento',
    'Tabla de cumplimiento',
    'Cada actividad con previstas, realizadas y % de cumplimiento.',
  ),
  OpcionCasilla(
    'detalle',
    'Detalle de tareas',
    'Cada actividad o tarea con sus datos y fotos.',
  ),
  OpcionCasilla(
    'novedades',
    'Novedades y pendientes',
    'No completadas, rechazadas y vencidas, con su motivo.',
  ),
  OpcionCasilla(
    'reemplazadas',
    'Tareas reemplazadas',
    'Preventivas que se reemplazaron y por qué.',
  ),
  OpcionCasilla(
    'consolidadoRecursos',
    'Consolidado de recursos',
    'Total de insumos, maquinaria y herramientas del periodo.',
  ),
  OpcionCasilla(
    'anexoTareas',
    'Anexo: listado de tareas',
    'Una fila por tarea con fechas, estado, responsable y fotos.',
  ),
];

const camposInforme = <OpcionCasilla>[
  OpcionCasilla('ubicacion', 'Ubicación', 'Ubicación y elemento.'),
  OpcionCasilla('fechas', 'Fechas', 'Fecha programada o periodo.'),
  OpcionCasilla('responsables', 'Responsables', 'Supervisor y operarios.'),
  OpcionCasilla(
    'cifras',
    'Cifras de la actividad',
    'Previstas, programadas y realizadas.',
  ),
  OpcionCasilla('estado', 'Estado', 'Estado de cada tarea y su motivo.'),
  OpcionCasilla(
    'puntualidad',
    'Puntualidad',
    'Cierre real frente al programado y duración.',
  ),
  OpcionCasilla('insumos', 'Insumos', 'Insumos usados.'),
  OpcionCasilla('maquinaria', 'Maquinaria', 'Maquinaria usada.'),
  OpcionCasilla('herramientas', 'Herramientas', 'Herramientas usadas.'),
  OpcionCasilla('observaciones', 'Observaciones', 'Notas del cierre.'),
  OpcionCasilla('reemplazos', 'Reemplazos', 'A qué tarea reemplazó.'),
  OpcionCasilla('numerosTarea', 'Número de tarea', 'El # de cada tarea.'),
  OpcionCasilla(
    'motivoRechazo',
    'Motivo de rechazo',
    'Por qué se devolvió un cierre.',
    interna: true,
  ),
  OpcionCasilla(
    'cerradoPor',
    'Quién cerró',
    'Nombre de quien cerró la tarea.',
    interna: true,
  ),
];

const _seccionesPorDefecto = {
  'resumen': true,
  'cumplimiento': false,
  'detalle': true,
  'novedades': false,
  'reemplazadas': true,
  'consolidadoRecursos': false,
  'anexoTareas': false,
};

const _camposPorDefecto = {
  'ubicacion': true,
  'responsables': true,
  'fechas': true,
  'cifras': true,
  'estado': false,
  'puntualidad': false,
  'insumos': true,
  'maquinaria': true,
  'herramientas': true,
  'observaciones': true,
  'reemplazos': true,
  'numerosTarea': true,
  'motivoRechazo': false,
  'cerradoPor': false,
};

const fotosPorTareaOpciones = <int?>[1, 2, 3, 4, 6, null];

class OpcionesInformeDetallado {
  final OrganizacionInforme organizacion;

  /// Filtros: null = sin filtro (todas). Un conjunto vacío no deja nada.
  final Set<String>? tipos;
  final Set<String>? estados;
  final Set<String>? frecuencias;
  final Set<String>? ubicaciones;
  final bool soloConEvidencia;

  final Map<String, bool> secciones;
  final Map<String, bool> campos;

  final bool incluirFotos;

  /// null = todas las fotos de cada tarea.
  final int? fotosPorTarea;
  final RegistrosConFoto registrosPorActividad;
  final TamanoFoto tamanoFotos;
  final CalidadFoto calidadFotos;

  final String titulo;
  final String observacionesGenerales;

  const OpcionesInformeDetallado({
    this.organizacion = OrganizacionInforme.actividad,
    this.tipos,
    this.estados,
    this.frecuencias,
    this.ubicaciones,
    this.soloConEvidencia = false,
    this.secciones = _seccionesPorDefecto,
    this.campos = _camposPorDefecto,
    this.incluirFotos = true,
    this.fotosPorTarea,
    this.registrosPorActividad = RegistrosConFoto.auto,
    this.tamanoFotos = TamanoFoto.auto,
    this.calidadFotos = CalidadFoto.estandar,
    this.titulo = '',
    this.observacionesGenerales = '',
  });

  bool seccion(String clave) => secciones[clave] ?? false;
  bool campo(String clave) => campos[clave] ?? false;

  bool get tieneFiltros =>
      tipos != null ||
      estados != null ||
      frecuencias != null ||
      ubicaciones != null ||
      soloConEvidencia;

  OpcionesInformeDetallado copyWith({
    OrganizacionInforme? organizacion,
    Set<String>? Function()? tipos,
    Set<String>? Function()? estados,
    Set<String>? Function()? frecuencias,
    Set<String>? Function()? ubicaciones,
    bool? soloConEvidencia,
    Map<String, bool>? secciones,
    Map<String, bool>? campos,
    bool? incluirFotos,
    int? Function()? fotosPorTarea,
    RegistrosConFoto? registrosPorActividad,
    TamanoFoto? tamanoFotos,
    CalidadFoto? calidadFotos,
    String? titulo,
    String? observacionesGenerales,
  }) {
    return OpcionesInformeDetallado(
      organizacion: organizacion ?? this.organizacion,
      tipos: tipos != null ? tipos() : this.tipos,
      estados: estados != null ? estados() : this.estados,
      frecuencias: frecuencias != null ? frecuencias() : this.frecuencias,
      ubicaciones: ubicaciones != null ? ubicaciones() : this.ubicaciones,
      soloConEvidencia: soloConEvidencia ?? this.soloConEvidencia,
      secciones: secciones ?? this.secciones,
      campos: campos ?? this.campos,
      incluirFotos: incluirFotos ?? this.incluirFotos,
      fotosPorTarea: fotosPorTarea != null
          ? fotosPorTarea()
          : this.fotosPorTarea,
      registrosPorActividad:
          registrosPorActividad ?? this.registrosPorActividad,
      tamanoFotos: tamanoFotos ?? this.tamanoFotos,
      calidadFotos: calidadFotos ?? this.calidadFotos,
      titulo: titulo ?? this.titulo,
      observacionesGenerales:
          observacionesGenerales ?? this.observacionesGenerales,
    );
  }

  OpcionesInformeDetallado conSeccion(String clave, bool valor) =>
      copyWith(secciones: {...secciones, clave: valor});

  OpcionesInformeDetallado conCampo(String clave, bool valor) =>
      copyWith(campos: {...campos, clave: valor});

  /// El administrador del conjunto (cliente) no recibe lo interno. El backend
  /// lo vuelve a imponer; esto solo evita ofrecerlo.
  OpcionesInformeDetallado paraAdministrador() {
    final limpios = Map<String, bool>.from(campos);
    for (final c in camposInforme.where((c) => c.interna)) {
      limpios[c.clave] = false;
    }
    return copyWith(campos: limpios);
  }

  /// Lo que impide generar el informe, en palabras para el usuario.
  List<String> get errores {
    final out = <String>[];
    if (!seccionesInforme.any((s) => seccion(s.clave))) {
      out.add('Elige al menos una sección para el informe.');
    }
    if (tipos != null && tipos!.isEmpty) out.add('Elige al menos un tipo.');
    if (estados != null && estados!.isEmpty) {
      out.add('Elige al menos un estado.');
    }
    if (frecuencias != null && frecuencias!.isEmpty) {
      out.add('Elige al menos una frecuencia.');
    }
    if (ubicaciones != null && ubicaciones!.isEmpty) {
      out.add('Elige al menos una ubicación.');
    }
    return out;
  }

  static List<String> _ordenados(Set<String> v) => v.toList()..sort();

  static String? _texto(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  Map<String, dynamic> toJson() => {
    'organizacion': organizacion.api,
    'filtros': {
      if (tipos != null) 'tipos': _ordenados(tipos!),
      if (estados != null) 'estados': _ordenados(estados!),
      if (frecuencias != null) 'frecuencias': _ordenados(frecuencias!),
      if (ubicaciones != null) 'ubicaciones': _ordenados(ubicaciones!),
      'soloConEvidencia': soloConEvidencia,
    },
    'secciones': {for (final s in seccionesInforme) s.clave: seccion(s.clave)},
    'campos': {for (final c in camposInforme) c.clave: campo(c.clave)},
    'fotos': {
      'incluir': incluirFotos,
      'porTarea': fotosPorTarea,
      'registrosPorActividad': registrosPorActividad.json,
      'tamano': tamanoFotos.api,
      'calidad': calidadFotos.api,
    },
    'textos': {
      if (_texto(titulo) != null) 'titulo': _texto(titulo),
      if (_texto(observacionesGenerales) != null)
        'observacionesGenerales': _texto(observacionesGenerales),
    },
  };

  static Set<String>? _set(Object? v) =>
      v is List ? v.map((e) => '$e').toSet() : null;

  static Map<String, bool> _bools(Object? v, Map<String, bool> base) {
    final out = Map<String, bool>.from(base);
    if (v is Map) {
      for (final k in base.keys) {
        if (v[k] is bool) out[k] = v[k] as bool;
      }
    }
    return out;
  }

  factory OpcionesInformeDetallado.fromJson(Map<String, dynamic> json) {
    final filtros = json['filtros'] is Map ? json['filtros'] as Map : const {};
    final fotos = json['fotos'] is Map ? json['fotos'] as Map : const {};
    final textos = json['textos'] is Map ? json['textos'] as Map : const {};
    final porTarea = fotos['porTarea'];
    return OpcionesInformeDetallado(
      organizacion: OrganizacionInforme.desdeApi(json['organizacion']),
      tipos: _set(filtros['tipos']),
      estados: _set(filtros['estados']),
      frecuencias: _set(filtros['frecuencias']),
      ubicaciones: _set(filtros['ubicaciones']),
      soloConEvidencia: filtros['soloConEvidencia'] == true,
      secciones: _bools(json['secciones'], _seccionesPorDefecto),
      campos: _bools(json['campos'], _camposPorDefecto),
      incluirFotos: fotos['incluir'] != false,
      fotosPorTarea: porTarea is num && fotosPorTareaOpciones.contains(porTarea)
          ? porTarea.toInt()
          : null,
      registrosPorActividad: RegistrosConFoto.desdeApi(
        fotos['registrosPorActividad'],
      ),
      tamanoFotos: TamanoFoto.desdeApi(fotos['tamano']),
      calidadFotos: CalidadFoto.desdeApi(fotos['calidad']),
      titulo: (textos['titulo'] ?? '').toString(),
      observacionesGenerales: (textos['observacionesGenerales'] ?? '')
          .toString(),
    );
  }

  /// Lo que se recuerda para la próxima vez. Los filtros y las observaciones
  /// generales son del periodo: recordarlos podría generar por error un
  /// informe filtrado o con notas de otro mes.
  Map<String, dynamic> toPreferencias() {
    final json = copyWith(
      tipos: () => null,
      estados: () => null,
      frecuencias: () => null,
      ubicaciones: () => null,
      soloConEvidencia: false,
      observacionesGenerales: '',
    ).toJson();
    return json;
  }

  /* ------------------------------ plantillas ------------------------------ */

  static const estandar = OpcionesInformeDetallado();

  static final auditoria = const OpcionesInformeDetallado().copyWith(
    secciones: {for (final s in seccionesInforme) s.clave: true},
    campos: {..._camposPorDefecto, 'estado': true, 'puntualidad': true},
  );

  static final fotografico = const OpcionesInformeDetallado().copyWith(
    secciones: {..._seccionesPorDefecto, 'reemplazadas': false},
    campos: {
      ..._camposPorDefecto,
      'cifras': false,
      'insumos': false,
      'maquinaria': false,
      'herramientas': false,
      'reemplazos': false,
    },
    registrosPorActividad: RegistrosConFoto.todos,
    tamanoFotos: TamanoFoto.grande,
  );

  static final ejecutivo = const OpcionesInformeDetallado().copyWith(
    secciones: {
      ..._seccionesPorDefecto,
      'cumplimiento': true,
      'detalle': false,
      'novedades': true,
      'consolidadoRecursos': true,
    },
    incluirFotos: false,
  );

  static OpcionesInformeDetallado deFormato(PlantillaInforme p) {
    switch (p) {
      case PlantillaInforme.auditoria:
        return auditoria;
      case PlantillaInforme.fotografico:
        return fotografico;
      case PlantillaInforme.ejecutivo:
        return ejecutivo;
      case PlantillaInforme.estandar:
      case PlantillaInforme.personalizado:
        return estandar;
    }
  }

  /// Aplica el formato de una plantilla conservando filtros y textos.
  OpcionesInformeDetallado conPlantilla(
    PlantillaInforme p, {
    bool esAdministrador = false,
  }) {
    final base = deFormato(p);
    final out = copyWith(
      organizacion: base.organizacion,
      secciones: base.secciones,
      campos: base.campos,
      incluirFotos: base.incluirFotos,
      fotosPorTarea: () => base.fotosPorTarea,
      registrosPorActividad: base.registrosPorActividad,
      tamanoFotos: base.tamanoFotos,
      calidadFotos: base.calidadFotos,
    );
    return esAdministrador ? out.paraAdministrador() : out;
  }

  /// Qué plantilla corresponde al formato elegido (sin mirar filtros ni textos).
  PlantillaInforme get plantilla {
    String formato(OpcionesInformeDetallado o) {
      final j = o.toJson();
      final campos = Map<String, dynamic>.from(j['campos'] as Map)
        ..remove('motivoRechazo')
        ..remove('cerradoPor');
      return '${j['organizacion']}|${j['secciones']}|$campos|${j['fotos']}';
    }

    final actual = formato(this);
    for (final p in PlantillaInforme.values) {
      if (p == PlantillaInforme.personalizado) continue;
      if (formato(deFormato(p)) == actual) return p;
    }
    return PlantillaInforme.personalizado;
  }
}

/* ------------------------------ estimación ------------------------------ */

const _ordenFrecuencias = [
  'DIARIA',
  'SEMANAL',
  'QUINCENAL',
  'MENSUAL',
  'BIMESTRAL',
  'TRIMESTRAL',
  'SEMESTRAL',
  'ANUAL',
];

String _sinTildes(String v) => v
    .replaceAll(RegExp('[áàä]'), 'a')
    .replaceAll(RegExp('[éèë]'), 'e')
    .replaceAll(RegExp('[íìï]'), 'i')
    .replaceAll(RegExp('[óòö]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll(RegExp('[ÁÀÄ]'), 'A')
    .replaceAll(RegExp('[ÉÈË]'), 'E')
    .replaceAll(RegExp('[ÍÌÏ]'), 'I')
    .replaceAll(RegExp('[ÓÒÖ]'), 'O')
    .replaceAll(RegExp('[ÚÙÜ]'), 'U');

String _clave(String? v) =>
    _sinTildes((v ?? '').trim().toUpperCase()).replaceAll(RegExp(r'\s+'), ' ');

/// Misma regla que el backend: "DIARIA_LUNES_A_SABADO" cuenta como "DIARIA".
String frecuenciaBase(String? raw) {
  final key = _clave(raw).replaceAll(RegExp(r'[\s-]+'), '_');
  if (key == 'DIARIO') return 'DIARIA';
  for (final f in _ordenFrecuencias) {
    if (key == f || key.startsWith('${f}_')) return f;
  }
  return key;
}

String etiquetaFrecuenciaInforme(String base) {
  if (base.isEmpty) return 'Sin frecuencia';
  final t = base.replaceAll('_', ' ').toLowerCase();
  return t[0].toUpperCase() + t.substring(1);
}

bool _esPreventiva(TareaDetalleRow t) => t.tipo.toUpperCase() == 'PREVENTIVA';

/// Valores presentes en las tareas cargadas, para armar los filtros.
class ValoresFiltroInforme {
  final List<String> estados;
  final List<String> frecuencias;
  final List<String> ubicaciones;
  final bool hayPreventivas;
  final bool hayCorrectivas;

  const ValoresFiltroInforme({
    required this.estados,
    required this.frecuencias,
    required this.ubicaciones,
    required this.hayPreventivas,
    required this.hayCorrectivas,
  });

  static const _ordenEstados = [
    'APROBADA',
    'COMPLETADA',
    'PENDIENTE_APROBACION',
    'EN_PROCESO',
    'ASIGNADA',
    'RECHAZADA',
    'NO_COMPLETADA',
    'PENDIENTE_REPROGRAMACION',
  ];

  factory ValoresFiltroInforme.desde(List<TareaDetalleRow> tareas) {
    final estados = tareas.map((t) => t.estado.toUpperCase()).toSet().toList()
      ..sort((a, b) {
        final ia = _ordenEstados.indexOf(a);
        final ib = _ordenEstados.indexOf(b);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });
    final frecuencias =
        tareas
            .where(_esPreventiva)
            .map((t) => frecuenciaBase(t.frecuencia))
            .where((f) => f.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) {
            final ia = _ordenFrecuencias.indexOf(a);
            final ib = _ordenFrecuencias.indexOf(b);
            return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
          });
    final porClave = <String, String>{};
    for (final t in tareas) {
      final u = (t.ubicacion ?? '').trim();
      if (u.isNotEmpty) porClave.putIfAbsent(_clave(u), () => u);
    }
    final ubicaciones = porClave.values.toList()
      ..sort((a, b) => _clave(a).compareTo(_clave(b)));
    return ValoresFiltroInforme(
      estados: estados,
      frecuencias: frecuencias,
      ubicaciones: ubicaciones,
      hayPreventivas: tareas.any(_esPreventiva),
      hayCorrectivas: tareas.any((t) => !_esPreventiva(t)),
    );
  }
}

class EstimacionInforme {
  final int tareas;
  final int fotos;
  final int fotosOmitidasPorLimite;
  final int limiteFotos;
  final double megas;
  final int segundos;

  const EstimacionInforme({
    required this.tareas,
    required this.fotos,
    required this.fotosOmitidasPorLimite,
    required this.limiteFotos,
    required this.megas,
    required this.segundos,
  });

  String get textoTamano => megas < 1
      ? 'menos de 1 MB'
      : '~${megas.toStringAsFixed(megas < 10 ? 1 : 0)} MB';

  String get textoTiempo =>
      segundos < 60 ? 'menos de 1 min' : '~${(segundos / 60).ceil()} min';
}

/// Posiciones repartidas de forma pareja (igual que el backend).
int _repartidas(int total, int max) => total <= 0 || max <= 0
    ? 0
    : total <= max
    ? total
    : max;

bool cumpleFiltrosInforme(TareaDetalleRow t, OpcionesInformeDetallado o) {
  final tipo = _esPreventiva(t) ? 'PREVENTIVA' : 'CORRECTIVA';
  if (o.tipos != null && !o.tipos!.contains(tipo)) return false;
  if (o.estados != null && !o.estados!.contains(t.estado.toUpperCase())) {
    return false;
  }
  if (o.frecuencias != null &&
      tipo == 'PREVENTIVA' &&
      !o.frecuencias!.contains(frecuenciaBase(t.frecuencia))) {
    return false;
  }
  if (o.ubicaciones != null &&
      !o.ubicaciones!.map(_clave).contains(_clave(t.ubicacion))) {
    return false;
  }
  if (o.soloConEvidencia && t.evidencias.isEmpty) return false;
  return true;
}

/// Cuántas tareas y fotos tendría el informe, sin pedir nada al servidor.
/// Agrupa las preventivas como el backend cuando no hay cronograma, así que
/// es una aproximación.
EstimacionInforme estimarInforme(
  List<TareaDetalleRow> tareas,
  OpcionesInformeDetallado o,
) {
  final incluidas = tareas.where((t) => cumpleFiltrosInforme(t, o)).toList();

  var fotos = 0;
  if (o.seccion('detalle') && o.incluirFotos) {
    final grupos = <String, List<TareaDetalleRow>>{};
    for (final t in incluidas) {
      final clave =
          o.organizacion == OrganizacionInforme.cronologico || !_esPreventiva(t)
          ? 'tarea:${t.id}'
          : [
              frecuenciaBase(t.frecuencia),
              _clave(t.descripcion),
              _clave(t.ubicacion),
              _clave(t.elemento),
            ].join('|');
      grupos.putIfAbsent(clave, () => []).add(t);
    }
    final porTarea = o.fotosPorTarea ?? 12;
    for (final g in grupos.values) {
      final conFoto = g.where((t) => t.evidencias.isNotEmpty).toList();
      final diaria =
          _esPreventiva(g.first) &&
          frecuenciaBase(g.first.frecuencia) == 'DIARIA';
      var registros = conFoto.length;
      var fotosPorRegistro = porTarea;
      switch (o.registrosPorActividad) {
        case RegistrosConFoto.auto:
          if (diaria && conFoto.length > 3) {
            registros = 3;
            fotosPorRegistro = o.fotosPorTarea ?? 1;
          }
        case RegistrosConFoto.todos:
          break;
        default:
          registros = _repartidas(
            conFoto.length,
            int.parse(o.registrosPorActividad.api),
          );
      }
      // Promedio de fotos de los registros con foto del grupo.
      if (registros == 0) continue;
      final promedio =
          conFoto
              .map((t) => _repartidas(t.evidencias.length, fotosPorRegistro))
              .fold<int>(0, (a, b) => a + b) /
          conFoto.length;
      fotos += (promedio * registros).round();
    }
  }

  final limite = o.calidadFotos.limiteFotos;
  final omitidas = fotos > limite ? fotos - limite : 0;
  final fotosFinales = fotos - omitidas;
  final megas = 0.3 + fotosFinales * o.calidadFotos.kbPorFoto / 1024;
  final segundos =
      (3 + fotosFinales * o.calidadFotos.segPorFoto + incluidas.length * 0.005)
          .round();

  return EstimacionInforme(
    tareas: incluidas.length,
    fotos: fotosFinales,
    fotosOmitidasPorLimite: omitidas,
    limiteFotos: limite,
    megas: megas,
    segundos: segundos,
  );
}
