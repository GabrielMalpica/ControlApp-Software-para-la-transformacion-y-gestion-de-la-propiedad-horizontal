import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/model/informe_detallado_opciones.dart';
import 'package:flutter_application_1/model/reporte_model.dart';

TareaDetalleRow _tarea({
  required int id,
  String tipo = 'PREVENTIVA',
  String? frecuencia = 'SEMANAL',
  String estado = 'APROBADA',
  String descripcion = 'Limpieza de pasillos',
  String? ubicacion = 'Torre 1',
  int dia = 1,
  List<String> evidencias = const [],
}) {
  return TareaDetalleRow(
    id: id,
    tipo: tipo,
    frecuencia: frecuencia,
    estado: estado,
    descripcion: descripcion,
    fechaInicio: DateTime(2026, 9, dia, 8),
    fechaFin: DateTime(2026, 9, dia, 9),
    duracionMinutos: 60,
    ubicacion: ubicacion,
    elemento: 'Pasillo',
    supervisor: null,
    operarios: const [],
    insumos: const [],
    maquinaria: const [],
    herramientas: const [],
    evidencias: evidencias,
  );
}

List<String> _fotos(int n, String prefijo) =>
    List.generate(n, (i) => 'https://ejemplo.com/$prefijo-$i.jpg');

