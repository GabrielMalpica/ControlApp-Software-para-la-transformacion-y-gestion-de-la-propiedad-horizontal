import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/widgets/aviso_version_nueva.dart';

Future<void> _volverALaApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'al volver a la app pregunta, pero no más de una vez cada 5 minutos',
    (tester) async {
      var revisiones = 0;
      var publicada = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AvisoVersionNueva(
            revisar: () async {
              revisiones++;
              return publicada;
            },
            child: child!,
          ),
          home: const Scaffold(body: Text('Cronograma')),
        ),
      );

      await _volverALaApp(tester);
      expect(revisiones, 1);
      expect(find.textContaining('versión nueva'), findsNothing);

      // Cambiar de pestaña seguido no vuelve a preguntar antes de 5 minutos.
      publicada = true;
      await _volverALaApp(tester);
      expect(revisiones, 1);
      expect(find.textContaining('versión nueva'), findsNothing);
    },
  );

  testWidgets('el aviso no tapa la app y se puede cerrar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AvisoVersionNueva(revisar: () async => true, child: child!),
        home: const Scaffold(body: Text('Cronograma')),
      ),
    );

    await _volverALaApp(tester);
    expect(find.text('Cronograma'), findsOneWidget);
    expect(find.textContaining('versión nueva'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('versión nueva'), findsNothing);
  });
}
