import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/planilla_usuario_model.dart';
import 'package:flutter_application_1/utils/enums/hoja_vida_etiquetas.dart';
import 'package:flutter_application_1/utils/planilla/vacaciones_planilla.dart';

/// Lógica pura de la vista de tabla de usuarios (planilla de personal):
/// columnas y su texto, orden y visibilidad, agrupación y el texto que se
/// copia para pegar en Excel. Ver docs/planilla-personal.md.

class ColumnaPlanilla {
  final String clave;
  final String titulo;
  final double ancho;
  final String Function(PlanillaUsuario u, DateTime hoy) valor;

  const ColumnaPlanilla({
    required this.clave,
    required this.titulo,
    required this.ancho,
    required this.valor,
  });
}

/// Todas las columnas, en su orden por defecto.
final List<ColumnaPlanilla> columnasPlanilla = [
  ColumnaPlanilla(
    clave: 'nombre',
    titulo: 'Nombre',
    ancho: 200,
    valor: (u, _) => u.nombre,
  ),
  ColumnaPlanilla(
    clave: 'cedula',
    titulo: 'Cédula',
    ancho: 120,
    valor: (u, _) => u.cedula,
  ),
  ColumnaPlanilla(
    clave: 'rol',
    titulo: 'Rol',
    ancho: 150,
    valor: (u, _) => etiquetaRol(u.rol),
  ),
  ColumnaPlanilla(
    clave: 'estado',
    titulo: 'Estado',
    ancho: 100,
    valor: (u, _) => u.activo ? 'Activo' : 'Inactivo',
  ),
  ColumnaPlanilla(
    clave: 'conjuntos',
    titulo: 'Conjunto(s)',
    ancho: 200,
    valor: (u, _) => u.conjuntosTodos.map((c) => c.nombre).join(', '),
  ),
  ColumnaPlanilla(
    clave: 'plaza',
    titulo: 'Plaza',
    ancho: 220,
    valor: (u, _) =>
        u.plazas.map((p) => '${p.etiqueta} · ${p.conjuntoNombre}').join('; '),
  ),
  ColumnaPlanilla(
    clave: 'funciones',
    titulo: 'Funciones',
    ancho: 170,
    valor: (u, _) => u.funciones.map(etiquetaEnum).join(', '),
  ),
  ColumnaPlanilla(
    clave: 'telefono',
    titulo: 'Teléfono',
    ancho: 130,
    valor: (u, _) => u.telefono,
  ),
  ColumnaPlanilla(
    clave: 'correo',
    titulo: 'Correo',
    ancho: 230,
    valor: (u, _) => u.correo,
  ),
  ColumnaPlanilla(
    clave: 'direccion',
    titulo: 'Dirección',
    ancho: 220,
    valor: (u, _) => u.direccion ?? '',
  ),
  ColumnaPlanilla(
    clave: 'contactoEmergenciaNombre',
    titulo: 'Contacto de emergencia',
    ancho: 200,
    valor: (u, _) => u.contactoEmergenciaNombre ?? '',
  ),
  ColumnaPlanilla(
    clave: 'contactoEmergenciaParentesco',
    titulo: 'Parentesco del contacto',
    ancho: 140,
    valor: (u, _) => u.contactoEmergenciaParentesco ?? '',
  ),
  ColumnaPlanilla(
    clave: 'contactoEmergenciaTelefono',
    titulo: 'Teléfono del contacto',
    ancho: 150,
    valor: (u, _) => u.contactoEmergenciaTelefono ?? '',
  ),
  ColumnaPlanilla(
    clave: 'fechaNacimiento',
    titulo: 'Fecha de nacimiento',
    ancho: 130,
    valor: (u, _) => _fecha(u.fechaNacimiento),
  ),
  ColumnaPlanilla(
    clave: 'edad',
    titulo: 'Edad',
    ancho: 90,
    valor: (u, hoy) {
      final n = aniosCumplidos(u.fechaNacimiento, hoy);
      return n == null ? '' : '$n años';
    },
  ),
  ColumnaPlanilla(
    clave: 'fechaIngreso',
    titulo: 'Fecha de ingreso',
    ancho: 130,
    valor: (u, _) => _fecha(u.fechaIngreso),
  ),
  ColumnaPlanilla(
    clave: 'antiguedad',
    titulo: 'Antigüedad',
    ancho: 150,
    valor: (u, hoy) => antiguedad(u.fechaIngreso, u.fechaSalida, hoy),
  ),
  ColumnaPlanilla(
    clave: 'vacaciones',
    titulo: 'Días para vacaciones',
    ancho: 270,
    valor: (u, hoy) => textoVacaciones(u, hoy),
  ),
  ColumnaPlanilla(
    clave: 'ultimasVacaciones',
    titulo: 'Últimas vacaciones',
    ancho: 130,
    valor: (u, hoy) => _fecha(estadoVacacionesDe(u, hoy).ultimasVacaciones),
  ),
  ColumnaPlanilla(
    clave: 'fechaSalida',
    titulo: 'Fecha de retiro',
    ancho: 130,
    valor: (u, _) => _fecha(u.fechaSalida),
  ),
  ColumnaPlanilla(
    clave: 'tipoContrato',
    titulo: 'Tipo de contrato',
    ancho: 160,
    valor: (u, _) => etiquetaEnum(u.tipoContrato),
  ),
  ColumnaPlanilla(
    clave: 'jornadaLaboral',
    titulo: 'Jornada',
    ancho: 140,
    valor: (u, _) => etiquetaEnum(u.jornadaLaboral),
  ),
  ColumnaPlanilla(
    clave: 'patronJornada',
    titulo: 'Patrón de media jornada',
    ancho: 200,
    valor: (u, _) => etiquetaEnum(u.patronJornada),
  ),
  ColumnaPlanilla(
    clave: 'descanso',
    titulo: 'Día de descanso',
    ancho: 190,
    valor: (u, _) {
      final dia = etiquetaEnum(u.diaDescanso);
      if (u.trabajaDomingo != true) return dia;
      return dia.isEmpty ? 'Trabaja domingos' : '$dia · trabaja domingos';
    },
  ),
  ColumnaPlanilla(
    clave: 'eps',
    titulo: 'EPS',
    ancho: 150,
    valor: (u, _) => etiquetaEnum(u.eps),
  ),
  ColumnaPlanilla(
    clave: 'fondoPensiones',
    titulo: 'Fondo de pensiones',
    ancho: 160,
    valor: (u, _) => etiquetaEnum(u.fondoPensiones),
  ),
  ColumnaPlanilla(
    clave: 'arl',
    titulo: 'ARL',
    ancho: 160,
    valor: (u, _) => etiquetaArl(u.arl),
  ),
  ColumnaPlanilla(
    clave: 'cajaCompensacion',
    titulo: 'Caja de compensación',
    ancho: 190,
    valor: (u, _) => etiquetaCajaCompensacion(u.cajaCompensacion),
  ),
  ColumnaPlanilla(
    clave: 'tipoSangre',
    titulo: 'Tipo de sangre',
    ancho: 110,
    valor: (u, _) => etiquetaTipoSangre(u.tipoSangre),
  ),
  ColumnaPlanilla(
    clave: 'estadoCivil',
    titulo: 'Estado civil',
    ancho: 120,
    valor: (u, _) => etiquetaEnum(u.estadoCivil),
  ),
  ColumnaPlanilla(
    clave: 'numeroHijos',
    titulo: 'Número de hijos',
    ancho: 110,
    valor: (u, _) => u.numeroHijos?.toString() ?? '',
  ),
  ColumnaPlanilla(
    clave: 'padresVivos',
    titulo: 'Padres vivos',
    ancho: 100,
    valor: (u, _) => _siNo(u.padresVivos),
  ),
  ColumnaPlanilla(
    clave: 'tallaCamisa',
    titulo: 'Talla de camisa',
    ancho: 110,
    valor: (u, _) => etiquetaTalla(u.tallaCamisa),
  ),
  ColumnaPlanilla(
    clave: 'tallaPantalon',
    titulo: 'Talla de pantalón',
    ancho: 120,
    valor: (u, _) => etiquetaTalla(u.tallaPantalon),
  ),
  ColumnaPlanilla(
    clave: 'tallaCalzado',
    titulo: 'Talla de calzado',
    ancho: 120,
    valor: (u, _) => etiquetaTalla(u.tallaCalzado),
  ),
  ColumnaPlanilla(
    clave: 'cursoAlturas',
    titulo: 'Curso de alturas',
    ancho: 110,
    valor: (u, _) => _siNo(u.cursoAlturas),
  ),
  ColumnaPlanilla(
    clave: 'cursoSalvamento',
    titulo: 'Curso de salvamento acuático',
    ancho: 150,
    valor: (u, _) => _siNo(u.cursoSalvamentoAcuatico),
  ),
  ColumnaPlanilla(
    clave: 'examenIngreso',
    titulo: 'Examen de ingreso',
    ancho: 110,
    valor: (u, _) => _siNo(u.examenIngreso),
  ),
  ColumnaPlanilla(
    clave: 'observaciones',
    titulo: 'Observaciones',
    ancho: 260,
    valor: (u, _) => u.observaciones ?? '',
  ),
];

