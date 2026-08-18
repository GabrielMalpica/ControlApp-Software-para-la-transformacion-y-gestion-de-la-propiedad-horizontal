import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter_application_1/model/cronograma_informe_jerarquico_model.dart';
import 'package:flutter_application_1/widgets/cronograma_informe_jerarquico.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets(
    'muestra tabla, árbol y tareas con cero horas usando texto legible',
    (tester) async {
      final informe = CronogramaInformeJerarquicoModel.fromJson({
        'periodo': {
          'anio': 2026,
          'mes': 8,
          'semanaInicio': '2026-08-03T00:00:00.000',
          'semanaFin': '2026-08-09T23:59:59.999',
        },
        'trazabilidadDisponible': true,
        'resumen': {
          'esperadas': 2,
          'conProgramacion': 1,
          'completas': 1,
          'parciales': 0,
          'sinProgramar': 1,
          'minutosEsperados': 120,
          'minutosProgramados': 60,
        },
        'operarios': [
          {'id': 'op-1', 'nombre': 'Ana'},
          {'id': 'op-2', 'nombre': 'Luis'},
        ],
        'ubicaciones': [
          {
            'id': 1,
            'nombre': 'Torre A',
            'resumen': {
              'esperadas': 2,
              'conProgramacion': 1,
              'completas': 1,
              'parciales': 0,
              'sinProgramar': 1,
              'minutosEsperados': 120,
              'minutosProgramados': 60,
            },
            'definiciones': [
              {
                'id': 'def:10',
                'definicionId': 10,
                'descripcion': 'Limpieza zona com\u00C3\u00BAn',
                'frecuencia': 'SEMANAL',
                'prioridad': 2,
                'elementoId': 2,
                'elementoNombre': 'Pasillo',
                'resumen': {
                  'esperadas': 2,
                  'conProgramacion': 1,
                  'completas': 1,
                  'parciales': 0,
                  'sinProgramar': 1,
                  'minutosEsperados': 120,
                  'minutosProgramados': 60,
                },
                'ocurrencias': [
                  {
                    'id': 'occ-1',
                    'fechaObjetivo': '2026-08-03T00:00:00.000',
                    'duracionEsperadaMin': 60,
                    'minutosProgramados': 60,
                    'estado': 'PROGRAMADA',
                    'reubicada': false,
                    'fechaRealInicio': '2026-08-03T08:00:00.000',
                    'fechaRealFin': '2026-08-03T09:00:00.000',
                    'operariosEsperados': [
                      {'id': 'op-1', 'nombre': 'Ana'},
                    ],
                    'bloques': const [],
                  },
                  {
                    'id': 'occ-2',
                    'fechaObjetivo': '2026-08-05T00:00:00.000',
                    'duracionEsperadaMin': 60,
                    'minutosProgramados': 0,
                    'estado': 'SIN_PROGRAMAR',
                    'reubicada': false,
                    'motivoCodigo': 'SIN_HUECO',
                    'motivoMensaje': 'No existe capacidad v\u00C3\u00A1lida.',
                    'operariosEsperados': [
                      {'id': 'op-2', 'nombre': 'Luis'},
                    ],
                    'bloques': const [],
                  },
                ],
              },
            ],
          },
        ],
      });
      String? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CronogramaInformeJerarquico(
                informe: informe,
                loading: false,
                operarioId: null,
                filtrarSemana: true,
                onFiltrarSemanaChanged: (_) {},
                onOperarioChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Torre A'), findsWidgets);
      expect(find.textContaining('Programadas 1/2'), findsWidgets);
      expect(find.text('Sin programar'), findsWidgets);
      expect(find.text('Limpieza zona común'), findsWidgets);
      expect(find.text('Limpieza zona com\u00C3\u00BAn'), findsNothing);
      expect(find.textContaining('0.0'), findsWidgets);
      expect(
        find.textContaining('No existe capacidad válida.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Todos los operarios'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luis').last);
      await tester.pumpAndSettle();
      expect(selected, 'op-2');
    },
  );
}
