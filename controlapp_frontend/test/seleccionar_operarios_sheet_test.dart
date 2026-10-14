import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/widgets/seleccionar_operarios_sheet.dart';

/// Abre la hoja con un botón y guarda lo que devuelve.
class _Anfitrion extends StatelessWidget {
  final List<OperarioElegible> candidatos;
  final List<String> actualesIds;
  final List<String> actualesNombres;
  final List<List<String>?> resultados;

  const _Anfitrion({
    required this.candidatos,
    required this.actualesIds,
    required this.resultados,
    this.actualesNombres = const [],
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultados.add(
                await seleccionarOperarios(
                  context,
                  candidatos: candidatos,
                  actualesIds: actualesIds,
                  actualesNombres: actualesNombres,
                ),
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('una tarea de A y B puede quedar en A y C', (tester) async {
    final resultados = <List<String>?>[];
    await tester.pumpWidget(
      _Anfitrion(
        candidatos: const [
          OperarioElegible(id: 'a', nombre: 'Ana'),
          OperarioElegible(id: 'b', nombre: 'Beto'),
          OperarioElegible(id: 'c', nombre: 'Carla'),
        ],
        actualesIds: const ['a', 'b'],
        resultados: resultados,
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    // Arranca con los actuales marcados y sin cambios no deja guardar.
    expect(find.text('Quedan: Ana, Beto'), findsOneWidget);
    final guardar = find.widgetWithText(FilledButton, 'Asignar a 2');
    expect(tester.widget<FilledButton>(guardar).onPressed, isNull);

    await tester.tap(find.text('Beto'));
    await tester.tap(find.text('Carla'));
    await tester.pumpAndSettle();
    expect(find.text('Quedan: Ana, Carla'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Asignar a 2'));
    await tester.pumpAndSettle();
    expect(resultados.single, ['a', 'c']);
  });

  testWidgets('el operario actual aparece aunque no venga sugerido', (
    tester,
  ) async {
    final resultados = <List<String>?>[];
    await tester.pumpWidget(
      _Anfitrion(
        candidatos: const [OperarioElegible(id: 'c', nombre: 'Carla')],
        actualesIds: const ['a'],
        actualesNombres: const ['Ana'],
        resultados: resultados,
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Operario actual'), findsOneWidget);

    // Sin nadie marcado no se puede guardar.
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Marca al menos un operario.'), findsOneWidget);
    final guardar = find.widgetWithText(FilledButton, 'Asignar');
    expect(tester.widget<FilledButton>(guardar).onPressed, isNull);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(resultados.single, isNull);
  });

  test('desdeSugerencia arma el detalle con horas o cruce', () {
    final libre = OperarioElegible.desdeSugerencia({
      'id': 7,
      'nombre': 'Luis',
      'horasSemana': 90,
      'solapa': false,
    });
    expect(libre.id, '7');
    expect(libre.conCruce, isFalse);
    expect(libre.detalle, contains('programadas esa semana'));

    final cruce = OperarioElegible.desdeSugerencia({
      'id': '8',
      'nombre': 'Rosa',
      'solapa': true,
    });
    expect(cruce.conCruce, isTrue);
    expect(cruce.detalle, 'Tiene cruce en ese horario');
  });
}
