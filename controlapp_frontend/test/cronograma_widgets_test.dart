import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pages/cronograma/cerrar_actividad_page.dart';
import 'package:flutter_application_1/pages/cronograma/mis_actividades_page.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/widgets/cerrar_tarea_sheet.dart';
import 'package:flutter_application_1/widgets/cronograma/actividad_card.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_controles.dart';

final _ahora = DateTime(2026, 10, 8, 9, 40);

TareaModel _tarea({
  int id = 1,
  String desc = 'Lavar y desinfectar los baños del salón social y la zona húmeda de la piscina',
  int iniH = 9,
  int finH = 11,
  String estado = 'ASIGNADA',
  List<String> ids = const ['10', '20'],
  List<String> nombres = const ['María Gómez', 'Juan Pérez'],
}) {
  return TareaModel(
    id: id,
    descripcion: desc,
    fechaInicio: DateTime(2026, 10, 8, iniH),
    fechaFin: DateTime(2026, 10, 8, finH),
    duracionMinutos: (finH - iniH) * 60,
    borrador: false,
    estado: estado,
    tipo: 'PREVENTIVA',
    ubicacionId: 1,
    elementoId: 1,
    ubicacionNombre: 'Salón social',
    elementoNombre: 'Baños',
    operariosIds: ids,
    operariosNombres: nombres,
    categoriaNombre: 'Aseo',
    categoriaColorHex: '#1F6FB2',
    categoriaIcono: 'limpieza',
  );
}

