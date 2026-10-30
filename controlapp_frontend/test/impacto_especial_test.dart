import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/impacto_correctiva_model.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/pages/crear_tarea_page.dart';
import 'package:flutter_application_1/utils/cronograma/impacto_especial.dart';
import 'package:flutter_application_1/widgets/cronograma/impacto_especial_dialog.dart';

final _dia = DateTime(2026, 10, 28);

TareaModel tarea(
  int id,
  String ini,
  String fin, {
  List<String> ids = const ['op-1'],
  List<String> nombres = const ['Pedro'],
  String tipo = 'PREVENTIVA',
  String estado = 'ASIGNADA',
  int prioridad = 2,
}) {
  DateTime at(String hm) {
    final p = hm.split(':');
    return DateTime(2026, 10, 28, int.parse(p[0]), int.parse(p[1]));
  }

  return TareaModel(
    id: id,
    descripcion: 'Tarea $id',
    fechaInicio: at(ini),
    fechaFin: at(fin),
    duracionMinutos: at(fin).difference(at(ini)).inMinutes,
    borrador: false,
    estado: estado,
    tipo: tipo,
    prioridad: prioridad,
    ubicacionId: 1,
    elementoId: 1,
    operariosIds: ids,
    operariosNombres: nombres,
  );
}

int m(int h, [int min = 0]) => h * 60 + min;

/// Jornada 7:00-16:00 con almuerzo 12:00-13:00.
const _jornada = [TramoDia(7 * 60, 12 * 60), TramoDia(13 * 60, 16 * 60)];

ImpactoLocalEspecial impacto(
  List<TareaModel> agenda, {
  Set<String> operarios = const {'op-1'},
  int prioridad = 2,
  required int deseado,
  int duracion = 60,
}) => calcularImpactoLocalEspecial(
  agendaDia: agenda,
  dia: _dia,
  operariosIds: operarios,
  prioridad: prioridad,
  deseado: deseado,
  duracion: duracion,
  rangosConjunto: _jornada,
);

