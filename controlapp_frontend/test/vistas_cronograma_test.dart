import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/utils/cronograma/vistas_cronograma.dart';
import 'package:flutter_application_1/widgets/cronograma/vistas/vista_diaria.dart';
import 'package:flutter_application_1/widgets/cronograma/vistas/vista_mensual.dart';
import 'package:flutter_application_1/widgets/cronograma/vistas/vista_semanal.dart';
import 'package:flutter_application_1/widgets/cronograma/vistas/vista_ui.dart';

const _yeimi = ('10', 'YEIMI MARTINEZ CARRILLO');
const _luis = ('20', 'LUIS ALBERTO TARACHE IBICA');
const _nico = ('30', 'NICOLAS PARRA');

TareaModel tarea(
  int id, {
  int dia = 17,
  int mes = 11,
  String ini = '07:00',
  String fin = '08:00',
  String ubicacion = 'Torre 1',
  int ubicacionId = 1,
  String elemento = 'Zonas internas > Ascensores',
  String desc = 'Limpiar cabina',
  String? estado = 'ASIGNADA',
  String tipo = 'PREVENTIVA',
  List<(String, String)> ops = const [_yeimi],
}) {
  DateTime at(String hm) {
    final p = hm.split(':');
    return DateTime(2026, mes, dia, int.parse(p[0]), int.parse(p[1]));
  }

  return TareaModel(
    id: id,
    descripcion: desc,
    fechaInicio: at(ini),
    fechaFin: at(fin),
    duracionMinutos: at(fin).difference(at(ini)).inMinutes,
    borrador: false,
    estado: estado,
    tipo: tipo,
    ubicacionId: ubicacionId,
    ubicacionNombre: ubicacion,
    elementoId: 1,
    elementoNombre: elemento,
    operariosIds: [for (final o in ops) o.$1],
    operariosNombres: [for (final o in ops) o.$2],
  );
}

