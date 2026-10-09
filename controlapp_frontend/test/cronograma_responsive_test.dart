import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pages/cronograma/cronograma_hoy_view.dart';
import 'package:flutter_application_1/pages/cronograma/grilla_horas_view.dart';
import 'package:flutter_application_1/pages/cronograma/mes_resumen_view.dart';
import 'package:flutter_application_1/pages/cronograma/mis_actividades_page.dart';
import 'package:flutter_application_1/pages/cronograma/semana_trabajador_view.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';

final _ahora = DateTime(2026, 10, 8, 9, 40);

/// Semana de ejemplo: 3 personas, una actividad compartida y dos a la vez.
List<TareaModel> _semana() {
  final out = <TareaModel>[];
  var id = 1;
  TareaModel t(int dia, int ini, int fin, String desc, List<String> ids, List<String> nombres, {String cat = 'Aseo', String color = '#1F6FB2', String tipo = 'PREVENTIVA', String estado = 'ASIGNADA'}) {
    return TareaModel(
      id: id++,
      descripcion: desc,
      fechaInicio: DateTime(2026, 10, dia, ini),
      fechaFin: DateTime(2026, 10, dia, fin),
      duracionMinutos: (fin - ini) * 60,
      borrador: false,
      estado: estado,
      tipo: tipo,
      ubicacionId: 1,
      elementoId: 1,
      ubicacionNombre: 'Torres y pasillos',
      elementoNombre: 'Circulaciones > Pasillos de las torres',
      operariosIds: ids,
      operariosNombres: nombres,
      categoriaNombre: tipo == 'CORRECTIVA' ? null : cat,
      categoriaColorHex: color,
    );
  }

  for (var d = 5; d <= 10; d++) {
    out.add(t(d, 7, 9, 'Barrido y recolección de residuos de la zona social', ['1'], ['Operario Aseo General'], estado: d < 8 ? 'APROBADA' : 'ASIGNADA'));
    out.add(t(d, 7, 8, 'Lavar y desinfectar baños', ['1'], ['Operario Aseo General']));
    out.add(t(d, 9, 11, 'Poda de árboles bajos y setos de la entrada', ['2'], ['Operario Todero Uno'], cat: 'Jardinería', color: '#2E7D32'));
    out.add(t(d, 10, 12, 'Lavado de pisos del lobby', ['1', '2'], ['Operario Aseo General', 'Operario Todero Uno']));
    out.add(t(d, 13, 15, 'Vigilar piscina', ['3'], ['Operario Salvavidas Fin de Semana'], cat: 'Salvamento acuático', color: '#D32F2F'));
  }
  out.add(t(8, 14, 15, 'Destapar sifón del salón social', ['2'], ['Operario Todero Uno'], tipo: 'CORRECTIVA'));
  return out;
}

