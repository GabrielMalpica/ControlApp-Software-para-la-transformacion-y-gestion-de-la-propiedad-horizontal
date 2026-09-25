import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/commerce_order_detail_page.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pintar(
  WidgetTester tester, {
  required String target,
  bool esConjunto = true,
  String label = 'Marcar recibido',
  bool enabled = true,
  VoidCallback? onPressed,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OrderNextStepCard(
            target: target,
            esConjunto: esConjunto,
            label: label,
            enabled: enabled,
            onPressed: onPressed ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('OrderNextStepCard', () {
    testWidgets(
      'RECIBIDO en un pedido de conjunto explica que suma al inventario',
      (tester) async {
        await _pintar(tester, target: 'RECIBIDO');

        expect(find.text('¿Ya llegó tu pedido?'), findsOneWidget);
        expect(find.textContaining('inventario del conjunto'), findsOneWidget);
        // Recibir cierra el pedido: no queda un segundo paso pendiente.
        expect(
          find.textContaining('el pedido queda entregado'),
          findsOneWidget,
        );
        expect(find.text('Confirmar recepción'), findsOneWidget);
      },
    );

    testWidgets('RECIBIDO en un pedido personal no habla de inventario', (
      tester,
    ) async {
      await _pintar(tester, target: 'RECIBIDO', esConjunto: false);

      expect(find.textContaining('inventario'), findsNothing);
      expect(find.text('Confirmar recepción'), findsOneWidget);
    });

    testWidgets('el botón dispara la acción', (tester) async {
      var veces = 0;
      await _pintar(tester, target: 'RECIBIDO', onPressed: () => veces++);

      await tester.tap(find.text('Confirmar recepción'));
      expect(veces, 1);
    });

    testWidgets('deshabilitado mientras se procesa otra acción', (
      tester,
    ) async {
      var veces = 0;
      await _pintar(
        tester,
        target: 'RECIBIDO',
        enabled: false,
        onPressed: () => veces++,
      );

      await tester.tap(find.text('Confirmar recepción'));
      expect(veces, 0);
    });

    testWidgets('no usa un fondo rojo/naranja que se lea como error', (
      tester,
    ) async {
      await _pintar(tester, target: 'RECIBIDO');

      final tarjeta = tester.widget<CommerceClayCard>(
        find.byType(CommerceClayCard),
      );
      expect(tarjeta.color, CommerceClayTokens.mint);
      expect(tarjeta.color, isNot(CommerceClayTokens.orangeSoft));
      // Tono verde: el canal verde domina al rojo.
      expect(tarjeta.color.g, greaterThan(tarjeta.color.r));
    });

    testWidgets('el botón principal es un objetivo táctil cómodo (48 px)', (
      tester,
    ) async {
      await _pintar(tester, target: 'RECIBIDO');

      final alto = tester.getSize(find.byType(FilledButton)).height;
      expect(alto, greaterThanOrEqualTo(48));
    });

    for (final caso in <(String, String, String)>[
      ('PAGADO', 'Pago por confirmar', 'Confirmar pago'),
      ('PENDIENTE_ENVIO', 'Listo para preparar', 'Marcar en preparación'),
      ('ENVIADO', 'Listo para despachar', 'Marcar en camino'),
      ('ENTREGADO', 'Cierra tu pedido', 'Marcar entregado'),
    ]) {
      testWidgets('${caso.$1}: título propio y botón "${caso.$3}"', (
        tester,
      ) async {
        await _pintar(tester, target: caso.$1, label: caso.$3);

        expect(find.text(caso.$2), findsOneWidget);
        expect(find.text(caso.$3), findsOneWidget);
      });
    }

    testWidgets('un estado desconocido igual muestra un paso genérico', (
      tester,
    ) async {
      await _pintar(tester, target: 'OTRO', label: 'Continuar');

      expect(find.text('Siguiente paso'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    });
  });
}