void main() {
  group('calcularImpactoLocalEspecial', () {
    test(
      'las tareas de otros operarios no estorban (antes bloqueaban todo)',
      () {
        final r = impacto([
          tarea(1, '09:00', '10:00', ids: ['op-2'], nombres: ['Ana']),
        ], deseado: m(9));
        expect(r.libre, isTrue);
        expect(r.valido, isTrue);
        expect(r.inicio, m(9));
      },
    );

    test('60 min sobre tres tareas de 30 min: las tres se reemplazan', () {
      final r = impacto([
        tarea(1, '09:00', '09:30'),
        tarea(2, '09:30', '10:00'),
        tarea(3, '10:00', '10:30'),
        tarea(4, '10:30', '11:00'),
      ], deseado: m(9, 15));
      expect(r.valido, isTrue);
      expect(r.reemplazos.map((c) => c.tarea.id), [1, 2, 3]);
      expect(r.bloqueos, isEmpty);
    });

    test('con varios operarios reúne las tareas de todos', () {
      final r = impacto(
        [
          tarea(1, '09:00', '10:00'),
          tarea(2, '08:30', '10:30', ids: ['op-2'], nombres: ['Ana']),
          tarea(3, '09:00', '10:00', ids: ['op-3'], nombres: ['Luis']),
        ],
        operarios: {'op-1', 'op-2'},
        deseado: m(9),
      );
      expect(r.reemplazos.map((c) => c.tarea.id), [2, 1]);
      expect(r.operariosAfectados, {'Pedro', 'Ana'});
    });

    test('una tarea compartida avisa quién más la pierde', () {
      final r = impacto([
        tarea(
          1,
          '09:00',
          '10:00',
          ids: ['op-1', 'op-3'],
          nombres: ['Pedro', 'Luis'],
        ),
      ], deseado: m(9));
      expect(r.reemplazos.single.operariosEnActividad, ['Pedro']);
      expect(r.reemplazos.single.otrosOperarios, ['Luis']);
    });

    test('otra correctiva o una prioridad más alta lo impiden', () {
      final r = impacto(
        [
          tarea(1, '09:00', '10:00', tipo: 'CORRECTIVA'),
          tarea(2, '09:00', '10:00', ids: ['op-2'], prioridad: 1),
        ],
        operarios: {'op-1', 'op-2'},
        deseado: m(9),
      );
      expect(r.valido, isFalse);
      expect(r.bloqueos.map((c) => c.bloqueo), [
        MotivoBloqueoEspecial.noEsPreventiva,
        MotivoBloqueoEspecial.prioridad,
      ]);
    });

    test('una P1 sí reemplaza preventivas P1', () {
      final r = impacto(
        [tarea(1, '09:00', '10:00', prioridad: 1)],
        prioridad: 1,
        deseado: m(9),
      );
      expect(r.valido, isTrue);
      expect(r.reemplazos, hasLength(1));
    });

    test('las tareas cerradas no ocupan la agenda', () {
      final r = impacto([
        tarea(1, '09:00', '10:00', estado: 'COMPLETADA'),
        tarea(2, '09:00', '10:00', estado: 'NO_COMPLETADA'),
      ], deseado: m(9));
      expect(r.libre, isTrue);
    });

    test('cerca del almuerzo o del cierre se corre para caber', () {
      final antesAlmuerzo = impacto([], deseado: m(11, 30));
      expect(antesAlmuerzo.inicio, m(11));
      expect(antesAlmuerzo.ajustado, isTrue);

      final enAlmuerzo = impacto([], deseado: m(12, 30));
      expect([m(11), m(13)], contains(enAlmuerzo.inicio));

      final alCierre = impacto([], deseado: m(15, 30));
      expect(alCierre.inicio, m(15));
    });

    test('si dura más que cualquier bloque del día lo explica', () {
      final r = impacto([], deseado: m(8), duracion: 6 * 60);
      expect(r.valido, isFalse);
      expect(r.fueraDeHorario, contains('6 h'));
      expect(r.fueraDeHorario, contains('5 h'));
    });

    test('las horas en que la plaza ya trabaja cuentan como jornada', () {
      // Plaza con horario especial: tiene tareas hasta las 18:00.
      final r = impacto([tarea(1, '16:00', '18:00')], deseado: m(17));
      expect(r.fueraDeHorario, isNull);
      expect(r.inicio, m(17));
      expect(r.reemplazos.single.tarea.id, 1);
    });
  });

  group('primerHuecoLibre', () {
    test('busca solo en la agenda de los operarios indicados', () {
      final inicio = primerHuecoLibre(
        agendaDia: [
          tarea(1, '07:00', '09:00'),
          tarea(2, '09:00', '12:00', ids: ['op-2']),
        ],
        dia: _dia,
        operariosIds: {'op-1'},
        duracion: 60,
        rangos: _jornada,
        desde: m(7),
      );
      expect(inicio, m(9));
    });

    test('salta el almuerzo y, si no hay después, busca antes', () {
      expect(
        primerHuecoLibre(
          agendaDia: [tarea(1, '13:00', '16:00')],
          dia: _dia,
          operariosIds: {'op-1'},
          duracion: 60,
          rangos: _jornada,
          desde: m(14),
        ),
        m(7),
      );
    });
  });

  test('lee la previsualización del servidor', () {
    final i = ImpactoCorrectiva.fromJson({
      'ok': true,
      'fechaInicio': '2026-10-28T14:00:00.000Z',
      'fechaFin': '2026-10-28T15:00:00.000Z',
      'duracionMinutos': 60,
      'prioridad': 2,
      'libre': false,
      'puedeProgramar': true,
      'reemplazarIds': [1, 2],
      'reemplazos': [
        {
          'tareaId': 1,
          'descripcion': 'Barrer',
          'tipo': 'PREVENTIVA',
          'estado': 'ASIGNADA',
          'prioridad': 3,
          'fechaInicio': '2026-10-28T14:00:00.000Z',
          'fechaFin': '2026-10-28T14:30:00.000Z',
          'tipoConfirmacion': 'AUTO',
          'operarios': [
            {'id': 'op-1', 'nombre': 'Pedro', 'enLaActividad': true},
          ],
        },
      ],
      'bloqueos': [],
      'operarios': [
        {
          'operarioId': 'op-1',
          'nombre': 'Pedro',
          'enLaActividad': true,
          'reemplazadasIds': [1, 2],
          'huecos': [
            {
              'fechaInicio': '2026-10-28T15:00:00.000Z',
              'fechaFin': '2026-10-28T16:00:00.000Z',
              'minutos': 60,
              'grande': true,
            },
          ],
          'minutosHueco': 60,
          'huecoGrande': true,
        },
      ],
      'hayHuecoGrande': true,
      'bloqueosGenerales': [],
      'avisos': [
        {'codigo': 'FUERA_HORARIO_OPERARIO', 'mensaje': 'Fuera de jornada'},
      ],
      'sugerencia': {
        'fechaInicio': '2026-10-28T16:00:00.000Z',
        'fechaFin': '2026-10-28T17:00:00.000Z',
      },
    });
    expect(i.reemplazarIds, [1, 2]);
    expect(i.operarios.single.reemplazadasIds, [1, 2]);
    expect(i.operarios.single.huecos.single.grande, isTrue);
    expect(i.avisos.single.codigo, 'FUERA_HORARIO_OPERARIO');
    expect(i.sugerenciaInicio, isNotNull);
    expect(i.directo, isFalse);
  });

  group('operarios para asignar', () {
    Usuario op(String id, String nombre) => Usuario(
      cedula: id,
      nombre: nombre,
      correo: '$id@x.co',
      rol: 'operario',
      telefono: BigInt.one,
      fechaNacimiento: DateTime(1990),
    );

    NecesidadOperario plaza(int id, String etiqueta, String? operarioId) =>
        NecesidadOperario(
          id: id,
          conjuntoId: 'c1',
          roles: const ['TODERO'],
          etiqueta: etiqueta,
          orden: id,
          horarioEspecial: false,
          activo: true,
          operarioId: operarioId,
        );

    Conjunto conjunto(List<NecesidadOperario> plazas) => Conjunto(
      nit: 'c1',
      nombre: 'Conjunto',
      direccion: '',
      correo: '',
      activo: true,
      tipoServicio: const [],
      consignasEspeciales: const [],
      valorAgregado: const [],
      operarios: [op('1', 'Pedro'), op('2', 'Ana'), op('3', 'Ex operario')],
      necesidades: plazas,
    );

    test('solo quienes ocupan hoy una plaza', () {
      final c = conjunto([plaza(1, 'Todero 1', '1'), plaza(2, 'Aseo', '2')]);
      expect(operariosParaAsignar(c).map((u) => u.nombre), ['Pedro', 'Ana']);
      expect(plazasPorOperario(c), {'1': 'Todero 1', '2': 'Aseo'});
    });

    test('al editar conserva a quien ya tenía la tarea', () {
      final c = conjunto([plaza(1, 'Todero 1', '1')]);
      expect(
        operariosParaAsignar(c, conservarIds: ['3']).map((u) => u.nombre),
        ['Pedro', 'Ex operario'],
      );
    });

    test('sin plazas ocupadas ofrece a todos los del conjunto', () {
      final c = conjunto([plaza(1, 'Vacante', null)]);
      expect(operariosParaAsignar(c), hasLength(3));
    });
  });

  group('ImpactoEspecialDialog', () {
    setUpAll(() => initializeDateFormatting('es'));

    ImpactoCorrectiva conReemplazos({bool puede = true}) => ImpactoCorrectiva(
      fechaInicio: DateTime(2026, 10, 28, 9),
      fechaFin: DateTime(2026, 10, 28, 10),
      duracionMinutos: 60,
      prioridad: 2,
      libre: false,
      puedeProgramar: puede,
      reemplazarIds: const [1, 2],
      reemplazos: [
        TareaImpactada(
          tareaId: 1,
          descripcion: 'Barrer zonas comunes',
          tipo: 'PREVENTIVA',
          estado: 'ASIGNADA',
          prioridad: 3,
          fechaInicio: DateTime(2026, 10, 28, 9),
          fechaFin: DateTime(2026, 10, 28, 9, 30),
          operarios: const [
            OperarioDeTarea(id: 'op-1', nombre: 'Pedro', enLaActividad: true),
          ],
        ),
        TareaImpactada(
          tareaId: 2,
          descripcion: 'Poda',
          tipo: 'PREVENTIVA',
          estado: 'ASIGNADA',
          prioridad: 2,
          fechaInicio: DateTime(2026, 10, 28, 8, 30),
          fechaFin: DateTime(2026, 10, 28, 10, 30),
          operarios: const [
            OperarioDeTarea(id: 'op-2', nombre: 'Ana', enLaActividad: true),
            OperarioDeTarea(id: 'op-3', nombre: 'Luis', enLaActividad: false),
          ],
        ),
      ],
      operarios: [
        const OperarioImpactado(
          operarioId: 'op-1',
          nombre: 'Pedro',
          enLaActividad: true,
          reemplazadasIds: [1],
        ),
        const OperarioImpactado(
          operarioId: 'op-2',
          nombre: 'Ana',
          enLaActividad: true,
          reemplazadasIds: [2],
        ),
        OperarioImpactado(
          operarioId: 'op-3',
          nombre: 'Luis',
          enLaActividad: false,
          reemplazadasIds: const [2],
          huecos: [
            HuecoImpacto(
              fechaInicio: DateTime(2026, 10, 28, 8, 30),
              fechaFin: DateTime(2026, 10, 28, 10, 30),
              minutos: 120,
              grande: true,
            ),
          ],
          minutosHueco: 120,
          huecoGrande: true,
        ),
      ],
      sugerenciaInicio: DateTime(2026, 10, 28, 11),
      sugerenciaFin: DateTime(2026, 10, 28, 12),
    );

    Future<DecisionImpactoEspecial?> abrir(
      WidgetTester tester,
      ImpactoCorrectiva i,
    ) async {
      DecisionImpactoEspecial? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  decision = await mostrarImpactoEspecialDialog(
                    context,
                    descripcion: 'Reparar bomba',
                    etiqueta: 'Actividad especial',
                    impacto: i,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return decision;
    }

    testWidgets('muestra por persona lo que pierde y el hueco grande', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await abrir(tester, conReemplazos());
      expect(find.text('Se reemplazarán tareas'), findsOneWidget);
      expect(
        find.textContaining('Se reemplazarán 2 tareas de 3 personas'),
        findsOneWidget,
      );
      expect(find.text('Pedro'), findsOneWidget);
      expect(find.text('Luis'), findsOneWidget);
      expect(find.text('No está en la actividad'), findsOneWidget);
      expect(find.textContaining('Hueco grande'), findsOneWidget);
      expect(find.text('Reemplazar 2 tareas y programar'), findsOneWidget);
    });

    testWidgets('un motivo de 1 o 2 letras se corrige antes de enviar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await abrir(tester, conReemplazos());
      await tester.enterText(find.byType(TextField), 'ok');
      await tester.tap(find.text('Reemplazar 2 tareas y programar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('al menos 3 caracteres'), findsOneWidget);
    });

    testWidgets('bloqueado: sin botón de programar y ofrece el horario libre', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final bloqueado = ImpactoCorrectiva(
        fechaInicio: DateTime(2026, 10, 28, 9),
        fechaFin: DateTime(2026, 10, 28, 10),
        duracionMinutos: 60,
        prioridad: 2,
        libre: false,
        puedeProgramar: false,
        bloqueos: [
          TareaImpactada(
            tareaId: 9,
            descripcion: 'Fuga de agua',
            tipo: 'CORRECTIVA',
            estado: 'ASIGNADA',
            prioridad: 1,
            fechaInicio: DateTime(2026, 10, 28, 9),
            fechaFin: DateTime(2026, 10, 28, 10),
            motivo: 'NO_ES_PREVENTIVA',
            operarios: const [
              OperarioDeTarea(id: 'op-1', nombre: 'Pedro', enLaActividad: true),
            ],
          ),
        ],
        sugerenciaInicio: DateTime(2026, 10, 28, 11),
        sugerenciaFin: DateTime(2026, 10, 28, 12),
      );
      DecisionImpactoEspecial? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  decision = await mostrarImpactoEspecialDialog(
                    context,
                    descripcion: 'Reparar bomba',
                    etiqueta: 'Actividad especial',
                    impacto: bloqueado,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('No se puede programar a esta hora'), findsOneWidget);
      expect(
        find.textContaining('Ya es una actividad especial'),
        findsOneWidget,
      );
      expect(find.text('Programar'), findsNothing);
      await tester.tap(find.text('Usar este horario'));
      await tester.pumpAndSettle();
      expect(decision?.usarSugerencia, isTrue);
    });
  });
}