Future<void> _tamano(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Cuántos desplazamientos verticales hay en pantalla (debe haber uno solo).
int _scrollsVerticales(WidgetTester tester) => tester
    .widgetList<Scrollable>(find.byType(Scrollable))
    .where((s) => axisDirectionToAxis(s.axisDirection) == Axis.vertical)
    .length;

Widget _app(Widget child, {double escala = 1}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  setUpAll(() async => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (nombre, size, escala) in [
    ('celular 360', const Size(360, 800), 1.3),
    ('tableta 768', const Size(768, 1024), 1.15),
    ('escritorio 1280', const Size(1280, 900), 1.0),
  ]) {
    testWidgets('Hoy sin desbordes en $nombre', (tester) async {
      await _tamano(tester, size);
      final dia = _semana().where((t) => mismoDia(t.fechaInicio, _ahora)).toList();
      for (final orden in OrdenHoy.values) {
        await tester.pumpWidget(
          _app(
            CronogramaHoyView(
              dia: _ahora,
              ahora: _ahora,
              base: dia,
              grupo: null,
              onGrupo: (_) {},
              orden: orden,
              onOrden: (_) {},
              seleccionadaId: null,
              onAbrir: (_) {},
              onElegirTrabajador: (_) {},
              cabecera: const Text('Cabecera'),
              panelDetalle: const Text('Detalle'),
              selectorTrabajador: const Text('Selector de trabajador'),
            ),
            escala: escala,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$nombre $orden');
        if (orden == OrdenHoy.porHora) {
          expect(find.textContaining('Ahora mismo'), findsOneWidget);
        }
        // El selector de trabajador sale al lado de "Por trabajador", y solo
        // cuando se elige esa opción.
        await tester.scrollUntilVisible(
          find.text('Ordenar:'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('Selector de trabajador'),
          orden == OrdenHoy.porTrabajador ? findsOneWidget : findsNothing,
          reason: '$nombre $orden',
        );
      }
    });

    testWidgets('Mes sin desbordes en $nombre', (tester) async {
      await _tamano(tester, size);
      await tester.pumpWidget(
        _app(
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MesResumenView(
                anio: 2026,
                mes: 10,
                tareas: _semana(),
                ahora: _ahora,
                festivo: (d) => d.day == 12 ? 'Día de la Raza' : null,
                onDia: (_) {},
              ),
            ],
          ),
          escala: escala,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Semana por trabajador en tableta: desplaza sin desbordes', (tester) async {
    await _tamano(tester, const Size(768, 1024));
    final semana = _semana();
    await tester.pumpWidget(
      _app(
        CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: SizedBox(height: 300, child: Text('Cabecera')),
            ),
            SemanaTrabajadorSliver(
              dias: [for (var d = 5; d <= 10; d++) DateTime(2026, 10, d)],
              tareas: semana,
              base: semana,
              trabajadores: trabajadoresDe(semana),
              ahora: _ahora,
              seleccionadaId: null,
              onAbrir: (_) {},
              onElegirTrabajador: (_) {},
              festivo: (_) => null,
            ),
          ],
        ),
        escala: 1.15,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Un solo scroll vertical: la tabla no tiene uno propio adentro.
    expect(_scrollsVerticales(tester), 1);
    // No caben los 6 días: se avisa y hay flechas para moverla.
    expect(find.textContaining('La semana sigue hacia los lados'), findsOneWidget);
    await tester.tap(find.byTooltip('Ver días siguientes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Al bajar, la fila de días queda fija arriba.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Trabajador')).dy, lessThan(120));
    // La compartida aparece en la fila de cada uno, con quién.
    expect(find.text('con Operario'), findsWidgets);
  });

  testWidgets('Semana en celular: franja de días y personas', (tester) async {
    await _tamano(tester, const Size(360, 800));
    final semana = _semana();
    await tester.pumpWidget(
      _app(
        SemanaMovilView(
          dias: [for (var d = 5; d <= 11; d++) DateTime(2026, 10, d)],
          diaSeleccionado: _ahora,
          onDia: (_) {},
          tareas: semana,
          base: semana,
          ahora: _ahora,
          seleccionadaId: null,
          onAbrir: (_) {},
          cabecera: const Text('Cabecera'),
        ),
        escala: 1.3,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Jueves 8 de octubre'), findsOneWidget);
  });

  testWidgets('Cuadrícula por horas: una columna por persona sin desbordes', (tester) async {
    await _tamano(tester, const Size(768, 900));
    final dia = _semana().where((t) => mismoDia(t.fechaInicio, _ahora)).toList();
    await tester.pumpWidget(
      _app(
        CustomScrollView(
          slivers: [
            GrillaHorasSliver(
              columnas: columnasPorTrabajador(
                dia: _ahora,
                tareasDia: dia,
                trabajadores: trabajadoresDe(dia),
                ahora: _ahora,
              ),
              ahora: _ahora,
              seleccionadaId: null,
              onAbrir: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    // La cuadrícula no tiene un scroll vertical propio.
    expect(_scrollsVerticales(tester), 1);
    expect(find.text('Operario Todero Uno'), findsOneWidget);
  });

  testWidgets('Operario en celular: detalle y resultado del cierre sin desbordes', (tester) async {
    await _tamano(tester, const Size(360, 800));
    final compartida = _semana().firstWhere(
      (t) => t.descripcion == 'Lavado de pisos del lobby' && mismoDia(t.fechaInicio, _ahora),
    );
    for (final escala in [1.0, 1.3]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(escala)),
            child: ActividadOperarioPage(
              tarea: compartida,
              usuarioActualId: '1',
              puedeCerrar: true,
              cierreSinEnviar: false,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Registrar cierre'), findsOneWidget);
      expect(find.text('La haces con'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(escala)),
            child: ResultadoCierrePage(
              tarea: compartida,
              guardadoSinSenal: false,
              noSeHizo: false,
              progreso: progresoDelDia([compartida], ahora: _ahora),
              siguiente: _semana().first,
              usuarioActualId: '1',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('También quedó cerrada para Operario Todero Uno'), findsOneWidget);
    }
  });
}
