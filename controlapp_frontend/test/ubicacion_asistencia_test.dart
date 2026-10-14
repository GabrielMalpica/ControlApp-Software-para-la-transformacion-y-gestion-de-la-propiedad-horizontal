import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_application_1/pages/asistencia_checkin_page.dart';
import 'package:flutter_application_1/service/ubicacion_service.dart';

/// GPS de mentiras: extender GeolocatorPlatform pasa su verificación de
/// instancia sin depender de plugin_platform_interface.
class _GpsFalso extends GeolocatorPlatform {
  LocationPermission permiso = LocationPermission.whileInUse;
  bool encendido = true;
  Position? posicion;
  int lecturas = 0;

  @override
  Future<LocationPermission> checkPermission() async => permiso;

  @override
  Future<LocationPermission> requestPermission() async => permiso;

  @override
  Future<bool> isLocationServiceEnabled() async => encendido;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    lecturas++;
    final p = posicion;
    if (p == null) throw TimeoutException('sin señal');
    return p;
  }
}

Position _en(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: 12,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late _GpsFalso gps;

  setUp(() {
    gps = _GpsFalso();
    GeolocatorPlatform.instance = gps;
  });

  group('UbicacionDispositivo.obtener', () {
    test('devuelve la posición cuando hay permiso y señal', () async {
      gps.posicion = _en(4.7, -74.05);
      final p = await UbicacionDispositivo.obtener();
      expect(p.latitude, 4.7);
    });

    test('dice la causa: permiso negado, GPS apagado o sin señal', () async {
      gps.permiso = LocationPermission.deniedForever;
      await expectLater(
        UbicacionDispositivo.obtener(),
        throwsA(
          isA<UbicacionException>().having(
            (e) => e.fallo,
            'fallo',
            FalloUbicacion.permisoDenegado,
          ),
        ),
      );

      gps.permiso = LocationPermission.whileInUse;
      gps.encendido = false;
      await expectLater(
        UbicacionDispositivo.obtener(),
        throwsA(
          isA<UbicacionException>().having(
            (e) => e.fallo,
            'fallo',
            FalloUbicacion.gpsApagado,
          ),
        ),
      );

      gps.encendido = true;
      await expectLater(
        UbicacionDispositivo.obtener(),
        throwsA(
          isA<UbicacionException>().having(
            (e) => e.fallo,
            'fallo',
            FalloUbicacion.sinSenal,
          ),
        ),
      );
    });
  });

  group('AsistenciaCheckinPage', () {
    testWidgets('con el permiso negado lo avisa de entrada y explica cómo '
        'activarlo', (tester) async {
      gps.permiso = LocationPermission.deniedForever;
      await tester.pumpWidget(const MaterialApp(home: AsistenciaCheckinPage()));
      await tester.pumpAndSettle();

      expect(find.text('Necesitamos tu ubicación'), findsOneWidget);
      await tester.tap(find.text('Cómo activarla'));
      await tester.pumpAndSettle();
      expect(find.text('Cómo activar la ubicación'), findsOneWidget);
    });

    testWidgets('sin ubicación no abre el escáner', (tester) async {
      gps.encendido = false;
      await tester.pumpWidget(const MaterialApp(home: AsistenciaCheckinPage()));
      await tester.pumpAndSettle();
      expect(find.text('Necesitamos tu ubicación'), findsNothing);

      await tester.tap(find.text('Escanear QR'));
      await tester.pumpAndSettle();

      expect(find.text('Necesitamos tu ubicación'), findsOneWidget);
      expect(find.textContaining('GPS) del celular está apagada'), findsOne);
      // Sigue en la pantalla inicial: el botón de escanear sigue ahí.
      expect(find.text('Escanear QR'), findsOneWidget);
      expect(gps.lecturas, 0);
    });
  });
}
