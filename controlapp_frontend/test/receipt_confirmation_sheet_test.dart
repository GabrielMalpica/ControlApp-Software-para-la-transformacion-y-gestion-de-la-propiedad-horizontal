import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_application_1/widgets/receipt_confirmation_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

const _sanitabs = CommerceInsumoRef(
  id: 7,
  nombre: 'Sanitabs',
  unidad: 'pastilla',
);

ReceiptPreviewItem _item({
  int id = 1,
  String producto = 'Sanitabs (60)',
  double cantidad = 2,
  double cantidadInventario = 120,
  CommerceInsumoRef? insumo = _sanitabs,
}) => ReceiptPreviewItem(
  itemId: id,
  producto: producto,
  sku: null,
  cantidad: cantidad,
  insumo: insumo,
  origenMapeo: insumo == null ? 'SIN_MAPEO' : 'AUTO_WOO',
  cantidadInventario: cantidadInventario,
  factorDesdeWoo: true,
);

ReceiptPreview _preview({
  List<ReceiptPreviewItem>? items,
  bool puedeAplicar = true,
  bool puedeMapear = false,
  List<CommerceInsumoRef> insumos = const <CommerceInsumoRef>[],
}) => ReceiptPreview(
  puedeAplicar: puedeAplicar,
  yaAplicada: false,
  mensaje: 'Revisa que llegó todo.',
  items: items ?? <ReceiptPreviewItem>[_item()],
  insumosDisponibles: insumos,
  puedeMapear: puedeMapear,
);

/// Abre la hoja como en la app y expone lo que devuelve al confirmar.
class _Resultado {
  List<Map<String, dynamic>>? valor;
  bool cerrada = false;
}

Future<_Resultado> _abrir(
  WidgetTester tester,
  ReceiptPreview preview, {
  Future<ReceiptPreview> Function(int, int, double?)? onMapear,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final resultado = _Resultado();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                resultado.valor =
                    await showModalBottomSheet<List<Map<String, dynamic>>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ReceiptConfirmationSheet(
                        preview: preview,
                        onMapear: onMapear,
                      ),
                    );
                resultado.cerrada = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return resultado;
}

