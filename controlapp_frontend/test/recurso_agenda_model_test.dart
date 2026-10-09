import 'package:flutter_application_1/model/preventiva_model.dart';
import 'package:flutter_application_1/model/maquinaria_model.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/utils/interval_lanes.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> reservaJson({
  int id = 1,
  String tipo = 'TAREA',
  String estado = 'RESERVADA',
  String origen = 'EMPRESA',
  String usoInicio = '2031-06-04T12:00:00.000Z',
  String usoFin = '2031-06-04T15:00:00.000Z',
  String bloqueoInicio = '2031-06-02T05:00:00.000Z',
  String bloqueoFin = '2031-06-08T04:59:59.999Z',
}) =>
    {
      'id': id,
      'clase': 'MAQUINARIA',
      'unidadId': 7,
      'recursoEtiqueta': 'Pulidora · PUL-01',
      'tipo': tipo,
      'estado': estado,
      'origen': origen,
      'conjuntoId': 'A',
      'conjuntoNombre': 'Conjunto A',
      'tareaId': 10,
      'tareaDescripcion': 'Pulido salón social',
      'tareaEstado': 'ASIGNADA',
      'necesidadId': 3,
      'usoInicio': usoInicio,
      'usoFin': usoFin,
      'bloqueoInicio': bloqueoInicio,
      'bloqueoFin': bloqueoFin,
      'responsables': ['Ana', ''],
      'supervisor': null,
      'observacion': null,
      'motivoCancelacion': null,
      'duracionMinutos': 180,
      'creadoEn': '2031-06-01T00:00:00.000Z',
      'canceladoEn': null,
      'finalizadaEn': null,
    };

