import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/model/planilla_usuario_model.dart';
import 'package:flutter_application_1/utils/planilla/planilla_tabla.dart';
import 'package:flutter_application_1/utils/planilla/vacaciones_planilla.dart';

final _hoy = DateTime(2026, 10, 22);

BloqueVacaciones _bloque(DateTime desde, DateTime hasta) =>
    BloqueVacaciones(desde: desde, hasta: hasta);

EstadoVacaciones _estado({
  DateTime? ingreso,
  DateTime? salida,
  DateTime? ultimas,
  List<BloqueVacaciones> bloques = const [],
  DateTime? hoy,
}) => calcularEstadoVacaciones(
  fechaIngreso: ingreso,
  fechaSalida: salida,
  fechaUltimasVacaciones: ultimas,
  bloques: bloques,
  hoy: hoy ?? _hoy,
);

PlanillaUsuario _persona({
  String cedula = '1001',
  String nombre = 'Ana Gómez',
  String rol = 'operario',
  List<ConjuntoPlanilla> conjuntos = const [],
  List<PlazaPlanilla> plazas = const [],
  String? observaciones,
}) => PlanillaUsuario(
  cedula: cedula,
  nombre: nombre,
  rol: rol,
  correo: '$cedula@correo.co',
  telefono: '3001234567',
  fechaNacimiento: DateTime(1990, 3, 15),
  fechaIngreso: DateTime(2022, 5, 1),
  eps: 'NUEVA_EPS',
  tipoSangre: 'O_POSITIVO',
  tallaPantalon: 'T_32',
  cursoAlturas: true,
  conjuntos: conjuntos,
  plazas: plazas,
  observaciones: observaciones,
);

const _bosque = ConjuntoPlanilla(nit: 'C-1', nombre: 'Bosque');
const _lago = ConjuntoPlanilla(nit: 'C-2', nombre: 'Lago');

