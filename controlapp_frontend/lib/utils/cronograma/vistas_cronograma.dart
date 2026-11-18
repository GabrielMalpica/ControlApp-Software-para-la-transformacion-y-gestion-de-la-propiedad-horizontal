// Lógica pura de las vistas Mensual, Semanal y Diaria del cronograma
// (borrador y definitivo). Sin widgets: la usan las vistas de
// `widgets/cronograma/vistas/` y se prueba en `test/vistas_cronograma_test.dart`.

import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';

// ─────────────────────────── Operarios ───────────────────────────

/// Un operario tal como se pinta en las vistas: nombre corto, iniciales y un
/// color fijo (índice de la paleta) para reconocerlo en todas las vistas.
class OperarioVista {
  final String id;
  final String nombre;
  final String nombreCorto;
  final String iniciales;
  final int indiceColor;

  const OperarioVista({
    required this.id,
    required this.nombre,
    required this.nombreCorto,
    required this.iniciales,
    required this.indiceColor,
  });
}

const _conectores = {'de', 'del', 'la', 'las', 'los', 'y', 'da', 'van', 'von'};

String _capitalizar(String palabra) {
  if (palabra.isEmpty) return palabra;
  final minus = palabra.toLowerCase();
  return minus[0].toUpperCase() + minus.substring(1);
}

List<String> _palabrasSignificativas(String nombre) {
  final palabras = nombre
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  final utiles = palabras
      .where((p) => !_conectores.contains(p.toLowerCase()))
      .toList();
  return utiles.isEmpty ? palabras : utiles;
}

/// "YEIMI MARTINEZ CARRILLO" → "Yeimi Martinez"; "LUIS ALBERTO TARACHE
/// IBICA" → "Luis Tarache" (con 4 palabras o más, la tercera es el primer
/// apellido).
String nombreCortoOperario(String nombre) {
  final p = _palabrasSignificativas(nombre);
  if (p.isEmpty) return 'Sin nombre';
  if (p.length == 1) return _capitalizar(p[0]);
  final apellido = p.length >= 4 ? p[2] : p[1];
  return '${_capitalizar(p[0])} ${_capitalizar(apellido)}';
}

/// Iniciales del nombre corto: "Yeimi Martinez" → "YM".
String inicialesOperario(String nombre) {
  final corto = nombreCortoOperario(nombre).split(' ');
  final buf = StringBuffer();
  for (final p in corto.take(2)) {
    if (p.isNotEmpty) buf.write(p[0].toUpperCase());
  }
  final s = buf.toString();
  return s.isEmpty ? '?' : s;
}

/// Operarios de [tareas] ordenados por carga (más tareas primero) y con un
/// color fijo cada uno. Si dos tienen las mismas iniciales, se les agrega la
/// segunda letra del apellido ("YMa", "YMo").
List<OperarioVista> operariosDeTareas(Iterable<TareaModel> tareas) {
  final nombres = <String, String>{};
  final conteo = <String, int>{};
  for (final t in tareas) {
    for (var i = 0; i < t.operariosNombres.length; i++) {
      final nombre = t.operariosNombres[i].trim();
      if (nombre.isEmpty) continue;
      final id =
          i < t.operariosIds.length && t.operariosIds[i].trim().isNotEmpty
          ? t.operariosIds[i].trim()
          : 'nombre:$nombre';
      nombres.putIfAbsent(id, () => nombre);
      conteo[id] = (conteo[id] ?? 0) + 1;
    }
  }
  final ids = nombres.keys.toList()
    ..sort((a, b) {
      final c = (conteo[b] ?? 0).compareTo(conteo[a] ?? 0);
      if (c != 0) return c;
      return nombres[a]!.compareTo(nombres[b]!);
    });

  final iniciales = <String, String>{
    for (final id in ids) id: inicialesOperario(nombres[id]!),
  };
  final repetidas = <String, int>{};
  for (final v in iniciales.values) {
    repetidas[v] = (repetidas[v] ?? 0) + 1;
  }
  for (final id in ids) {
    final ini = iniciales[id]!;
    if ((repetidas[ini] ?? 0) < 2) continue;
    final corto = nombreCortoOperario(nombres[id]!).split(' ');
    if (corto.length >= 2 && corto[1].length >= 2) {
      iniciales[id] = '$ini${corto[1][1].toLowerCase()}';
    }
  }

  return [
    for (var i = 0; i < ids.length; i++)
      OperarioVista(
        id: ids[i],
        nombre: nombres[ids[i]]!,
        nombreCorto: nombreCortoOperario(nombres[ids[i]]!),
        iniciales: iniciales[ids[i]]!,
        indiceColor: i,
      ),
  ];
}

