import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/utils/enums/hoja_vida_etiquetas.dart';
import 'package:flutter_application_1/utils/enums/usuario_enums.dart';
import 'package:flutter_application_1/widgets/usuario/hoja_vida_campos.dart';

/// Hoja de vida del usuario: ARL, caja de compensación y contacto de
/// emergencia en el modelo, los catálogos y el formulario.
void main() {
  group('etiquetas', () {
    test('nombres claros para ARL y cajas', () {
      expect(etiquetaArl('BOLIVAR'), 'Seguros Bolívar');
      expect(etiquetaArl('AXA_COLPATRIA'), 'AXA Colpatria');
      expect(etiquetaArl(null), '');
      expect(
        etiquetaCajaCompensacion('COMFENALCO_QUINDIO'),
        'Comfenalco Quindío',
      );
      expect(etiquetaCajaCompensacion('COMPENSAR'), 'Compensar');
      // Un valor nuevo del backend que la app aún no conoce.
      expect(etiquetaCajaCompensacion('CAJA_NUEVA'), 'Caja Nueva');
      expect(etiquetaCajaCompensacion('  '), '');
    });
  });

  group('modelo', () {
    final json = {
      'id': '1001',
      'nombre': 'Ana Gómez',
      'correo': 'ana@correo.co',
      'rol': 'operario',
      'telefono': '3001234567',
      'fechaNacimiento': '1990-03-15T00:00:00.000Z',
      'arl': 'SURA',
      'cajaCompensacion': 'CAFAM',
      'contactoEmergenciaNombre': 'Luis Gómez',
      'contactoEmergenciaParentesco': 'Hermano',
      'contactoEmergenciaTelefono': '310 555 1234',
    };

    test('el usuario lee y envía los datos nuevos', () {
      final u = Usuario.fromJson(json);
      expect(u.arl, 'SURA');
      expect(u.cajaCompensacion, 'CAFAM');
      expect(u.contactoEmergenciaNombre, 'Luis Gómez');
      final salida = u.toJson();
      expect(salida['arl'], 'SURA');
      expect(salida['cajaCompensacion'], 'CAFAM');
      expect(salida['contactoEmergenciaParentesco'], 'Hermano');
      expect(salida['contactoEmergenciaTelefono'], '310 555 1234');
    });

    test('los catálogos traen ARL y cajas (vacíos si el backend es viejo)', () {
      final enums = UsuarioEnums.fromJson({
        'arl': ['SURA', 'POSITIVA'],
        'cajaCompensacion': ['COMPENSAR'],
      });
      expect(enums.arl, ['SURA', 'POSITIVA']);
      expect(enums.cajasCompensacion, ['COMPENSAR']);
      expect(UsuarioEnums.fromJson(const {}).arl, isEmpty);
    });
  });

  group('teléfono de emergencia', () {
    test('opcional, con 7 a 15 números', () {
      expect(validarTelefonoEmergencia(null), isNull);
      expect(validarTelefonoEmergencia('   '), isNull);
      expect(validarTelefonoEmergencia('+57 (310) 555-1234'), isNull);
      expect(validarTelefonoEmergencia('6011234567'), isNull);
      expect(validarTelefonoEmergencia('12345'), isNotNull);
      expect(validarTelefonoEmergencia('1234567890123456'), isNotNull);
      expect(validarTelefonoEmergencia('310-ABC-1234'), isNotNull);
    });

    test('texto vacío se envía como null para borrar el dato', () {
      expect(textoOpcional(TextEditingController(text: '  ')), isNull);
      expect(textoOpcional(TextEditingController(text: ' Madre ')), 'Madre');
    });
  });

  group('tarjeta de contacto de emergencia', () {
    Future<GlobalKey<FormState>> montar(
      WidgetTester tester, {
      String nombre = '',
      String telefono = '',
    }) async {
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: form,
                child: ContactoEmergenciaCard(
                  nombreCtrl: TextEditingController(text: nombre),
                  parentescoCtrl: TextEditingController(),
                  telefonoCtrl: TextEditingController(text: telefono),
                ),
              ),
            ),
          ),
        ),
      );
      return form;
    }

    testWidgets('vacía es válida', (tester) async {
      final form = await montar(tester);
      expect(form.currentState!.validate(), isTrue);
    });

    testWidgets('con nombre pide el teléfono', (tester) async {
      final form = await montar(tester, nombre: 'Luis');
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Escriba el teléfono del contacto'), findsOneWidget);
    });

    testWidgets('con teléfono pide a quién llamar', (tester) async {
      final form = await montar(tester, telefono: '3105551234');
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Escriba a quién llamar'), findsOneWidget);
    });

    testWidgets('nombre y teléfono válidos pasan', (tester) async {
      final form = await montar(
        tester,
        nombre: 'Luis',
        telefono: '310 555 1234',
      );
      expect(form.currentState!.validate(), isTrue);
    });
  });
}
