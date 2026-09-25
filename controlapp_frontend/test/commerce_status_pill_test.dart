import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

const _estados = <String>[
  'PENDIENTE_PAGO',
  'PAGADO',
  'PENDIENTE_ENVIO',
  'ENVIADO',
  'RECIBIDO',
  'ENTREGADO',
  'CANCELADO',
];

Future<({Color fondo, Color texto, String etiqueta})> _pintar(
  WidgetTester tester,
  String estado, {
  required bool onDark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: CommerceStatusPill(status: estado, onDark: onDark),
        ),
      ),
    ),
  );
  final contenedor = tester.widget<Container>(
    find.descendant(
      of: find.byType(CommerceStatusPill),
      matching: find.byType(Container),
    ),
  );
  final decoracion = contenedor.decoration! as BoxDecoration;
  final texto = tester.widget<Text>(
    find.descendant(
      of: find.byType(CommerceStatusPill),
      matching: find.byType(Text),
    ),
  );
  return (
    // La píldora se pinta sobre el degradado: se compone con el fondo real.
    fondo: decoracion.color!,
    texto: texto.style!.color!,
    etiqueta: texto.data!,
  );
}

void main() {
  final degradado = CommerceClayTokens.heroGradient.colors;

  group('CommerceStatusPill sobre la tarjeta verde (onDark)', () {
    for (final estado in _estados) {
      testWidgets('$estado se distingue del degradado y su texto se lee', (
        tester,
      ) async {
        final pill = await _pintar(tester, estado, onDark: true);

        // El texto se lee sobre la píldora.
        final fondoOpaco = Color.alphaBlend(pill.fondo, Colors.white);
        expect(
          _contrast(pill.texto, fondoOpaco),
          greaterThanOrEqualTo(3.5),
          reason: '${pill.etiqueta}: texto sobre la píldora',
        );

        // La píldora se destaca del degradado verde de la tarjeta.
        for (final color in degradado) {
          expect(
            _contrast(fondoOpaco, color),
            greaterThanOrEqualTo(3),
            reason: '${pill.etiqueta}: píldora contra el degradado',
          );
        }
      });
    }

    testWidgets('el diseño anterior se perdía contra el verde (regresión)', (
      tester,
    ) async {
      final pill = await _pintar(tester, 'PAGADO', onDark: false);
      final fondoSobreVerde = Color.alphaBlend(pill.fondo, degradado[1]);
      // Verde sobre verde: contraste muy bajo, justo lo que se veía en pantalla.
      expect(_contrast(pill.texto, fondoSobreVerde), lessThan(2));
    });
  });

  group('CommerceStatusPill en tarjetas claras (listas)', () {
    testWidgets('conserva el estilo translúcido de siempre', (tester) async {
      final pill = await _pintar(tester, 'PAGADO', onDark: false);
      expect(pill.fondo.a, lessThan(0.2));
      expect(pill.etiqueta, 'Pagado');
    });
  });
}
