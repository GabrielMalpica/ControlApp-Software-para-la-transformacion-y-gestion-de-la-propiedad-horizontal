// lib/utils/week_layout.dart
//
// Diseño (carriles) de las tarjetas de tareas de UN día en la grilla semanal.
// Es una función pura para poder probarla y compartirla entre el cronograma
// general y el borrador.
//
// Reglas:
// - Solo las tareas que SE SOLAPAN DE VERDAD (por su horario real) se reparten
//   el ancho. La altura mínima dibujable NO cuenta como solape: una tarea de
//   10 min seguida de otra no debe dejarla a media anchura.
// - Cada tarjeta se ensancha hacia ambos lados mientras los carriles contiguos
//   estén libres en su franja, para que no queden "huecos" en blanco.
// - La altura visual mínima se recorta para no pisar a la tarea que sigue
//   en la misma zona horizontal.

class WeekLayoutInput {
  final DateTime inicio;
  final DateTime fin;

  const WeekLayoutInput({required this.inicio, required this.fin});
}

class WeekLayoutOutput {
  final int lane;
  final int laneCount;
  final int laneSpan;

  /// Fin con el que se dibuja la tarjeta (>= fin real).
  final DateTime visualFin;

  const WeekLayoutOutput({
    required this.lane,
    required this.laneCount,
    required this.laneSpan,
    required this.visualFin,
  });
}

/// Devuelve un resultado por entrada, en el mismo orden que [items].
/// [minVisual] es la duración mínima con la que se dibuja una tarjeta.
List<WeekLayoutOutput> layoutWeekDayTasks(
  List<WeekLayoutInput> items, {
  required Duration minVisual,
}) {
  final n = items.length;
  if (n == 0) return const [];

  bool solapa(int a, int b) =>
      items[a].inicio.isBefore(items[b].fin) &&
      items[a].fin.isAfter(items[b].inicio);

  final orden = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final porInicio = items[a].inicio.compareTo(items[b].inicio);
      if (porInicio != 0) return porInicio;
      final porFin = items[a].fin.compareTo(items[b].fin);
      if (porFin != 0) return porFin;
      return a.compareTo(b);
    });

  // 1) Grupos de solape real.
  final grupos = <List<int>>[];
  DateTime? finGrupo;
  for (final i in orden) {
    if (grupos.isEmpty || !items[i].inicio.isBefore(finGrupo!)) {
      grupos.add([i]);
      finGrupo = items[i].fin;
    } else {
      grupos.last.add(i);
      if (items[i].fin.isAfter(finGrupo)) finGrupo = items[i].fin;
    }
  }

  final lane = List<int>.filled(n, 0);
  final span = List<int>.filled(n, 1);
  final laneCount = List<int>.filled(n, 1);

  for (final grupo in grupos) {
    // 2) Carril: el que quedó libre más cerca del inicio (menos hueco).
    final finCarril = <DateTime>[];
    for (final i in grupo) {
      var mejor = -1;
      for (var l = 0; l < finCarril.length; l++) {
        if (finCarril[l].isAfter(items[i].inicio)) continue;
        if (mejor < 0 || finCarril[l].isAfter(finCarril[mejor])) mejor = l;
      }
      if (mejor < 0) {
        finCarril.add(items[i].fin);
        mejor = finCarril.length - 1;
      } else {
        finCarril[mejor] = items[i].fin;
      }
      lane[i] = mejor;
    }
    final total = finCarril.length;

    // 3) Ensanchar hacia ambos lados mientras el carril contiguo esté libre
    // durante toda la franja de la tarea.
    bool carrilLibre(int i, int l) {
      for (final j in grupo) {
        if (j == i || lane[j] != l) continue;
        if (solapa(i, j)) return false;
      }
      return true;
    }

    final izquierda = <int, int>{};
    final derecha = <int, int>{};
    for (final i in grupo) {
      var l = lane[i];
      var r = lane[i];
      while (r + 1 < total && carrilLibre(i, r + 1)) {
        r++;
      }
      while (l - 1 >= 0 && carrilLibre(i, l - 1)) {
        l--;
      }
      izquierda[i] = l;
      derecha[i] = r;
    }
    for (final i in grupo) {
      laneCount[i] = total;
      span[i] = derecha[i]! - izquierda[i]! + 1;
      lane[i] = izquierda[i]!;
    }
  }

  // 4) Fin visual: la altura mínima se recorta si la tarea siguiente en la
  // misma zona horizontal empieza antes (cualquier grupo del día).
  double desde(int i) => lane[i] / laneCount[i];
  double hasta(int i) => (lane[i] + span[i]) / laneCount[i];
  bool comparteZona(int a, int b) =>
      desde(a) < hasta(b) - 1e-9 && desde(b) < hasta(a) - 1e-9;

  final salida = <WeekLayoutOutput>[];
  for (var i = 0; i < n; i++) {
    final minimo = items[i].inicio.add(minVisual);
    var visual = items[i].fin.isAfter(minimo) ? items[i].fin : minimo;
    for (var j = 0; j < n; j++) {
      if (j == i) continue;
      final empiezaDespues = !items[j].inicio.isBefore(items[i].fin);
      if (empiezaDespues &&
          items[j].inicio.isBefore(visual) &&
          comparteZona(i, j)) {
        visual = items[j].inicio;
      }
    }
    salida.add(
      WeekLayoutOutput(
        lane: lane[i],
        laneCount: laneCount[i],
        laneSpan: span[i],
        visualFin: visual,
      ),
    );
  }
  return salida;
}