/// [base] más los operarios de [tareas] que no estén (p. ej. de un mes
/// vecino), con colores a continuación. Devuelve [base] tal cual si no falta
/// ninguno.
List<OperarioVista> completarOperarios(
  List<OperarioVista> base,
  Iterable<TareaModel> tareas,
) {
  final indice = IndiceOperarios(base);
  final faltan = tareas.where((t) {
    final ops = indice.de(t);
    return ops.length <
        t.operariosNombres.where((n) => n.trim().isNotEmpty).length;
  }).toList();
  if (faltan.isEmpty) return base;
  final conocidos = {for (final o in base) o.id};
  final nuevos = operariosDeTareas(
    faltan,
  ).where((o) => !conocidos.contains(o.id)).toList();
  if (nuevos.isEmpty) return base;
  return [
    ...base,
    for (var i = 0; i < nuevos.length; i++)
      OperarioVista(
        id: nuevos[i].id,
        nombre: nuevos[i].nombre,
        nombreCorto: nuevos[i].nombreCorto,
        iniciales: nuevos[i].iniciales,
        indiceColor: base.length + i,
      ),
  ];
}

/// Busca rápido el operario de una tarea por id (o por nombre si no trae id).
class IndiceOperarios {
  final List<OperarioVista> lista;
  final Map<String, OperarioVista> _porId;
  final Map<String, OperarioVista> _porNombre;

  IndiceOperarios(this.lista)
    : _porId = {for (final o in lista) o.id: o},
      _porNombre = {for (final o in lista) o.nombre.trim().toLowerCase(): o};

  /// Operarios de [t] en el orden en que vienen en la tarea.
  List<OperarioVista> de(TareaModel t) {
    final out = <OperarioVista>[];
    for (var i = 0; i < t.operariosNombres.length; i++) {
      final id = i < t.operariosIds.length ? t.operariosIds[i].trim() : '';
      final nombre = t.operariosNombres[i].trim().toLowerCase();
      final o =
          _porId[id] ??
          _porId['nombre:${t.operariosNombres[i].trim()}'] ??
          _porNombre[nombre];
      if (o != null && !out.contains(o)) out.add(o);
    }
    return out;
  }

  List<OperarioVista> deExcluida(PreventivaExcluidaBorradorModel e) {
    final out = <OperarioVista>[];
    for (var i = 0; i < e.operariosNombres.length; i++) {
      final id = i < e.operariosIds.length ? e.operariosIds[i].trim() : '';
      final o =
          _porId[id] ?? _porNombre[e.operariosNombres[i].trim().toLowerCase()];
      if (o != null && !out.contains(o)) out.add(o);
    }
    return out;
  }

  bool tieneA(TareaModel t, OperarioVista o) => de(t).contains(o);
}

// ─────────────────────────── Tareas ───────────────────────────

/// Cómo se pinta una tarea según su estado: abierta (color del operario),
/// ejecutada (verde) o no ejecutada (rojo).
enum TonoTarea { abierta, ejecutada, noEjecutada }

TonoTarea tonoDeTarea(TareaModel t) {
  switch ((t.estado ?? '').trim().toUpperCase()) {
    case 'COMPLETADA':
    case 'APROBADA':
    case 'PENDIENTE_APROBACION':
      return TonoTarea.ejecutada;
    case 'NO_COMPLETADA':
    case 'RECHAZADA':
    case 'PENDIENTE_REPROGRAMACION':
      return TonoTarea.noEjecutada;
    default:
      return TonoTarea.abierta;
  }
}

bool esEspecial(TareaModel t) =>
    (t.tipo ?? '').trim().toUpperCase() == 'CORRECTIVA';

