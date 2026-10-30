import 'package:flutter_application_1/model/tarea_model.dart';

/// Tramo del día en minutos desde las 00:00: [inicio, fin).
class TramoDia {
  final int inicio;
  final int fin;

  const TramoDia(this.inicio, this.fin);

  int get minutos => fin - inicio;

  bool cruzaCon(int otroInicio, int otroFin) =>
      inicio < otroFin && fin > otroInicio;

  @override
  bool operator ==(Object other) =>
      other is TramoDia && other.inicio == inicio && other.fin == fin;

  @override
  int get hashCode => Object.hash(inicio, fin);

  @override
  String toString() => 'TramoDia($inicio-$fin)';
}

/// Por qué una tarea no se puede reemplazar con la actividad nueva.
enum MotivoBloqueoEspecial { noEsPreventiva, prioridad }

/// Una tarea que choca con el horario de la actividad.
class TareaChoque {
  final TareaModel tarea;
  final MotivoBloqueoEspecial? bloqueo;

  /// Operarios de la actividad que tienen esta tarea.
  final List<String> operariosEnActividad;

  /// Quienes comparten la tarea sin estar en la actividad: si se reemplaza,
  /// también la pierden.
  final List<String> otrosOperarios;

  const TareaChoque({
    required this.tarea,
    required this.bloqueo,
    required this.operariosEnActividad,
    required this.otrosOperarios,
  });

  bool get bloquea => bloqueo != null;
}

/// Resultado de ubicar una actividad especial en un horario, calculado con
/// lo que el cronograma ya tiene cargado (para la previsualización mientras
/// se arrastra). Al soltar manda la previsualización del servidor.
class ImpactoLocalEspecial {
  final int inicio;
  final int fin;

  /// La hora pedida no cabía y se movió dentro del horario.
  final bool ajustado;

  /// Texto si no cabe en el horario de ese día (null si cabe).
  final String? fueraDeHorario;
  final List<TareaChoque> choques;

  const ImpactoLocalEspecial({
    required this.inicio,
    required this.fin,
    this.ajustado = false,
    this.fueraDeHorario,
    this.choques = const [],
  });

  List<TareaChoque> get reemplazos =>
      choques.where((c) => !c.bloquea).toList(growable: false);
  List<TareaChoque> get bloqueos =>
      choques.where((c) => c.bloquea).toList(growable: false);

  bool get libre => choques.isEmpty;
  bool get valido => fueraDeHorario == null && bloqueos.isEmpty;

  /// Personas (de la actividad o no) que pierden alguna tarea.
  Set<String> get operariosAfectados => {
    for (final c in reemplazos) ...c.operariosEnActividad,
    for (final c in reemplazos) ...c.otrosOperarios,
  };
}

const _estadosOcupanAgenda = {'ASIGNADA', 'EN_PROCESO'};

/// Si la tarea ocupa la agenda de sus operarios (las cerradas, canceladas o
/// por reprogramar ya no).
bool ocupaAgenda(TareaModel t) {
  final estado = (t.estado ?? 'ASIGNADA').trim().toUpperCase();
  return _estadosOcupanAgenda.contains(estado);
}

/// Prioridades de preventiva que una actividad de [prioridadActividad] puede
/// reemplazar (P1 todas, P2 las P2 y P3, P3 solo las P3). Igual al backend.
bool puedeReemplazarPrioridad(int prioridadActividad, int prioridadPreventiva) {
  if (prioridadActividad <= 1) return true;
  if (prioridadActividad == 2) return prioridadPreventiva >= 2;
  return prioridadPreventiva >= 3;
}

int _minutoDelDia(DateTime d) {
  final l = d.toLocal();
  return l.hour * 60 + l.minute;
}

/// Tramo de [t] en minutos del día [dia] (recortado a ese día).
TramoDia? tramoDeTareaEnDia(TareaModel t, DateTime dia) {
  final ini = t.fechaInicio.toLocal();
  final fin = t.fechaFin.toLocal();
  final d0 = DateTime(dia.year, dia.month, dia.day);
  final d1 = d0.add(const Duration(days: 1));
  if (!ini.isBefore(d1) || !fin.isAfter(d0)) return null;
  final a = ini.isBefore(d0) ? 0 : _minutoDelDia(ini);
  final b = fin.isBefore(d1) ? _minutoDelDia(fin) : 24 * 60;
  if (b <= a) return null;
  return TramoDia(a, b);
}

/// Une tramos que se tocan o se cruzan.
List<TramoDia> unirTramos(Iterable<TramoDia> tramos) {
  final ordenados = tramos.where((t) => t.fin > t.inicio).toList()
    ..sort((a, b) => a.inicio.compareTo(b.inicio));
  final out = <TramoDia>[];
  for (final t in ordenados) {
    if (out.isNotEmpty && t.inicio <= out.last.fin) {
      final ultimo = out.removeLast();
      out.add(TramoDia(ultimo.inicio, t.fin > ultimo.fin ? t.fin : ultimo.fin));
    } else {
      out.add(t);
    }
  }
  return out;
}

