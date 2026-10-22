import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/utils/week_layout.dart';

/// Medidas de la hoja impresa del cronograma: A4 horizontal, en puntos.
/// El PDF y la vista previa las comparten para que se vean iguales.
class MedidasHoja {
  static const double ancho = 841.89;
  static const double alto = 595.28;

  /// Franja verde del borde superior.
  static const double franjaSuperior = 5;
  static const double margen = 20;
  static const double espacioSuperior = 14;
  static const double espacioInferior = 12;
  static const double encabezado = 62;
  static const double separacion = 8;
  static const double titulosDias = 30;
  static const double pie = 40;
  static const double anchoHoras = 38;

  static const double anchoContenido = ancho - margen * 2;
  static const double anchoGrilla = anchoContenido - anchoHoras;
  static const double altoGrilla =
      alto -
      franjaSuperior -
      espacioSuperior -
      encabezado -
      separacion -
      titulosDias -
      separacion -
      pie -
      espacioInferior;

  /// Alto con el que una tarjeta se alcanza a leer (hora + nombre en una
  /// línea). Igual que en «Por horas», si hay actividades muy seguidas la
  /// escala sube; aquí, en vez de desplazarse, el día se parte en hojas.
  static const double altoMinTarjeta = 15;

  /// Tope de la escala (144 pt por hora) para tareas de pocos minutos.
  static const double ptPorMinutoMax = 2.4;

  static const double margenColumna = 3;
  static const double separacionTarjetas = 1.5;
}

/// Colores de la hoja impresa (marca ControlApp, como los ejemplos).
class ColoresHoja {
  static const Color marca = Color(0xFF0E8A43);
  static const Color tinta = Color(0xFF12352A);
  static const Color cabecera = Color(0xFF173F2E);
  static const Color texto = Color(0xFF1F2D26);
  static const Color textoSuave = Color(0xFF5E7467);
  static const Color borde = Color(0xFFD5DED8);
  static const Color linea = Color(0xFFDCE5DF);
  static const Color lineaMedia = Color(0xFFF0F3F1);
  static const Color fondoSuave = Color(0xFFF5F8F6);
  static const Color fueraMes = Color(0xFFA3ADA6);
  static const Color rayado = Color(0xFFDCE1DD);
  static const Color festivo = Color(0xFFB42318);
  static const Color festivoFondo = Color(0xFFFDF1F0);
  static const Color libreFondo = Color(0xFFFFFAF0);
  static const Color libreBorde = Color(0xFFF3C46F);
  static const Color libreTexto = Color(0xFF8A5300);
  static const Color descansoFondo = Color(0xFFF3F5F3);
  static const Color hecha = Color(0xFF15803D);
  static const Color noHecha = Color(0xFFB45309);
  static const Color casilla = Color(0xFF8A9A90);

  /// Colores de las iniciales de cada operario (como en el ejemplo).
  static const List<Color> avatares = [
    Color(0xFF15803D),
    Color(0xFF1D4ED8),
    Color(0xFFD69E00),
    Color(0xFFC2410C),
    Color(0xFF7C3AED),
    Color(0xFF0F766E),
    Color(0xFFBE185D),
    Color(0xFF4D7C0F),
  ];

  /// Texto legible sobre [fondo] (blanco o tinta oscura).
  static Color textoSobre(Color fondo) =>
      contraste(Colors.white, fondo) >= 3 ? Colors.white : tinta;

  /// [color] mezclado con blanco (el PDF no maneja transparencias).
  static Color aclarar(Color color, double cuanto) =>
      Color.lerp(color, Colors.white, cuanto)!;
}

/// Tamaños del texto de las tarjetas (los usan el PDF y la vista previa
/// para repartir el alto igual).
class TextosHoja {
  static const double hora = 7.2;
  static const double titulo = 7.4;
  static const double detalle = 6.4;

  /// Alto de una línea respecto al tamaño de la letra (Roboto).
  static const double factorLinea = 1.18;
  static const double filaHora = 9.5;
  static const double separacionFila = 1.2;
  static const double filaSigue = 7;
  static const double padH = 3;
  static const double padV = 2;
  static const double barra = 2.4;
}

/// Cómo quedó la actividad: la casilla de la hoja sale vacía para que el
/// operario la marque, o ya marcada si se cerró.
enum MarcaCierre { pendiente, hecha, noHecha }

enum TamanoTarjeta { chica, mediana, grande }

enum TipoFranja { libre, descanso }

class TarjetaHoja {
  final TareaModel tarea;
  final CategoriaVisual visual;

  /// Posición dentro del cuerpo de la grilla (sin la columna de horas).
  final double x;
  final double y;
  final double ancho;
  final double alto;

  /// La actividad empezó en la hoja anterior o sigue en la siguiente.
  final bool continuaAntes;
  final bool continuaDespues;
  final int personas;
  final MarcaCierre marca;

  const TarjetaHoja({
    required this.tarea,
    required this.visual,
    required this.x,
    required this.y,
    required this.ancho,
    required this.alto,
    required this.continuaAntes,
    required this.continuaDespues,
    required this.personas,
    required this.marca,
  });

  TamanoTarjeta get tamano {
    if (alto >= 34) return TamanoTarjeta.grande;
    if (alto >= 21) return TamanoTarjeta.mediana;
    return TamanoTarjeta.chica;
  }

