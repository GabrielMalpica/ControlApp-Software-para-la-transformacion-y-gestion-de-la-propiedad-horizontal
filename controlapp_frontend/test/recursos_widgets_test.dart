import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/recursos_api.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/pages/recursos/recursos_conjunto_page.dart';
import 'package:flutter_application_1/service/api_exception.dart';
import 'package:flutter_application_1/widgets/recursos/asignar_recurso_sheet.dart';
import 'package:flutter_application_1/widgets/recursos/resource_list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, dynamic> _candidato({
  required int id,
  required String etiqueta,
  required String grupo,
  required bool disponible,
  bool sugerida = false,
  String? motivo,
}) =>
    {
      'clase': 'MAQUINARIA',
      'unidadId': id,
      'etiqueta': etiqueta,
      'tipoNombre': 'Guadaña',
      'estado': 'OPERATIVA',
      'grupo': grupo,
      'origen': grupo == 'EMPRESA' ? 'EMPRESA' : 'CONJUNTO',
      'disponible': disponible,
      'sugerida': sugerida,
      'motivo': motivo,
    };

CandidatosResponse _candidatos({int pendientes = 1}) => CandidatosResponse.fromJson({
      'necesidad': {
        'id': 3,
        'clase': 'MAQUINARIA',
        'tipoNombre': 'Guadaña',
        'cantidad': pendientes,
        'asignadas': 0,
        'pendientes': pendientes,
      },
      'tarea': {
        'id': 10,
        'descripcion': 'Poda zonas comunes',
        'fechaInicio': '2031-06-04T12:00:00.000Z',
        'fechaFin': '2031-06-04T14:00:00.000Z',
        'conjuntoNombre': 'Conjunto A',
      },
      'grupo': {'tareasConPendiente': 0},
      'candidatos': [
        _candidato(id: 1, etiqueta: 'Guadaña · GUA-A1', grupo: 'CONJUNTO', disponible: true, sugerida: true),
        _candidato(id: 2, etiqueta: 'Guadaña · GUA-02', grupo: 'EMPRESA', disponible: true),
        _candidato(
          id: 3,
          etiqueta: 'Guadaña · GUA-01',
          grupo: 'EMPRESA',
          disponible: false,
          motivo: 'Ya está en uso por "Poda C" en Conjunto C.',
        ),
      ],
    });

class _FakeRecursosApi extends RecursosApi {
  _FakeRecursosApi({this.pendientes = 1, this.error, this.semana});

  final int pendientes;
  final Object? error;
  final SemanaConjuntoResponse? semana;
  final List<List<int>> reservas = [];

  @override
  Future<CandidatosResponse> candidatos({String? empresaNit, required int necesidadId}) async =>
      _candidatos(pendientes: pendientes);

  @override
  Future<List<String>> reservar({
    String? empresaNit,
    required int necesidadId,
    required List<CandidatoRecursoModel> unidades,
    bool aplicarAGrupo = false,
    String? observacion,
  }) async {
    if (error != null) throw error!;
    reservas.add(unidades.map((u) => u.unidadId).toList());
    return const [];
  }

  @override
  Future<SemanaConjuntoResponse> semanaConjunto({required String conjuntoId, DateTime? desde, int? dias}) async =>
      semana!;
}

