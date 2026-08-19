import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/model/zona_cronograma_model.dart';

void main() {
  test('ZonaCronogramaModel interpreta configuración efectiva', () {
    final zona = ZonaCronogramaModel.fromJson({
      'elementoId': 970,
      'nombre': 'Zonas humedas',
      'orden': 10,
      'colorHex': '#2196f3',
      'configurado': true,
    });

    expect(zona.elementoZonaId, 970);
    expect(zona.colorHex, '#2196F3');
    expect(zona.configurado, isTrue);
  });

  test('TareaModel conserva zona, agrupación y equipo', () {
    final tarea = TareaModel.fromJson({
      'id': 1,
      'descripcion': 'Aspirado de piscina',
      'fechaInicio': '2026-09-01T08:00:00.000Z',
      'fechaFin': '2026-09-01T09:00:00.000Z',
      'duracionMinutos': 60,
      'borrador': true,
      'ubicacionId': 224,
      'elementoId': 971,
      'operarios': [
        {
          'id': 'op-1',
          'usuario': {'nombre': 'Ana'},
        },
        {
          'id': 'op-2',
          'usuario': {'nombre': 'Luis'},
        },
      ],
      'ocurrenciaPlanId': 'occ-1',
      'grupoPlanId': 'grupo-1',
      'bloqueIndex': 2,
      'bloquesTotales': 3,
      'zonaCronograma': {
        'elementoId': 970,
        'nombre': 'Zonas humedas',
        'orden': 10,
        'colorHex': '#2196F3',
      },
    });

    expect(tarea.operariosIds.toSet(), {'op-1', 'op-2'});
    expect(tarea.zonaCronograma?.nombre, 'Zonas humedas');
    expect(tarea.ocurrenciaPlanId, 'occ-1');
    expect(tarea.bloqueIndex, 2);
    expect(tarea.bloquesTotales, 3);
  });
}