void main() {
  group('opciones: JSON para el backend', () {
    test('las de siempre coinciden con los defaults del backend', () {
      final json = const OpcionesInformeDetallado().toJson();
      expect(json['organizacion'], 'ACTIVIDAD');
      expect(json['filtros'], {'soloConEvidencia': false});
      expect(json['secciones'], {
        'resumen': true,
        'cumplimiento': false,
        'detalle': true,
        'novedades': false,
        'reemplazadas': true,
        'consolidadoRecursos': false,
        'anexoTareas': false,
      });
      expect(json['fotos'], {
        'incluir': true,
        'porTarea': null,
        'registrosPorActividad': 'AUTO',
        'tamano': 'AUTO',
        'calidad': 'ESTANDAR',
      });
      expect(json['textos'], <String, dynamic>{});
    });

    test(
      'manda los registros por actividad como número y los filtros ordenados',
      () {
        final json = const OpcionesInformeDetallado(
          estados: {'NO_COMPLETADA', 'APROBADA'},
          registrosPorActividad: RegistrosConFoto.cinco,
          titulo: '  Informe de auditoría ',
        ).toJson();
        expect((json['fotos'] as Map)['registrosPorActividad'], 5);
        expect((json['filtros'] as Map)['estados'], [
          'APROBADA',
          'NO_COMPLETADA',
        ]);
        expect((json['textos'] as Map)['titulo'], 'Informe de auditoría');
      },
    );

    test('ida y vuelta sin perder nada', () {
      final o = OpcionesInformeDetallado.auditoria.copyWith(
        organizacion: OrganizacionInforme.cronologico,
        ubicaciones: () => {'Torre 1'},
        fotosPorTarea: () => 2,
        tamanoFotos: TamanoFoto.pequena,
        calidadFotos: CalidadFoto.alta,
        titulo: 'Informe de auditoría',
      );
      final copia = OpcionesInformeDetallado.fromJson(o.toJson());
      expect(copia.toJson(), o.toJson());
    });

    test('lo que se recuerda no incluye filtros ni observaciones del mes', () {
      final o = const OpcionesInformeDetallado(
        estados: {'APROBADA'},
        soloConEvidencia: true,
        observacionesGenerales: 'Notas de septiembre',
        titulo: 'Informe de auditoría',
      );
      final guardado = OpcionesInformeDetallado.fromJson(o.toPreferencias());
      expect(guardado.tieneFiltros, isFalse);
      expect(guardado.observacionesGenerales, isEmpty);
      expect(guardado.titulo, 'Informe de auditoría');
    });
  });

  group('opciones: plantillas y roles', () {
    test('reconoce la plantilla y pasa a personalizado al tocar algo', () {
      expect(
        const OpcionesInformeDetallado().plantilla,
        PlantillaInforme.estandar,
      );
      final auditoria = const OpcionesInformeDetallado().conPlantilla(
        PlantillaInforme.auditoria,
      );
      expect(auditoria.plantilla, PlantillaInforme.auditoria);
      expect(auditoria.seccion('anexoTareas'), isTrue);
      expect(auditoria.toJson()['secciones'], isNot(contains('firmas')));
      expect(auditoria.campo('puntualidad'), isTrue);
      expect(
        auditoria.conCampo('insumos', false).plantilla,
        PlantillaInforme.personalizado,
      );
      expect(OpcionesInformeDetallado.ejecutivo.incluirFotos, isFalse);
    });

    test('cambiar de plantilla conserva filtros y textos', () {
      final o = const OpcionesInformeDetallado(
        estados: {'APROBADA'},
        titulo: 'Mi informe',
      ).conPlantilla(PlantillaInforme.fotografico);
      expect(o.estados, {'APROBADA'});
      expect(o.titulo, 'Mi informe');
      expect(o.tamanoFotos, TamanoFoto.grande);
    });

    test('al administrador se le quitan los datos internos', () {
      final o = const OpcionesInformeDetallado()
          .conCampo('motivoRechazo', true)
          .conCampo('cerradoPor', true)
          .paraAdministrador();
      expect(o.campo('motivoRechazo'), isFalse);
      expect(o.campo('cerradoPor'), isFalse);
      // La plantilla de auditoría sigue reconociéndose para el cliente.
      expect(
        o
            .conPlantilla(PlantillaInforme.auditoria, esAdministrador: true)
            .plantilla,
        PlantillaInforme.auditoria,
      );
    });

    test('explica qué impide generar', () {
      final sinSecciones = const OpcionesInformeDetallado(secciones: {});
      expect(
        sinSecciones.errores,
        contains('Elige al menos una sección para el informe.'),
      );
      expect(
        const OpcionesInformeDetallado(estados: {}).errores,
        contains('Elige al menos un estado.'),
      );
      expect(const OpcionesInformeDetallado().errores, isEmpty);
    });
  });

  group('estimación', () {
    final diarias = List.generate(
      10,
      (i) => _tarea(
        id: i + 1,
        frecuencia: 'DIARIA',
        dia: i + 1,
        evidencias: _fotos(3, 'd$i'),
      ),
    );

    test('aplica la regla automática de las diarias y las fotos por tarea', () {
      expect(
        estimarInforme(diarias, const OpcionesInformeDetallado()).fotos,
        3,
      );
      expect(
        estimarInforme(
          diarias,
          const OpcionesInformeDetallado(
            fotosPorTarea: 2,
            registrosPorActividad: RegistrosConFoto.cinco,
          ),
        ).fotos,
        10,
      );
      expect(
        estimarInforme(
          diarias,
          const OpcionesInformeDetallado(
            registrosPorActividad: RegistrosConFoto.todos,
          ),
        ).fotos,
        30,
      );
      // En orden cronológico cada tarea es un bloque con todas sus fotos.
      expect(
        estimarInforme(
          diarias,
          const OpcionesInformeDetallado(
            organizacion: OrganizacionInforme.cronologico,
          ),
        ).fotos,
        30,
      );
    });

    test('filtra igual que el backend', () {
      final tareas = [
        _tarea(id: 1, estado: 'APROBADA', evidencias: _fotos(1, 'a')),
        _tarea(id: 2, estado: 'NO_COMPLETADA', ubicacion: 'Torre 2'),
        _tarea(id: 3, tipo: 'CORRECTIVA', frecuencia: null),
        _tarea(id: 4, frecuencia: 'DIARIA_LUNES_A_SABADO'),
      ];
      int contar(OpcionesInformeDetallado o) =>
          estimarInforme(tareas, o).tareas;
      expect(contar(const OpcionesInformeDetallado()), 4);
      expect(contar(const OpcionesInformeDetallado(tipos: {'CORRECTIVA'})), 1);
      expect(
        contar(const OpcionesInformeDetallado(estados: {'NO_COMPLETADA'})),
        1,
      );
      expect(
        contar(const OpcionesInformeDetallado(ubicaciones: {'torre 2'})),
        1,
      );
      expect(contar(const OpcionesInformeDetallado(soloConEvidencia: true)), 1);
      // La frecuencia solo filtra preventivas.
      expect(
        contar(const OpcionesInformeDetallado(frecuencias: {'DIARIA'})),
        2,
      );
    });

    test('respeta el tope de fotos y sin fotos no cuenta ninguna', () {
      final muchas = List.generate(
        50,
        (i) => _tarea(
          id: i + 1,
          tipo: 'CORRECTIVA',
          frecuencia: null,
          descripcion: 'Arreglo $i',
          evidencias: _fotos(10, 'c$i'),
        ),
      );
      final estandar = estimarInforme(muchas, const OpcionesInformeDetallado());
      expect(estandar.fotos, 400);
      expect(estandar.fotosOmitidasPorLimite, 100);
      expect(
        estimarInforme(
          muchas,
          const OpcionesInformeDetallado(calidadFotos: CalidadFoto.alta),
        ).fotos,
        250,
      );
      expect(
        estimarInforme(
          muchas,
          const OpcionesInformeDetallado(incluirFotos: false),
        ).fotos,
        0,
      );
    });

    test('arma los valores de los filtros con las tareas cargadas', () {
      final valores = ValoresFiltroInforme.desde([
        _tarea(id: 1, frecuencia: 'SEMANAL', ubicacion: 'Torre 2'),
        _tarea(
          id: 2,
          frecuencia: 'DIARIA',
          estado: 'NO_COMPLETADA',
          ubicacion: 'torre 2',
        ),
        _tarea(id: 3, tipo: 'CORRECTIVA', frecuencia: null, ubicacion: 'Lobby'),
      ]);
      expect(valores.estados, ['APROBADA', 'NO_COMPLETADA']);
      expect(valores.frecuencias, ['DIARIA', 'SEMANAL']);
      expect(valores.ubicaciones, ['Lobby', 'Torre 2']);
      expect(valores.hayPreventivas && valores.hayCorrectivas, isTrue);
      expect(frecuenciaBase('Diario'), 'DIARIA');
    });
  });
}