  /// "Torre 1 · Pisos": lo que se ve primero, como en el ejemplo.
  String get lugar => [
    (tarea.ubicacionNombre ?? '').trim(),
    (tarea.elementoNombre ?? '').trim(),
  ].where((s) => s.isNotEmpty).join(' · ');

  String get titulo {
    if (lugar.isNotEmpty) return lugar;
    final d = tarea.descripcion.trim();
    return d.isEmpty ? 'Sin descripción' : d;
  }

  /// La descripción, si el título es el lugar.
  String get detalle => lugar.isEmpty ? '' : tarea.descripcion.trim();

  String get horaInicio => horaTexto(tarea.fechaInicio);

  String get rango =>
      '${horaTexto(tarea.fechaInicio)} – ${horaTexto(tarea.fechaFin)}';

  String get duracion => duracionTexto(
    math.max(0, tarea.fechaFin.difference(tarea.fechaInicio).inMinutes),
  );

  double get _anchoTexto => ancho - TextosHoja.barra - TextosHoja.padH * 2 - 1;

  double get _altoTexto =>
      alto -
      TextosHoja.padV * 2 -
      TextosHoja.filaHora -
      TextosHoja.separacionFila -
      (continuaDespues ? TextosHoja.filaSigue : 0);

  static const _lineaTitulo = TextosHoja.titulo * TextosHoja.factorLinea;
  static const _lineaDetalle = TextosHoja.detalle * TextosHoja.factorLinea;

  /// Líneas del título en una tarjeta grande (las que necesita, hasta 3,
  /// si caben).
  int get lineasTitulo {
    final caben = (_altoTexto / _lineaTitulo).floor().clamp(1, 3);
    return _lineasEstimadas(
      titulo,
      TextosHoja.titulo,
      _anchoTexto,
    ).clamp(1, caben);
  }

  /// Líneas de la descripción que caben debajo del título.
  int get lineasDetalle {
    if (detalle.isEmpty) return 0;
    return math.max(
      0,
      ((_altoTexto - lineasTitulo * _lineaTitulo) / _lineaDetalle).floor(),
    );
  }
}

/// Cuántas líneas ocupa más o menos [texto] a ese tamaño y ancho.
int _lineasEstimadas(String texto, double tam, double ancho) {
  if (texto.isEmpty || ancho <= 0) return 0;
  final porLinea = (ancho / (tam * 0.5)).floor().clamp(1, 1000);
  return (texto.length / porLinea).ceil();
}

class FranjaHoja {
  final TipoFranja tipo;
  final double x;
  final double y;
  final double ancho;
  final double alto;
  final int inicioMin;
  final int finMin;

  const FranjaHoja({
    required this.tipo,
    required this.x,
    required this.y,
    required this.ancho,
    required this.alto,
    required this.inicioMin,
    required this.finMin,
  });

  String get texto => tipo == TipoFranja.descanso
      ? 'Descanso'
      : 'Libre · ${duracionTexto(finMin - inicioMin)}';
}

class DiaHoja {
  final DateTime fecha;
  final double x;
  final double ancho;
  final bool fueraDelMes;
  final bool mesAnterior;
  final bool festivo;
  final String? festivoNombre;

  const DiaHoja({
    required this.fecha,
    required this.x,
    required this.ancho,
    required this.fueraDelMes,
    required this.mesAnterior,
    required this.festivo,
    this.festivoNombre,
  });

  static const _nombres = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];

  String get nombreCorto => _nombres[fecha.weekday - 1];

  /// Lo que se escribe dentro del día cuando no se trabaja en él.
  String? get aviso {
    if (fueraDelMes) return mesAnterior ? 'Mes anterior' : 'Mes siguiente';
    if (festivo) {
      final n = festivoNombre?.trim() ?? '';
      return n.isEmpty ? 'Festivo' : 'Festivo: $n';
    }
    return null;
  }
}

class LineaHora {
  final double y;

  /// null en las líneas de media hora (sin etiqueta).
  final String? texto;

  const LineaHora({required this.y, this.texto});

  bool get principal => texto != null;
}

/// Quien aparece en la hoja, con su puesto y su plaza.
class OperarioImpresion {
  final TrabajadorRef ref;
  final String puesto;
  final String plaza;
  final Color color;
  final List<CategoriaVisual> categorias;
  final int actividades;
  final int minutos;

  const OperarioImpresion({
    required this.ref,
    required this.puesto,
    required this.plaza,
    required this.color,
    required this.categorias,
    required this.actividades,
    required this.minutos,
  });

  String get inicial => ref.nombre.trim().isEmpty
      ? '?'
      : ref.nombre.trim().substring(0, 1).toUpperCase();

  String get subtitulo =>
      [puesto, plaza].where((s) => s.trim().isNotEmpty).join(' · ');

  /// Una categoría por ícono (para los íconos junto al nombre).
  List<CategoriaVisual> get iconos {
    final vistos = <int>{};
    return [
      for (final v in categorias)
        if (vistos.add(v.icono.codePoint)) v,
    ];
  }
}

