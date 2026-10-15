import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter_application_1/service/actualizacion_web/version_web.dart';
import 'package:flutter_application_1/widgets/version_web_texto.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('lee la fecha HTTP de Hostinger en UTC', () {
    expect(
      fechaHttp('Wed, 14 Oct 2026 19:41:58 GMT'),
      DateTime.utc(2026, 10, 14, 19, 41, 58),
    );
    expect(fechaHttp(null), isNull);
    expect(fechaHttp(''), isNull);
    expect(fechaHttp('no es una fecha'), isNull);
  });

  test('la muestra en español con la hora del dispositivo', () {
    final local = DateTime(2026, 10, 14, 14, 41);
    final texto = textoVersionWeb(local);
    expect(texto, contains('14'));
    expect(texto, contains('2026'));
    expect(texto, contains('2:41'));
    expect(texto.toLowerCase(), contains('oct'));
  });

  testWidgets('el texto solo aparece si hay fecha de versión', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VersionWebTexto(
            fechaHttpVersion: 'Wed, 14 Oct 2026 19:41:58 GMT',
          ),
        ),
      ),
    );
    expect(find.textContaining('Versión de la app: 14'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VersionWebTexto())),
    );
    expect(find.textContaining('Versión de la app'), findsNothing);
  });
}