final Map<String, ColumnaPlanilla> _columnasPorClave = {
  for (final c in columnasPlanilla) c.clave: c,
};

ColumnaPlanilla? columnaPlanilla(String clave) => _columnasPorClave[clave];

/* ------------------------------ vacaciones ------------------------------ */

EstadoVacaciones estadoVacacionesDe(PlanillaUsuario u, DateTime hoy) =>
    calcularEstadoVacaciones(
      fechaIngreso: u.fechaIngreso,
      fechaSalida: u.fechaSalida,
      fechaUltimasVacaciones: u.fechaUltimasVacaciones,
      bloques: u.vacaciones,
      hoy: hoy,
    );

/// El administrador es el cliente del conjunto, no un empleado: no aplica.
String textoVacaciones(PlanillaUsuario u, DateTime hoy) {
  if (u.rol == 'administrador' && u.fechaIngreso == null) return 'No aplica';
  return estadoVacacionesDe(u, hoy).texto;
}

/* ------------------------------ etiquetas ------------------------------- */

const Map<String, String> _etiquetasRol = {
  'gerente': 'Gerente',
  'jefe_operaciones': 'Jefe de operaciones',
  'supervisor': 'Supervisor',
  'administrador': 'Administrador',
  'operario': 'Operario',
};

String etiquetaRol(String rol) => _etiquetasRol[rol] ?? etiquetaEnum(rol);

