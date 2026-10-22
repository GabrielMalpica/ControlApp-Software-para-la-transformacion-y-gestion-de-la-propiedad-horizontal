import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pdf/cronograma_pdf.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/hoja_impresion.dart';
import 'package:flutter_application_1/widgets/cronograma/hoja_impresion_vista.dart';

/// Ruta opcional para guardar el PDF de muestra y revisarlo a ojo:
/// flutter test test/cronograma_impresion_test.dart --dart-define=PDF_SALIDA=C:/tmp/cronograma.pdf
const _salida = String.fromEnvironment('PDF_SALIDA');

/// Igual, para una imagen de la vista previa (--dart-define=PNG_SALIDA=...).
const _png = String.fromEnvironment('PNG_SALIDA');

/// Roboto (la de la app) y la fuente de íconos del SDK, para que las
/// muestras se vean como en la app. Sin FLUTTER_ROOT, los íconos salen en
/// blanco y las pruebas igual pasan.
Future<void> _cargarFuentes() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  await roboto.load();
  final iconos = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (iconos.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(ByteData.sublistView(iconos.readAsBytesSync())),
        ))
        .load();
  }
}

var _id = 0;

const _aseo = ('Aseo', '7B1FA2', 'limpieza');
const _jardin = ('Jardinería', '2E7D32', 'jardin');
const _piscina = ('Mantenimiento de piscinas', '0277BD', 'piscina');
const _manto = ('Mantenimientos básicos', 'EF6C00', 'mantenimiento');

const _yeimi = ('1', 'Yeimi Martínez Carrillo', 'Servicios generales');
const _daniel = ('2', 'Daniel Fernando Zuluaga Castañeda', 'Todero');
const _luis = ('3', 'Luis Alberto Tarache Ibica', 'Todero');
const _nicolas = ('4', 'Nicolás Mauricio Parra', 'Todero / Salvavidas');

TareaModel _t(
  (String, String, String) op,
  int dia,
  String ini,
  int minutos,
  String ubicacion,
  String elemento,
  String desc,
  (String, String, String) cat, {
  String estado = 'ASIGNADA',
  String tipo = 'PREVENTIVA',
  List<(String, String, String)> con = const [],
}) {
  final p = ini.split(':');
  final inicio = DateTime(2026, 10, dia, int.parse(p[0]), int.parse(p[1]));
  final ops = [op, ...con];
  return TareaModel(
    id: ++_id,
    descripcion: desc,
    fechaInicio: inicio,
    fechaFin: inicio.add(Duration(minutes: minutos)),
    duracionMinutos: minutos,
    borrador: false,
    estado: estado,
    tipo: tipo,
    ubicacionId: 1,
    elementoId: 1,
    ubicacionNombre: ubicacion,
    elementoNombre: elemento,
    operariosIds: [for (final o in ops) o.$1],
    operariosNombres: [for (final o in ops) o.$2],
    operariosCargos: [for (final o in ops) o.$3],
    categoriaNombre: cat.$1,
    categoriaColorHex: cat.$2,
    categoriaIcono: cat.$3,
  );
}

