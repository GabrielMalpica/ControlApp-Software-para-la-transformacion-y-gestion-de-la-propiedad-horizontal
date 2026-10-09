import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';

/// Persona que aparece en el cronograma (sale de los operarios de las tareas).
class TrabajadorRef {
  final String id;
  final String nombre;
  final String cargo;

  const TrabajadorRef({
    required this.id,
    required this.nombre,
    this.cargo = '',
  });

  String get iniciales {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes[0].substring(0, 1) + partes[1].substring(0, 1))
        .toUpperCase();
  }

  String get primerNombre => nombre.trim().split(RegExp(r'\s+')).first;
}

/// Trabajadores de [tareas], sin repetir, ordenados por nombre. Si la tarea
/// no trae ids, se usa el nombre como identificador.
List<TrabajadorRef> trabajadoresDe(Iterable<TareaModel> tareas) {
  final porId = <String, TrabajadorRef>{};
  for (final t in tareas) {
    for (var i = 0; i < t.operariosNombres.length; i++) {
      final nombre = t.operariosNombres[i].trim();
      if (nombre.isEmpty) continue;
      final id = i < t.operariosIds.length ? t.operariosIds[i].trim() : nombre;
      final cargo = i < t.operariosCargos.length
          ? t.operariosCargos[i].trim()
          : '';
      porId.putIfAbsent(
        id.isEmpty ? nombre : id,
        () => TrabajadorRef(
          id: id.isEmpty ? nombre : id,
          nombre: nombre,
          cargo: cargo,
        ),
      );
    }
  }
  final lista = porId.values.toList()
    ..sort(
      (a, b) => normalizarTexto(a.nombre).compareTo(normalizarTexto(b.nombre)),
    );
  return lista;
}

/// Ids (o nombres, si faltan ids) de los trabajadores de [t].
Set<String> idsTrabajadores(TareaModel t) {
  final out = <String>{};
  for (var i = 0; i < t.operariosNombres.length; i++) {
    final nombre = t.operariosNombres[i].trim();
    final id = i < t.operariosIds.length ? t.operariosIds[i].trim() : '';
    if (id.isNotEmpty) {
      out.add(id);
    } else if (nombre.isNotEmpty) {
      out.add(nombre);
    }
  }
  if (out.isEmpty) out.addAll(t.operariosIds.map((e) => e.trim()));
  return out;
}

bool tareaEsDe(TareaModel t, String trabajadorId) =>
    idsTrabajadores(t).contains(trabajadorId);

/// Sin tildes ni mayúsculas, para comparar textos escritos por personas.
String normalizarTexto(String texto) {
  const de = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
  const a = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
  final buffer = StringBuffer();
  for (final rune in texto.runes) {
    final c = String.fromCharCode(rune);
    final i = de.indexOf(c);
    buffer.write(i >= 0 ? a[i] : c);
  }
  return buffer.toString().toLowerCase().trim();
}

/// true si todas las palabras de [consulta] aparecen en la actividad
/// (nombre, lugar, elemento, trabajadores o categoría). Ignora tildes.
bool coincideBusqueda(TareaModel t, String consulta, {String? categoria}) {
  final palabras = normalizarTexto(
    consulta,
  ).split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (palabras.isEmpty) return true;
  final texto = normalizarTexto(
    [
      t.descripcion,
      t.ubicacionNombre ?? '',
      t.elementoNombre ?? '',
      t.categoriaNombre ?? '',
      categoria ?? '',
      ...t.operariosNombres,
      t.id.toString(),
    ].join(' '),
  );
  return palabras.every(texto.contains);
}

/// Actividades que se cruzan en el tiempo (encadenadas). Para usar con las
/// actividades de UNA persona: con todo el equipo, el día entero se volvería
/// un solo grupo.
class FranjaActividades {
  final DateTime inicio;
  DateTime fin;
  final List<TareaModel> tareas;

  FranjaActividades(this.inicio, this.fin, this.tareas);

  bool get simultaneas => tareas.length > 1;
}

List<FranjaActividades> agruparSimultaneas(Iterable<TareaModel> tareas) {
  final orden = tareas.toList()
    ..sort((a, b) {
      final c = a.fechaInicio.compareTo(b.fechaInicio);
      return c != 0 ? c : a.fechaFin.compareTo(b.fechaFin);
    });
  final out = <FranjaActividades>[];
  for (final t in orden) {
    if (out.isNotEmpty && t.fechaInicio.isBefore(out.last.fin)) {
      out.last.tareas.add(t);
      if (t.fechaFin.isAfter(out.last.fin)) out.last.fin = t.fechaFin;
    } else {
      out.add(FranjaActividades(t.fechaInicio, t.fechaFin, [t]));
    }
  }
  return out;
}