const Map<String, String> _etiquetasEspeciales = {
  'NUEVA_EPS': 'Nueva EPS',
  'SAVIA_SALUD': 'Savia Salud',
  'UNION_LIBRE': 'Unión libre',
  'VIUDOA': 'Viudo(a)',
  'TERMINO_INDEFINIDO': 'Término indefinido',
  'TERMINO_FIJO': 'Término fijo',
  'OBRA_LABOR': 'Obra o labor',
  'MEDIO_TIEMPO': 'Medio tiempo',
  'FINES_DE_SEMANA': 'Fines de semana',
  'MEDIO_SEMANA_SABADO': 'Mañanas entre semana y sábado',
  'MEDIO_SEMANA_SABADO_TARDE': 'Tardes entre semana y sábado',
  'MEDIO_DIAS_INTERCALADOS': 'Días intercalados',
  'MIERCOLES': 'Miércoles',
  'SABADO': 'Sábado',
};

/// Nombres de EPS, fondos y cajas: cada palabra con mayúscula inicial.
const Set<String> _nombresPropios = {
  'SANITAS',
  'SALUD_TOTAL',
  'SURA',
  'COMPENSAR',
  'FAMISANAR',
  'COOSALUD',
  'MUTUAL_SER',
  'CAPITAL_SALUD',
  'ASMET_SALUD',
  'ECOOPSOS',
  'EMSSANAR',
  'CAJACOPI',
  'COMFENALCO_ANTIOQUIA',
  'COMFACHOCO',
  'COMPARTA',
  'DUSAKAWI',
  'MALLAMAS',
  'ANAS_WAIMAS',
  'COLPENSIONES',
  'PORVENIR',
  'PROTECCION',
  'COLFONDOS',
  'SKANDIA',
  'OLD_MUTUAL',
};

/// `TERMINO_FIJO` → `Término fijo`; `SALUD_TOTAL` → `Salud Total`.
String etiquetaEnum(String? valor) {
  final v = valor?.trim() ?? '';
  if (v.isEmpty) return '';
  final especial = _etiquetasEspeciales[v];
  if (especial != null) return especial;
  final palabras = v.toLowerCase().split('_').where((p) => p.isNotEmpty);
  if (_nombresPropios.contains(v)) {
    return palabras.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
  }
  final texto = palabras.join(' ');
  return texto.isEmpty ? '' : texto[0].toUpperCase() + texto.substring(1);
}

