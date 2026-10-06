import 'package:flutter_application_1/model/catalogo_operativo_model.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/model/novedad_cronograma_model.dart';
import 'package:flutter_application_1/model/preventiva_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _tareaJson([Map<String, dynamic> extra = const {}]) => {
  'id': 1,
  'descripcion': 'Poda A',
  'fechaInicio': '2026-03-02T12:00:00.000Z',
  'fechaFin': '2026-03-02T13:00:00.000Z',
  'duracionMinutos': 60,
  'prioridad': 2,
  'estado': 'ASIGNADA',
  'tipo': 'PREVENTIVA',
  'ubicacionId': 1,
  'elementoId': 2,
  ...extra,
};

Map<String, dynamic> _defJson([Map<String, dynamic> extra = const {}]) => {
  'id': 7,
  'conjuntoId': '900',
  'ubicacionId': 1,
  'elementoId': 2,
  'descripcion': 'Shock de piscina',
  'frecuencia': 'SEMANAL',
  'prioridad': 1,
  ...extra,
};

void main() {
  group('CategoriaTarea / PerfilOperativo', () {
    test('parsea una categoría con sus palabras clave y uso', () {
      final c = CategoriaTarea.fromJson({
        'id': 3,
        'nombre': 'Poda',
        'ordenProgramacion': 2,
        'colorHex': '#558B2F',
        'palabrasClave': ['poda', 'deshoje'],
        'activa': false,
        'preventivas': 12,
      });
      expect(c.id, 3);
      expect(c.ordenProgramacion, 2);
      expect(c.palabrasClave, ['poda', 'deshoje']);
      expect(c.activa, isFalse);
      expect(c.preventivas, 12);
    });

    test('valores por defecto seguros cuando faltan campos', () {
      final c = CategoriaTarea.fromJson({'id': 1, 'nombre': 'X'});
      expect(c.activa, isTrue);
      expect(c.palabrasClave, isEmpty);
      expect(c.preventivas, 0);
      expect(c.ordenProgramacion, 100);
    });

    test('parsea un perfil con capacidades y arma su etiqueta de roles', () {
      final p = PerfilOperativo.fromJson({
        'id': 5,
        'nombre': 'Todero-Salvavidas',
        'roles': ['TODERO', 'SALVAVIDAS'],
        'categoriasIds': [2, 3, 6],
        'plazas': 5,
      });
      expect(p.etiquetaRoles, 'Todero-Salvavidas');
      expect(p.categoriasIds, [2, 3, 6]);
      expect(p.activo, isTrue);
      expect(p.plazas, 5);
    });

    test('resultados de sugerencias y de asignación en lote', () {
      final s = SugerenciasCategoriaResultado.fromJson({
        'sugerencias': [
          {
            'defId': 1,
            'descripcion': 'Poda Cesped',
            'categoriaId': 2,
            'categoriaNombre': 'Poda',
            'coincidencias': ['poda', 'cesped'],
          },
        ],
        'sinSugerencia': [
          {'defId': 9, 'descripcion': 'Reunión'},
        ],
      });
      expect(s.sugerencias.single.categoriaNombre, 'Poda');
      expect(s.sinSugerencia.single.defId, 9);

      final a = AsignacionCategoriaResultado.fromJson({
        'actualizadas': 2,
        'omitidas': [
          {'id': 4, 'descripcion': 'X', 'motivo': 'No habilitada'},
        ],
      });
      expect(a.actualizadas, 2);
      expect(a.omitidas.single.motivo, 'No habilitada');
    });
  });

  group('NecesidadOperario con perfil', () {
    Map<String, dynamic> plaza([Map<String, dynamic> extra = const {}]) => {
      'id': 2,
      'conjuntoId': '900',
      'roles': ['TODERO'],
      'etiqueta': 'Todero #1',
      'orden': 0,
      ...extra,
    };

    test('lee perfil y categorías habilitadas', () {
      final n = NecesidadOperario.fromJson(
        plaza({
          'perfilId': 4,
          'perfil': {
            'id': 4,
            'nombre': 'Todero',
            'activo': true,
            'categorias': [
              {'categoriaId': 2},
              {'categoriaId': 3},
            ],
          },
        }),
      );
      expect(n.perfilId, 4);
      expect(n.perfilNombre, 'Todero');
      expect(n.perfilCategoriasIds, [2, 3]);
      expect(n.admiteCategoria(2), isTrue);
      expect(n.admiteCategoria(6), isFalse);
    });

    test('un perfil sin categorías configuradas no bloquea (igual que el backend)', () {
      final n = NecesidadOperario.fromJson(
        plaza({
          'perfil': {'id': 4, 'nombre': 'Todero', 'categorias': []},
        }),
      );
      expect(n.admiteCategoria(6), isTrue);
    });

    test('datos antiguos sin perfil siguen funcionando', () {
      final n = NecesidadOperario.fromJson(plaza());
      expect(n.perfilId, isNull);
      expect(n.perfilNombre, isNull);
      expect(n.perfilActivo, isTrue);
      expect(n.perfilCategoriasIds, isEmpty);
    });
  });

  group('DefinicionPreventiva con categoría', () {
    test('lee categoría y orden interno', () {
      final d = DefinicionPreventiva.fromJson(
        _defJson({
          'categoriaId': 1,
          'ordenEnCategoria': 1,
          'categoria': {
            'id': 1,
            'nombre': 'Mantenimiento de piscinas',
            'ordenProgramacion': 1,
            'colorHex': '#0288D1',
            'activa': true,
          },
        }),
      );
      expect(d.prioridad, 1); // la prioridad de selección no cambia
      expect(d.categoriaId, 1);
      expect(d.categoria?.nombre, 'Mantenimiento de piscinas');
      expect(d.ordenEnCategoria, 1);
    });

    test('preventivas antiguas sin categoría', () {
      final d = DefinicionPreventiva.fromJson(_defJson());
      expect(d.categoriaId, isNull);
      expect(d.categoria, isNull);
      expect(d.ordenEnCategoria, isNull);
    });

    DefinicionPreventivaRequest req({
      bool incluir = false,
      int? categoriaId,
      int? orden,
    }) => DefinicionPreventivaRequest(
      ubicacionId: 1,
      elementoId: 2,
      descripcion: 'Shock',
      frecuencia: 'SEMANAL',
      prioridad: 2,
      incluirCategoria: incluir,
      categoriaId: categoriaId,
      ordenEnCategoria: orden,
    );

    test('sin incluirCategoria no se envía nada (no toca la categoría)', () {
      final json = req(categoriaId: 3, orden: 1).toJson();
      expect(json.containsKey('categoriaId'), isFalse);
      expect(json.containsKey('ordenEnCategoria'), isFalse);
    });

    test('con categoría envía categoriaId y orden', () {
      final json = req(incluir: true, categoriaId: 3, orden: 2).toJson();
      expect(json['categoriaId'], 3);
      expect(json['ordenEnCategoria'], 2);
    });

    test('quitar la categoría envía null y descarta el orden', () {
      final json = req(incluir: true, categoriaId: null, orden: 5).toJson();
      expect(json.containsKey('categoriaId'), isTrue);
      expect(json['categoriaId'], isNull);
      expect(json['ordenEnCategoria'], isNull);
    });
  });

  group('TareaModel / novedades', () {
    test('lee categoría, orden y reasignación automática', () {
      final t = TareaModel.fromJson(
        _tareaJson({
          'categoriaId': 2,
          'ordenEnCategoria': 1,
          'reasignadaAutomaticamente': true,
          'necesidadPrevistaId': 1,
        }),
      );
      expect(t.categoriaId, 2);
      expect(t.ordenEnCategoria, 1);
      expect(t.reasignadaAutomaticamente, isTrue);
      expect(t.necesidadPrevistaId, 1);
      final copia = t.copyWith(ordenEnCategoria: 3);
      expect(copia.ordenEnCategoria, 3);
      expect(copia.categoriaId, 2);
      expect(copia.reasignadaAutomaticamente, isTrue);
    });

    test('tareas antiguas sin categoría ni reasignación', () {
      final t = TareaModel.fromJson(_tareaJson());
      expect(t.categoriaId, isNull);
      expect(t.ordenEnCategoria, isNull);
      expect(t.reasignadaAutomaticamente, isFalse);
      expect(t.necesidadPrevistaId, isNull);
    });

    test('la novedad REASIGNADA_POR_CAPACIDAD se conserva como tipo propio', () {
      final n = NovedadCronogramaModel.fromJson({
        'tipo': 'REASIGNADA_POR_CAPACIDAD',
        'defId': 10,
        'descripcion': 'Poda A',
        'prioridad': 2,
        'fecha': '2026-03-02',
        'nuevaTareaIds': [55],
        'mensaje': 'La ejecuta Carlos.',
      });
      expect(n.tipo, 'REASIGNADA_POR_CAPACIDAD');
      expect(n.nuevaTareaIds, [55]);
      expect(n.mensaje, 'La ejecuta Carlos.');
    });
  });
}