/// Una hoja del PDF: la semana de un operario (o una parte de su día si
/// las actividades son muy seguidas y no caben legibles en una sola hoja).
class HojaCronograma {
  final String conjuntoNombre;
  final OperarioImpresion operario;
  final int semana;
  final String rangoTexto;
  final int minutosProgramados;
  final List<DiaHoja> dias;
  final List<LineaHora> lineas;
  final List<FranjaHoja> franjas;
  final List<TarjetaHoja> tarjetas;
  final int parte;
  final int totalPartes;
  final int ventanaInicioMin;
  final int ventanaFinMin;

  const HojaCronograma({
    required this.conjuntoNombre,
    required this.operario,
    required this.semana,
    required this.rangoTexto,
    required this.minutosProgramados,
    required this.dias,
    required this.lineas,
    required this.franjas,
    required this.tarjetas,
    required this.parte,
    required this.totalPartes,
    required this.ventanaInicioMin,
    required this.ventanaFinMin,
  });

  bool get ultimaParte => parte == totalPartes;

  String get etiquetaSuperior =>
      '$conjuntoNombre · Semana $semana · $rangoTexto'.toUpperCase();

  String get programadoTexto => duracionTexto(minutosProgramados);

  /// "Parte 1 de 2 · 07:00 a 11:30" (vacío si la semana cabe en una hoja).
  String get parteTexto => totalPartes <= 1
      ? ''
      : 'Parte $parte de $totalPartes · ${minutosTexto(ventanaInicioMin)} a ${minutosTexto(ventanaFinMin)}';

  /// Categorías de las actividades de esta hoja, para la leyenda.
  List<CategoriaVisual> get categorias =>
      categoriasDistintas(tarjetas.map((t) => t.visual));

  bool get hayLibres => franjas.any((f) => f.tipo == TipoFranja.libre);

  bool get hayCompartidas => tarjetas.any((t) => t.personas > 1);

  bool get hayNoHechas => tarjetas.any((t) => t.marca == MarcaCierre.noHecha);
}

class CategoriaResumen {
  final CategoriaVisual visual;
  final int actividades;
  final int minutos;

  const CategoriaResumen({
    required this.visual,
    required this.actividades,
    required this.minutos,
  });
}

class PuestoImpresion {
  final String nombre;
  final String detalle;

  const PuestoImpresion({required this.nombre, required this.detalle});
}

/// Primera hoja cuando se imprime a todo el equipo.
class PortadaCronograma {
  final String conjuntoNombre;
  final String periodoTexto;
  final String semanaTexto;
  final List<CategoriaResumen> categorias;
  final List<PuestoImpresion> puestos;
  final List<OperarioImpresion> operarios;

  const PortadaCronograma({
    required this.conjuntoNombre,
    required this.periodoTexto,
    required this.semanaTexto,
    required this.categorias,
    required this.puestos,
    required this.operarios,
  });

  String get etiquetaSuperior =>
      'Conjunto $conjuntoNombre · $periodoTexto'.toUpperCase();
}

class PlanImpresion {
  final PortadaCronograma? portada;
  final List<HojaCronograma> hojas;
  final String nombreArchivo;

  const PlanImpresion({
    required this.portada,
    required this.hojas,
    required this.nombreArchivo,
  });

  bool get vacio => portada == null && hojas.isEmpty;
}

/* ============================== Textos ============================== */

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String nombreMes(int mes) => _meses[(mes - 1).clamp(0, 11)];