/// `O_POSITIVO` → `O+`.
String etiquetaTipoSangre(String? valor) {
  final v = valor?.trim() ?? '';
  final m = RegExp(r'^(AB|A|B|O)_(POSITIVO|NEGATIVO)$').firstMatch(v);
  if (m == null) return etiquetaEnum(v);
  return '${m.group(1)}${m.group(2) == 'POSITIVO' ? '+' : '-'}';
}

/// `T_32` → `32`; `F_8` → `F8`; `XL` → `XL`.
String etiquetaTalla(String? valor) {
  final v = valor?.trim() ?? '';
  if (v.startsWith('T_')) return v.substring(2);
  return v.replaceAll('_', '');
}

String _siNo(bool? v) => v == null ? '' : (v ? 'Sí' : 'No');

String _fecha(DateTime? d) =>
    d == null ? '' : DateFormat('dd/MM/yyyy').format(d);

/* ------------------------------ edades ---------------------------------- */

/// Años cumplidos de [desde] a [hoy] (null sin fecha o si es futura).
int? aniosCumplidos(DateTime? desde, DateTime hoy) {
  if (desde == null) return null;
  var n = hoy.year - desde.year;
  if (hoy.month < desde.month ||
      (hoy.month == desde.month && hoy.day < desde.day)) {
    n--;
  }
  return n < 0 ? null : n;
}

/// `3 años y 2 meses`, `8 meses`, `Menos de un mes`. Hasta el retiro si ya
/// salió.
String antiguedad(DateTime? ingreso, DateTime? salida, DateTime hoy) {
  if (ingreso == null) return '';
  final fin = salida != null && salida.isBefore(hoy) ? salida : hoy;
  var meses = (fin.year - ingreso.year) * 12 + fin.month - ingreso.month;
  if (fin.day < ingreso.day) meses--;
  if (meses < 0) return '';
  final anios = meses ~/ 12;
  final resto = meses % 12;
  String nAnios(int n) => n == 1 ? '1 año' : '$n años';
  String nMeses(int n) => n == 1 ? '1 mes' : '$n meses';
  if (anios == 0) return resto == 0 ? 'Menos de un mes' : nMeses(resto);
  return resto == 0 ? nAnios(anios) : '${nAnios(anios)} y ${nMeses(resto)}';
}

/* -------------------------- orden y visibilidad ------------------------- */

enum AgrupacionPlanilla { ninguna, conjunto, rol }

/// Columnas en orden (todas, también las ocultas), cuáles se ocultan y cómo
/// se agrupan las filas. Se guarda por dispositivo.
class ConfigPlanilla {
  final List<String> orden;
  final Set<String> ocultas;
  final AgrupacionPlanilla agrupacion;

  const ConfigPlanilla({
    required this.orden,
    this.ocultas = const {},
    this.agrupacion = AgrupacionPlanilla.ninguna,
  });

  factory ConfigPlanilla.porDefecto({
    AgrupacionPlanilla agrupacion = AgrupacionPlanilla.ninguna,
  }) => ConfigPlanilla(
    orden: [for (final c in columnasPlanilla) c.clave],
    agrupacion: agrupacion,
  );

  /// Lee lo guardado tolerando datos viejos o dañados: descarta columnas que
  /// ya no existen y agrega las nuevas junto a la que las precede por
  /// defecto.
  factory ConfigPlanilla.fromJson(
    Map<String, dynamic> json, {
    AgrupacionPlanilla agrupacionPorDefecto = AgrupacionPlanilla.ninguna,
  }) {
    final guardado = (json['orden'] is List ? json['orden'] as List : const [])
        .map((e) => e.toString())
        .toList();
    final ocultas =
        (json['ocultas'] is List ? json['ocultas'] as List : const [])
            .map((e) => e.toString())
            .where(_columnasPorClave.containsKey)
            .toSet();
    final agrupacion = AgrupacionPlanilla.values.firstWhere(
      (a) => a.name == json['agrupacion'],
      orElse: () => agrupacionPorDefecto,
    );
    final config = ConfigPlanilla(
      orden: normalizarOrden(guardado),
      ocultas: ocultas,
      agrupacion: agrupacion,
    );
    // Nunca todas ocultas: la tabla quedaría vacía sin forma de arreglarla.
    return config.visibles.isEmpty
        ? ConfigPlanilla(orden: config.orden, agrupacion: agrupacion)
        : config;
  }