void main() {
  group('Operarios', () {
    test('nombre corto e iniciales', () {
      expect(nombreCortoOperario('YEIMI MARTINEZ CARRILLO'), 'Yeimi Martinez');
      expect(nombreCortoOperario('LUIS ALBERTO TARACHE IBICA'), 'Luis Tarache');
      expect(
        nombreCortoOperario('maria de los angeles perez'),
        'Maria Angeles',
      );
      expect(inicialesOperario('LUIS ALBERTO TARACHE IBICA'), 'LT');
      expect(inicialesOperario('Reynaldo'), 'R');
    });

    test('ordenados por carga, con color fijo e iniciales sin repetir', () {
      final tareas = [
        tarea(1, ops: [_luis]),
        tarea(2, ops: [_yeimi]),
        tarea(3, ops: [_yeimi]),
        tarea(4, ops: [('40', 'YESID MORALES')]),
      ];
      final ops = operariosDeTareas(tareas);
      expect(ops.map((o) => o.id), ['10', '20', '40']);
      expect(ops.map((o) => o.indiceColor), [0, 1, 2]);
      // Yeimi Martinez y Yesid Morales chocan en "YM".
      expect(ops[0].iniciales, 'YMa');
      expect(ops[2].iniciales, 'YMo');
    });

    test('completar agrega los de otro mes sin cambiar los colores', () {
      final base = operariosDeTareas([tarea(1)]);
      expect(identical(completarOperarios(base, [tarea(2)]), base), isTrue);
      final mas = completarOperarios(base, [
        tarea(3, ops: [_nico]),
      ]);
      expect(mas.length, 2);
      expect(mas.first.indiceColor, 0);
      expect(mas.last.id, '30');
      expect(mas.last.indiceColor, 1);
    });
  });

  group('Mensual', () {
    final tareas = [
      tarea(1, dia: 3),
      tarea(2, dia: 4),
      tarea(3, dia: 4, ops: [_luis], elemento: 'Ventanas', desc: 'Vidrios'),
      tarea(
        4,
        dia: 5,
        ubicacion: 'Piscina',
        ubicacionId: 7,
        elemento: 'Piscina',
        desc: 'Toma de parámetros',
        ops: [_luis],
      ),
      tarea(5, dia: 16, ops: [_nico]), // festivo
      tarea(6, dia: 22, ops: [_nico]), // domingo
    ];
    final indice = IndiceOperarios(operariosDeTareas(tareas));

    test('agrupa por ubicación con una fila por actividad', () {
      final m = construirMatrizMensual(
        tareas: tareas,
        operarios: indice,
        anio: 2026,
        mes: 11,
        agrupacion: AgrupacionMensual.ubicacion,
      );
      expect(m.grupos.map((g) => g.titulo), ['Torre 1', 'Piscina']);
      final torre = m.grupos.first;
      expect(torre.filas.first.titulo, 'Ascensores');
      expect(torre.filas.first.porDia.keys, containsAll([3, 4, 16, 22]));
      expect(torre.diasConActividad, 4);
      expect(m.totalPorDia[4], 2);
      expect(m.total, 6);
    });

    test('agrupa por operario y agrega las excluidas al final', () {
      final ex = PreventivaExcluidaBorradorModel(
        id: 9,
        descripcion: 'Podar',
        prioridad: 2,
        duracionMinutos: 60,
        fechaObjetivo: DateTime(2026, 11, 20),
        ubicacionId: 3,
        ubicacionNombre: 'Kiosko',
        elementoId: 1,
        elementoNombre: 'Zonas verdes > Jardines',
        operariosIds: const ['10'],
        operariosNombres: const ['YEIMI MARTINEZ CARRILLO'],
        motivoTipo: 'SIN_CAPACIDAD',
        estado: 'PENDIENTE',
      );
      final m = construirMatrizMensual(
        tareas: tareas,
        operarios: indice,
        anio: 2026,
        mes: 11,
        agrupacion: AgrupacionMensual.operario,
        excluidas: [ex],
      );
      expect(m.grupos.first.operario?.id, isNotNull);
      expect(m.grupos.last.esExcluidas, isTrue);
      expect(m.grupos.last.filas.single.titulo, 'Kiosko · Jardines');
    });

    test('resumen: vencidas, domingos/festivos y días hábiles', () {
      final r = resumirMes(
        tareas: [
          ...tareas,
          tarea(7, dia: 4, estado: 'COMPLETADA'),
        ],
        operarios: indice,
        anio: 2026,
        mes: 11,
        calendario: const CalendarioVista(
          festivos: {'2026-11-16': 'Independencia'},
        ),
        hoy: DateTime(2026, 11, 17, 10),
      );
      expect(r.tareas, 7);
      // 1, 2, 3, 4 y 5 abiertas antes del 17; la COMPLETADA no cuenta.
      expect(r.vencidas, 5);
      expect(r.ultimoDiaPasado, 16);
      expect(r.festivos.single.day, 16);
      expect(r.operariosDomingoFestivo.single.id, '30');
      expect(r.maxHabil, 3);
      expect(r.minHabil, 0);
      expect(r.cargas.first.tareas, greaterThan(0));
    });
  });

  group('Semanal', () {
    test('filas por operario, día más cargado y carga más baja hábil', () {
      final tareas = [
        tarea(1, dia: 17, ini: '07:00', fin: '09:00'),
        tarea(2, dia: 17, ini: '09:00', fin: '10:00'),
        tarea(3, dia: 18, ini: '07:00', fin: '07:30', ops: [_luis]),
        tarea(4, dia: 22, ini: '07:00', fin: '08:00', ops: [_luis]),
        tarea(5, dia: 25, ini: '07:00', fin: '08:00'), // otra semana
      ];
      final indice = IndiceOperarios(operariosDeTareas(tareas));
      final r = resumirSemana(
        inicioSemana: DateTime(2026, 11, 19),
        tareas: tareas,
        operarios: indice,
        calendario: const CalendarioVista(),
      );
      expect(r.inicio, DateTime(2026, 11, 16));
      expect(r.tareas, 4);
      expect(r.diaMasCargado, DateTime(2026, 11, 17));
      expect(r.maxMinutosCelda, 180);
      // El domingo 22 no cuenta como día hábil.
      expect(r.cargaMasBaja?.minutos, 30);
      expect(r.operarioCargaMasBaja?.id, '20');
      expect(r.minutos, 270);
    });
  });

  group('Diaria', () {
    test('las tareas que se cruzan van en carriles', () {
      final b = ubicarEnCarriles([
        tarea(1, ini: '07:00', fin: '08:00'),
        tarea(2, ini: '07:30', fin: '08:30'),
        tarea(3, ini: '09:00', fin: '10:00'),
      ]);
      final porId = {for (final x in b) x.tarea.id: x};
      expect(porId[1]!.carriles, 2);
      expect(porId[2]!.carril, 1);
      expect(porId[3]!.carriles, 1);
    });

    test('rango visible cubre la jornada y las tareas, y cuenta avance', () {
      final tareas = [
        tarea(1, ini: '06:30', fin: '07:30', estado: 'COMPLETADA'),
        tarea(2, ini: '15:00', fin: '17:10', estado: 'NO_COMPLETADA'),
        tarea(3, ini: '09:00', fin: '10:00', ops: [_luis]),
      ];
      final indice = IndiceOperarios(operariosDeTareas(tareas));
      final r = resumirDia(
        dia: DateTime(2026, 11, 17),
        tareas: tareas,
        operarios: indice,
        horaInicioJornada: 7,
        horaFinJornada: 16,
      );
      expect(r.desde, 6 * 60);
      expect(r.hasta, 18 * 60);
      expect(r.columnas.length, 2);
      expect(r.ejecutadas, 1);
      expect(r.noEjecutadas, 1);
      expect(r.avance, closeTo(2 / 3, 0.001));
    });
  });

  group('Widgets', () {
    final tareas = [
      tarea(1, dia: 16, ops: [_nico]),
      tarea(2, dia: 17),
      tarea(3, dia: 17, ini: '08:00', fin: '09:30', ops: [_luis]),
      tarea(4, dia: 18, tipo: 'CORRECTIVA', desc: 'Fuga'),
    ];
    final operarios = operariosDeTareas(tareas);
    const calendario = CalendarioVista(festivos: {'2026-11-16': 'Festivo'});

    Future<void> montar(WidgetTester tester, Widget hijo) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: hijo)));
      await tester.pump();
    }

    testWidgets('mensual muestra indicadores y abre el día', (tester) async {
      DateTime? abierto;
      await montar(
        tester,
        VistaMensualCronograma(
          anio: 2026,
          mes: 11,
          tareas: tareas,
          operarios: operarios,
          calendario: calendario,
          hoy: DateTime(2026, 11, 17, 9),
          agrupacion: AgrupacionMensual.ubicacion,
          onTapTarea: (_) {},
          onTapDia: (d) => abierto = d,
        ),
      );
      expect(find.text('Tareas del mes'), findsOneWidget);
      expect(find.text('Carga por operario'), findsOneWidget);
      expect(find.textContaining('Torre 1'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('18').first);
      expect(abierto, DateTime(2026, 11, 18));
    });

    testWidgets('semanal muestra una fila por operario', (tester) async {
      await montar(
        tester,
        VistaSemanalCronograma(
          inicioSemana: DateTime(2026, 11, 16),
          tareas: tareas,
          operarios: operarios,
          calendario: calendario,
          hoy: DateTime(2026, 11, 17, 9),
          onTapTarea: (_) {},
          onTapDia: (_) {},
        ),
      );
      expect(find.text('Tareas de la semana'), findsOneWidget);
      expect(find.text('Luis Tarache'), findsOneWidget);
      expect(find.text('Festivo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('semanal muestra las excluidas y deja programarlas', (
      tester,
    ) async {
      final ex = PreventivaExcluidaBorradorModel(
        id: 7,
        descripcion: 'Podar setos',
        prioridad: 2,
        duracionMinutos: 60,
        fechaObjetivo: DateTime(2026, 11, 18),
        ubicacionId: 3,
        ubicacionNombre: 'Kiosko',
        elementoId: 1,
        elementoNombre: 'Zonas verdes > Jardines',
        operariosIds: const ['10'],
        operariosNombres: const ['YEIMI MARTINEZ CARRILLO'],
        motivoTipo: 'SIN_CAPACIDAD',
        estado: 'PENDIENTE',
      );
      PreventivaExcluidaBorradorModel? tocada;
      var programar = 0;
      await montar(
        tester,
        VistaSemanalCronograma(
          inicioSemana: DateTime(2026, 11, 16),
          tareas: tareas,
          operarios: operarios,
          calendario: calendario,
          hoy: DateTime(2026, 11, 17, 9),
          onTapTarea: (_) {},
          onTapDia: (_) {},
          excluidas: [ex],
          onTapExcluida: (e) => tocada = e,
          onProgramarExcluidas: () => programar++,
        ),
      );
      expect(find.text('Excluidas de esta semana (1)'), findsOneWidget);
      await tester.tap(find.text('Kiosko · Jardines'));
      expect(tocada?.id, 7);
      await tester.tap(find.text('Ubicarlas arrastrando (Planeación)'));
      expect(programar, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('diaria muestra el detalle al tocar una tarea', (tester) async {
      var cambiar = 0;
      await montar(
        tester,
        VistaDiariaCronograma(
          dia: DateTime(2026, 11, 17),
          tareas: tareas,
          operarios: operarios,
          hoy: DateTime(2026, 11, 17, 9),
          horaInicio: 7,
          horaFin: 16,
          descansoInicio: 12 * 60,
          descansoFin: 13 * 60,
          acciones: (t) => [
            AccionTareaVista(
              texto: 'Cambiar responsable',
              icono: Icons.person_outline,
              onPressed: () => cambiar++,
            ),
          ],
          onAbrirDetalle: (_) {},
        ),
      );
      expect(find.text('Sin turno hoy'), findsOneWidget);
      expect(find.text('Sin tareas 12:00–13:00'), findsWidgets);
      await tester.tap(find.text('07:00 · Torre 1'));
      await tester.pump();
      expect(find.text('Detalle de la tarea'), findsOneWidget);
      await tester.tap(find.text('Cambiar responsable'));
      expect(cambiar, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