/// Tarea abierta de un día anterior a [hoy]: "fecha pasada sin cerrar".
bool estaVencida(TareaModel t, DateTime hoy) {
  if (tonoDeTarea(t) != TonoTarea.abierta) return false;
  final d = soloFecha(t.fechaInicio.toLocal());
  return d.isBefore(soloFecha(hoy));
}

DateTime soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

bool mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Minutos que ocupa la tarea (duración guardada o, si falta, fin - inicio).
int minutosDe(TareaModel t) {
  if (t.duracionMinutos > 0) return t.duracionMinutos;
  final m = t.fechaFin.difference(t.fechaInicio).inMinutes;
  return m > 0 ? m : 0;
}

/// Último tramo de "Zonas internas > Pisos, puertas y mobiliario".
String elementoCorto(String? elemento) {
  final e = (elemento ?? '').trim();
  if (e.isEmpty) return '';
  final partes = e.split('>');
  return partes.last.trim();
}

String ubicacionDe(TareaModel t) {
  final u = (t.ubicacionNombre ?? '').trim();
  return u.isEmpty ? 'Ubicación ${t.ubicacionId}' : u;
}

/// "Kiosko · Baños"
String lugarDe(TareaModel t) {
  final e = elementoCorto(t.elementoNombre);
  return e.isEmpty ? ubicacionDe(t) : '${ubicacionDe(t)} · $e';
}