void main() {
  group('días para vacaciones', () {
    test('sin fecha de ingreso no se calcula', () {
      final e = _estado();
      expect(e.tipo, TipoEstadoVacaciones.sinFechaIngreso);
      expect(e.texto, 'Sin fecha de ingreso');
    });

    test('retirado: fecha de retiro hoy o antes; una futura no cuenta', () {
      final e = _estado(
        ingreso: DateTime(2022, 5, 1),
        salida: DateTime(2026, 5, 3),
      );
      expect(e.tipo, TipoEstadoVacaciones.retirado);
      expect(e.texto, 'Retirado el 03/05/2026');
      expect(
        _estado(
          ingreso: DateTime(2022, 5, 1),
          salida: DateTime(2026, 12, 31),
        ).tipo,
        TipoEstadoVacaciones.pendientes,
      );
    });

    test('primer año: le tocan en el primer aniversario', () {
      final e = _estado(ingreso: DateTime(2026, 4, 1));
      expect(e.tipo, TipoEstadoVacaciones.primerAnio);
      expect(e.texto, 'Primer año · le tocan en 161 días');
      expect(e.proximoAniversario, DateTime.utc(2027, 4, 1));
      expect(
        _estado(ingreso: DateTime(2025, 10, 23)).texto,
        'Primer año · le tocan en 1 día',
      );
    });

    test('cumplió otro año sin tomarlas: pendientes desde el aniversario', () {
      final e = _estado(ingreso: DateTime(2022, 5, 1));
      expect(e.tipo, TipoEstadoVacaciones.pendientes);
      expect(e.texto, 'Pendientes desde el 01/05/2026 · hace 174 días');
      expect(e.diasParaAniversario, 191);
      expect(e.proximoAniversario, DateTime.utc(2027, 5, 1));
    });

    test('el día del aniversario le tocan desde hoy', () {
      final e = _estado(ingreso: DateTime(2020, 10, 22));
      expect(e.tipo, TipoEstadoVacaciones.pendientes);
      expect(e.texto, 'Le tocan desde hoy');
      expect(e.diasParaAniversario, 365);
      // También el día exacto del primer año.
      expect(
        _estado(ingreso: DateTime(2025, 10, 22)).texto,
        'Le tocan desde hoy',
      );
    });

    test(
      'ya tomó las de este año (Asistencia) y cuenta los días al próximo',
      () {
        final e = _estado(
          ingreso: DateTime(2022, 5, 1),
          bloques: [_bloque(DateTime(2026, 9, 7), DateTime(2026, 9, 14))],
        );
        expect(e.tipo, TipoEstadoVacaciones.yaTomo);
        expect(e.texto, 'Ya tomó las de este año · faltan 191 días');
        expect(e.ultimasVacaciones, DateTime.utc(2026, 9, 14));
      },
    );

    test(
      'también cuenta la fecha de últimas vacaciones de la hoja de vida',
      () {
        final e = _estado(
          ingreso: DateTime(2022, 5, 1),
          ultimas: DateTime(2026, 6, 10),
        );
        expect(e.tipo, TipoEstadoVacaciones.yaTomo);
        // Una fecha futura en la hoja de vida no cuenta como tomadas.
        expect(
          _estado(
            ingreso: DateTime(2022, 5, 1),
            ultimas: DateTime(2026, 12, 1),
          ).tipo,
          TipoEstadoVacaciones.pendientes,
        );
      },
    );

    test('vacaciones antes del último aniversario no cubren el período', () {
      final e = _estado(
        ingreso: DateTime(2022, 5, 1),
        bloques: [_bloque(DateTime(2026, 3, 1), DateTime(2026, 3, 15))],
      );
      expect(e.tipo, TipoEstadoVacaciones.pendientes);
      expect(e.ultimasVacaciones, DateTime.utc(2026, 3, 15));
      // Un bloque que termina después del aniversario sí lo cubre.
      expect(
        _estado(
          ingreso: DateTime(2022, 5, 1),
          bloques: [_bloque(DateTime(2026, 4, 25), DateTime(2026, 5, 5))],
        ).tipo,
        TipoEstadoVacaciones.yaTomo,
      );
    });

    test('de vacaciones hoy: muestra hasta cuándo', () {
      final e = _estado(
        ingreso: DateTime(2022, 5, 1),
        bloques: [_bloque(DateTime(2026, 10, 20), DateTime(2026, 11, 15))],
      );
      expect(e.tipo, TipoEstadoVacaciones.deVacaciones);
      expect(e.texto, 'De vacaciones hasta el 15/11');
      expect(
        _estado(
          ingreso: DateTime(2022, 5, 1),
          bloques: [_bloque(DateTime(2026, 12, 20), DateTime(2027, 1, 10))],
          hoy: DateTime(2026, 12, 28),
        ).texto,
        'De vacaciones hasta el 10/01/2027',
      );
    });

    test('vacaciones programadas en Asistencia: cuándo salen', () {
      final e = _estado(
        ingreso: DateTime(2022, 5, 1),
        bloques: [_bloque(DateTime(2026, 12, 10), DateTime(2026, 12, 24))],
      );
      expect(e.tipo, TipoEstadoVacaciones.programadas);
      expect(e.texto, 'Programadas del 10/12 al 24/12 · en 49 días');
      expect(
        _estado(
          ingreso: DateTime(2022, 5, 1),
          bloques: [_bloque(DateTime(2026, 10, 23), DateTime(2026, 10, 30))],
        ).texto,
        'Programadas del 23/10 al 30/10 · mañana',
      );
    });

    test('quien entró un 29 de febrero cumple el 28 en años no bisiestos', () {
      expect(
        aniversarioIngreso(DateTime(2024, 2, 29), 2027),
        DateTime.utc(2027, 2, 28),
      );
      expect(
        aniversarioIngreso(DateTime(2024, 2, 29), 2028),
        DateTime.utc(2028, 2, 29),
      );
      expect(
        _estado(
          ingreso: DateTime(2024, 2, 29),
          hoy: DateTime(2027, 2, 28),
        ).texto,
        'Le tocan desde hoy',
      );
    });

    test('la hora de "hoy" no cambia el resultado', () {
      expect(
        _estado(
          ingreso: DateTime(2022, 5, 1),
          hoy: DateTime(2026, 10, 22, 23, 59),
        ).texto,
        'Pendientes desde el 01/05/2026 · hace 174 días',
      );
    });

    test('el administrador (cliente) sin fecha de ingreso: no aplica', () {
      final admin = PlanillaUsuario(
        cedula: '9',
        nombre: 'Admin',
        rol: 'administrador',
      );
      expect(textoVacaciones(admin, _hoy), 'No aplica');
      final supervisor = PlanillaUsuario(
        cedula: '8',
        nombre: 'Sup',
        rol: 'supervisor',
      );
      expect(textoVacaciones(supervisor, _hoy), 'Sin fecha de ingreso');
    });
  });

  group('modelo', () {
    test('lee fechas como día calendario y ordena las vacaciones', () {
      final u = PlanillaUsuario.fromJson({
        'cedula': '1001',
        'nombre': 'Ana',
        'rol': 'operario',
        'activo': true,
        'telefono': '3001234567',
        'fechaNacimiento': '1990-03-15',
        'fechaIngreso': '2022-05-01T05:00:00.000Z',
        'funciones': ['ASEO', 'TODERO'],
        'conjuntos': [
          {'nit': 'C-1', 'nombre': 'Bosque'},
        ],
        'plazas': [
          {
            'etiqueta': 'Aseo #1',
            'conjuntoNit': 'C-2',
            'conjuntoNombre': 'Lago',
            'perfil': 'Aseo',
          },
        ],
        'vacaciones': [
          {'desde': '2026-12-10', 'hasta': '2026-12-24'},
          {'desde': '2026-09-07', 'hasta': '2026-09-14'},
          {'desde': 'mal', 'hasta': '2026-01-01'},
        ],
        'contrasena': 'nunca-se-usa',
      });
      expect(u.fechaNacimiento, DateTime(1990, 3, 15));
      expect(u.fechaIngreso, DateTime(2022, 5, 1));
      expect(u.vacaciones.map((b) => b.desde), [
        DateTime(2026, 9, 7),
        DateTime(2026, 12, 10),
      ]);
      expect(u.conjuntosTodos.map((c) => c.nombre), ['Bosque', 'Lago']);
      expect(diaDesdeJson(null), isNull);
    });

    test('lee ARL, caja y contacto de emergencia; vacío es sin dato', () {
      final u = PlanillaUsuario.fromJson({
        'cedula': '1001',
        'nombre': 'Ana',
        'rol': 'operario',
        'arl': 'POSITIVA',
        'cajaCompensacion': 'COMPENSAR',
        'contactoEmergenciaNombre': 'Luis Gómez',
        'contactoEmergenciaParentesco': 'Hermano',
        'contactoEmergenciaTelefono': '310 555 1234',
      });
      expect(u.arl, 'POSITIVA');
      expect(u.cajaCompensacion, 'COMPENSAR');
      expect(u.contactoEmergenciaNombre, 'Luis Gómez');
      expect(u.contactoEmergenciaParentesco, 'Hermano');
      expect(u.contactoEmergenciaTelefono, '310 555 1234');

      final sinDatos = PlanillaUsuario.fromJson({
        'cedula': '1002',
        'nombre': 'Beto',
        'rol': 'supervisor',
        'arl': null,
        'contactoEmergenciaNombre': '  ',
      });
      expect(sinDatos.arl, isNull);
      expect(sinDatos.cajaCompensacion, isNull);
      expect(sinDatos.contactoEmergenciaNombre, isNull);
    });
  });

  group('texto de las celdas', () {
    String valor(String clave, PlanillaUsuario u) =>
        columnaPlanilla(clave)!.valor(u, _hoy);

    test('etiquetas claras para los datos guardados como códigos', () {
      final u = _persona(
        plazas: const [
          PlazaPlanilla(
            etiqueta: 'Aseo #1',
            conjuntoNit: 'C-1',
            conjuntoNombre: 'Bosque',
          ),
        ],
      );
      expect(valor('eps', u), 'Nueva EPS');
      expect(valor('tipoSangre', u), 'O+');
      expect(valor('tallaPantalon', u), '32');
      expect(valor('cursoAlturas', u), 'Sí');
      expect(valor('fechaNacimiento', u), '15/03/1990');
      expect(valor('edad', u), '36 años');
      expect(valor('antiguedad', u), '4 años y 5 meses');
      expect(valor('rol', u), 'Operario');
      expect(valor('plaza', u), 'Aseo #1 · Bosque');
      expect(valor('conjuntos', u), 'Bosque');
      expect(etiquetaEnum('SALUD_TOTAL'), 'Salud Total');
      expect(etiquetaEnum('TERMINO_FIJO'), 'Término fijo');
      expect(etiquetaEnum(null), '');
      expect(etiquetaTipoSangre('AB_NEGATIVO'), 'AB-');
      expect(etiquetaTalla('F_8'), 'F8');
      expect(etiquetaRol('jefe_operaciones'), 'Jefe de operaciones');
    });

    test('ARL, caja y contacto de emergencia', () {
      const u = PlanillaUsuario(
        cedula: '1001',
        nombre: 'Ana',
        rol: 'operario',
        arl: 'HDI_LIBERTY',
        cajaCompensacion: 'COMFAMILIAR_NARINO',
        contactoEmergenciaNombre: 'Luis Gómez',
        contactoEmergenciaParentesco: 'Hermano',
        contactoEmergenciaTelefono: '+57 310 555 1234',
      );
      expect(valor('arl', u), 'HDI (antes Liberty)');
      expect(valor('cajaCompensacion', u), 'Comfamiliar Nariño');
      expect(valor('contactoEmergenciaNombre', u), 'Luis Gómez');
      expect(valor('contactoEmergenciaParentesco', u), 'Hermano');
      expect(valor('contactoEmergenciaTelefono', u), '+57 310 555 1234');

      final sinDatos = _persona();
      for (final clave in [
        'arl',
        'cajaCompensacion',
        'contactoEmergenciaNombre',
        'contactoEmergenciaParentesco',
        'contactoEmergenciaTelefono',
      ]) {
        expect(valor(clave, sinDatos), '', reason: clave);
      }
    });

    test('las columnas nuevas van junto a dirección y fondo de pensiones', () {
      final claves = columnasPlanilla.map((c) => c.clave).toList();
      final direccion = claves.indexOf('direccion');
      expect(claves.sublist(direccion + 1, direccion + 4), [
        'contactoEmergenciaNombre',
        'contactoEmergenciaParentesco',
        'contactoEmergenciaTelefono',
      ]);
      final fondo = claves.indexOf('fondoPensiones');
      expect(claves.sublist(fondo + 1, fondo + 3), ['arl', 'cajaCompensacion']);
    });

    test('antigüedad y edad', () {
      expect(antiguedad(DateTime(2026, 10, 1), null, _hoy), 'Menos de un mes');
      expect(antiguedad(DateTime(2026, 4, 1), null, _hoy), '6 meses');
      expect(antiguedad(DateTime(2025, 10, 22), null, _hoy), '1 año');
      expect(
        antiguedad(DateTime(2020, 1, 10), DateTime(2023, 3, 10), _hoy),
        '3 años y 2 meses',
      );
      expect(antiguedad(null, null, _hoy), '');
      expect(aniosCumplidos(DateTime(1990, 10, 23), _hoy), 35);
      expect(aniosCumplidos(DateTime(1990, 10, 22), _hoy), 36);
    });
  });

  group('orden y visibilidad de columnas', () {
    ConfigPlanilla soloCon(List<String> claves) {
      final base = ConfigPlanilla.porDefecto();
      final orden = [
        ...claves,
        ...base.orden.where((c) => !claves.contains(c)),
      ];
      return ConfigPlanilla(
        orden: orden,
        ocultas: base.orden.where((c) => !claves.contains(c)).toSet(),
      );
    }

    List<String> visibles(ConfigPlanilla c) =>
        c.visibles.map((x) => x.clave).toList();

    test('por defecto se ven todas, en el orden definido', () {
      final c = ConfigPlanilla.porDefecto();
      expect(visibles(c), columnasPlanilla.map((x) => x.clave).toList());
      expect(visibles(c).take(3), ['nombre', 'cedula', 'rol']);
    });

    test(
      'arrastrar: nombre·cédula·eps·conjunto → nombre·cédula·conjunto·eps',
      () {
        final c = soloCon(['nombre', 'cedula', 'eps', 'conjuntos']);
        expect(visibles(c.mover('conjuntos', 'eps')), [
          'nombre',
          'cedula',
          'conjuntos',
          'eps',
        ]);
        // Igual si se arrastra eps sobre conjunto (de izquierda a derecha).
        expect(visibles(c.mover('eps', 'conjuntos')), [
          'nombre',
          'cedula',
          'conjuntos',
          'eps',
        ]);
        expect(identical(c.mover('eps', 'eps'), c), isTrue);
        expect(identical(c.mover('eps', 'no-existe'), c), isTrue);
      },
    );

    test('las flechas mueven entre columnas visibles, saltando ocultas', () {
      final c = ConfigPlanilla.porDefecto().alternar('rol');
      final movida = c.moverUnPaso('cedula', 1);
      expect(visibles(movida).take(3), ['nombre', 'estado', 'cedula']);
      expect(visibles(c.moverUnPaso('cedula', -1)).take(2), [
        'cedula',
        'nombre',
      ]);
      expect(identical(c.moverUnPaso('nombre', -1), c), isTrue);
      expect(identical(c.moverUnPaso('observaciones', 1), c), isTrue);
    });

    test('ocultar y mostrar; la última columna visible no se oculta', () {
      final c = soloCon(['nombre']);
      expect(identical(c.alternar('nombre'), c), isTrue);
      final conCedula = c.alternar('cedula');
      expect(visibles(conCedula), ['nombre', 'cedula']);
      expect(visibles(conCedula.alternar('nombre')), ['cedula']);
      expect(conCedula.mostrarTodas().visibles.length, columnasPlanilla.length);
      expect(visibles(c.mover('cedula', 'nombre').restablecerOrden()), [
        'nombre',
      ]);
    });

    test('se guarda y se recupera igual', () {
      final c = soloCon([
        'cedula',
        'nombre',
        'vacaciones',
      ]).conAgrupacion(AgrupacionPlanilla.conjunto);
      final leida = ConfigPlanilla.fromJson(c.toJson());
      expect(visibles(leida), ['cedula', 'nombre', 'vacaciones']);
      expect(leida.agrupacion, AgrupacionPlanilla.conjunto);
    });

    test('lo guardado viejo o dañado se corrige', () {
      final porDefecto = ConfigPlanilla.porDefecto().orden;
      // Falta una columna nueva ("edad"): vuelve junto a la que la precede.
      final sinEdad = porDefecto.where((c) => c != 'edad').toList();
      final leida = ConfigPlanilla.fromJson({
        'orden': ['columna-vieja', ...sinEdad, 'nombre'],
        'ocultas': ['otra-vieja', 'eps'],
        'agrupacion': 'por-color',
      }, agrupacionPorDefecto: AgrupacionPlanilla.rol);
      expect(leida.orden, porDefecto);
      expect(leida.ocultas, {'eps'});
      expect(leida.agrupacion, AgrupacionPlanilla.rol);
      // Todas ocultas no se permite: vuelven a verse.
      final todasOcultas = ConfigPlanilla.fromJson({'ocultas': porDefecto});
      expect(todasOcultas.visibles.length, columnasPlanilla.length);
      expect(ConfigPlanilla.fromJson(const {}).orden, porDefecto);
    });

    test(
      'lo guardado antes de ARL, caja y contacto suma esas columnas visibles',
      () {
        const nuevas = {
          'arl',
          'cajaCompensacion',
          'contactoEmergenciaNombre',
          'contactoEmergenciaParentesco',
          'contactoEmergenciaTelefono',
        };
        // Orden guardado sin las columnas nuevas y con "Dirección" al inicio.
        final viejo = ConfigPlanilla.porDefecto().orden
            .where((c) => !nuevas.contains(c) && c != 'direccion')
            .toList();
        final leida = ConfigPlanilla.fromJson({
          'orden': ['direccion', ...viejo],
          'ocultas': ['eps'],
        });
        expect(leida.orden.take(4), [
          'direccion',
          'contactoEmergenciaNombre',
          'contactoEmergenciaParentesco',
          'contactoEmergenciaTelefono',
        ]);
        final fondo = leida.orden.indexOf('fondoPensiones');
        expect(leida.orden.sublist(fondo + 1, fondo + 3), [
          'arl',
          'cajaCompensacion',
        ]);
        expect(leida.ocultas, {'eps'});
        expect(
          leida.visibles.map((c) => c.clave).toSet().containsAll(nuevas),
          isTrue,
        );
      },
    );
  });

  group('agrupación', () {
    final ana = _persona(
      cedula: '1',
      nombre: 'Ana',
      conjuntos: [_bosque, _lago],
    );
    final beto = _persona(
      cedula: '2',
      nombre: 'Beto',
      plazas: const [
        PlazaPlanilla(
          etiqueta: 'Todero',
          conjuntoNit: 'C-2',
          conjuntoNombre: 'Lago',
        ),
      ],
    );
    final ceci = _persona(cedula: '3', nombre: 'Ceci', rol: 'gerente');
    final dani = _persona(
      cedula: '4',
      nombre: 'Dani',
      rol: 'administrador',
      conjuntos: [_bosque],
    );

    test('sin agrupar: un solo grupo sin título', () {
      final g = agruparPlanilla([ana, beto], AgrupacionPlanilla.ninguna);
      expect(g, hasLength(1));
      expect(g.first.titulo, '');
      expect(g.first.filas, [ana, beto]);
    });

    test(
      'por conjunto: quien está en varios sale en cada uno, sin conjunto al final',
      () {
        final g = agruparPlanilla([
          ana,
          beto,
          ceci,
          dani,
        ], AgrupacionPlanilla.conjunto);
        expect(g.map((x) => x.encabezado), [
          'Bosque · 2 personas',
          'Lago · 2 personas',
          'Sin conjunto · 1 persona',
        ]);
        expect(g[0].filas, [ana, dani]);
        expect(g[1].filas, [ana, beto]);
        expect(g[2].clave, isNull);
      },
    );

    test('por rol, en orden de jerarquía', () {
      final g = agruparPlanilla([
        ana,
        beto,
        ceci,
        dani,
      ], AgrupacionPlanilla.rol);
      expect(g.map((x) => x.titulo), [
        'Gerentes',
        'Administradores',
        'Operarios',
      ]);
      expect(g.last.filas, [ana, beto]);
    });
  });

  group('copiar para Excel', () {
    final columnas = [
      columnaPlanilla('nombre')!,
      columnaPlanilla('cedula')!,
      columnaPlanilla('eps')!,
      columnaPlanilla('observaciones')!,
    ];

    test('una celda nunca parte la fila ni empieza como fórmula', () {
      expect(
        celdaParaExcel('Calle 1\tBloque 2\nApto 3'),
        'Calle 1 Bloque 2 Apto 3',
      );
      expect(celdaParaExcel('=SUMA(A1)'), ' =SUMA(A1)');
      expect(celdaParaExcel('-no tiene'), ' -no tiene');
      expect(celdaParaExcel('+57 300'), ' +57 300');
      expect(celdaParaExcel('  normal  '), 'normal');
      expect(celdaParaExcel(''), '');
    });

    test('fila separada por tabuladores, con o sin títulos', () {
      final u = _persona(observaciones: 'Usa\tbotas\nnuevas');
      expect(
        filaParaExcel(u, columnas, _hoy),
        'Ana Gómez\t1001\tNueva EPS\tUsa botas nuevas',
      );
      expect(
        filaParaExcel(u, columnas, _hoy, conEncabezado: true),
        'Nombre\tCédula\tEPS\tObservaciones\n'
        'Ana Gómez\t1001\tNueva EPS\tUsa botas nuevas',
      );
    });

    test('la tabla sale como se ve: títulos, grupos y filas', () {
      final ana = _persona(cedula: '1', nombre: 'Ana', conjuntos: [_bosque]);
      final beto = _persona(cedula: '2', nombre: 'Beto');
      final cols = columnas.take(2).toList();
      expect(
        tablaParaExcel(
          agruparPlanilla([ana, beto], AgrupacionPlanilla.ninguna),
          cols,
          _hoy,
        ),
        'Nombre\tCédula\nAna\t1\nBeto\t2',
      );
      expect(
        tablaParaExcel(
          agruparPlanilla([ana, beto], AgrupacionPlanilla.conjunto),
          cols,
          _hoy,
        ),
        'Nombre\tCédula\n'
        'Bosque · 1 persona\nAna\t1\n'
        'Sin conjunto · 1 persona\nBeto\t2',
      );
    });
  });
}
