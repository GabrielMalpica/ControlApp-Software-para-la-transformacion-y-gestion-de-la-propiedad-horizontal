import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/model/compromiso_model.dart';

void main() {
  test('lee estado e historial de seguimiento de una PQRS', () {
    final item = CompromisoModel.fromJson({
      'id': 4,
      'titulo': 'Reparar luminaria',
      'estado': 'EN_PROCESO',
      'estadoLabel': 'En proceso',
      'completado': false,
      'actualizaciones': [
        {
          'id': 12,
          'estado': 'EN_PROCESO',
          'estadoLabel': 'En proceso',
          'observacion': 'El repuesto fue solicitado',
          'evidencias': ['https://drive.google.com/file/d/abc123456789/view'],
          'actorNombre': 'Gerente Uno',
          'actorRol': 'Gerente',
          'creadaEn': '2026-11-14T12:30:00.000Z',
        },
      ],
    });

    expect(item.estado, 'EN_PROCESO');
    expect(item.estadoLabel, 'En proceso');
    expect(item.actualizaciones, hasLength(1));
    expect(
      item.actualizaciones.single.observacion,
      'El repuesto fue solicitado',
    );
    expect(item.actualizaciones.single.evidencias, hasLength(1));
    expect(item.actualizaciones.single.actorLabel, 'Gerente Uno · Gerente');
  });

  test('mantiene compatibilidad con PQRS previas al campo de estado', () {
    final abiertas = CompromisoModel.fromJson({
      'id': 5,
      'titulo': 'Solicitud antigua',
      'completado': false,
    });
    final cerradas = CompromisoModel.fromJson({
      'id': 6,
      'titulo': 'Solicitud cerrada',
      'completado': true,
    });

    expect(abiertas.estado, 'RECIBIDO');
    expect(cerradas.estado, 'CERRADO');
  });
}
