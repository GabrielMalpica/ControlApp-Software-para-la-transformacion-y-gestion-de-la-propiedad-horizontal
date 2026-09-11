import 'package:flutter_application_1/model/inventario_activo_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsea una maquinaria física con catálogo, custodia y auditoría', () {
    final item = ActivoInventario.fromJson(<String, dynamic>{
      'id': 12,
      'codigoInterno': 'MAQ-000012',
      'tipoCatalogoId': 8,
      'tipoCatalogo': <String, dynamic>{'id': 8, 'nombre': 'Cortasetos'},
      'alias': 'Equipo de zonas verdes',
      'marca': 'Stihl',
      'modelo': 'HS 45',
      'serial': 'ABC-99',
      'estado': 'OPERATIVA',
      'estadoAprobacion': 'APROBADA',
      'propietarioTipo': 'EMPRESA',
      'prestada': true,
      'disponible': false,
      'ubicacionActual': <String, dynamic>{
        'nit': 'CONJ-1',
        'nombre': 'Conjunto A',
      },
      'fotoUrl': '/inventario/maquinaria/12/foto',
      'creadoPorId': 'ger-1',
      'creadoPorNombre': 'Gerente Uno',
      'creadoEn': '2026-09-08T15:30:00.000Z',
    }, ClaseActivoInventario.maquinaria);

    expect(item.nombreCatalogo, 'Cortasetos');
    expect(item.codigoInterno, 'MAQ-000012');
    expect(item.ubicacionActual?.nit, 'CONJ-1');
    expect(item.prestada, isTrue);
    expect(item.disponible, isFalse);
    expect(item.creadoPorNombre, 'Gerente Uno');
    expect(item.creadoEn, isNotNull);
  });

  test('parsea una herramienta individual y el resumen sin asumir campos', () {
    final item = ActivoInventario.fromJson(<String, dynamic>{
      'id': 4,
      'codigoInterno': 'HER-LOTE-001',
      'herramientaId': 3,
      'herramienta': <String, dynamic>{'id': 3, 'nombre': 'Destornillador'},
      'estado': 'EN_MANTENIMIENTO',
      'estadoAprobacion': 'PENDIENTE',
      'propietarioTipo': 'CONJUNTO',
      'prestada': false,
      'disponible': false,
    }, ClaseActivoInventario.herramienta);
    final summary = ResumenInventarioActivos.fromJson(<String, dynamic>{
      'maquinaria': 12,
      'herramientas': 27,
      'pendientes': 2,
    });

    expect(item.nombreCatalogo, 'Destornillador');
    expect(item.catalogoId, 3);
    expect(item.estadoAprobacion, 'PENDIENTE');
    expect(summary.maquinaria, 12);
    expect(summary.herramientas, 27);
    expect(summary.pendientes, 2);
  });
}
