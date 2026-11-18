import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/widgets/aviso_descarga_app.dart';

final _manifiesto = Uri.parse(
  'https://controlapp.ejemplo.co/descargas/android.json',
);

void main() {
  group('revisarApkPublicada', () {
    Future<(DisponibilidadApk, InfoApkPublicada?)> con(http.Response r) =>
        revisarApkPublicada(_manifiesto, cliente: MockClient((_) async => r));

    test('android.json publicado: versión y tamaño', () async {
      final (d, info) = await con(
        http.Response(
          jsonEncode({
            'versionCode': 3,
            'versionName': '1.1.0',
            'tamanoBytes': 26214400,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(d, DisponibilidadApk.publicada);
      expect(info?.resumen, 'Versión 1.1.0 · 25 MB');
    });

    test(
      'Hostinger responde con la página de la app: no está publicada',
      () async {
        final (d, _) = await con(
          http.Response(
            '<!DOCTYPE html><html></html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        );
        expect(d, DisponibilidadApk.noPublicada);
      },
    );

    test('404: no está publicada', () async {
      final (d, _) = await con(http.Response('no', 404));
      expect(d, DisponibilidadApk.noPublicada);
    });

    test(
      'error del servidor o sin señal: desconocida (se muestra igual)',
      () async {
        expect(
          (await con(http.Response('x', 500))).$1,
          DisponibilidadApk.desconocida,
        );
        final (d, _) = await revisarApkPublicada(
          _manifiesto,
          cliente: MockClient(
            (_) async => throw http.ClientException('sin red'),
          ),
        );
        expect(d, DisponibilidadApk.desconocida);
      },
    );
  });

  group('AvisoDescargaApp', () {
    Future<void> montar(WidgetTester tester, Widget w) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: w)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('publicada: muestra la versión y abre la APK', (tester) async {
      Uri? abierta;
      await montar(
        tester,
        AvisoDescargaApp(
          forzarMostrar: true,
          revisar: () async => (
            DisponibilidadApk.publicada,
            const InfoApkPublicada(versionName: '1.1.0', tamanoBytes: 26214400),
          ),
          abrir: (u) async {
            abierta = u;
            return true;
          },
        ),
      );
      expect(find.text('Versión 1.1.0 · 25 MB'), findsOneWidget);
      await tester.tap(find.text('Descargar la app'));
      await tester.pumpAndSettle();
      expect(abierta?.path, '/descargas/controlapp.apk');
    });

    testWidgets('no publicada: no se muestra el aviso', (tester) async {
      await montar(
        tester,
        AvisoDescargaApp(
          forzarMostrar: true,
          revisar: () async => (DisponibilidadApk.noPublicada, null),
        ),
      );
      expect(find.text('Descargar la app'), findsNothing);
    });

    testWidgets('si al tocar ya no está publicada, avisa y no abre nada', (
      tester,
    ) async {
      var llamadas = 0;
      var abrio = false;
      await montar(
        tester,
        AvisoDescargaApp(
          forzarMostrar: true,
          revisar: () async {
            llamadas++;
            return llamadas == 1
                ? (DisponibilidadApk.desconocida, null)
                : (DisponibilidadApk.noPublicada, null);
          },
          abrir: (_) async => abrio = true,
        ),
      );
      await tester.tap(find.text('Descargar la app'));
      await tester.pumpAndSettle();
      expect(abrio, isFalse);
      expect(find.textContaining('todavía no está publicada'), findsOneWidget);
    });
  });
}