List<TareaModel> _tareas() {
  _id = 0;
  return [
    // Yeimi, jueves 1 (como en el ejemplo).
    _t(
      _yeimi,
      1,
      '07:00',
      120,
      'Torre 1',
      'Pisos, puertas y mobiliario',
      'Barrer y trapear pisos, limpiar puertas y paredes, retirar polvo y telarañas.',
      _aseo,
      estado: 'COMPLETADA',
    ),
    _t(
      _yeimi,
      1,
      '09:00',
      30,
      'Kiosco',
      'Baños',
      'Lavar y desinfectar sanitarios, lavamanos, espejos, puertas, pisos y canecas.',
      _aseo,
      estado: 'COMPLETADA',
    ),
    _t(
      _yeimi,
      1,
      '09:30',
      30,
      'Kiosco',
      'Jardines',
      'Realizar deshierbe, poda y retiro de residuos vegetales.',
      _jardin,
      estado: 'NO_COMPLETADA',
    ),
    _t(
      _yeimi,
      1,
      '10:00',
      20,
      'Torre 1',
      'Ascensores',
      'Limpiar y desinfectar cabina, botones, espejos, puertas, rieles y piso.',
      _aseo,
    ),
    _t(
      _yeimi,
      1,
      '10:20',
      90,
      'Kiosco',
      'Pisos, puertas, ventanas y mobiliario',
      'Barrer, trapear, limpiar puertas, paredes y retirar telarañas.',
      _aseo,
    ),
    _t(
      _yeimi,
      1,
      '11:50',
      10,
      'Oficina administración',
      'Ventanas',
      'Limpiar vidrios, marcos y retirar manchas.',
      _aseo,
    ),
    _t(
      _yeimi,
      1,
      '13:00',
      60,
      'Torre 1',
      'Ventanas',
      'Limpiar vidrios, marcos y retirar manchas.',
      _aseo,
    ),
    _t(
      _yeimi,
      1,
      '14:00',
      60,
      'Salón social',
      'Pisos, puertas, ventanas y mobiliario',
      'Barrer, trapear o lavar pisos; limpiar puertas y paredes.',
      _aseo,
    ),
    _t(
      _yeimi,
      1,
      '15:00',
      20,
      'Portería',
      'Pisos, puertas, ventanas y mobiliario',
      'Barrer y trapear pisos, limpiar puertas y paredes.',
      _aseo,
    ),
    // Yeimi, viernes 2: muchas actividades cortas seguidas.
    _t(
      _yeimi,
      2,
      '07:00',
      30,
      'Kiosco',
      'Baños',
      'Lavar y desinfectar sanitarios, lavamanos, espejos, puertas, pisos y canecas.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '07:30',
      120,
      'Torre 1',
      'Pisos, puertas y mobiliario',
      'Barrer y trapear pisos, limpiar puertas y paredes.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '09:30',
      90,
      'Torre 1',
      'Sótano',
      'Barrer, recoger residuos, limpiar rejillas, columnas y señalización.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '11:00',
      20,
      'Torre 1',
      'Ascensores',
      'Limpiar y desinfectar cabina, botones, espejos y piso.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '11:20',
      15,
      'Portería',
      'Mobiliario',
      'Limpiar, desempolvar escritorios, sillas y demás mobiliario.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '11:35',
      15,
      'Portería',
      'Ventanas',
      'Limpiar vidrios marcos y retirar manchas.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '11:50',
      10,
      'Oficina administración',
      'Ventanas',
      'Limpiar vidrios, marcos y retirar manchas.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '13:00',
      15,
      'Oficina administración',
      'Mobiliario',
      'Limpiar y desinfectar escritorios, sillas y mesas.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '13:15',
      90,
      'Kiosco',
      'Pisos, puertas, ventanas y mobiliario',
      'Barrer, trapear, limpiar puertas y paredes.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '14:45',
      20,
      'Salón social',
      'Baños',
      'Lavar y desinfectar sanitarios, lavamanos y espejos.',
      _aseo,
    ),
    _t(
      _yeimi,
      2,
      '15:05',
      30,
      'Kiosco',
      'Jardines',
      'Realizar deshierbe, poda y retiro de residuos vegetales.',
      _jardin,
    ),
    _t(
      _yeimi,
      3,
      '08:00',
      60,
      'Salón social',
      '',
      'Montaje para asamblea de copropietarios',
      _aseo,
      tipo: 'CORRECTIVA',
    ),
    // Daniel y Luis (toderos).
    _t(
      _daniel,
      1,
      '07:00',
      90,
      'Zonas comunes',
      'Luminarias',
      'Revisar y cambiar bombillos dañados.',
      _manto,
    ),
    _t(
      _daniel,
      1,
      '09:00',
      120,
      'Parque infantil',
      'Juegos',
      'Ajustar tornillería y pintar juegos.',
      _manto,
      con: [_luis],
    ),
    _t(
      _daniel,
      2,
      '07:00',
      240,
      'Zonas verdes',
      'Césped',
      'Corte de césped y bordes.',
      _jardin,
    ),
    _t(
      _luis,
      1,
      '07:00',
      60,
      'Cuarto de bombas',
      'Equipos',
      'Revisión de presión y fugas.',
      _manto,
    ),
    _t(
      _luis,
      2,
      '13:00',
      120,
      'Fachada',
      'Muro norte',
      'Resanar y pintar.',
      _manto,
    ),
    // Nicolás: piscina el fin de semana (sale el domingo).
    _t(
      _nicolas,
      3,
      '09:00',
      60,
      'Piscina',
      'Agua',
      'Medir cloro y pH, ajustar químicos.',
      _piscina,
    ),
    _t(
      _nicolas,
      3,
      '10:00',
      240,
      'Piscina',
      'Zona húmeda',
      'Salvavidas: vigilancia de bañistas.',
      _piscina,
    ),
    _t(
      _nicolas,
      4,
      '09:00',
      60,
      'Piscina',
      'Agua',
      'Medir cloro y pH, ajustar químicos.',
      _piscina,
    ),
    _t(
      _nicolas,
      4,
      '10:00',
      300,
      'Piscina',
      'Zona húmeda',
      'Salvavidas: vigilancia de bañistas.',
      _piscina,
    ),
    // Festivo del lunes 12 (Nicolás trabaja festivos).
    _t(
      _nicolas,
      12,
      '09:00',
      240,
      'Piscina',
      'Zona húmeda',
      'Salvavidas: vigilancia de bañistas.',
      _piscina,
    ),
  ];
}