/// Ubica [duracion] minutos lo más cerca posible de [deseado] sin salirse de
/// un tramo de [rangos]: si al empezar ahí se pasa del cierre (o del
/// almuerzo), se corre hacia atrás; si cae en el almuerzo o fuera de la
/// jornada, va al tramo más cercano. Null si no cabe en ningún tramo.
int? ajustarInicioAlHorario({
  required int deseado,
  required int duracion,
  required List<TramoDia> rangos,
}) {
  int? mejor;
  int? mejorDistancia;
  for (final r in rangos) {
    if (r.minutos < duracion) continue;
    final maxInicio = r.fin - duracion;
    final inicio = deseado < r.inicio
        ? r.inicio
        : (deseado > maxInicio ? maxInicio : deseado);
    final distancia = (inicio - deseado).abs();
    if (mejorDistancia == null || distancia < mejorDistancia) {
      mejor = inicio;
      mejorDistancia = distancia;
    }
  }
  return mejor;
}

String _duracionTexto(int minutos) {
  final h = minutos ~/ 60;
  final m = minutos % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Impacto de ubicar la actividad en [deseado] (minuto del día) de [dia].
///
/// [agendaDia]: tareas publicadas del cronograma ese día SIN filtros (así se
/// ven también las de operarios ocultos por el filtro). [rangosConjunto]: el
/// horario del conjunto ese día sin el almuerzo; se le suman las horas en
/// que los operarios de la actividad ya tienen tareas (una plaza con horario
/// especial puede trabajar fuera del horario general).
ImpactoLocalEspecial calcularImpactoLocalEspecial({
  required List<TareaModel> agendaDia,
  required DateTime dia,
  required Set<String> operariosIds,
  required int prioridad,
  required int deseado,
  required int duracion,
  required List<TramoDia> rangosConjunto,
  int? excluirTareaId,
}) {
  final propias = agendaDia
      .where(
        (t) =>
            t.id != excluirTareaId &&
            ocupaAgenda(t) &&
            t.operariosIds.any(operariosIds.contains),
      )
      .toList();

  final rangos = unirTramos([
    ...rangosConjunto,
    for (final t in propias) ?tramoDeTareaEnDia(t, dia),
  ]);

  final inicio = ajustarInicioAlHorario(
    deseado: deseado,
    duracion: duracion,
    rangos: rangos,
  );
  if (inicio == null) {
    final masLargo = rangos.fold<int>(
      0,
      (m, r) => r.minutos > m ? r.minutos : m,
    );
    return ImpactoLocalEspecial(
      inicio: deseado,
      fin: deseado + duracion,
      fueraDeHorario: rangos.isEmpty
          ? 'Ese día no hay horario de trabajo.'
          : 'Dura ${_duracionTexto(duracion)} y el bloque de trabajo más '
                'largo de ese día es de ${_duracionTexto(masLargo)}.',
    );
  }
  final fin = inicio + duracion;

  final choques = <TareaChoque>[];
  for (final t in propias) {
    final tramo = tramoDeTareaEnDia(t, dia);
    if (tramo == null || !tramo.cruzaCon(inicio, fin)) continue;
    final tipo = (t.tipo ?? '').trim().toUpperCase();
    final bloqueo = tipo != 'PREVENTIVA'
        ? MotivoBloqueoEspecial.noEsPreventiva
        : (puedeReemplazarPrioridad(prioridad, t.prioridad)
              ? null
              : MotivoBloqueoEspecial.prioridad);
    final enActividad = <String>[];
    final otros = <String>[];
    for (var i = 0; i < t.operariosIds.length; i++) {
      final nombre = i < t.operariosNombres.length
          ? t.operariosNombres[i].trim()
          : t.operariosIds[i];
      (operariosIds.contains(t.operariosIds[i]) ? enActividad : otros).add(
        nombre.isEmpty ? t.operariosIds[i] : nombre,
      );
    }
    choques.add(
      TareaChoque(
        tarea: t,
        bloqueo: bloqueo,
        operariosEnActividad: enActividad,
        otrosOperarios: otros,
      ),
    );
  }
  choques.sort((a, b) => a.tarea.fechaInicio.compareTo(b.tarea.fechaInicio));

  return ImpactoLocalEspecial(
    inicio: inicio,
    fin: fin,
    ajustado: inicio != deseado,
    choques: choques,
  );
}

/// Primer inicio del día (desde [desde]) donde caben [duracion] minutos sin
/// cruzarse con ninguna tarea de [operariosIds]; si no hay, desde el inicio
/// del día. Para mover correctivas a un hueco libre de sus operarios.
int? primerHuecoLibre({
  required List<TareaModel> agendaDia,
  required DateTime dia,
  required Set<String> operariosIds,
  required int duracion,
  required List<TramoDia> rangos,
  required int desde,
  int? excluirTareaId,
  int paso = 1,
}) {
  final ocupados = unirTramos([
    for (final t in agendaDia)
      if (t.id != excluirTareaId &&
          ocupaAgenda(t) &&
          (operariosIds.isEmpty || t.operariosIds.any(operariosIds.contains)))
        ?tramoDeTareaEnDia(t, dia),
  ]);

  int? buscar(int minimo) {
    for (final r in [...rangos]..sort((a, b) => a.inicio.compareTo(b.inicio))) {
      var inicio = r.inicio > minimo ? r.inicio : minimo;
      if (paso > 1 && inicio % paso != 0) inicio += paso - inicio % paso;
      while (inicio + duracion <= r.fin) {
        final fin = inicio + duracion;
        TramoDia? choque;
        for (final o in ocupados) {
          if (o.cruzaCon(inicio, fin)) {
            choque = o;
            break;
          }
        }
        if (choque == null) return inicio;
        inicio = choque.fin;
        if (paso > 1 && inicio % paso != 0) inicio += paso - inicio % paso;
      }
    }
    return null;
  }

  return buscar(desde) ?? buscar(0);
}