void main() {
  group('lo definido en la tienda es solo lectura', () {
    testWidgets(
      'muestra el insumo y la cantidad que suma, sin campos para editarlos',
      (tester) async {
        await _abrir(tester, _preview());

        expect(find.text('Suma 120 pastilla a «Sanitabs»'), findsOneWidget);
        expect(
          find.text('Definido en la tienda: no se puede cambiar aquí.'),
          findsOneWidget,
        );
        // Nada para cambiar la unidad, el factor ni el insumo.
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        expect(
          find.widgetWithText(
            TextField,
            'Unidades de pastilla por unidad comprada',
          ),
          findsNothing,
        );
        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'con un pedido anterior (factor no declarado en la tienda) tampoco se edita',
      (tester) async {
        final item = ReceiptPreviewItem(
          itemId: 1,
          producto: 'Pastillas',
          sku: null,
          cantidad: 2,
          insumo: _sanitabs,
          origenMapeo: 'MANUAL',
          cantidadInventario: 10,
          factorDesdeWoo: false,
        );
        await _abrir(tester, _preview(items: <ReceiptPreviewItem>[item]));

        expect(find.byType(TextField), findsNothing);
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        expect(find.text('Suma 10 pastilla a «Sanitabs»'), findsOneWidget);
      },
    );
  });

  group('reportar lo que llegó', () {
    testWidgets('por defecto todo llegó completo y confirma sin novedades', (
      tester,
    ) async {
      final resultado = await _abrir(tester, _preview());

      expect(find.text('Confirmar recepción'), findsOneWidget);
      await tester.tap(find.text('Confirmar recepción'));
      await tester.pumpAndSettle();

      expect(resultado.cerrada, isTrue);
      expect(resultado.valor, isEmpty);
    });

    testWidgets(
      '"No llegó completo" recalcula lo que se sumará y pide confirmar con novedades',
      (tester) async {
        await _abrir(tester, _preview());

        await tester.tap(find.text('No llegó completo'));
        await tester.pumpAndSettle();

        expect(find.text('Llegaron 1 de 2'), findsOneWidget);
        // 1 de 2 Sanitabs de 60 = 60 pastillas.
        expect(
          find.text('Se sumarán 60 pastilla a «Sanitabs»'),
          findsOneWidget,
        );
        expect(find.text('Confirmar con novedades'), findsOneWidget);
        expect(find.textContaining('se avisará a Control SAS'), findsOneWidget);
        expect(
          find.widgetWithText(TextField, '¿Qué pasó? (opcional)'),
          findsOneWidget,
        );
      },
    );

    testWidgets('devuelve la cantidad recibida y la nota al backend', (
      tester,
    ) async {
      final resultado = await _abrir(tester, _preview());

      await tester.tap(find.text('No llegó completo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '¿Qué pasó? (opcional)'),
        'Una caja llegó rota',
      );
      await tester.tap(find.text('Confirmar con novedades'));
      await tester.pumpAndSettle();

      expect(resultado.valor, <Map<String, dynamic>>[
        <String, dynamic>{
          'itemId': 1,
          'cantidadRecibida': 1.0,
          'nota': 'Una caja llegó rota',
        },
      ]);
    });

    testWidgets(
      'el contador baja hasta 0 (no llegó nada) y sube sin pasar de lo pedido',
      (tester) async {
        await _abrir(tester, _preview());
        await tester.tap(find.text('No llegó completo'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Menos'));
        await tester.pumpAndSettle();
        expect(find.text('Llegaron 0 de 2'), findsOneWidget);
        expect(find.text('Se sumarán 0 pastilla a «Sanitabs»'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.remove_rounded),
              )
              .onPressed,
          isNull,
        );

        await tester.tap(find.byTooltip('Más'));
        await tester.pumpAndSettle();
        // Ya no se puede subir más: el máximo en "no llegó completo" es uno menos.
        await tester.tap(find.byTooltip('Más'), warnIfMissed: false);
        await tester.pumpAndSettle();
        // Un "Más" de más no puede superar lo pedido: al llegar al máximo el botón se desactiva.
        expect(find.text('Llegaron 1 de 2'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.add_rounded),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('volver a "Llegó completo" borra la novedad y la nota', (
      tester,
    ) async {
      final resultado = await _abrir(tester, _preview());
      await tester.tap(find.text('No llegó completo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '¿Qué pasó? (opcional)'),
        'algo',
      );

      await tester.tap(find.text('Llegó completo'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar recepción'), findsOneWidget);
      await tester.tap(find.text('Confirmar recepción'));
      await tester.pumpAndSettle();

      expect(resultado.valor, isEmpty);
    });

    testWidgets('solo se reportan los productos con novedad', (tester) async {
      final resultado = await _abrir(
        tester,
        _preview(
          items: <ReceiptPreviewItem>[
            _item(),
            _item(
              id: 2,
              producto: 'Cloro 4L',
              cantidad: 3,
              cantidadInventario: 12,
            ),
          ],
        ),
      );

      // Segundo producto: "No llegó completo".
      await tester.tap(find.text('No llegó completo').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar con novedades'));
      await tester.pumpAndSettle();

      expect(resultado.valor, <Map<String, dynamic>>[
        <String, dynamic>{'itemId': 2, 'cantidadRecibida': 2.0},
      ]);
    });

    testWidgets('con cantidades decimales el contador avanza de a 0,5', (
      tester,
    ) async {
      await _abrir(
        tester,
        _preview(
          items: <ReceiptPreviewItem>[
            _item(cantidad: 2.5, cantidadInventario: 5),
          ],
        ),
      );
      await tester.tap(find.text('No llegó completo'));
      await tester.pumpAndSettle();

      expect(find.text('Llegaron 2 de 2,50'), findsOneWidget);
    });

    testWidgets('Volver cierra sin confirmar nada', (tester) async {
      final resultado = await _abrir(tester, _preview());
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();

      expect(resultado.cerrada, isTrue);
      expect(resultado.valor, isNull);
    });
  });

  group('productos sin insumo configurado', () {
    testWidgets(
      'quien compra NO puede mapear: ve el aviso y no puede confirmar',
      (tester) async {
        await _abrir(
          tester,
          _preview(
            items: <ReceiptPreviewItem>[_item(insumo: null)],
            puedeAplicar: false,
            puedeMapear: false,
            insumos: const <CommerceInsumoRef>[_sanitabs],
          ),
        );

        expect(find.textContaining('Avisa a Control SAS'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        // Sin insumo tampoco hay nada que reportar todavía.
        expect(find.text('No llegó completo'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirmar recepción'),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('el equipo de Control SAS sí puede elegir el insumo', (
      tester,
    ) async {
      int? insumoElegido;
      await _abrir(
        tester,
        _preview(
          items: <ReceiptPreviewItem>[_item(insumo: null)],
          puedeAplicar: false,
          puedeMapear: true,
          insumos: const <CommerceInsumoRef>[_sanitabs],
        ),
        onMapear: (itemId, insumoId, factor) async {
          insumoElegido = insumoId;
          return _preview(puedeMapear: true);
        },
      );

      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sanitabs (pastilla)').last);
      await tester.pumpAndSettle();

      expect(insumoElegido, 7);
      // Ya mapeado: pasa a ser solo lectura y se puede confirmar.
      expect(find.text('Suma 120 pastilla a «Sanitabs»'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    });
  });
}