final _horarios = [
  for (final d in ['LUNES', 'MARTES', 'MIERCOLES', 'JUEVES', 'VIERNES'])
    HorarioConjunto(
      dia: d,
      horaApertura: '07:00',
      horaCierre: '16:00',
      descansoInicio: '12:00',
      descansoFin: '13:00',
    ),
  HorarioConjunto(dia: 'SABADO', horaApertura: '07:00', horaCierre: '13:00'),
];

NecesidadOperario _plaza(
  int id,
  String etiqueta,
  String perfil,
  (String, String, String) op, {
  bool festivos = false,
}) => NecesidadOperario.fromJson({
  'id': id,
  'conjuntoId': '900',
  'roles': ['TODERO'],
  'etiqueta': etiqueta,
  'orden': id,
  'horarioEspecial': false,
  'activo': true,
  'operarioId': op.$1,
  'trabajaFestivos': festivos,
  if (festivos) 'festivoHoraApertura': '09:00',
  if (festivos) 'festivoHoraCierre': '17:00',
  'perfil': {'id': id, 'nombre': perfil},
});

final _necesidades = [
  _plaza(1, 'Aseadora #1', 'Operaria de aseo', _yeimi),
  _plaza(2, 'Todero #2', 'Operario todero', _daniel),
  _plaza(3, 'Todero #1', 'Operario todero', _luis),
  _plaza(
    4,
    'Todero-salvavidas #1',
    'Operario todero-salvavidas',
    _nicolas,
    festivos: true,
  ),
];

PlanImpresion _plan({
  List<TareaModel>? tareas,
  List<String>? soloIds,
  List<int> semanas = const [1],
  bool portada = false,
}) {
  final todas = tareas ?? _tareas();
  final equipo = trabajadoresDe(todas);
  return construirPlanImpresion(
    conjuntoNombre: 'Bosques de Morelia',
    anio: 2026,
    mes: 10,
    tareasMes: todas,
    equipo: equipo,
    operarios: soloIds == null
        ? equipo
        : equipo.where((e) => soloIds.contains(e.id)).toList(),
    semanas: semanas,
    horariosConjunto: _horarios,
    necesidades: _necesidades,
    festivos: const {'2026-10-12': 'Día de la Raza'},
    conPortada: portada,
  );
}

void _sinTarjetasEncimadas(HojaCronograma h) {
  for (final a in h.tarjetas) {
    expect(a.y, greaterThanOrEqualTo(0));
    expect(a.y + a.alto, lessThanOrEqualTo(MedidasHoja.altoGrilla + 0.01));
    for (final b in h.tarjetas) {
      if (identical(a, b)) continue;
      final mismaZona =
          a.x < b.x + b.ancho - 0.01 && b.x < a.x + a.ancho - 0.01;
      final seCruzan = a.y < b.y + b.alto - 0.01 && b.y < a.y + a.alto - 0.01;
      expect(
        mismaZona && seCruzan,
        isFalse,
        reason: '${a.titulo} pisa a ${b.titulo} (${h.operario.ref.nombre})',
      );
    }
  }
}