Future<void> _montarSheet(WidgetTester tester, _FakeRecursosApi api) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AsignarRecursoSheet(necesidadId: 3, api: api, empresaNit: 'EMP'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Hoja de asignación de recursos', () {
    testWidgets('pre-selecciona la sugerida (del conjunto) y reserva solo lo confirmado', (tester) async {
      final api = _FakeRecursosApi();
      await _montarSheet(tester, api);

      expect(find.text('Del conjunto (1)'), findsOneWidget);
      expect(find.text('Préstamo de la empresa (1)'), findsOneWidget);
      expect(find.text('Sugerida'), findsOneWidget);
      expect(find.text('1 de 1 seleccionada(s)'), findsOneWidget);

      await tester.tap(find.text('Reservar'));
      await tester.pumpAndSettle();
      expect(api.reservas, [
        [1],
      ]);
    });

    testWidgets('las no disponibles se ven con su motivo y no se pueden elegir', (tester) async {
      final api = _FakeRecursosApi();
      await _montarSheet(tester, api);

      expect(find.textContaining('Poda C'), findsNothing);
      await tester.tap(find.text('No disponibles (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Poda C'), findsOneWidget);

      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      // GUA-A1 y GUA-02 seleccionables; GUA-01 deshabilitada.
      expect(checkboxes.last.onChanged, isNull);
      await tester.tap(find.text('Guadaña · GUA-01'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 1 seleccionada(s)'), findsOneWidget);
    });

    testWidgets('una necesidad de 2 se cubre mezclando conjunto + empresa', (tester) async {
      final api = _FakeRecursosApi(pendientes: 2);
      await _montarSheet(tester, api);

      expect(find.text('2 de 2 seleccionada(s)'), findsOneWidget);
      await tester.tap(find.text('Reservar'));
      await tester.pumpAndSettle();
      expect(api.reservas.single..sort(), [1, 2]);
    });

    testWidgets('si otra persona reservó primero se muestra el conflicto', (tester) async {
      final api = _FakeRecursosApi(
        error: ApiException(
          statusCode: 409,
          message: 'Guadaña · GUA-A1: Ya está en uso por "Poda B".',
          reason: 'RECURSO_OCUPADO',
          details: {
            'ok': false,
            'reason': 'RECURSO_OCUPADO',
            'title': 'El recurso no está disponible',
            'conflictos': [
              {'unidadEtiqueta': 'Guadaña · GUA-A1', 'motivo': 'Ya está en uso por "Poda B".'},
            ],
          },
        ),
      );
      await _montarSheet(tester, api);
      await tester.tap(find.text('Reservar'));
      // El botón muestra un spinner mientras el diálogo está abierto.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('El recurso no está disponible'), findsOneWidget);
      expect(find.text('Ya está en uso por "Poda B".'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('vista lista: unidad → día → conjunto, horario y tarea', (tester) async {
    final agenda = AgendaRecursosResponse.fromJson({
      'desde': '2031-06-02',
      'hasta': '2031-06-03',
      'dias': ['2031-06-02', '2031-06-03'],
      'totalUnidades': 1,
      'grupos': [
        {
          'clase': 'MAQUINARIA',
          'tipoNombre': 'Pulidora',
          'total': 1,
          'disponiblesHoy': 1,
          'unidades': [
            {
              'clase': 'MAQUINARIA',
              'id': 7,
              'codigo': 'PUL-01',
              'etiqueta': 'Pulidora · PUL-01',
              'tipoNombre': 'Pulidora',
              'propietarioTipo': 'EMPRESA',
              'ubicacionBase': 'Bodega de la empresa',
              'estadoActual': 'DISPONIBLE',
              'dias': [
                {'fecha': '2031-06-02', 'estado': 'RESERVADO', 'conjuntoNombre': 'Conjunto A'},
                {'fecha': '2031-06-03', 'estado': 'DISPONIBLE'},
              ],
              'reservas': [
                {
                  'id': 1,
                  'clase': 'MAQUINARIA',
                  'unidadId': 7,
                  'recursoEtiqueta': 'Pulidora · PUL-01',
                  'tipo': 'TAREA',
                  'estado': 'RESERVADA',
                  'origen': 'EMPRESA',
                  'conjuntoId': 'A',
                  'conjuntoNombre': 'Conjunto A',
                  'tareaDescripcion': 'Pulido salón social',
                  'usoInicio': DateTime(2031, 6, 2, 7).toUtc().toIso8601String(),
                  'usoFin': DateTime(2031, 6, 2, 10).toUtc().toIso8601String(),
                  'bloqueoInicio': DateTime(2031, 6, 2).toUtc().toIso8601String(),
                  'bloqueoFin': DateTime(2031, 6, 2, 23).toUtc().toIso8601String(),
                },
              ],
            },
          ],
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResourceListView(grupos: agenda.grupos, onTapReserva: (_, __) {}, onTapUnidad: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pulidora · PUL-01'), findsOneWidget);
    expect(find.textContaining('Conjunto A · 7:00'), findsOneWidget);
    expect(find.textContaining('Pulido salón social'), findsOneWidget);
    expect(find.text('Disponible'), findsWidgets);
  });

  group('Recursos del conjunto', () {
    SemanaConjuntoResponse semana({bool conDatos = false}) => SemanaConjuntoResponse.fromJson({
          'conjunto': {'nit': 'A', 'nombre': 'Conjunto A'},
          'desde': '2031-06-02',
          'hasta': '2031-06-08',
          'dias': ['2031-06-02'],
          'necesidades': [],
          'resumenNecesidades': {'total': 0},
          'recursosPropios': [],
          'recursosEmpresa': conDatos
              ? [
                  {
                    'fecha': '2031-06-03',
                    'reservas': [
                      {
                        'id': 9,
                        'clase': 'MAQUINARIA',
                        'unidadId': 2,
                        'recursoEtiqueta': 'Hidrolavadora · HID-02',
                        'tipo': 'TAREA',
                        'estado': 'RESERVADA',
                        'origen': 'EMPRESA',
                        'conjuntoNombre': 'Conjunto A',
                        'tareaDescripcion': 'Lavado de fachada',
                        'usoInicio': '2031-06-03T13:00:00.000Z',
                        'usoFin': '2031-06-03T16:00:00.000Z',
                        'bloqueoInicio': '2031-06-02T05:00:00.000Z',
                        'bloqueoFin': '2031-06-05T04:59:00.000Z',
                      },
                    ],
                  },
                ]
              : [],
        });

    testWidgets('estados vacíos', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RecursosConjuntoPage(conjuntoId: 'A', api: _FakeRecursosApi(semana: semana()))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ninguna tarea de esta semana pide maquinaria o herramientas.'), findsOneWidget);
      expect(find.text('Esta semana no llega ningún recurso de la empresa.'), findsOneWidget);
      expect(find.text('El conjunto no tiene maquinaria ni herramientas propias registradas.'), findsOneWidget);
    });

    testWidgets('muestra qué recursos de la empresa llegan y cuándo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecursosConjuntoPage(conjuntoId: 'A', api: _FakeRecursosApi(semana: semana(conDatos: true))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hidrolavadora · HID-02'), findsOneWidget);
      expect(find.textContaining('Lavado de fachada'), findsOneWidget);
      expect(find.textContaining('Entrega'), findsOneWidget);
    });
  });
}
