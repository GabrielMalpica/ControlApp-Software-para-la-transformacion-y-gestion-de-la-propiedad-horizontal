// lib/utils/interval_lanes.dart

/// Intervalo [inicio, fin) a ubicar en una fila de la línea de tiempo.
class IntervalLaneInput {
  final DateTime inicio;
  final DateTime fin;

  const IntervalLaneInput({required this.inicio, required this.fin});
}

class IntervalLaneOutput {
  /// Carril (0 = arriba) asignado al intervalo.
  final int lane;

  const IntervalLaneOutput(this.lane);
}

/// Reparte intervalos de varios días en carriles para que no se dibujen uno
/// encima del otro (p. ej. un préstamo largo y las tareas que caen dentro).
///
/// Algoritmo voraz por inicio: cada intervalo va al primer carril cuyo último
/// intervalo ya terminó. Devuelve la salida en el MISMO orden de la entrada y
/// el total de carriles usados. Los intervalos son semiabiertos: [8,12) y
/// [12,14) comparten carril.
({List<IntervalLaneOutput> lanes, int laneCount}) packIntervalsIntoLanes(
  List<IntervalLaneInput> intervalos,
) {
  final orden = List<int>.generate(intervalos.length, (i) => i)
    ..sort((a, b) {
      final porInicio = intervalos[a].inicio.compareTo(intervalos[b].inicio);
      if (porInicio != 0) return porInicio;
      // A igual inicio, el más largo primero: queda arriba y estable.
      return intervalos[b].fin.compareTo(intervalos[a].fin);
    });

  final finDeCarril = <DateTime>[];
  final salida = List<IntervalLaneOutput>.filled(
    intervalos.length,
    const IntervalLaneOutput(0),
  );

  for (final i in orden) {
    final it = intervalos[i];
    var carril = finDeCarril.indexWhere((fin) => !fin.isAfter(it.inicio));
    if (carril == -1) {
      finDeCarril.add(it.fin);
      carril = finDeCarril.length - 1;
    } else {
      finDeCarril[carril] = it.fin;
    }
    salida[i] = IntervalLaneOutput(carril);
  }

  return (lanes: salida, laneCount: finDeCarril.isEmpty ? 1 : finDeCarril.length);
}
