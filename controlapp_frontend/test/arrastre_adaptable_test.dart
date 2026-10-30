import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/widgets/cronograma/arrastre_adaptable.dart';

Widget _escena(List<String> soltados) => MaterialApp(
  home: Scaffold(
    body: Row(
      children: [
        const SizedBox(width: 20),
        ArrastreAdaptable<String>(
          data: 'especial',
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: const Material(child: Text('arrastrando')),
          child: Container(
            key: const Key('tarjeta'),
            width: 120,
            height: 60,
            color: Colors.purple,
          ),
        ),
        const SizedBox(width: 200),
        DragTarget<String>(
          onAcceptWithDetails: (d) => soltados.add(d.data),
          builder: (context, _, _) => Container(
            key: const Key('destino'),
            width: 200,
            height: 200,
            color: Colors.green,
          ),
        ),
      ],
    ),
  ),
);

void main() {
  // El orden importa: una vez que se ve un mouse, la app lo recuerda.
  testWidgets('con el dedo hay que mantener presionado', (tester) async {
    final soltados = <String>[];
    await tester.pumpWidget(_escena(soltados));
    final tarjeta = tester.getCenter(find.byKey(const Key('tarjeta')));
    final destino = tester.getCenter(find.byKey(const Key('destino')));

    // Deslizar sin esperar no arrastra (deja desplazar la lista).
    await tester.dragFrom(tarjeta, destino - tarjeta);
    await tester.pumpAndSettle();
    expect(soltados, isEmpty);

    // Mantener presionado y luego mover sí.
    final dedo = await tester.startGesture(tarjeta);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await dedo.moveTo(destino);
    await tester.pump();
    await dedo.up();
    await tester.pumpAndSettle();
    expect(soltados, ['especial']);
  });

  testWidgets('con mouse se arrastra de inmediato (clic y arrastrar)', (
    tester,
  ) async {
    final soltados = <String>[];
    await tester.pumpWidget(_escena(soltados));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(const Key('tarjeta'))),
    );
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('tarjeta'))));
    await tester.pump();

    await mouse.down(tester.getCenter(find.byKey(const Key('tarjeta'))));
    await mouse.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(find.text('arrastrando'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('destino'))));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(soltados, ['especial']);
  });
}
