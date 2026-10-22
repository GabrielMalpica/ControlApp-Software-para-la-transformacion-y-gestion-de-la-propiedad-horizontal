import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/model/planilla_usuario_model.dart';
import 'package:flutter_application_1/utils/planilla/planilla_tabla.dart';
import 'package:flutter_application_1/widgets/planilla/tabla_planilla.dart';

final _hoy = DateTime(2026, 10, 22);
const _contexto = 'prueba';

final _filas = [
  PlanillaUsuario(
    cedula: '1001',
    nombre: 'Ana Gómez',
    rol: 'operario',
    correo: 'ana@correo.co',
    telefono: '3001234567',
    eps: 'SURA',
    fechaIngreso: DateTime(2022, 5, 1),
    conjuntos: const [ConjuntoPlanilla(nit: 'C-1', nombre: 'Bosque')],
  ),
  PlanillaUsuario(
    cedula: '1002',
    nombre: 'Beto Ruiz',
    rol: 'operario',
    eps: 'NUEVA_EPS',
    fechaIngreso: DateTime(2023, 1, 10),
    vacaciones: [
      BloqueVacaciones(
        desde: DateTime(2026, 10, 20),
        hasta: DateTime(2026, 11, 15),
      ),
    ],
    conjuntos: const [ConjuntoPlanilla(nit: 'C-2', nombre: 'Lago')],
  ),
  const PlanillaUsuario(cedula: '9', nombre: 'Carla Díaz', rol: 'gerente'),
];