/// "7h 30m", "7h", "45m", "—" si es 0.
String formatoHorasCorto(int minutos) {
  if (minutos <= 0) return '0m';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String hhmmMin(int minutos) {
  final h = (minutos ~/ 60) % 24;
  final m = minutos % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

int minutoDelDia(DateTime d) => d.hour * 60 + d.minute;

/// Calendario del período: domingos y festivos.
class CalendarioVista {
  /// Festivos por 'yyyy-mm-dd' con su nombre (puede ser vacío).
  final Map<String, String> festivos;

  const CalendarioVista({this.festivos = const {}});

  bool esFestivo(DateTime d) => festivos.containsKey(ymd(d));
  bool esDomingo(DateTime d) => d.weekday == DateTime.sunday;

  /// Ni domingo ni festivo.
  bool esHabil(DateTime d) => !esDomingo(d) && !esFestivo(d);

  String? nombreFestivo(DateTime d) {
    final n = festivos[ymd(d)];
    if (n == null) return null;
    return n.trim().isEmpty ? 'Festivo' : n.trim();
  }
}

const _diasCortos = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _diasLargos = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];
const _mesesCortos = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String diaCorto(DateTime d) => _diasCortos[d.weekday - 1];
String diaLargo(DateTime d) => _diasLargos[d.weekday - 1];
String mesCorto(int mes) => _mesesCortos[mes - 1];

/// "L", "M", "M", "J", "V", "S", "D"
String letraDia(DateTime d) =>
    const ['L', 'M', 'M', 'J', 'V', 'S', 'D'][d.weekday - 1];

/// "lun 2 y lun 16", "lun 2, lun 9 y lun 16"
String unirConY(List<String> partes) {
  if (partes.isEmpty) return '';
  if (partes.length == 1) return partes.first;
  return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
}

String decimalCorto(double v) {
  final r = (v * 10).round() / 10;
  if (r == r.roundToDouble()) return r.toStringAsFixed(0);
  return r.toStringAsFixed(1).replaceAll('.', ',');
}

/// Tareas sin repetir (por id).
List<TareaModel> sinRepetir(Iterable<TareaModel> tareas) {
  final vistos = <int>{};
  return [
    for (final t in tareas)
      if (vistos.add(t.id)) t,
  ];
}

// ─────────────────────────── Mensual ───────────────────────────

enum AgrupacionMensual { ubicacion, operario }

class FilaMensual {
  final String clave;
  final String titulo;
  final String subtitulo;
  final bool especial;

  /// Tareas por día del mes (1..31).
  final Map<int, List<TareaModel>> porDia;

  /// Excluida que representa la fila (filas de seguimiento de excluidas).
  final PreventivaExcluidaBorradorModel? excluida;

  const FilaMensual({
    required this.clave,
    required this.titulo,
    required this.subtitulo,
    required this.porDia,
    this.especial = false,
    this.excluida,
  });

  bool get esExcluida => excluida != null;

  /// Días del mes en que la fila tiene algo.
  int get dias => excluida != null ? 1 : porDia.length;
}

class GrupoMensual {
  final String clave;
  final String titulo;

  /// Solo al agrupar por operario.
  final OperarioVista? operario;
  final List<FilaMensual> filas;

  /// Días distintos con actividad en el grupo.
  final int diasConActividad;
  final int tareas;
  final bool esExcluidas;

  const GrupoMensual({
    required this.clave,
    required this.titulo,
    required this.filas,
    required this.diasConActividad,
    required this.tareas,
    this.operario,
    this.esExcluidas = false,
  });
}

class MatrizMensual {
  final List<GrupoMensual> grupos;

  /// Tareas distintas por día del mes.
  final Map<int, int> totalPorDia;
  final int total;

  const MatrizMensual({
    required this.grupos,
    required this.totalPorDia,
    required this.total,
  });
}

String _claveActividad(TareaModel t) =>
    '${ubicacionDe(t).toLowerCase()}|${elementoCorto(t.elementoNombre).toLowerCase()}|'
    '${t.descripcion.trim().toLowerCase()}|${esEspecial(t) ? 'E' : 'P'}';

MatrizMensual construirMatrizMensual({
  required List<TareaModel> tareas,
  required IndiceOperarios operarios,
  required int anio,
  required int mes,
  required AgrupacionMensual agrupacion,
  List<PreventivaExcluidaBorradorModel> excluidas = const [],
}) {
  final delMes = sinRepetir(tareas).where((t) {
    final d = t.fechaInicio.toLocal();
    return d.year == anio && d.month == mes;
  }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

  final totalPorDia = <int, int>{};
  for (final t in delMes) {
    final dia = t.fechaInicio.toLocal().day;
    totalPorDia[dia] = (totalPorDia[dia] ?? 0) + 1;
  }

  FilaMensual filaDe(String clave, List<TareaModel> lista, {String? titulo}) {
    final t0 = lista.first;
    final porDia = <int, List<TareaModel>>{};
    for (final t in lista) {
      porDia.putIfAbsent(t.fechaInicio.toLocal().day, () => []).add(t);
    }
    final elemento = elementoCorto(t0.elementoNombre);
    return FilaMensual(
      clave: clave,
      titulo: titulo ?? (elemento.isEmpty ? ubicacionDe(t0) : elemento),
      subtitulo: t0.descripcion.trim(),
      especial: esEspecial(t0),
      porDia: porDia,
    );
  }

  int ordenFilas(FilaMensual a, FilaMensual b) {
    final c = b.dias.compareTo(a.dias);
    if (c != 0) return c;
    return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
  }

  final grupos = <GrupoMensual>[];
  if (agrupacion == AgrupacionMensual.ubicacion) {
    final porUbicacion = <String, List<TareaModel>>{};
    final idUbicacion = <String, int>{};
    for (final t in delMes) {
      final u = ubicacionDe(t);
      porUbicacion.putIfAbsent(u, () => []).add(t);
      final previo = idUbicacion[u];
      if (previo == null || t.ubicacionId < previo) {
        idUbicacion[u] = t.ubicacionId;
      }
    }
    final nombres = porUbicacion.keys.toList()
      ..sort((a, b) {
        final c = idUbicacion[a]!.compareTo(idUbicacion[b]!);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final u in nombres) {
      final lista = porUbicacion[u]!;
      final porActividad = <String, List<TareaModel>>{};
      for (final t in lista) {
        porActividad.putIfAbsent(_claveActividad(t), () => []).add(t);
      }
      final filas = [
        for (final e in porActividad.entries) filaDe(e.key, e.value),
      ]..sort(ordenFilas);
      grupos.add(
        GrupoMensual(
          clave: 'u:$u',
          titulo: u,
          filas: filas,
          diasConActividad: lista
              .map((t) => t.fechaInicio.toLocal().day)
              .toSet()
              .length,
          tareas: lista.length,
        ),
      );
    }
  } else {
    for (final o in operarios.lista) {
      final lista = delMes.where((t) => operarios.tieneA(t, o)).toList();
      if (lista.isEmpty) continue;
      final porActividad = <String, List<TareaModel>>{};
      for (final t in lista) {
        porActividad.putIfAbsent(_claveActividad(t), () => []).add(t);
      }
      final filas = [
        for (final e in porActividad.entries)
          filaDe('${o.id}|${e.key}', e.value, titulo: lugarDe(e.value.first)),
      ]..sort(ordenFilas);
      grupos.add(
        GrupoMensual(
          clave: 'o:${o.id}',
          titulo: o.nombreCorto,
          operario: o,
          filas: filas,
          diasConActividad: lista
              .map((t) => t.fechaInicio.toLocal().day)
              .toSet()
              .length,
          tareas: lista.length,
        ),
      );
    }
    final sinOperario = delMes.where((t) => operarios.de(t).isEmpty).toList();
    if (sinOperario.isNotEmpty) {
      final porActividad = <String, List<TareaModel>>{};
      for (final t in sinOperario) {
        porActividad.putIfAbsent(_claveActividad(t), () => []).add(t);
      }
      grupos.add(
        GrupoMensual(
          clave: 'o:-',
          titulo: 'Sin operario asignado',
          filas: [
            for (final e in porActividad.entries)
              filaDe('-|${e.key}', e.value, titulo: lugarDe(e.value.first)),
          ]..sort(ordenFilas),
          diasConActividad: sinOperario
              .map((t) => t.fechaInicio.toLocal().day)
              .toSet()
              .length,
          tareas: sinOperario.length,
        ),
      );
    }
  }

  final excluidasMes = excluidas.where((e) {
    final d = e.fechaObjetivo;
    return d.year == anio && d.month == mes;
  }).toList()..sort((a, b) => a.fechaObjetivo.compareTo(b.fechaObjetivo));
  if (excluidasMes.isNotEmpty) {
    grupos.add(
      GrupoMensual(
        clave: 'excluidas',
        titulo: 'Excluidas',
        esExcluidas: true,
        filas: [
          for (final e in excluidasMes)
            FilaMensual(
              clave: 'ex:${e.id}',
              titulo: () {
                final u = (e.ubicacionNombre ?? '').trim();
                final el = elementoCorto(e.elementoNombre);
                final lugar = u.isEmpty ? 'Ubicación ${e.ubicacionId}' : u;
                return el.isEmpty ? lugar : '$lugar · $el';
              }(),
              subtitulo: e.descripcion.trim(),
              porDia: const {},
              excluida: e,
            ),
        ],
        diasConActividad: excluidasMes
            .map((e) => e.fechaObjetivo.day)
            .toSet()
            .length,
        tareas: excluidasMes.length,
      ),
    );
  }

  return MatrizMensual(
    grupos: grupos,
    totalPorDia: totalPorDia,
    total: delMes.length,
  );
}

class CargaOperarioMes {
  final OperarioVista operario;
  final int tareas;
  final int dias;
  final int minutos;

  const CargaOperarioMes({
    required this.operario,
    required this.tareas,
    required this.dias,
    required this.minutos,
  });

  double get porDia => dias == 0 ? 0 : tareas / dias;
}

class ResumenMensual {
  final int tareas;
  final int actividades;
  final int ubicaciones;

  /// Abiertas de días anteriores a hoy.
  final int vencidas;

  /// Último día del mes ya pasado (0 si el mes aún no empieza).
  final int ultimoDiaPasado;

  final int diasDomingoFestivo;
  final double promedioDomingoFestivo;

  /// Operarios que tienen tareas en domingos o festivos.
  final List<OperarioVista> operariosDomingoFestivo;

  final int minHabil;
  final int maxHabil;
  final List<DateTime> festivos;
  final List<CargaOperarioMes> cargas;

  const ResumenMensual({
    required this.tareas,
    required this.actividades,
    required this.ubicaciones,
    required this.vencidas,
    required this.ultimoDiaPasado,
    required this.diasDomingoFestivo,
    required this.promedioDomingoFestivo,
    required this.operariosDomingoFestivo,
    required this.minHabil,
    required this.maxHabil,
    required this.festivos,
    required this.cargas,
  });
}

ResumenMensual resumirMes({
  required List<TareaModel> tareas,
  required IndiceOperarios operarios,
  required int anio,
  required int mes,
  required CalendarioVista calendario,
  required DateTime hoy,
}) {
  final delMes = sinRepetir(tareas).where((t) {
    final d = t.fechaInicio.toLocal();
    return d.year == anio && d.month == mes;
  }).toList();
  final diasMes = DateTime(anio, mes + 1, 0).day;

  final porDia = <int, List<TareaModel>>{};
  for (final t in delMes) {
    porDia.putIfAbsent(t.fechaInicio.toLocal().day, () => []).add(t);
  }

  final hoyF = soloFecha(hoy);
  final inicioMes = DateTime(anio, mes, 1);
  final finMes = DateTime(anio, mes, diasMes);
  final ultimoPasado = hoyF.isAfter(finMes)
      ? diasMes
      : hoyF.isAfter(inicioMes)
      ? hoyF.day - 1
      : 0;

  var diasDf = 0;
  var tareasDf = 0;
  final opsDf = <OperarioVista>{};
  int? minH;
  int? maxH;
  final festivos = <DateTime>[];
  for (var d = 1; d <= diasMes; d++) {
    final fecha = DateTime(anio, mes, d);
    final lista = porDia[d] ?? const <TareaModel>[];
    if (calendario.esFestivo(fecha)) festivos.add(fecha);
    if (!calendario.esHabil(fecha)) {
      diasDf++;
      tareasDf += lista.length;
      for (final t in lista) {
        opsDf.addAll(operarios.de(t));
      }
    } else {
      minH = minH == null || lista.length < minH ? lista.length : minH;
      maxH = maxH == null || lista.length > maxH ? lista.length : maxH;
    }
  }

  final cargas = <CargaOperarioMes>[];
  for (final o in operarios.lista) {
    final suyas = delMes.where((t) => operarios.tieneA(t, o)).toList();
    if (suyas.isEmpty) continue;
    cargas.add(
      CargaOperarioMes(
        operario: o,
        tareas: suyas.length,
        dias: suyas.map((t) => t.fechaInicio.toLocal().day).toSet().length,
        minutos: suyas.fold(0, (s, t) => s + minutosDe(t)),
      ),
    );
  }

  return ResumenMensual(
    tareas: delMes.length,
    actividades: delMes.map(_claveActividad).toSet().length,
    ubicaciones: delMes.map(ubicacionDe).toSet().length,
    vencidas: delMes.where((t) => estaVencida(t, hoy)).length,
    ultimoDiaPasado: ultimoPasado,
    diasDomingoFestivo: diasDf,
    promedioDomingoFestivo: diasDf == 0 ? 0 : tareasDf / diasDf,
    operariosDomingoFestivo: operarios.lista.where(opsDf.contains).toList(),
    minHabil: minH ?? 0,
    maxHabil: maxH ?? 0,
    festivos: festivos,
    cargas: cargas,
  );
}

// ─────────────────────────── Semanal ───────────────────────────

class CeldaSemanal {
  final DateTime dia;
  final List<TareaModel> tareas;
  final int minutos;

  const CeldaSemanal({
    required this.dia,
    required this.tareas,
    required this.minutos,
  });
}

class FilaSemanal {
  final OperarioVista? operario;
  final List<CeldaSemanal> dias;

  const FilaSemanal({required this.operario, required this.dias});

  int get tareas => dias.fold(0, (s, c) => s + c.tareas.length);
  int get minutos => dias.fold(0, (s, c) => s + c.minutos);
}

class ResumenSemanal {
  final DateTime inicio;
  final List<FilaSemanal> filas;
  final int tareas;
  final int minutos;

  /// Día con más tareas distintas (null si la semana está vacía).
  final DateTime? diaMasCargado;
  final int tareasDiaMasCargado;

  /// Menor carga de un operario en un día hábil en que sí trabaja.
  final CeldaSemanal? cargaMasBaja;
  final OperarioVista? operarioCargaMasBaja;

  /// Mayor carga de un operario en un día (100 % de las barras).
  final int maxMinutosCelda;

  const ResumenSemanal({
    required this.inicio,
    required this.filas,
    required this.tareas,
    required this.minutos,
    required this.diaMasCargado,
    required this.tareasDiaMasCargado,
    required this.cargaMasBaja,
    required this.operarioCargaMasBaja,
    required this.maxMinutosCelda,
  });

  List<DateTime> get dias => [
    for (var i = 0; i < 7; i++)
      DateTime(inicio.year, inicio.month, inicio.day + i),
  ];
}

DateTime lunesDe(DateTime d) {
  final f = soloFecha(d);
  return DateTime(f.year, f.month, f.day - (f.weekday - DateTime.monday));
}

ResumenSemanal resumirSemana({
  required DateTime inicioSemana,
  required List<TareaModel> tareas,
  required IndiceOperarios operarios,
  required CalendarioVista calendario,
}) {
  final inicio = lunesDe(inicioSemana);
  final dias = [
    for (var i = 0; i < 7; i++)
      DateTime(inicio.year, inicio.month, inicio.day + i),
  ];
  final fin = DateTime(inicio.year, inicio.month, inicio.day + 7);
  final semana = sinRepetir(tareas).where((t) {
    final d = t.fechaInicio.toLocal();
    return !d.isBefore(inicio) && d.isBefore(fin);
  }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

  FilaSemanal filaDe(OperarioVista? o, List<TareaModel> suyas) {
    return FilaSemanal(
      operario: o,
      dias: [
        for (final d in dias)
          () {
            final lista = suyas
                .where((t) => mismoDia(t.fechaInicio.toLocal(), d))
                .toList();
            return CeldaSemanal(
              dia: d,
              tareas: lista,
              minutos: lista.fold(0, (s, t) => s + minutosDe(t)),
            );
          }(),
      ],
    );
  }

  final filas = <FilaSemanal>[
    for (final o in operarios.lista)
      filaDe(o, semana.where((t) => operarios.tieneA(t, o)).toList()),
  ];
  final sinOperario = semana.where((t) => operarios.de(t).isEmpty).toList();
  if (sinOperario.isNotEmpty) filas.add(filaDe(null, sinOperario));

  DateTime? diaMax;
  var tareasMax = 0;
  for (final d in dias) {
    final n = semana.where((t) => mismoDia(t.fechaInicio.toLocal(), d)).length;
    if (n > tareasMax) {
      tareasMax = n;
      diaMax = d;
    }
  }

  CeldaSemanal? baja;
  OperarioVista? opBaja;
  var maxCelda = 0;
  for (final f in filas) {
    for (final c in f.dias) {
      if (c.minutos > maxCelda) maxCelda = c.minutos;
      if (f.operario == null || c.tareas.isEmpty) continue;
      if (!calendario.esHabil(c.dia)) continue;
      if (baja == null || c.minutos < baja.minutos) {
        baja = c;
        opBaja = f.operario;
      }
    }
  }

  return ResumenSemanal(
    inicio: inicio,
    filas: filas,
    tareas: semana.length,
    minutos: filas.fold(0, (s, f) => s + f.minutos),
    diaMasCargado: diaMax,
    tareasDiaMasCargado: tareasMax,
    cargaMasBaja: baja,
    operarioCargaMasBaja: opBaja,
    maxMinutosCelda: maxCelda,
  );
}

// ─────────────────────────── Diaria ───────────────────────────

class BloqueDiario {
  final TareaModel tarea;
  final int inicio;
  final int fin;
  final int carril;
  final int carriles;

  const BloqueDiario({
    required this.tarea,
    required this.inicio,
    required this.fin,
    required this.carril,
    required this.carriles,
  });
}

class ColumnaDiaria {
  final OperarioVista? operario;
  final List<BloqueDiario> bloques;

  const ColumnaDiaria({required this.operario, required this.bloques});

  int get tareas => bloques.length;
  int get minutos => bloques.fold(0, (s, b) => s + minutosDe(b.tarea));
}

class ResumenDiario {
  final DateTime dia;
  final List<ColumnaDiaria> columnas;
  final int tareas;
  final int ejecutadas;
  final int noEjecutadas;
  final int ubicaciones;

  /// Rango visible de la cuadrícula en minutos del día (horas completas).
  final int desde;
  final int hasta;

  const ResumenDiario({
    required this.dia,
    required this.columnas,
    required this.tareas,
    required this.ejecutadas,
    required this.noEjecutadas,
    required this.ubicaciones,
    required this.desde,
    required this.hasta,
  });

  int get cerradas => ejecutadas + noEjecutadas;
  double get avance => tareas == 0 ? 0 : cerradas / tareas;
}

/// Reparte en carriles las tareas que se cruzan (de una misma persona).
List<BloqueDiario> ubicarEnCarriles(List<TareaModel> tareas) {
  final ordenadas = [...tareas]
    ..sort((a, b) {
      final c = a.fechaInicio.compareTo(b.fechaInicio);
      return c != 0 ? c : b.fechaFin.compareTo(a.fechaFin);
    });
  final salida = <BloqueDiario>[];
  var grupo = <({TareaModel t, int ini, int fin, int carril})>[];
  var finGrupo = -1;
  final finCarril = <int>[];

  void cerrarGrupo() {
    final carriles = finCarril.isEmpty ? 1 : finCarril.length;
    for (final g in grupo) {
      salida.add(
        BloqueDiario(
          tarea: g.t,
          inicio: g.ini,
          fin: g.fin,
          carril: g.carril,
          carriles: carriles,
        ),
      );
    }
    grupo = [];
    finCarril.clear();
  }

  for (final t in ordenadas) {
    final ini = minutoDelDia(t.fechaInicio.toLocal());
    var fin = ini + minutosDe(t);
    final finReal = t.fechaFin.toLocal();
    if (mismoDia(finReal, t.fechaInicio.toLocal())) {
      final f = minutoDelDia(finReal);
      if (f > ini) fin = f;
    }
    if (fin <= ini) fin = ini + 15;
    if (grupo.isNotEmpty && ini >= finGrupo) cerrarGrupo();
    var carril = finCarril.indexWhere((f) => f <= ini);
    if (carril == -1) {
      carril = finCarril.length;
      finCarril.add(fin);
    } else {
      finCarril[carril] = fin;
    }
    grupo.add((t: t, ini: ini, fin: fin, carril: carril));
    if (fin > finGrupo) finGrupo = fin;
  }
  cerrarGrupo();
  return salida;
}

ResumenDiario resumirDia({
  required DateTime dia,
  required List<TareaModel> tareas,
  required IndiceOperarios operarios,
  int horaInicioJornada = 7,
  int horaFinJornada = 16,
}) {
  final delDia = sinRepetir(
    tareas,
  ).where((t) => mismoDia(t.fechaInicio.toLocal(), dia)).toList();

  final columnas = <ColumnaDiaria>[
    for (final o in operarios.lista)
      ColumnaDiaria(
        operario: o,
        bloques: ubicarEnCarriles(
          delDia.where((t) => operarios.tieneA(t, o)).toList(),
        ),
      ),
  ];
  final sinOperario = delDia.where((t) => operarios.de(t).isEmpty).toList();
  if (sinOperario.isNotEmpty) {
    columnas.add(
      ColumnaDiaria(operario: null, bloques: ubicarEnCarriles(sinOperario)),
    );
  }

  var desde = horaInicioJornada * 60;
  var hasta = horaFinJornada * 60;
  for (final c in columnas) {
    for (final b in c.bloques) {
      if (b.inicio < desde) desde = b.inicio;
      if (b.fin > hasta) hasta = b.fin;
    }
  }
  desde = (desde ~/ 60) * 60;
  hasta = ((hasta + 59) ~/ 60) * 60;
  if (hasta > 24 * 60) hasta = 24 * 60;
  if (hasta <= desde) hasta = desde + 60;

  return ResumenDiario(
    dia: soloFecha(dia),
    columnas: columnas,
    tareas: delDia.length,
    ejecutadas: delDia
        .where((t) => tonoDeTarea(t) == TonoTarea.ejecutada)
        .length,
    noEjecutadas: delDia
        .where((t) => tonoDeTarea(t) == TonoTarea.noEjecutada)
        .length,
    ubicaciones: delDia.map(ubicacionDe).toSet().length,
    desde: desde,
    hasta: hasta,
  );
}