  Map<String, dynamic> toJson() => {
    'orden': orden,
    'ocultas': ocultas.toList()..sort(),
    'agrupacion': agrupacion.name,
  };

  List<ColumnaPlanilla> get visibles => [
    for (final clave in orden)
      if (!ocultas.contains(clave) && _columnasPorClave[clave] != null)
        _columnasPorClave[clave]!,
  ];

  bool esVisible(String clave) => !ocultas.contains(clave);

  /// Lleva [clave] al lugar de [destino] (queda antes de [destino] si venía
  /// de la derecha y después si venía de la izquierda), como al arrastrar.
  ConfigPlanilla mover(String clave, String destino) {
    final i = orden.indexOf(clave);
    final j = orden.indexOf(destino);
    if (i < 0 || j < 0 || i == j) return this;
    final nuevo = [...orden]..removeAt(i);
    nuevo.insert(j, clave);
    return _con(orden: nuevo);
  }

  /// Mueve [clave] una posición entre las columnas visibles (-1 izquierda,
  /// +1 derecha). Sin vecina en esa dirección no cambia nada.
  ConfigPlanilla moverUnPaso(String clave, int direccion) {
    final vis = visibles.map((c) => c.clave).toList();
    final i = vis.indexOf(clave);
    final j = i + direccion.sign;
    if (i < 0 || direccion == 0 || j < 0 || j >= vis.length) return this;
    return mover(clave, vis[j]);
  }

  /// Muestra u oculta [clave]. La última columna visible no se oculta.
  ConfigPlanilla alternar(String clave) {
    if (!_columnasPorClave.containsKey(clave)) return this;
    if (ocultas.contains(clave)) {
      return _con(ocultas: {...ocultas}..remove(clave));
    }
    if (visibles.length <= 1) return this;
    return _con(ocultas: {...ocultas, clave});
  }

  ConfigPlanilla mostrarTodas() => _con(ocultas: const {});

  /// Vuelve al orden por defecto sin cambiar qué columnas se ocultan.
  ConfigPlanilla restablecerOrden() =>
      _con(orden: [for (final c in columnasPlanilla) c.clave]);

  ConfigPlanilla conAgrupacion(AgrupacionPlanilla a) => _con(agrupacion: a);

  ConfigPlanilla _con({
    List<String>? orden,
    Set<String>? ocultas,
    AgrupacionPlanilla? agrupacion,
  }) => ConfigPlanilla(
    orden: orden ?? this.orden,
    ocultas: ocultas ?? this.ocultas,
    agrupacion: agrupacion ?? this.agrupacion,
  );
}

/// Orden guardado → orden válido con todas las columnas actuales.
List<String> normalizarOrden(List<String> guardado) {
  final porDefecto = [for (final c in columnasPlanilla) c.clave];
  final resultado = <String>[];
  for (final clave in guardado) {
    if (_columnasPorClave.containsKey(clave) && !resultado.contains(clave)) {
      resultado.add(clave);
    }
  }
  for (var i = 0; i < porDefecto.length; i++) {
    final clave = porDefecto[i];
    if (resultado.contains(clave)) continue;
    var pos = 0;
    for (var k = i - 1; k >= 0; k--) {
      final previa = resultado.indexOf(porDefecto[k]);
      if (previa >= 0) {
        pos = previa + 1;
        break;
      }
    }
    resultado.insert(pos, clave);
  }
  return resultado;
}

/* ------------------------------ agrupación ------------------------------ */

class GrupoPlanilla {
  /// NIT o rol del grupo; null en la tabla sin agrupar o en "Sin conjunto".
  final String? clave;
  final String titulo;
  final List<PlanillaUsuario> filas;

  const GrupoPlanilla({
    required this.clave,
    required this.titulo,
    required this.filas,
  });

  /// `Bosque · 12 personas`.
  String get encabezado =>
      '$titulo · ${filas.length == 1 ? '1 persona' : '${filas.length} personas'}';
}

const List<String> _ordenRoles = [
  'gerente',
  'jefe_operaciones',
  'supervisor',
  'administrador',
  'operario',
];

