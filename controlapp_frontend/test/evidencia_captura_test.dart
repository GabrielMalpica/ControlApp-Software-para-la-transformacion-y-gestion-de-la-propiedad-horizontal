import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/api/evidencias_multipart.dart';
import 'package:flutter_application_1/model/cierre_tarea_pendiente_model.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/utils/cronograma/cierre_utils.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

void main() {
  final tomadaEn = DateTime.utc(2026, 10, 2, 0, 39, 9);

  group('CapturaEvidencia', () {
    test('se envía en UTC y con GPS solo si trae latitud y longitud', () {
      expect(CapturaEvidencia(tomadaEn: tomadaEn).toJson(), {
        'tomadaEn': '2026-10-02T00:39:09.000Z',
      });
      expect(
        CapturaEvidencia(
          tomadaEn: tomadaEn,
        ).conGps(4.142013, -73.626641).toJson(),
        {
          'tomadaEn': '2026-10-02T00:39:09.000Z',
          'latitud': 4.142013,
          'longitud': -73.626641,
        },
      );
    });

    test('ida y vuelta por JSON (cola sin conexión)', () {
      final original = CapturaEvidencia(
        tomadaEn: tomadaEn,
        latitud: 4.1,
        longitud: -73.6,
      );
      final leida = CapturaEvidencia.fromJson(original.toJson())!;
      expect(leida.tomadaEn, tomadaEn);
      expect(leida.latitud, 4.1);
      expect(leida.longitud, -73.6);
      expect(CapturaEvidencia.fromJson(null), isNull);
      expect(CapturaEvidencia.fromJson({'tomadaEn': 'no'}), isNull);
    });

    test('evidenciasCapturaJson solo se manda si alguna foto trae datos', () {
      expect(evidenciasCapturaJson(const [null, null]), isNull);
      final json = evidenciasCapturaJson([
        null,
        CapturaEvidencia(tomadaEn: tomadaEn),
      ]);
      expect(jsonDecode(json!), [
        null,
        {'tomadaEn': '2026-10-02T00:39:09.000Z'},
      ]);
    });
  });

  test('EvidenciaPendiente conserva la captura y lee registros viejos', () {
    final pendiente = EvidenciaPendiente(
      nombre: 'foto.jpg',
      path: '/tmp/foto.jpg',
      captura: CapturaEvidencia(tomadaEn: tomadaEn, latitud: 4, longitud: -73),
    );
    final leida = EvidenciaPendiente.fromJson(
      jsonDecode(jsonEncode(pendiente.toJson())) as Map<String, dynamic>,
    );
    expect(leida.captura?.tomadaEn, tomadaEn);
    expect(leida.captura?.tieneGps, isTrue);

    final vieja = EvidenciaPendiente.fromJson({
      'nombre': 'foto.jpg',
      'path': '/tmp/foto.jpg',
      'bytesBase64': null,
    });
    expect(vieja.captura, isNull);
  });

  test('evidenciasDesdeArchivos pasa la captura de la cámara al adjunto', () {
    final adjuntos = evidenciasDesdeArchivos([
      SelectedUploadFile(
        name: 'foto.jpg',
        path: '/tmp/foto.jpg',
        captura: CapturaEvidencia(tomadaEn: tomadaEn),
      ),
      const SelectedUploadFile(name: 'galeria.jpg', path: '/tmp/galeria.jpg'),
    ]);
    expect(adjuntos.first.captura?.tomadaEn, tomadaEn);
    expect(adjuntos.last.captura, isNull);
  });

  test(
    'adjuntarEvidencias alinea evidenciasCaptura con los archivos enviados',
    () async {
      final dir = await Directory.systemTemp.createTemp('evidencias_');
      addTearDown(() => dir.delete(recursive: true));
      final camara = File('${dir.path}/camara.jpg')..writeAsBytesSync([1, 2]);
      final galeria = File('${dir.path}/galeria.jpg')..writeAsBytesSync([3, 4]);

      final req = http.MultipartRequest('POST', Uri.parse('http://x/cerrar'));
      await adjuntarEvidencias(req, [
        // Ya no existe en disco: no se envía, y tampoco su captura.
        EvidenciaAdjunto(
          nombre: 'perdida.jpg',
          path: '${dir.path}/no-existe.jpg',
          captura: CapturaEvidencia(tomadaEn: tomadaEn),
        ),
        EvidenciaAdjunto(nombre: 'galeria.jpg', path: galeria.path),
        EvidenciaAdjunto(
          nombre: 'camara.jpg',
          path: camara.path,
          captura: CapturaEvidencia(tomadaEn: tomadaEn).conGps(4.1, -73.6),
        ),
      ]);

      expect(req.files.map((f) => f.filename), ['galeria.jpg', 'camara.jpg']);
      expect(jsonDecode(req.fields['evidenciasCaptura']!), [
        null,
        {
          'tomadaEn': '2026-10-02T00:39:09.000Z',
          'latitud': 4.1,
          'longitud': -73.6,
        },
      ]);
    },
  );
}