String horaTexto(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String minutosTexto(int m) {
  final c = m.clamp(0, 24 * 60);
  return '${(c ~/ 60).toString().padLeft(2, '0')}:${(c % 60).toString().padLeft(2, '0')}';
}

/// "18 h 55", "2 h", "45 min".
String duracionTexto(int minutos) {
  final h = minutos ~/ 60;
  final m = minutos % 60;
  if (h <= 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h ${m.toString().padLeft(2, '0')}';
}

/// "1 al 4 de octubre" o "29 de septiembre al 4 de octubre".
String rangoDiasTexto(DateTime desde, DateTime hasta) {
  if (desde.year == hasta.year && desde.month == hasta.month) {
    if (desde.day == hasta.day) {
      return '${desde.day} de ${nombreMes(desde.month)}';
    }
    return '${desde.day} al ${hasta.day} de ${nombreMes(hasta.month)}';
  }
  return '${desde.day} de ${nombreMes(desde.month)} al ${hasta.day} de ${nombreMes(hasta.month)}';
}

/// Una categoría por nombre, en orden alfabético; las especiales al final.
List<CategoriaVisual> categoriasDistintas(Iterable<CategoriaVisual> visuales) {
  final porNombre = <String, CategoriaVisual>{};
  for (final v in visuales) {
    porNombre.putIfAbsent('${v.esEspecial}|${v.nombre}', () => v);
  }
  final lista = porNombre.values.toList()
    ..sort((a, b) {
      if (a.esEspecial != b.esEspecial) return a.esEspecial ? 1 : -1;
      return normalizarTexto(a.nombre).compareTo(normalizarTexto(b.nombre));
    });
  return lista;
}

MarcaCierre marcaDe(TareaModel t) {
  final estado = EstadoVisual.de(t);
  if (identical(estado, EstadoVisual.noSeHizo)) return MarcaCierre.noHecha;
  return estado.cerrada ? MarcaCierre.hecha : MarcaCierre.pendiente;
}

/* ============================ Construcción ============================ */

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Lunes de cada semana que toca el mes (la semana 1 es la del día 1).
List<DateTime> semanasDelMes(int anio, int mes) {
  final primero = DateTime(anio, mes, 1);
  final ultimo = DateTime(anio, mes + 1, 0);
  var lunes = primero.subtract(Duration(days: primero.weekday - 1));
  final out = <DateTime>[];
  while (!lunes.isAfter(ultimo)) {
    out.add(lunes);
    lunes = DateTime(lunes.year, lunes.month, lunes.day + 7);
  }
  return out;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Arma lo que se imprime: portada (si se pide) y las hojas de cada
/// operario en cada semana.
///
/// [equipo] son todas las personas del mes: fija el color de cada una para
/// que no cambie si se imprime solo a una. [festivos] va de "yyyy-MM-dd" al
/// nombre del festivo (vacío si no lo tiene).
PlanImpresion construirPlanImpresion({
  required String conjuntoNombre,
  required int anio,
  required int mes,
  required List<TareaModel> tareasMes,
  required List<TrabajadorRef> equipo,
  required List<TrabajadorRef> operarios,
  required List<int> semanas,
  required List<HorarioConjunto> horariosConjunto,
  List<NecesidadOperario> necesidades = const [],
  Map<String, String> festivos = const {},
  bool conPortada = false,
}) {
  final lunesMes = semanasDelMes(anio, mes);
  final numeros = semanas.where((n) => n >= 1 && n <= lunesMes.length).toList()
    ..sort();
  final horarioGeneral = _HorariosSemana.desde(horariosConjunto);

  bool enPeriodo(DateTime d) => d.year == anio && d.month == mes;
  bool enSemanas(DateTime d) {
    final dia = _dia(d.toLocal());
    if (!enPeriodo(dia)) return false;
    return numeros.any((n) {
      final lunes = lunesMes[n - 1];
      return !dia.isBefore(lunes) &&
          dia.isBefore(lunes.add(const Duration(days: 7)));
    });
  }

  final ctxs = <_OperarioCtx>[];
  for (final ref in operarios) {
    final indice = equipo.indexWhere((e) => e.id == ref.id);
    final plazas =
        necesidades
            .where(
              (n) => n.activo && n.operarioId != null && n.operarioId == ref.id,
            )
            .toList()
          ..sort((a, b) => a.orden.compareTo(b.orden));
    final tareas =
        tareasMes
            .where((t) => tareaEsDe(t, ref.id) && enSemanas(t.fechaInicio))
            .toList()
          ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    final principal = plazas.isEmpty ? null : plazas.first;
    final puesto = (principal?.perfilNombre ?? '').trim().isNotEmpty
        ? principal!.perfilNombre!.trim()
        : ref.cargo;
    ctxs.add(
      _OperarioCtx(
        info: OperarioImpresion(
          ref: ref,
          puesto: puesto,
          plaza: plazas.map((p) => p.etiqueta.trim()).join(', '),
          color:
              ColoresHoja.avatares[(indice < 0 ? ctxs.length : indice) %
                  ColoresHoja.avatares.length],
          categorias: categoriasDistintas(tareas.map(CategoriaVisual.deTarea)),
          actividades: tareas.length,
          minutos: tareas.fold(0, (s, t) => s + _duracion(t)),
        ),
        plaza: principal,
      ),
    );
  }

  // Una semana sin actividades solo se imprime si se pidió justo esa
  // semana de esa persona (muestra su horario libre); con todo el equipo o
  // el mes entero serían hojas en blanco.
  final incluirVacias = operarios.length == 1 && numeros.length == 1;
  final hojas = <HojaCronograma>[];
  for (final ctx in ctxs) {
    for (final n in numeros) {
      hojas.addAll(
        _hojasSemana(
          ctx: ctx,
          numeroSemana: n,
          lunes: lunesMes[n - 1],
          anio: anio,
          mes: mes,
          conjuntoNombre: conjuntoNombre,
          tareasMes: tareasMes,
          horarioGeneral: horarioGeneral,
          festivos: festivos,
          incluirVacia: incluirVacias,
        ),
      );
    }
  }

  PortadaCronograma? portada;
  if (conPortada && hojas.isNotEmpty) {
    final tareasPeriodo = tareasMes
        .where(
          (t) =>
              enSemanas(t.fechaInicio) &&
              operarios.any((o) => tareaEsDe(t, o.id)),
        )
        .toList();
    String semanaTexto = '';
    if (numeros.length == 1) {
      final lunes = lunesMes[numeros.first - 1];
      final visibles = [
        for (var i = 0; i < 7; i++) lunes.add(Duration(days: i)),
      ].where(enPeriodo).toList();
      semanaTexto =
          'Semana ${numeros.first} · ${rangoDiasTexto(visibles.first, visibles.last)}';
    }
    portada = PortadaCronograma(
      conjuntoNombre: conjuntoNombre,
      periodoTexto: '${nombreMes(mes)} $anio',
      semanaTexto: semanaTexto,
      categorias: _resumenCategorias(tareasPeriodo),
      puestos: _puestos(necesidades, ctxs),
      operarios: [
        for (final c in ctxs)
          if (c.info.actividades > 0) c.info,
      ],
    );
  }

  final mesTxt = '${nombreMes(mes)} $anio';
  final quien = operarios.length == 1 ? operarios.first.nombre : 'Todos';
  final cuando = numeros.length == 1 && lunesMes.length > 1
      ? ' - Semana ${numeros.first}'
      : '';
  return PlanImpresion(
    portada: portada,
    hojas: hojas,
    nombreArchivo: _archivoSeguro('Cronograma $mesTxt$cuando - $quien.pdf'),
  );
}

String _archivoSeguro(String s) => s
    .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _duracion(TareaModel t) =>
    math.max(0, t.fechaFin.difference(t.fechaInicio).inMinutes);

List<CategoriaResumen> _resumenCategorias(List<TareaModel> tareas) {
  final porNombre = <String, List<TareaModel>>{};
  final visuales = <String, CategoriaVisual>{};
  for (final t in tareas) {
    final v = CategoriaVisual.deTarea(t);
    final k = '${v.esEspecial}|${v.nombre}';
    porNombre.putIfAbsent(k, () => []).add(t);
    visuales.putIfAbsent(k, () => v);
  }
  final orden = categoriasDistintas(visuales.values);
  return [
    for (final v in orden)
      CategoriaResumen(
        visual: v,
        actividades: porNombre['${v.esEspecial}|${v.nombre}']!.length,
        minutos: porNombre['${v.esEspecial}|${v.nombre}']!.fold(
          0,
          (s, t) => s + _duracion(t),
        ),
      ),
  ];
}

const _rolesTexto = {
  'TODERO': 'Todero',
  'ASEO': 'Aseo',
  'SALVAVIDAS': 'Salvavidas',
  'PISCINERO': 'Piscinero',
  'JARDINERO': 'Jardinero',
};

String _rolesDe(NecesidadOperario n) => n.roles
    .map((r) => _rolesTexto[r.trim().toUpperCase()] ?? r.trim())
    .where((r) => r.isNotEmpty)
    .join('-');

/// Puestos: las plazas del conjunto agrupadas por perfil. Si no se pudieron
/// leer las plazas, los cargos de las personas del cronograma.
List<PuestoImpresion> _puestos(
  List<NecesidadOperario> necesidades,
  List<_OperarioCtx> ctxs,
) {
  final activas = necesidades.where((n) => n.activo).toList()
    ..sort((a, b) => a.orden.compareTo(b.orden));
  if (activas.isNotEmpty) {
    final grupos = <String, List<NecesidadOperario>>{};
    for (final n in activas) {
      final perfil = (n.perfilNombre ?? '').trim();
      final nombre = perfil.isNotEmpty ? perfil : _rolesDe(n);
      grupos.putIfAbsent(nombre.isEmpty ? 'Plaza' : nombre, () => []).add(n);
    }
    return [
      for (final e in grupos.entries)
        PuestoImpresion(
          nombre: e.key,
          detalle: [
            e.value.map((n) => n.etiqueta.trim()).join(' · '),
            if (e.value.any((n) => n.trabajaFestivos)) 'trabaja festivos',
          ].join(' · '),
        ),
    ];
  }
  final grupos = <String, int>{};
  for (final c in ctxs) {
    final p = c.info.puesto.trim();
    if (p.isEmpty) continue;
    grupos[p] = (grupos[p] ?? 0) + 1;
  }
  return [
    for (final e in grupos.entries)
      PuestoImpresion(
        nombre: e.key,
        detalle: e.value == 1 ? '1 operario' : '${e.value} operarios',
      ),
  ];
}

class _OperarioCtx {
  final OperarioImpresion info;
  final NecesidadOperario? plaza;

  const _OperarioCtx({required this.info, required this.plaza});

  String get id => info.ref.id;
}

/// Horario de un día en minutos desde la medianoche.
class _HorarioDia {
  final int apertura;
  final int cierre;
  final int? descansoInicio;
  final int? descansoFin;

  const _HorarioDia(
    this.apertura,
    this.cierre,
    this.descansoInicio,
    this.descansoFin,
  );

  static _HorarioDia? parse(
    String? apertura,
    String? cierre,
    String? descansoInicio,
    String? descansoFin,
  ) {
    final a = _horaMin(apertura);
    final cRaw = _horaMin(cierre);
    if (a == null || cRaw == null) return null;
    final c = _posterior(a, cRaw);
    if (c <= a) return null;
    final diRaw = _horaMin(descansoInicio);
    final dfRaw = _horaMin(descansoFin);
    final di = diRaw == null ? null : _posterior(a, diRaw);
    final df = di == null || dfRaw == null ? null : _posterior(di, dfRaw);
    final conDescanso = di != null && df != null && df > di;
    return _HorarioDia(a, c, conDescanso ? di : null, conDescanso ? df : null);
  }

  /// Tramos de trabajo: antes y después del descanso.
  List<(int, int)> get tramos => [
    (apertura, descansoInicio ?? cierre),
    if (descansoInicio != null && descansoFin != null) (descansoFin!, cierre),
  ];
}

int? _horaMin(String? raw) {
  final partes = (raw ?? '').trim().split(':');
  if (partes.length < 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}

/// Horas escritas en formato de 12 h ("01:00" como cierre de una jornada de
/// 07:00): se corren 12 h si quedan antes de la referencia.
int _posterior(int referencia, int candidato) {
  var v = candidato;
  while (v <= referencia && v + 12 * 60 <= 24 * 60) {
    v += 12 * 60;
  }
  return v;
}

int? _weekdayDe(String dia) {
  final d = normalizarTexto(dia).replaceAll(RegExp(r'[_\-\s]'), '');
  const dias = {
    'lunes': DateTime.monday,
    'monday': DateTime.monday,
    'martes': DateTime.tuesday,
    'tuesday': DateTime.tuesday,
    'miercoles': DateTime.wednesday,
    'wednesday': DateTime.wednesday,
    'jueves': DateTime.thursday,
    'thursday': DateTime.thursday,
    'viernes': DateTime.friday,
    'friday': DateTime.friday,
    'sabado': DateTime.saturday,
    'saturday': DateTime.saturday,
    'domingo': DateTime.sunday,
    'sunday': DateTime.sunday,
  };
  return dias[d];
}

class _HorariosSemana {
  final Map<int, _HorarioDia> porDia;

  const _HorariosSemana(this.porDia);

  factory _HorariosSemana.desde(List<HorarioConjunto> horarios) {
    final out = <int, _HorarioDia>{};
    for (final h in horarios) {
      final wd = _weekdayDe(h.dia);
      final parsed = _HorarioDia.parse(
        h.horaApertura,
        h.horaCierre,
        h.descansoInicio,
        h.descansoFin,
      );
      if (wd != null && parsed != null) out.putIfAbsent(wd, () => parsed);
    }
    return _HorariosSemana(out);
  }
}

/// Horario con el que trabaja la persona ese día: el de su plaza si tiene
/// horario especial (o el festivo de la plaza), si no el del conjunto. En
/// un festivo solo hay horario si la plaza trabaja festivos.
_HorarioDia? _horarioDe(
  _OperarioCtx ctx,
  DateTime dia,
  bool festivo,
  _HorariosSemana general,
) {
  final plaza = ctx.plaza;
  if (festivo) {
    final f = plaza?.horarioFestivo;
    if (plaza == null || !plaza.trabajaFestivos || f == null) return null;
    return _HorarioDia.parse(
      f.horaApertura,
      f.horaCierre,
      f.descansoInicio,
      f.descansoFin,
    );
  }
  if (plaza != null && plaza.horarioEspecial && plaza.horarios.isNotEmpty) {
    return _HorariosSemana.desde(plaza.horarios).porDia[dia.weekday];
  }
  return general.porDia[dia.weekday];
}

class _TareaPos {
  final TareaModel tarea;
  final int dia;
  final int ini;
  final int fin;

  /// Fin máximo dibujable sin pisar a la siguiente (del layout).
  final int finLibre;
  final int carril;
  final int carriles;
  final int span;

  const _TareaPos({
    required this.tarea,
    required this.dia,
    required this.ini,
    required this.fin,
    required this.finLibre,
    required this.carril,
    required this.carriles,
    required this.span,
  });

  /// Fin con el que se dibuja a la escala [pt] (pt por minuto).
  int finDibujo(double pt) {
    final minimo = ini + (MedidasHoja.altoMinTarjeta / pt).ceil();
    return math.min(finLibre, math.max(fin, minimo));
  }
}

int _minDelDia(DateTime d) {
  final l = d.toLocal();
  return l.hour * 60 + l.minute;
}

List<HojaCronograma> _hojasSemana({
  required _OperarioCtx ctx,
  required int numeroSemana,
  required DateTime lunes,
  required int anio,
  required int mes,
  required String conjuntoNombre,
  required List<TareaModel> tareasMes,
  required _HorariosSemana horarioGeneral,
  required Map<String, String> festivos,
  required bool incluirVacia,
}) {
  bool enPeriodo(DateTime d) => d.year == anio && d.month == mes;
  final domingo = lunes.add(const Duration(days: 6));

  final tareasSemana = tareasMes.where((t) {
    final d = _dia(t.fechaInicio.toLocal());
    return tareaEsDe(t, ctx.id) &&
        enPeriodo(d) &&
        !d.isBefore(lunes) &&
        !d.isAfter(domingo);
  }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
  if (tareasSemana.isEmpty && !incluirVacia) return const [];

  // De lunes a sábado; el domingo solo si ese día tiene actividades
  // (salvavidas y plazas de fin de semana).
  final conDomingo = tareasSemana.any(
    (t) => t.fechaInicio.toLocal().weekday == DateTime.sunday,
  );
  final fechas = [
    for (var i = 0; i < (conDomingo ? 7 : 6); i++)
      DateTime(lunes.year, lunes.month, lunes.day + i),
  ];
  final anchoCol = MedidasHoja.anchoGrilla / fechas.length;

  final horarios = <int, _HorarioDia?>{};
  final dias = <DiaHoja>[];
  for (var i = 0; i < fechas.length; i++) {
    final f = fechas[i];
    final fuera = !enPeriodo(f);
    final festivo = festivos.containsKey(_ymd(f));
    dias.add(
      DiaHoja(
        fecha: f,
        x: anchoCol * i,
        ancho: anchoCol,
        fueraDelMes: fuera,
        mesAnterior: f.isBefore(DateTime(anio, mes, 1)),
        festivo: festivo && !fuera,
        festivoNombre: festivos[_ymd(f)],
      ),
    );
    horarios[i] = fuera ? null : _horarioDe(ctx, f, festivo, horarioGeneral);
  }

  // Posición de cada actividad en su día (carriles como en «Por horas»).
  final posiciones = <_TareaPos>[];
  for (var i = 0; i < fechas.length; i++) {
    final delDia = tareasSemana
        .where((t) => _dia(t.fechaInicio.toLocal()) == fechas[i])
        .toList();
    if (delDia.isEmpty) continue;
    final layout = layoutWeekDayTasks([
      for (final t in delDia)
        WeekLayoutInput(
          inicio: t.fechaInicio.toLocal(),
          fin: t.fechaFin.isAfter(t.fechaInicio)
              ? t.fechaFin.toLocal()
              : t.fechaInicio.toLocal().add(const Duration(minutes: 1)),
        ),
    ], minVisual: const Duration(minutes: 60));
    for (var k = 0; k < delDia.length; k++) {
      final t = delDia[k];
      final ini = _minDelDia(t.fechaInicio);
      final mismoDiaFin = _dia(t.fechaFin.toLocal()) == fechas[i];
      final fin = math.max(
        ini + 1,
        mismoDiaFin ? _minDelDia(t.fechaFin) : 24 * 60,
      );
      final l = layout[k];
      final libre = _dia(l.visualFin) == fechas[i]
          ? _minDelDia(l.visualFin)
          : 24 * 60;
      posiciones.add(
        _TareaPos(
          tarea: t,
          dia: i,
          ini: ini,
          fin: math.min(fin, 24 * 60),
          finLibre: math.min(24 * 60, math.max(libre, fin)),
          carril: l.lane,
          carriles: l.laneCount,
          span: l.laneSpan,
        ),
      );
    }
  }

  // Rango de horas: el horario de los días visibles y las actividades.
  int? desde;
  int? hasta;
  for (final h in horarios.values.whereType<_HorarioDia>()) {
    desde = desde == null ? h.apertura : math.min(desde, h.apertura);
    hasta = hasta == null ? h.cierre : math.max(hasta, h.cierre);
  }
  for (final p in posiciones) {
    desde = desde == null ? p.ini : math.min(desde, p.ini);
    hasta = hasta == null ? p.fin : math.max(hasta, p.fin);
  }
  var a0 = ((desde ?? 7 * 60) ~/ 60) * 60;
  var b0 = math.min(24 * 60, (((hasta ?? 16 * 60) + 59) ~/ 60) * 60);
  if (b0 <= a0) {
    a0 = math.min(a0, 23 * 60);
    b0 = a0 + 60;
  }

  // Escala: la actividad con menos espacio libre antes de la siguiente
  // debe quedar de al menos [MedidasHoja.altoMinTarjeta].
  var espacioMin = double.infinity;
  for (final p in posiciones) {
    final m = p.finLibre - p.ini;
    if (m > 0) espacioMin = math.min(espacioMin, m.toDouble());
  }
  final ptNecesario = espacioMin.isFinite
      ? math.min(
          MedidasHoja.ptPorMinutoMax,
          MedidasHoja.altoMinTarjeta / espacioMin,
        )
      : 0.0;
  final ptBase = MedidasHoja.altoGrilla / (b0 - a0);
  final ventanas = ptBase >= ptNecesario
      ? [(a0, b0)]
      : cortarVentanas(
          a0,
          b0,
          maxMinutos: MedidasHoja.altoGrilla / ptNecesario,
          cruza: (t) =>
              posiciones.any((p) => p.ini < t && t < p.finDibujo(ptNecesario)),
        );

  final visibles = fechas.where(enPeriodo).toList();
  final rangoTexto = visibles.isEmpty
      ? ''
      : rangoDiasTexto(visibles.first, visibles.last);
  final minutosProgramados = tareasSemana.fold(0, (s, t) => s + _duracion(t));

  return [
    for (var k = 0; k < ventanas.length; k++)
      _hoja(
        ctx: ctx,
        conjuntoNombre: conjuntoNombre,
        numeroSemana: numeroSemana,
        rangoTexto: rangoTexto,
        minutosProgramados: minutosProgramados,
        dias: dias,
        horarios: horarios,
        posiciones: posiciones,
        a: ventanas[k].$1,
        b: ventanas[k].$2,
        parte: k + 1,
        totalPartes: ventanas.length,
      ),
  ];
}

/// Parte el rango [a0, b0) (minutos) en tramos de a lo sumo [maxMinutos],
/// cortando en cuartos de hora donde no quede ninguna actividad partida
/// ([cruza] dice si alguna atraviesa ese minuto). Si no hay dónde, corta
/// igual y la actividad sale en las dos hojas.
List<(int, int)> cortarVentanas(
  int a0,
  int b0, {
  required double maxMinutos,
  required bool Function(int minuto) cruza,
}) {
  final maxLen = math.max(60, (maxMinutos / 15).floor() * 15);
  final out = <(int, int)>[];
  var a = a0;
  while (b0 - a > maxLen) {
    final partes = ((b0 - a) / maxLen).ceil();
    final ideal = a + (((b0 - a) / partes) / 15).round() * 15;
    final limite = math.min(a + maxLen, b0 - 15);
    int? corte;
    for (var d = 0; d <= maxLen && corte == null; d += 15) {
      for (final t in {ideal + d, ideal - d}) {
        if (t < a + 30 || t > limite) continue;
        if (!cruza(t)) {
          corte = t;
          break;
        }
      }
    }
    corte ??= math.max(a + 30, math.min(ideal, limite));
    out.add((a, corte));
    a = corte;
  }
  out.add((a, b0));
  return out;
}

HojaCronograma _hoja({
  required _OperarioCtx ctx,
  required String conjuntoNombre,
  required int numeroSemana,
  required String rangoTexto,
  required int minutosProgramados,
  required List<DiaHoja> dias,
  required Map<int, _HorarioDia?> horarios,
  required List<_TareaPos> posiciones,
  required int a,
  required int b,
  required int parte,
  required int totalPartes,
}) {
  final pt = MedidasHoja.altoGrilla / (b - a);
  double y(int minuto) => (minuto.clamp(a, b) - a) * pt;
  const margen = MedidasHoja.margenColumna;

  final lineas = <LineaHora>[
    if (a % 60 != 0) LineaHora(y: 0, texto: minutosTexto(a)),
    for (var m = ((a + 59) ~/ 60) * 60; m <= b; m += 60)
      LineaHora(y: y(m), texto: minutosTexto(m)),
    if (pt * 30 >= 16)
      for (var m = ((a + 29) ~/ 30) * 30; m < b; m += 30)
        if (m % 60 != 0 && m != a) LineaHora(y: y(m)),
  ];

  final franjas = <FranjaHoja>[];
  final tarjetas = <TarjetaHoja>[];
  for (var i = 0; i < dias.length; i++) {
    final dia = dias[i];
    final h = horarios[i];
    final delDia = posiciones.where((p) => p.dia == i).toList();

    if (h != null) {
      if (h.descansoInicio != null && h.descansoFin != null) {
        final di = math.max(a, h.descansoInicio!);
        final df = math.min(b, h.descansoFin!);
        if (df > di) {
          franjas.add(
            FranjaHoja(
              tipo: TipoFranja.descanso,
              x: dia.x,
              y: y(di),
              ancho: dia.ancho,
              alto: y(df) - y(di),
              inicioMin: h.descansoInicio!,
              finMin: h.descansoFin!,
            ),
          );
        }
      }
      for (final (ini, fin) in _libres(h, delDia)) {
        // No arrancar debajo de una tarjeta corta dibujada más alta.
        var desdeDibujo = ini;
        for (final p in delDia) {
          if (p.ini < ini) desdeDibujo = math.max(desdeDibujo, p.finDibujo(pt));
        }
        final yi = y(math.max(desdeDibujo, a));
        final yf = y(math.min(fin, b));
        if (yf - yi < 7) continue;
        franjas.add(
          FranjaHoja(
            tipo: TipoFranja.libre,
            x: dia.x + margen,
            y: yi + 0.5,
            ancho: dia.ancho - margen * 2,
            alto: yf - yi - MedidasHoja.separacionTarjetas,
            inicioMin: ini,
            finMin: fin,
          ),
        );
      }
    }

    for (final p in delDia) {
      final fd = p.finDibujo(pt);
      if (p.ini >= b || fd <= a) continue;
      final anchoCarril = (dia.ancho - margen * 2) / p.carriles;
      final top = y(p.ini);
      final alto = y(fd) - top - MedidasHoja.separacionTarjetas;
      tarjetas.add(
        TarjetaHoja(
          tarea: p.tarea,
          visual: CategoriaVisual.deTarea(p.tarea),
          x: dia.x + margen + anchoCarril * p.carril,
          y: top,
          ancho: anchoCarril * p.span - (p.carriles > 1 ? 2 : 0),
          alto: math.max(6, alto),
          continuaAntes: p.ini < a,
          continuaDespues: p.fin > b,
          personas: trabajadoresDe([p.tarea]).length,
          marca: marcaDe(p.tarea),
        ),
      );
    }
  }

  return HojaCronograma(
    conjuntoNombre: conjuntoNombre,
    operario: ctx.info,
    semana: numeroSemana,
    rangoTexto: rangoTexto,
    minutosProgramados: minutosProgramados,
    dias: dias,
    lineas: lineas,
    franjas: franjas,
    tarjetas: tarjetas,
    parte: parte,
    totalPartes: totalPartes,
    ventanaInicioMin: a,
    ventanaFinMin: b,
  );
}

/// Espacios del horario sin actividades (para actividades especiales), de
/// al menos 5 minutos.
List<(int, int)> _libres(_HorarioDia h, List<_TareaPos> tareas) {
  final out = <(int, int)>[];
  final orden = [...tareas]..sort((x, y) => x.ini.compareTo(y.ini));
  for (final (inicio, fin) in h.tramos) {
    if (fin <= inicio) continue;
    var cursor = inicio;
    for (final t in orden) {
      final ti = math.max(t.ini, inicio);
      final tf = math.min(t.fin, fin);
      if (tf <= ti) continue;
      if (ti > cursor) out.add((cursor, ti));
      cursor = math.max(cursor, tf);
    }
    if (cursor < fin) out.add((cursor, fin));
  }
  return out.where((r) => r.$2 - r.$1 >= 5).toList();
}