/// Actividades agrupadas por la hora en que empiezan (vista general del día).
List<(int, List<TareaModel>)> agruparPorHoraInicio(
  Iterable<TareaModel> tareas,
) {
  final mapa = <int, List<TareaModel>>{};
  for (final t in tareas) {
    mapa.putIfAbsent(t.fechaInicio.toLocal().hour, () => []).add(t);
  }
  final horas = mapa.keys.toList()..sort();
  return [
    for (final h in horas)
      (
        h,
        mapa[h]!..sort((a, b) {
          final c = a.fechaInicio.compareTo(b.fechaInicio);
          return c != 0 ? c : a.fechaFin.compareTo(b.fechaFin);
        }),
      ),
  ];
}

/// Otras actividades de las mismas personas que se cruzan con [t].
List<TareaModel> simultaneasDe(TareaModel t, Iterable<TareaModel> delDia) {
  final mias = idsTrabajadores(t);
  if (mias.isEmpty) return const [];
  return delDia
      .where(
        (o) =>
            o.id != t.id &&
            o.fechaInicio.isBefore(t.fechaFin) &&
            t.fechaInicio.isBefore(o.fechaFin) &&
            idsTrabajadores(o).any(mias.contains),
      )
      .toList();
}

/// Una entrada por id (una compartida que aparece en la fila de cada
/// trabajador se cuenta una sola vez).
List<TareaModel> unicasPorId(Iterable<TareaModel> tareas) {
  final vistos = <int>{};
  return [
    for (final t in tareas)
      if (vistos.add(t.id)) t,
  ];
}

class ResumenEstados {
  final int total;
  final Map<GrupoEstado, int> porGrupo;

  const ResumenEstados(this.total, this.porGrupo);

  int de(GrupoEstado g) => porGrupo[g] ?? 0;
}

ResumenEstados contarPorGrupo(Iterable<TareaModel> tareas, {DateTime? ahora}) {
  final unicas = unicasPorId(tareas);
  final conteo = <GrupoEstado, int>{};
  for (final t in unicas) {
    final g = EstadoVisual.de(t, ahora: ahora).grupo;
    conteo[g] = (conteo[g] ?? 0) + 1;
  }
  return ResumenEstados(unicas.length, conteo);
}

/// Progreso del día del operario. Cuenta como cerradas las terminadas y las
/// que no se pudieron hacer (cerradas con motivo), y los cierres guardados
/// sin conexión.
class ProgresoDia {
  final int total;
  final int hechas;
  final int noSeHicieron;
  final int enviando;

  const ProgresoDia({
    required this.total,
    required this.hechas,
    required this.noSeHicieron,
    required this.enviando,
  });

  int get cerradas => hechas + noSeHicieron;
  int get pendientes => total - cerradas;
  double get fraccion => total == 0 ? 0 : cerradas / total;
  int get porcentaje => (fraccion * 100).round();

  /// Frase corta y sobria para motivar, sin exagerar.
  String get mensaje {
    if (total == 0) return 'Hoy no tienes actividades programadas.';
    if (cerradas == 0) {
      return total == 1
          ? 'Hoy tienes 1 actividad. ¡Vamos!'
          : 'Hoy tienes $total actividades. ¡Vamos con la primera!';
    }
    if (pendientes == 0) {
      return 'Terminaste todas las actividades de hoy. ¡Buen trabajo!';
    }
    final quedan = pendientes == 1
        ? 'Te queda 1 actividad'
        : 'Te quedan $pendientes actividades';
    final llevas = cerradas == 1 ? 'Ya cerraste 1.' : 'Ya cerraste $cerradas.';
    final mitad = fraccion >= 0.5 && fraccion < 1
        ? ' Vas por más de la mitad.'
        : '';
    return '$llevas $quedan.$mitad';
  }
}

ProgresoDia progresoDelDia(
  Iterable<TareaModel> tareasDelDia, {
  Set<int> cierresPendientesEnvio = const {},
  DateTime? ahora,
}) {
  var hechas = 0;
  var noSeHicieron = 0;
  var enviando = 0;
  final unicas = unicasPorId(tareasDelDia);
  for (final t in unicas) {
    final pendienteEnvio = cierresPendientesEnvio.contains(t.id);
    final e = EstadoVisual.de(
      t,
      ahora: ahora,
      cierrePendienteEnvio: pendienteEnvio,
    );
    if (pendienteEnvio) {
      enviando++;
      hechas++;
    } else if (identical(e, EstadoVisual.noSeHizo)) {
      noSeHicieron++;
    } else if (e.cerrada) {
      hechas++;
    }
  }
  return ProgresoDia(
    total: unicas.length,
    hechas: hechas,
    noSeHicieron: noSeHicieron,
    enviando: enviando,
  );
}

/// "1 actividad", "3 actividades".
String cantidadActividades(int n) => n == 1 ? '1 actividad' : '$n actividades';

/// "30 min", "1 h", "2 h 5 min".
String duracionLegible(int minutos) {
  if (minutos < 60) return '$minutos min';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

DateTime soloFecha(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

bool mismoDia(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

DateTime inicioSemana(DateTime d) {
  final f = soloFecha(d);
  return f.subtract(Duration(days: f.weekday - DateTime.monday));
}
