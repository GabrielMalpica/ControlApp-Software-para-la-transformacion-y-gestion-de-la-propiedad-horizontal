import 'package:flutter_application_1/model/solicitud_web_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Solicitudes de la página web', () {
    test('la postulación trae foto, documentos y datos de contacto', () {
      final pagina = PaginaWeb<PostulacionWeb>.fromJson(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{
            'id': 7,
            'nombres': 'Ana María',
            'apellidos': 'Ruiz',
            'telefono': '3001112233',
            'documentoTipo': 'CC',
            'documentoUltimos4': '6789',
            'habilidades': <dynamic>['Aseo general', ''],
            'estado': 'en_revision',
            'estadoEtiqueta': 'En revisión',
            'creadoEn': '2026-10-14T15:14:48+00:00',
            'foto': <String, dynamic>{
              'tipo': 'foto',
              'etiqueta': 'Foto',
              'driveFileId': '1AbCdEfGhIjKlMnOp',
              'mime': 'image/jpeg',
            },
            'documentos': <dynamic>[
              <String, dynamic>{
                'tipo': 'cedula_frontal',
                'etiqueta': 'Cédula (frente)',
                'driveFileId': '1QrStUvWxYz012345',
                'mime': 'application/pdf',
              },
              <String, dynamic>{
                'tipo': 'hoja_vida',
                'etiqueta': 'Hoja de vida',
                'pendiente': true,
              },
            ],
          },
        ],
        'total': 25,
        'pagina': 1,
        'porPagina': 20,
      }, PostulacionWeb.fromJson);

      expect(pagina.hayMas, isTrue);
      final p = pagina.items.single;
      expect(p.nombreCompleto, 'Ana María Ruiz');
      expect(p.habilidades, <String>['Aseo general']);
      expect(p.creadoEn, isNotNull);
      expect(p.foto?.esImagen, isTrue);
      expect(p.documentos.first.esImagen, isFalse);
      expect(
        p.documentos.first.urlDrive,
        'https://drive.google.com/file/d/1QrStUvWxYz012345/view',
      );
      expect(p.documentos.last.pendiente, isTrue);
      expect(p.documentos.last.enDrive, isFalse);
    });

    test('un conjunto con documentos viejos del servidor', () {
      final c = RegistroConjuntoWeb.fromJson(<String, dynamic>{
        'id': 3,
        'nombre': 'Torres del Llano',
        'nit': '900123',
        'estado': 'pending',
        'estadoEtiqueta': 'Pendiente de revisión',
        'documentos': <dynamic>[
          <String, dynamic>{
            'tipo': 'rut',
            'etiqueta': 'RUT',
            'enServidor': true,
            'urlServidor': 'https://tienda.test/wp-content/uploads/rut.pdf',
          },
        ],
      });

      expect(c.estadoEtiqueta, 'Pendiente de revisión');
      expect(c.documentos.single.enServidor, isTrue);
      expect(c.documentos.single.urlDrive, isNull);
      expect(c.documentos.single.urlServidor, contains('rut.pdf'));
    });

    test('respuestas incompletas no rompen el parseo', () {
      final pagina = PaginaWeb<RegistroConjuntoWeb>.fromJson(<String, dynamic>{
        'items': <dynamic>[<String, dynamic>{}],
      }, RegistroConjuntoWeb.fromJson);
      expect(pagina.items.single.nombre, 'Sin nombre');
      expect(pagina.items.single.estado, 'pending');
      expect(pagina.hayMas, isFalse);
    });

    test('la postulación trae quién la revisó y cuándo', () {
      final p = PostulacionWeb.fromJson(<String, dynamic>{
        'id': 4,
        'nombres': 'Ana',
        'revisada': true,
        'revisadaEn': '2026-10-14T20:00:00+00:00',
        'revisadaPor': 'Laura Gerente',
      });
      expect(p.revisada, isTrue);
      expect(p.revisadaPor, 'Laura Gerente');
      expect(p.revisadaEn, isNotNull);

      final sinRevisar = PostulacionWeb.fromJson(<String, dynamic>{'id': 5});
      expect(sinRevisar.revisada, isFalse);
      expect(sinRevisar.revisadaEn, isNull);
    });

    test('el resultado de borrar cuenta los documentos movidos', () {
      final r = PostulacionEliminada.fromJson(<String, dynamic>{
        'eliminada': true,
        'archivosEnPapelera': 3,
        'archivosSinMover': 1,
      });
      expect(r.archivosEnPapelera, 3);
      expect(r.archivosSinMover, 1);
      expect(
        PostulacionEliminada.fromJson(<String, dynamic>{}).archivosEnPapelera,
        0,
      );
    });
  });
}
