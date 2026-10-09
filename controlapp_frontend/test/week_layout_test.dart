import 'package:flutter_application_1/utils/week_layout.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _t(int h, [int m = 0]) => DateTime(2026, 8, 6, h, m);

WeekLayoutInput _i(DateTime a, DateTime b) =>
    WeekLayoutInput(inicio: a, fin: b);

const _minVisual = Duration(minutes: 17);

void main() {
  test('una tarea corta seguida de otra no deja a ninguna a media anchura', () {
    // Toma de parámetros (10 min) y debajo Aspirar por filtro.
    final r = layoutWeekDayTasks([
      _i(_t(7), _t(7, 10)),
      _i(_t(7, 10), _t(8, 10)),
    ], minVisual: _minVisual);

    expect(r[0].laneCount, 1);
    expect(r[0].laneSpan, 1);
    expect(r[1].laneCount, 1);
    expect(r[1].laneSpan, 1);
    // La altura mínima de la corta se recorta donde empieza la siguiente.
    expect(r[0].visualFin, _t(7, 10));
  });

  test('una tarea corta aislada conserva su altura mínima legible', () {
    final r = layoutWeekDayTasks([_i(_t(7), _t(7, 10))], minVisual: _minVisual);
    expect(r[0].visualFin, _t(7, 17));
  });

  test('solo las tareas que se solapan de verdad se reparten el ancho', () {
    final r = layoutWeekDayTasks([
      _i(_t(7), _t(8)),
      _i(_t(7, 30), _t(8, 30)),
      _i(_t(9), _t(10)), // otro grupo: ocupa todo el ancho
    ], minVisual: _minVisual);

    expect(r[0].laneCount, 2);
    expect(r[1].laneCount, 2);
    expect(r[0].lane, isNot(r[1].lane));
    expect(r[2].laneCount, 1);
    expect(r[2].laneSpan, 1);
  });

  test('la siguiente tarea reutiliza el carril que acaba de liberarse', () {
    // A y B se solapan; C empieza justo cuando termina A: debe ir en el
    // carril de A (sin dejar un hueco bajo A y sin abrir un tercer carril).
    final r = layoutWeekDayTasks([
      _i(_t(7), _t(7, 30)), // A
      _i(_t(7, 20), _t(8, 20)), // B
      _i(_t(7, 30), _t(8)), // C
    ], minVisual: _minVisual);

    expect(r[0].lane, r[2].lane);
    expect(r[0].laneCount, 2);
    expect(r[2].laneCount, 2);
  });

  test('una tarea se ensancha por los carriles libres durante su franja', () {
    // A ocupa el carril 0 todo el rato; B y C en el carril 1 pero C llega
    // cuando A ya terminó: C puede ocupar los dos carriles.
    final r = layoutWeekDayTasks([
      _i(_t(7), _t(8)), // A
      _i(_t(7), _t(8, 30)), // B
      _i(_t(8, 15), _t(9)), // C: A terminó, B aún no
    ], minVisual: _minVisual);

    // B tiene el carril 1 y C no lo comparte con A durante su franja.
    expect(r[0].laneCount, 2);
    expect(r[2].laneCount, 2);
    expect(r[2].laneSpan, 1);
    expect(r[2].lane, 0);
  });

  test('devuelve un resultado por entrada y en el mismo orden', () {
    final r = layoutWeekDayTasks([
      _i(_t(9), _t(10)),
      _i(_t(7), _t(8)),
    ], minVisual: _minVisual);
    expect(r, hasLength(2));
    expect(r[0].visualFin, _t(10));
    expect(r[1].visualFin, _t(8));
  });

  test('ninguna pareja de tarjetas se pisa en días aleatorios', () {
    var semilla = 12345;
    int siguiente(int tope) {
      semilla = (semilla * 1103515245 + 12345) & 0x7fffffff;
      return semilla % tope;
    }

    for (var caso = 0; caso < 400; caso++) {
      final n = 3 + siguiente(14);
      final items = <WeekLayoutInput>[];
      for (var i = 0; i < n; i++) {
        final inicio = 7 * 60 + siguiente(10 * 60);
        final duracion = 5 + siguiente(120);
        items.add(
          _i(
            _t(inicio ~/ 60, inicio % 60),
            _t((inicio + duracion) ~/ 60, (inicio + duracion) % 60),
          ),
        );
      }
      final r = layoutWeekDayTasks(items, minVisual: _minVisual);

      double desde(int i) => r[i].lane / r[i].laneCount;
      double hasta(int i) => (r[i].lane + r[i].laneSpan) / r[i].laneCount;

      for (var a = 0; a < n; a++) {
        expect(r[a].lane + r[a].laneSpan, lessThanOrEqualTo(r[a].laneCount));
        expect(r[a].visualFin.isBefore(items[a].fin), isFalse);
        for (var b = a + 1; b < n; b++) {
          final zona = desde(a) < hasta(b) - 1e-9 && desde(b) < hasta(a) - 1e-9;
          if (!zona) continue;
          // Misma zona horizontal: no pueden coincidir en el horario real...
          final solapan =
              items[a].inicio.isBefore(items[b].fin) &&
              items[b].inicio.isBefore(items[a].fin);
          expect(
            solapan,
            isFalse,
            reason: 'caso $caso: $a y $b comparten zona y se solapan',
          );
          // ...ni al dibujarse (altura mínima incluida).
          final primero = items[a].inicio.isBefore(items[b].inicio) ? a : b;
          final segundo = primero == a ? b : a;
          expect(
            r[primero].visualFin.isAfter(items[segundo].inicio),
            isFalse,
            reason: 'caso $caso: $primero pisa visualmente a $segundo',
          );
        }
      }
    }
  });
}