void main() {
  group('Modelos de la agenda de recursos', () {
    test('reserva: parsea fechas a hora local, flags y ventana logística', () {
      final r = ReservaRecursoModel.fromJson(reservaJson());
      expect(r.clase, ClaseRecurso.maquinaria);
      expect(r.vigente, isTrue);
      expect(r.esTarea, isTrue);
      expect(r.deEmpresa, isTrue);
      expect(r.tieneVentanaLogistica, isTrue);
      expect(r.usoInicio.isUtc, isFalse);
      expect(r.responsables, ['Ana']);

      final propia = ReservaRecursoModel.fromJson(reservaJson(
        origen: 'CONJUNTO',
        bloqueoInicio: '2031-06-04T12:00:00.000Z',
        bloqueoFin: '2031-06-04T15:00:00.000Z',
      ));
      expect(propia.tieneVentanaLogistica, isFalse);
    });

    test('agenda: grupos, unidades, días y estado actual', () {
      final resp = AgendaRecursosResponse.fromJson({
        'desde': '2031-06-02',
        'hasta': '2031-06-08',
        'dias': ['2031-06-02', '2031-06-03'],
        'totalUnidades': 1,
        'grupos': [
          {
            'clase': 'MAQUINARIA',
            'tipoId': 4,
            'tipoNombre': 'Pulidora',
            'total': 1,
            'disponiblesHoy': 0,
            'unidades': [
              {
                'clase': 'MAQUINARIA',
                'id': 7,
                'codigo': 'PUL-01',
                'nombre': 'Pulidora',
                'etiqueta': 'Pulidora · PUL-01',
                'tipoNombre': 'Pulidora',
                'estado': 'OPERATIVA',
                'reservable': true,
                'propietarioTipo': 'EMPRESA',
                'ubicacionBase': 'Bodega de la empresa',
                'estadoActual': 'EN_USO',
                'ubicacionActual': {'tipo': 'CONJUNTO', 'conjuntoId': 'A', 'nombre': 'Conjunto A'},
                'libreDesde': '2031-06-08T04:59:59.999Z',
                'dias': [
                  {'fecha': '2031-06-02', 'estado': 'EN_TRASLADO', 'conjuntoNombre': 'Conjunto A'},
                  {'fecha': '2031-06-03', 'estado': 'RESERVADO', 'conjuntoNombre': 'Conjunto A'},
                ],
                'reservas': [reservaJson()],
              },
            ],
          },
        ],
      });
      expect(resp.dias.first, DateTime(2031, 6, 2));
      final u = resp.grupos.single.unidades.single;
      expect(u.estadoActual, EstadoActualRecurso.enUso);
      expect(u.ubicacionActual, 'Conjunto A');
      expect(u.esDeEmpresa, isTrue);
      expect(u.dias.map((d) => d.estado), [EstadoDiaRecurso.enTraslado, EstadoDiaRecurso.reservado]);
      expect(u.reservas.single.tareaDescripcion, 'Pulido salón social');
    });

    test('necesidad y candidatos (grupo, disponibilidad, contexto)', () {
      final n = NecesidadRecursoModel.fromJson({
        'id': 3,
        'clase': 'HERRAMIENTA',
        'tipoId': 2,
        'tipoNombre': 'Escalera',
        'cantidad': 2,
        'obligatorio': false,
        'origen': 'PLAN_PREVENTIVA',
        'asignadas': 1,
        'pendientes': 1,
        'cobertura': 'PARCIAL',
        'asignable': true,
        'conflictos': [
          {'reservaId': 5, 'motivo': 'ESC-01 ya no está operativa.'},
        ],
        'tarea': {
          'id': 10,
          'descripcion': 'Limpieza de canales',
          'estado': 'ASIGNADA',
          'tipo': 'PREVENTIVA',
          'fechaInicio': '2031-06-04T12:00:00.000Z',
          'fechaFin': '2031-06-04T14:00:00.000Z',
          'conjuntoId': 'A',
          'conjuntoNombre': 'Conjunto A',
          'operarios': ['Ana'],
        },
        'reservas': [],
      });
      expect(n.clase, ClaseRecurso.herramienta);
      expect(n.cobertura, CoberturaNecesidad.parcial);
      expect(n.obligatorio, isFalse);
      expect(n.tieneConflicto, isTrue);

      final c = CandidatosResponse.fromJson({
        'necesidad': {'id': 3, 'clase': 'MAQUINARIA', 'tipoNombre': 'Guadaña', 'cantidad': 2, 'asignadas': 0, 'pendientes': 2},
        'tarea': {
          'id': 10,
          'descripcion': 'Poda',
          'fechaInicio': '2031-06-04T12:00:00.000Z',
          'fechaFin': '2031-06-04T14:00:00.000Z',
          'conjuntoNombre': 'Conjunto A',
        },
        'grupo': {'tareasConPendiente': 2},
        'candidatos': [
          {
            'clase': 'MAQUINARIA',
            'unidadId': 1,
            'etiqueta': 'Guadaña · GUA-01',
            'grupo': 'CUSTODIA',
            'origen': 'CONJUNTO',
            'disponible': true,
            'sugerida': true,
            'ventana': {'bloqueoInicio': '2031-06-04T12:00:00.000Z', 'bloqueoFin': '2031-06-04T14:00:00.000Z'},
            'reservaAnterior': {
              'reservaId': 9,
              'tipo': 'TAREA',
              'conjuntoNombre': 'Conjunto B',
              'usoInicio': '2031-06-02T12:00:00.000Z',
              'usoFin': '2031-06-02T14:00:00.000Z',
            },
          },
        ],
      });
      expect(c.pendientes, 2);
      expect(c.tareasDelGrupoConPendiente, 2);
      final cand = c.candidatos.single;
      expect(cand.grupo, GrupoCandidato.custodia);
      expect(cand.sugerida, isTrue);
      expect(cand.reservaAnterior?.conjuntoNombre, 'Conjunto B');
      expect(cand.reservaSiguiente, isNull);
    });

    test('conflictos de un 409 RECURSO_OCUPADO; otros errores no', () {
      final conflictos = ConflictoRecursoModel.desdeError({
        'ok': false,
        'reason': 'RECURSO_OCUPADO',
        'conflictos': [
          {
            'unidadEtiqueta': 'PUL-01',
            'motivo': 'PUL-01: Ya está en uso',
            'ocupadoPor': {
              'conjuntoNombre': 'Conjunto B',
              'tareaDescripcion': 'Pulido B',
              'bloqueoInicio': '2031-06-04T05:00:00.000Z',
              'bloqueoFin': '2031-06-07T04:59:00.000Z',
            },
          },
        ],
      });
      expect(conflictos.single.ocupadoConjunto, 'Conjunto B');
      expect(conflictos.single.ocupadoDesde, isNotNull);
      expect(ConflictoRecursoModel.desdeError({'reason': 'OTRO'}), isEmpty);
      expect(ConflictoRecursoModel.desdeError('texto'), isEmpty);
    });

    test('semana del conjunto e historial de la unidad', () {
      final semana = SemanaConjuntoResponse.fromJson({
        'conjunto': {'nit': 'A', 'nombre': 'Conjunto A'},
        'desde': '2031-06-02',
        'hasta': '2031-06-08',
        'dias': ['2031-06-02'],
        'necesidades': [],
        'resumenNecesidades': {'total': 0},
        'recursosPropios': [],
        'recursosEmpresa': [
          {'fecha': '2031-06-03', 'reservas': [reservaJson()]},
        ],
      });
      expect(semana.conjuntoNombre, 'Conjunto A');
      expect(semana.recursosEmpresa.single.fecha, DateTime(2031, 6, 3));
      expect(semana.recursosEmpresa.single.reservas.single.recursoEtiqueta, 'Pulidora · PUL-01');

      final h = HistorialUnidadResponse.fromJson({
        'unidad': {'etiqueta': 'PUL-01', 'tipoNombre': 'Pulidora', 'estado': 'DANADA', 'reservable': false},
        'estadoActual': {'estado': 'NO_OPERATIVA', 'ubicacion': {'nombre': 'Bodega de la empresa'}, 'libreDesde': null},
        'resumen': {'reservas': 3, 'finalizadas': 2, 'canceladas': 1, 'minutosDeUso': 300, 'conjuntosDistintos': 2},
        'reservas': [reservaJson(estado: 'FINALIZADA'), reservaJson(id: 2, estado: 'CANCELADA')],
      });
      expect(h.reservable, isFalse);
      expect(h.estadoActual, EstadoActualRecurso.noOperativa);
      expect(h.reservas.where((r) => r.cancelada), hasLength(1));
      expect(h.minutosDeUso, 300);
    });

    test('configuración logística ida y vuelta', () {
      final c = ConfigLogisticaRecursos.fromJson({'diasEntregaRecursos': [1, 3, 6], 'margenTrasladoMinutos': 0});
      expect(c.porHoras, isFalse);
      expect(c.toJson(), {'diasEntregaRecursos': [1, 3, 6], 'margenTrasladoMinutos': 0});
      expect(ConfigLogisticaRecursos.fromJson({'diasEntregaRecursos': [], 'margenTrasladoMinutos': 60}).porHoras, isTrue);
    });
  });

  group('Plan de recursos de la preventiva', () {
    test('se envía por tipo de catálogo con obligatorio; el legado sigue funcionando', () {
      expect(
        MaquinariaPlanItemRequest(tipoCatalogoId: 14, cantidad: 2, obligatorio: false).toJson(),
        {'tipoCatalogoId': 14, 'cantidad': 2, 'obligatorio': false},
      );
      expect(
        MaquinariaPlanItemRequest(tipo: TipoMaquinariaFlutter.GUADANIA).toJson(),
        {'tipo': 'GUADANIA', 'cantidad': 1, 'obligatorio': true},
      );
      expect(
        HerramientaPlanItemRequest(herramientaId: 3, cantidad: 2).toJson(),
        {'herramientaId': 3, 'cantidad': 2, 'obligatorio': true},
      );
      final leido = MaquinariaPlanItem.fromJson({'tipoCatalogoId': 14, 'cantidad': 2, 'obligatorio': false});
      expect(leido.tipoCatalogoId, 14);
      expect(leido.obligatorio, isFalse);
      expect(MaquinariaPlanItem.fromJson({'tipo': 'GUADANIA'}).obligatorio, isTrue);
    });

    test('la tarea lee recursosPlan (con cobertura) y el plan crudo', () {
      final t = TareaModel.fromJson({
        'id': 1,
        'descripcion': 'Poda',
        'fechaInicio': '2031-06-04T12:00:00.000Z',
        'fechaFin': '2031-06-04T14:00:00.000Z',
        'duracionMinutos': 120,
        'ubicacionId': 1,
        'elementoId': 1,
        'maquinariaPlanJson': [
          {'tipoCatalogoId': 4, 'cantidad': 2},
        ],
        'recursosPlan': [
          {
            'clase': 'MAQUINARIA',
            'tipoNombre': 'Guadaña',
            'cantidad': 2,
            'obligatorio': true,
            'asignadas': 1,
            'unidades': ['Guadaña · GUA-01'],
          },
          {
            'clase': 'HERRAMIENTA',
            'tipoNombre': 'Escalera',
            'cantidad': 1,
            'obligatorio': false,
            'asignadas': null,
            'unidades': [],
          },
        ],
      });
      expect(t.maquinariaPlan?.single.tipoCatalogoId, 4);
      expect(t.recursosPlan, hasLength(2));
      expect(t.recursosPlan.first.resumen, 'Guadaña × 2 · 1/2 asignadas · Guadaña · GUA-01');
      expect(t.recursosPlan.first.cubierta, isFalse);
      expect(t.recursosPlan.last.resumen, 'Escalera (opcional)');
    });
  });

  group('packIntervalsIntoLanes', () {
    DateTime h(int hora) => DateTime(2031, 6, 4, hora);

    test('intervalos que se cruzan van a carriles distintos; contiguos comparten', () {
      final out = packIntervalsIntoLanes([
        IntervalLaneInput(inicio: h(8), fin: h(12)),
        IntervalLaneInput(inicio: h(10), fin: h(13)),
        IntervalLaneInput(inicio: h(12), fin: h(14)),
      ]);
      expect(out.lanes.map((l) => l.lane), [0, 1, 0]);
      expect(out.laneCount, 2);
    });

    test('un préstamo largo y tareas dentro quedan en carriles separados', () {
      final out = packIntervalsIntoLanes([
        IntervalLaneInput(inicio: h(9), fin: h(10)),
        IntervalLaneInput(inicio: h(0), fin: DateTime(2031, 6, 10)),
        IntervalLaneInput(inicio: h(11), fin: h(12)),
      ]);
      // El largo (inicia antes) toma el carril 0; las tareas comparten el 1.
      expect(out.lanes.map((l) => l.lane), [1, 0, 1]);
      expect(out.laneCount, 2);
    });

    test('lista vacía', () {
      final out = packIntervalsIntoLanes(const []);
      expect(out.lanes, isEmpty);
      expect(out.laneCount, 1);
    });
  });
}