const Map<String, String> _rolesPlural = {
  'gerente': 'Gerentes',
  'jefe_operaciones': 'Jefes de operaciones',
  'supervisor': 'Supervisores',
  'administrador': 'Administradores',
  'operario': 'Operarios',
};

/// Agrupa conservando el orden de [filas] dentro de cada grupo. Por
/// conjunto, quien está en varios aparece en cada uno; quien no tiene
/// ninguno va al final en "Sin conjunto".
List<GrupoPlanilla> agruparPlanilla(
  List<PlanillaUsuario> filas,
  AgrupacionPlanilla agrupacion,
) {
  switch (agrupacion) {
    case AgrupacionPlanilla.ninguna:
      return [GrupoPlanilla(clave: null, titulo: '', filas: filas)];

    case AgrupacionPlanilla.conjunto:
      final nombres = <String, String>{};
      final porNit = <String, List<PlanillaUsuario>>{};
      final sinConjunto = <PlanillaUsuario>[];
      for (final u in filas) {
        final conjuntos = u.conjuntosTodos;
        if (conjuntos.isEmpty) sinConjunto.add(u);
        for (final c in conjuntos) {
          nombres[c.nit] = c.nombre;
          porNit.putIfAbsent(c.nit, () => []).add(u);
        }
      }
      final nits = porNit.keys.toList()
        ..sort((a, b) {
          final n = nombres[a]!.toLowerCase().compareTo(
            nombres[b]!.toLowerCase(),
          );
          return n != 0 ? n : a.compareTo(b);
        });
      return [
        for (final nit in nits)
          GrupoPlanilla(clave: nit, titulo: nombres[nit]!, filas: porNit[nit]!),
        if (sinConjunto.isNotEmpty)
          GrupoPlanilla(
            clave: null,
            titulo: 'Sin conjunto',
            filas: sinConjunto,
          ),
      ];

    case AgrupacionPlanilla.rol:
      final porRol = <String, List<PlanillaUsuario>>{};
      for (final u in filas) {
        porRol.putIfAbsent(u.rol, () => []).add(u);
      }
      int posicion(String rol) {
        final i = _ordenRoles.indexOf(rol);
        return i < 0 ? _ordenRoles.length : i;
      }

      final roles = porRol.keys.toList()
        ..sort((a, b) {
          final p = posicion(a).compareTo(posicion(b));
          return p != 0 ? p : a.compareTo(b);
        });
      return [
        for (final rol in roles)
          GrupoPlanilla(
            clave: rol,
            titulo: _rolesPlural[rol] ?? etiquetaRol(rol),
            filas: porRol[rol]!,
          ),
      ];
  }
}

/* ---------------------------- copiar a Excel ---------------------------- */

/// Texto de una celda listo para pegar en Excel: sin tabuladores ni saltos
/// de línea (partirían la fila) y sin que empiece como fórmula.
String celdaParaExcel(String valor) {
  final limpio = valor.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  if (limpio.isNotEmpty && '=+-@'.contains(limpio[0])) return ' $limpio';
  return limpio;
}

String encabezadoParaExcel(List<ColumnaPlanilla> columnas) =>
    columnas.map((c) => celdaParaExcel(c.titulo)).join('\t');

/// Una fila separada por tabuladores, en el orden de [columnas].
String filaParaExcel(
  PlanillaUsuario u,
  List<ColumnaPlanilla> columnas,
  DateTime hoy, {
  bool conEncabezado = false,
}) {
  final fila = columnas.map((c) => celdaParaExcel(c.valor(u, hoy))).join('\t');
  return conEncabezado ? '${encabezadoParaExcel(columnas)}\n$fila' : fila;
}

/// La tabla tal como se ve: encabezados, y por cada grupo una línea con su
/// título (si está agrupada) seguida de sus filas.
String tablaParaExcel(
  List<GrupoPlanilla> grupos,
  List<ColumnaPlanilla> columnas,
  DateTime hoy,
) {
  final lineas = <String>[encabezadoParaExcel(columnas)];
  for (final g in grupos) {
    if (g.titulo.isNotEmpty) lineas.add(celdaParaExcel(g.encabezado));
    for (final u in g.filas) {
      lineas.add(filaParaExcel(u, columnas, hoy));
    }
  }
  return lineas.join('\n');
}