void main() {
  test('las semanas del mes empiezan el lunes de la semana del día 1', () {
    final semanas = semanasDelMes(2026, 10);
    expect(semanas.first, DateTime(2026, 9, 28));
    expect(semanas.length, 5);
  });

  test(
    'hoja de Yeimi: días fuera del mes, encabezado y tarjetas sin encimarse',
    () {
      final plan = _plan(soloIds: ['1']);
      expect(plan.portada, isNull);
      expect(
        plan.nombreArchivo,
        'Cronograma octubre 2026 - Semana 1 - Yeimi Martínez Carrillo.pdf',
      );
      final hojas = plan.hojas;
      expect(hojas, isNotEmpty);
      final h = hojas.first;
      expect(
        h.etiquetaSuperior,
        'BOSQUES DE MORELIA · SEMANA 1 · 1 AL 3 DE OCTUBRE',
      );
      expect(h.operario.subtitulo, 'Operaria de aseo · Aseadora #1');
      expect(h.dias.length, 6, reason: 'sin domingo: Yeimi no trabaja ese día');
      expect(
        h.dias.take(3).every((d) => d.fueraDelMes && d.mesAnterior),
        isTrue,
      );
      expect(h.dias[3].aviso, isNull);
      expect(h.programadoTexto, '15 h 55');
      for (final hoja in hojas) {
        _sinTarjetasEncimadas(hoja);
      }
      final tarjetas = hojas.expand((x) => x.tarjetas).toList();
      expect(
        tarjetas.where((t) => !t.continuaAntes).length,
        21,
        reason: 'cada actividad sale una vez (más las continuaciones)',
      );
      expect(
        tarjetas.firstWhere((t) => t.horaInicio == '07:00').marca,
        MarcaCierre.hecha,
      );
      expect(
        tarjetas.firstWhere((t) => t.titulo == 'Kiosco · Jardines').marca,
        MarcaCierre.noHecha,
      );
      final especial = tarjetas.firstWhere((t) => t.tarea.tipo == 'CORRECTIVA');
      expect(especial.visual.esEspecial, isTrue);
      expect(especial.titulo, 'Salón social');
    },
  );

  test(
    'las actividades cortas se leen: el día se parte en hojas sin cortar ninguna',
    () {
      final hojas = _plan(soloIds: ['1']).hojas;
      expect(hojas.length, greaterThan(1));
      for (final h in hojas) {
        expect(
          h.parteTexto,
          startsWith('Parte ${h.parte} de ${h.totalPartes}'),
        );
        for (final t in h.tarjetas.where(
          (t) => !t.continuaAntes && !t.continuaDespues,
        )) {
          expect(
            t.alto,
            greaterThanOrEqualTo(
              MedidasHoja.altoMinTarjeta -
                  MedidasHoja.separacionTarjetas -
                  0.01,
            ),
          );
        }
      }
      expect(
        hojas.expand((h) => h.tarjetas).any((t) => t.continuaDespues),
        isFalse,
      );
      expect(hojas.first.ventanaInicioMin, 7 * 60);
      expect(hojas.last.ventanaFinMin, 16 * 60);
      expect(hojas.where((h) => h.ultimaParte).length, 1);
    },
  );

  test('espacios libres y descanso salen del horario del conjunto', () {
    final hojas = _plan(soloIds: ['1']).hojas;
    final franjas = hojas.expand((h) => h.franjas).toList();
    final libres = franjas.where((f) => f.tipo == TipoFranja.libre).toList();
    // Jueves: 15:20 a 16:00 queda libre.
    expect(
      libres.any((f) => f.inicioMin == 15 * 60 + 20 && f.finMin == 16 * 60),
      isTrue,
    );
    expect(
      libres.firstWhere((f) => f.inicioMin == 15 * 60 + 20).texto,
      'Libre · 40 min',
    );
    expect(
      franjas.any(
        (f) => f.tipo == TipoFranja.descanso && f.texto == 'Descanso',
      ),
      isTrue,
    );
  });

  test(
    'el domingo aparece si hay actividades y el festivo usa el horario de la plaza',
    () {
      final nico = _plan(soloIds: ['4'], semanas: [1, 3]).hojas;
      final semana1 = nico.where((h) => h.semana == 1).first;
      expect(semana1.dias.length, 7);
      expect(semana1.dias.last.nombreCorto, 'DOM');
      final semana3 = nico.where((h) => h.semana == 3).first;
      final lunes = semana3.dias.first;
      expect(lunes.festivo, isTrue);
      expect(lunes.aviso, 'Festivo: Día de la Raza');
      expect(semana3.tarjetas.where((t) => t.x < lunes.ancho).length, 1);
      final libresLunes = semana3.franjas.where(
        (f) => f.tipo == TipoFranja.libre && f.x < lunes.ancho,
      );
      // Horario festivo de la plaza: 09:00 a 17:00, vigilancia de 09:00 a 13:00.
      expect(libresLunes.single.inicioMin, 13 * 60);
      expect(libresLunes.single.finMin, 17 * 60);
    },
  );

  test('portada con categorías, puestos y operarios', () {
    final plan = _plan(portada: true);
    final p = plan.portada!;
    expect(
      plan.nombreArchivo,
      'Cronograma octubre 2026 - Semana 1 - Todos.pdf',
    );
    expect(p.etiquetaSuperior, 'CONJUNTO BOSQUES DE MORELIA · OCTUBRE 2026');
    expect(p.semanaTexto, 'Semana 1 · 1 al 4 de octubre');
    expect(p.categorias.map((c) => c.visual.nombre), contains('Aseo'));
    expect(p.categorias.last.visual.esEspecial, isTrue);
    expect(p.puestos.map((x) => x.nombre), [
      'Operaria de aseo',
      'Operario todero',
      'Operario todero-salvavidas',
    ]);
    expect(p.puestos[1].detalle, 'Todero #2 · Todero #1');
    expect(p.operarios.length, 4);
    expect(p.operarios.map((o) => o.color).toSet().length, 4);
    // Cada operario conserva su color aunque se imprima solo.
    final solo = _plan(soloIds: ['3']).hojas.first.operario;
    expect(solo.color, p.operarios.firstWhere((o) => o.ref.id == '3').color);
    // La compartida de Daniel y Luis cuenta para los dos.
    expect(p.operarios.firstWhere((o) => o.ref.id == '3').actividades, 3);
  });

  test('sin hojas en blanco al imprimir el mes o a todo el equipo', () {
    // Luis solo tiene actividades en la semana 1.
    final mes = _plan(soloIds: ['3'], semanas: [1, 2, 3, 4, 5]).hojas;
    expect(mes.map((h) => h.semana).toSet(), {1});
    final equipoSemana3 = _plan(semanas: [3], portada: true);
    expect(equipoSemana3.hojas.map((h) => h.operario.ref.id).toSet(), {'4'});
    expect(equipoSemana3.portada!.operarios.map((o) => o.ref.id), ['4']);
    // Pedir justo esa semana de esa persona sí la imprime (horario libre).
    final soloSemana3 = _plan(soloIds: ['3'], semanas: [3]).hojas;
    expect(soloSemana3.length, 1);
    expect(soloSemana3.single.tarjetas, isEmpty);
    expect(soloSemana3.single.hayLibres, isTrue);
  });

  test('cortarVentanas evita partir actividades si puede', () {
    final cortes = cortarVentanas(
      7 * 60,
      16 * 60,
      maxMinutos: 200,
      cruza: (m) => m > 9 * 60 && m < 10 * 60 + 30,
    );
    expect(cortes.first.$1, 7 * 60);
    expect(cortes.last.$2, 16 * 60);
    for (var i = 0; i < cortes.length; i++) {
      expect(cortes[i].$2 - cortes[i].$1, lessThanOrEqualTo(195));
      if (i > 0) expect(cortes[i].$1, cortes[i - 1].$2);
      expect(cortes[i].$2 > 9 * 60 && cortes[i].$2 < 10 * 60 + 30, isFalse);
    }
  });

  testWidgets('genera el PDF con portada y hojas', (tester) async {
    await tester.runAsync(() async {
      await _cargarFuentes();
      final plan = _plan(portada: true);
      final bytes = await generarPdfCronograma(
        plan,
        generado: DateTime(2026, 10, 22),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      if (_salida.isNotEmpty) File(_salida).writeAsBytesSync(bytes);
    });
  });

  testWidgets('la vista previa dibuja portada y hojas como el PDF', (
    tester,
  ) async {
    await tester.runAsync(_cargarFuentes);
    final plan = _plan(portada: true);
    tester.view.physicalSize = const Size(900, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clave = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: clave,
              child: ColoredBox(
                color: const Color(0xFFE5E9E6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PapelImpresion(
                      etiqueta: 'Portada',
                      hoja: PortadaImpresionVista(portada: plan.portada!),
                    ),
                    for (var i = 0; i < plan.hojas.length; i++)
                      PapelImpresion(
                        etiqueta: 'Hoja ${i + 2}',
                        hoja: HojaImpresionVista(
                          hoja: plan.hojas[i],
                          pagina: i + 2,
                          paginas: plan.hojas.length + 1,
                          generado: DateTime(2026, 10, 22),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/logo.png'),
        tester.element(find.byType(Scaffold)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Cronograma de actividades por operario'), findsOneWidget);
    expect(find.text('Yeimi Martínez Carrillo'), findsWidgets);
    expect(find.text('Marcar al terminar'), findsNWidgets(plan.hojas.length));
    expect(find.text('Firma de quien recibe'), findsNWidgets(4));

    if (_png.isNotEmpty) {
      await tester.runAsync(() async {
        final borde =
            clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await borde.toImage(pixelRatio: 1.4);
        final datos = await img.toByteData(format: ui.ImageByteFormat.png);
        File(_png).writeAsBytesSync(datos!.buffer.asUint8List());
      });
    }

    // Tocar una hoja la abre en grande.
    await tester.tap(find.byType(PapelImpresion).first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Portada'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
