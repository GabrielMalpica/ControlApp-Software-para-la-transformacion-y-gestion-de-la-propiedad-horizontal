import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/model/informe_detallado_opciones.dart';
import 'package:flutter_application_1/model/reporte_model.dart';
import 'package:flutter_application_1/widgets/informe_detallado_opciones_sheet.dart';

TareaDetalleRow _tarea(
  int id, {
  String estado = 'APROBADA',
  String ubicacion = 'Torre 1',
  List<String> evidencias = const [],
}) {
  return TareaDetalleRow(
    id: id,
    tipo: id.isEven ? 'PREVENTIVA' : 'CORRECTIVA',
    frecuencia: id.isEven ? 'SEMANAL' : null,
    estado: estado,
    descripcion: 'Tarea $id',
    fechaInicio: DateTime(2026, 9, id, 8),
    fechaFin: DateTime(2026, 9, id, 9),
    duracionMinutos: 60,
    ubicacion: ubicacion,
    elemento: 'Elemento',
    supervisor: null,
    operarios: const [],
    insumos: const [],
    maquinaria: const [],
    herramientas: const [],
    evidencias: evidencias,
  );
}

final _tareas = [
  _tarea(1, evidencias: const ['https://ejemplo.com/1.jpg']),
  _tarea(2, estado: 'NO_COMPLETADA', ubicacion: 'Torre 2'),
  _tarea(3),
  _tarea(4, evidencias: const ['https://ejemplo.com/4.jpg']),
];

/// Pantalla que abre el panel con un botón y guarda lo que devuelve.
class _Anfitrion extends StatefulWidget {
  final List<TareaDetalleRow> tareas;
  final bool esAdministrador;
  final List<OpcionesInformeDetallado?> resultados;

  const _Anfitrion({
    required this.tareas,
    required this.resultados,
    this.esAdministrador = false,
  });

  @override
  State<_Anfitrion> createState() => _AnfitrionState();
}

class _AnfitrionState extends State<_Anfitrion> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await mostrarOpcionesInformeDetallado(
              context,
              tareas: widget.tareas,
              esAdministrador: widget.esAdministrador,
            );
            widget.resultados.add(r);
          },
          child: const Text('Abrir panel'),
        ),
      ),
    );
  }
}

Future<void> _abrir(
  WidgetTester tester, {
  List<TareaDetalleRow>? tareas,
  bool esAdministrador = false,
  List<OpcionesInformeDetallado?>? resultados,
  double escala = 1,
  Size tamano = const Size(400, 900),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala)),
          child: _Anfitrion(
            tareas: tareas ?? _tareas,
            esAdministrador: esAdministrador,
            resultados: resultados ?? [],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir panel'));
  await tester.pumpAndSettle();
}

Finder get _generar => find.widgetWithText(FilledButton, 'Generar PDF');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('un doble toque en Generar cierra el panel una sola vez', (
    tester,
  ) async {
    final resultados = <OpcionesInformeDetallado?>[];
    await _abrir(tester, resultados: resultados);

    expect(find.textContaining('Incluye 4 tareas'), findsOneWidget);
    await tester.tap(_generar);
    await tester.tap(_generar, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(resultados, hasLength(1));
    expect(resultados.single, isNotNull);
    // La pantalla de abajo sigue ahí: no se cerró una ruta de más.
    expect(find.text('Abrir panel'), findsOneWidget);
  });

  testWidgets('recuerda la plantilla elegida para la próxima vez', (
    tester,
  ) async {
    final resultados = <OpcionesInformeDetallado?>[];
    await _abrir(tester, resultados: resultados);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Auditoría'));
    await tester.pumpAndSettle();
    await tester.tap(_generar);
    await tester.pumpAndSettle();
    expect(resultados.single!.plantilla, PlantillaInforme.auditoria);

    await tester.tap(find.text('Abrir panel'));
    await tester.pumpAndSettle();
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Auditoría'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('al administrador no le ofrece datos internos', (tester) async {
    await _abrir(tester, esAdministrador: true);
    await tester.scrollUntilVisible(
      find.text('Qué mostrar de cada tarea'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('(interno)'), findsNothing);
  });

  testWidgets('el gerente sí ve los datos internos', (tester) async {
    await _abrir(tester);
    await tester.scrollUntilVisible(
      find.text('Motivo de rechazo (interno)'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Motivo de rechazo (interno)'), findsOneWidget);
  });

  testWidgets('sin tareas que cumplan los filtros no deja generar', (
    tester,
  ) async {
    await _abrir(tester, tareas: [_tarea(1), _tarea(3)]);
    await tester.scrollUntilVisible(
      find.text('Solo tareas con evidencia'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    // Que no quede tapado por el pie fijo del panel.
    await tester.ensureVisible(find.text('Solo tareas con evidencia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solo tareas con evidencia'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ninguna tarea cumple los filtros elegidos.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_generar).onPressed, isNull);
  });

  testWidgets('la plantilla ejecutiva quita las fotos y no hay firmas', (
    tester,
  ) async {
    await _abrir(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ejecutivo (sin fotos)'));
    await tester.pumpAndSettle();
    expect(find.text('Incluir fotos de evidencia'), findsNothing);
    expect(find.textContaining('sin fotos'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Textos del informe'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('firma', findRichText: true), findsNothing);
    expect(find.textContaining('Elaboró'), findsNothing);
  });

  testWidgets('accesible con letra al 200 % en un celular', (tester) async {
    final semantics = tester.ensureSemantics();
    await _abrir(tester, escala: 2, tamano: const Size(390, 844));
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('en pantallas anchas se abre como diálogo', (tester) async {
    await _abrir(tester, tamano: const Size(1280, 900));
    expect(find.byType(Dialog), findsOneWidget);
    expect(_generar, findsOneWidget);
  });
}