Widget _app({double escala = 1, List<PlanillaUsuario>? filas}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(escala)),
        child: Scaffold(
          body: SelectionArea(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: TablaPlanillaSliver(
                    filas: filas ?? _filas,
                    contexto: _contexto,
                    hoy: _hoy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Preferencias con solo estas columnas visibles, en este orden.
Map<String, Object> _prefsCon(List<String> claves, {String? agrupacion}) {
  final todas = columnasPlanilla.map((c) => c.clave).toList();
  return {
    TablaPlanillaSliver.clavePreferencias(_contexto): jsonEncode({
      'orden': [...claves, ...todas.where((c) => !claves.contains(c))],
      'ocultas': todas.where((c) => !claves.contains(c)).toList(),
      'agrupacion': ?agrupacion,
    }),
  };
}

Future<Map<String, dynamic>> _guardado() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(TablaPlanillaSliver.clavePreferencias(_contexto));
  return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
}

void _pantalla(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Encabezado de la tabla (no el texto del menú ni la ficha que se arrastra).
Finder _titulo(String texto) => find.descendant(
  of: find.byType(DragTarget<String>),
  matching: find.text(texto),
);

double _x(WidgetTester tester, String titulo) =>
    tester.getTopLeft(_titulo(titulo)).dx;

void main() {
  late String? copiado;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    copiado = null;
  });

  void capturarPortapapeles(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  testWidgets('muestra todas las columnas y el estado de vacaciones', (
    tester,
  ) async {
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Columnas (${columnasPlanilla.length} de ${columnasPlanilla.length})',
      ),
      findsOneWidget,
    );
    expect(_titulo('Nombre'), findsOneWidget);
    expect(_titulo('Días para vacaciones'), findsOneWidget);
    expect(find.text('Ana Gómez'), findsOneWidget);
    expect(find.text('Nueva EPS'), findsOneWidget);
    expect(
      find.text('Pendientes desde el 01/05/2026 · hace 174 días'),
      findsOneWidget,
    );
    expect(find.text('De vacaciones hasta el 15/11'), findsOneWidget);
    expect(find.text('Sin fecha de ingreso'), findsOneWidget);
  });

  testWidgets('el menú de columnas oculta una y lo recuerda en el dispositivo', (
    tester,
  ) async {
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Columnas ('));
    await tester.pumpAndSettle();
    // El menú se abre debajo del botón.
    final boton = tester.getBottomLeft(find.textContaining('Columnas ('));
    final primera = find.widgetWithText(InkWell, 'Nombre');
    expect(tester.getTopLeft(primera).dy, greaterThan(boton.dy));

    // La lista de columnas es larga: el menú se desplaza por dentro.
    final opcion = find.widgetWithText(InkWell, 'EPS');
    await tester.ensureVisible(opcion);
    await tester.pumpAndSettle();
    await tester.tap(opcion);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Columnas (${columnasPlanilla.length - 1} de ${columnasPlanilla.length})',
      ),
      findsOneWidget,
    );
    expect(_titulo('EPS'), findsNothing);
    expect((await _guardado())['ocultas'], contains('eps'));

    // Al volver a abrir la pantalla sigue oculta.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(_titulo('EPS'), findsNothing);
    expect(_titulo('Cédula'), findsOneWidget);
  });

  testWidgets('las flechas del menú mueven la columna', (tester) async {
    SharedPreferences.setMockInitialValues(
      _prefsCon(['nombre', 'cedula', 'eps', 'conjuntos']),
    );
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Columnas ('));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mover Conjunto(s) a la izquierda'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1380, 980));
    await tester.pumpAndSettle();

    expect(_x(tester, 'Conjunto(s)'), lessThan(_x(tester, 'EPS')));
    expect((await _guardado())['orden'].take(4), [
      'nombre',
      'cedula',
      'conjuntos',
      'eps',
    ]);
  });

  testWidgets('arrastrar un título con el mouse cambia el orden', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      _prefsCon(['nombre', 'cedula', 'eps', 'conjuntos']),
    );
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(_x(tester, 'EPS'), lessThan(_x(tester, 'Conjunto(s)')));

    final gesture = await tester.startGesture(
      tester.getCenter(_titulo('Conjunto(s)')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(_titulo('EPS')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_x(tester, 'Conjunto(s)'), lessThan(_x(tester, 'EPS')));
    expect((await _guardado())['orden'].take(4), [
      'nombre',
      'cedula',
      'conjuntos',
      'eps',
    ]);
  });

  testWidgets('con el dedo se arrastra después de mantener presionado', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      _prefsCon(['nombre', 'cedula', 'eps', 'conjuntos']),
    );
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(_titulo('EPS')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(_titulo('Conjunto(s)')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_x(tester, 'Conjunto(s)'), lessThan(_x(tester, 'EPS')));
  });

  testWidgets('agrupa por conjunto con título y conteo', (tester) async {
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agrupar: Sin agrupar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Por conjunto'));
    await tester.pumpAndSettle();

    expect(find.text('Agrupar: Por conjunto'), findsOneWidget);
    expect(find.text('Bosque · 1 persona'), findsOneWidget);
    expect(find.text('Lago · 1 persona'), findsOneWidget);
    expect(find.text('Sin conjunto · 1 persona'), findsOneWidget);
    expect((await _guardado())['agrupacion'], 'conjunto');
  });

  testWidgets('copiar fila y copiar tabla dejan texto para Excel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      _prefsCon(['nombre', 'cedula', 'eps']),
    );
    capturarPortapapeles(tester);
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copiar fila de Ana Gómez'));
    await tester.pumpAndSettle();
    expect(copiado, 'Nombre\tCédula\tEPS\nAna Gómez\t1001\tSura');

    await tester.tap(find.text('Copiar tabla'));
    await tester.pumpAndSettle();
    expect(
      copiado,
      'Nombre\tCédula\tEPS\n'
      'Ana Gómez\t1001\tSura\n'
      'Beto Ruiz\t1002\tNueva EPS\n'
      'Carla Díaz\t9\t',
    );
    expect(find.textContaining('Tabla copiada (3 personas'), findsOneWidget);
  });

  testWidgets('el texto de las celdas se puede seleccionar', (tester) async {
    _pantalla(tester, const Size(1400, 1000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final celda = find.text('Ana Gómez');
    expect(
      find.ancestor(of: celda, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
    // Los títulos no participan de la selección (se arrastran).
    expect(
      find.ancestor(
        of: _titulo('Nombre'),
        matching: find.byType(SelectionContainer),
      ),
      findsWidgets,
    );
  });

  testWidgets('sin personas muestra el aviso', (tester) async {
    _pantalla(tester, const Size(800, 800));
    await tester.pumpWidget(_app(filas: const []));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay personas para mostrar con estos filtros.'),
      findsOneWidget,
    );
  });

  testWidgets('celular con letra al 200 %: sin desbordes y accesible', (
    tester,
  ) async {
    _pantalla(tester, const Size(390, 844));
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(escala: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Copiar tabla'), findsOneWidget);
    // La tabla sigue hacia los lados: aparece el aviso con flechas.
    await tester.scrollUntilVisible(
      find.byTooltip('Ver días siguientes'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ver días siguientes'), findsOneWidget);
    expect(find.text('Ana Gómez'), findsOneWidget);
    await tester.tap(find.byTooltip('Ver días siguientes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