Widget _app(Widget child, {double escala = 1}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tarjeta normal: con letra al 200 % no desborda y se describe completa', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        ListView(
          padding: const EdgeInsets.all(16),
          children: [ActividadCard(tarea: _tarea(), ahora: _ahora, onTap: () {})],
        ),
        escala: 2,
      ),
    );
    expect(tester.takeException(), isNull);

    final etiqueta = tester.getSemantics(find.byType(ActividadCard)).label;
    expect(etiqueta, contains('09:00 a 11:00'));
    expect(etiqueta, contains('Lavar y desinfectar'));
    expect(etiqueta, contains('Le toca ahora'));
    expect(etiqueta, contains('compartida por 2 personas'));
    semantics.dispose();
  });

  testWidgets('tarjetas compacta y grande no desbordan con letra grande', (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              width: 160,
              child: ActividadCard(
                tarea: _tarea(),
                densidad: DensidadTarjeta.compacta,
                ahora: _ahora,
                trabajadorFilaId: '10',
                onTap: () {},
              ),
            ),
            const SizedBox(height: 12),
            ActividadCard(
              tarea: _tarea(),
              densidad: DensidadTarjeta.grande,
              ahora: _ahora,
              trabajadorActualId: '10',
              onTap: () {},
            ),
          ],
        ),
        escala: 1.6,
      ),
    );
    expect(tester.takeException(), isNull);
    // En la fila de María, la compartida dice con quién.
    expect(find.text('con Juan'), findsOneWidget);
    // En la agenda de María: "Con Juan Pérez".
    expect(find.text('Con Juan Pérez'), findsOneWidget);
  });

  testWidgets('controles del cronograma cumplen tamaño táctil, etiquetas y contraste', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FechaNavegador(
              titulo: 'Hoy, jueves 8 de octubre de 2026',
              unidad: 'Día',
              onAnterior: () {},
              onHoy: () {},
              onSiguiente: () {},
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TrabajadorFiltro(
                trabajadores: trabajadoresDe([_tarea()]),
                seleccionadoId: null,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 12),
            ResumenDiaTarjetas(
              resumen: contarPorGrupo([_tarea()], ahora: _ahora),
              seleccionado: null,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            ActividadCard(tarea: _tarea(), ahora: _ahora, onTap: () {}),
          ],
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('filtro de trabajador: la lista se abre justo debajo del botón', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? elegido = 'sin cambio';
    await tester.pumpWidget(
      _app(
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 300),
            Align(
              alignment: Alignment.centerLeft,
              child: TrabajadorFiltro(
                trabajadores: trabajadoresDe([_tarea()]),
                seleccionadoId: '20',
                onChanged: (id) => elegido = id,
              ),
            ),
          ],
        ),
      ),
    );
    // El botón dice a quién se está viendo.
    expect(find.text('Trabajador: Juan Pérez'), findsOneWidget);
    final boton = tester.getRect(find.byType(OutlinedButton));

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    final todos = tester.getRect(find.text('Todos los trabajadores'));
    final maria = tester.getRect(find.text('María Gómez'));
    // La lista aparece debajo del botón, no encima ni en otra parte.
    expect(todos.top, greaterThan(boton.bottom));
    expect(maria.top, greaterThan(todos.top));

    await tester.tap(find.text('María Gómez'));
    await tester.pumpAndSettle();
    expect(elegido, '10');
    expect(find.text('Todos los trabajadores'), findsNothing);
  });

  testWidgets('filtro de trabajador cerca del borde inferior: sube la página y abre debajo', (tester) async {
    tester.view.physicalSize = const Size(1280, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 600),
            Align(
              alignment: Alignment.centerLeft,
              child: TrabajadorFiltro(
                trabajadores: trabajadoresDe([_tarea()]),
                seleccionadoId: null,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 800),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    final boton = tester.getRect(find.byType(OutlinedButton));
    final todos = tester.getRect(find.text('Todos los trabajadores'));
    expect(todos.top, greaterThan(boton.bottom));
    expect(tester.getRect(find.text('Juan Pérez')).bottom, lessThan(700));
  });

  testWidgets('progreso del operario: texto y porcentaje', (tester) async {
    final p = progresoDelDia(
      [
        _tarea(id: 1, estado: 'APROBADA'),
        _tarea(id: 2, iniH: 12, finH: 13),
      ],
      ahora: _ahora,
    );
    await tester.pumpWidget(_app(TarjetaProgreso(progreso: p)));
    expect(find.text('Llevas 1 de 2'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('Te queda 1 actividad'), findsOneWidget);
  });

  testWidgets('cierre guiado: "No pude hacerla" exige motivo y avisa si es compartida', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    CerrarTareaResult? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  resultado = await Navigator.of(context).push<CerrarTareaResult>(
                    MaterialPageRoute(
                      builder: (_) => CerrarActividadPage(
                        tarea: _tarea(),
                        usuarioActualId: '10',
                      ),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Paso 1 de 3'), findsOneWidget);
    await tester.tap(find.text('No pude hacerla'));
    await tester.pumpAndSettle();

    // Sin motivo no avanza.
    await tester.tap(find.text('Siguiente: revisar'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe el motivo con al menos una palabra.'), findsOneWidget);

    // Motivo rápido llena el texto.
    await tester.tap(find.text('Llovió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siguiente: revisar'));
    await tester.pumpAndSettle();

    expect(find.text('Revisa antes de enviar'), findsOneWidget);
    expect(find.textContaining('compartida con Juan Pérez'), findsOneWidget);
    expect(find.text('No se pudo hacer'), findsOneWidget);

    await tester.tap(find.text('Enviar cierre'));
    await tester.pumpAndSettle();

    expect(resultado, isNotNull);
    expect(resultado!.accion, 'NO_COMPLETADA');
    expect(resultado!.observaciones, 'Llovió.');
    expect(resultado!.insumosUsados, isEmpty);
  });

  testWidgets('cierre guiado: "Sí, la terminé" devuelve COMPLETADA', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    CerrarTareaResult? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  resultado = await Navigator.of(context).push<CerrarTareaResult>(
                    MaterialPageRoute(
                      builder: (_) => CerrarActividadPage(
                        tarea: _tarea(ids: const ['10'], nombres: const ['María Gómez']),
                        usuarioActualId: '10',
                      ),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, la terminé'));
    await tester.pumpAndSettle();
    expect(find.text('Cuéntanos cómo quedó'), findsOneWidget);
    await tester.tap(find.text('Siguiente: revisar'));
    await tester.pumpAndSettle();
    // Sin compañeros no hay aviso de compartida.
    expect(find.textContaining('compartida con'), findsNothing);
    await tester.tap(find.text('Enviar cierre'));
    await tester.pumpAndSettle();
    expect(resultado?.accion, 'COMPLETADA');
  });
}
