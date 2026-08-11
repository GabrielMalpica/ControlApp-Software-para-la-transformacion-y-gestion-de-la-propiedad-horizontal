import 'package:flutter_application_1/model/commerce_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsea la configuración clx normalizada de un servicio', () {
    final product = CommerceProduct.fromJson(<String, dynamic>{
      'id': 77,
      'name': 'Servicio de fumigación',
      'price': <String, dynamic>{'current': 120000},
      'audience': <String, dynamic>{
        'paraResidente': true,
        'paraConjunto': false,
        'esServicio': true,
      },
      'service': <String, dynamic>{
        'enabled': true,
        'depositPct': 50,
        'allowFull': true,
        'minDays': 2,
        'daysAllowed': <int>[1, 2, 3, 4, 5],
        'maxPerDay': 1,
        'slots': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'am', 'label': 'MaÃ±ana', 'capacity': 2},
        ],
        'showRange': true,
        'range': <String, dynamic>{'min': 120000, 'max': 200000},
        'addons': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'extras',
            'label': 'Extras',
            'type': 'checkbox',
            'required': false,
            'group': <Map<String, dynamic>>[
              <String, dynamic>{'id': 4, 'label': 'Canaleta', 'price': 13500},
            ],
          },
        ],
      },
    });

    expect(product.service?.enabled, isTrue);
    expect(product.service?.effectiveSlots.single.id, 'am');
    expect(product.service?.effectiveSlots.single.label, 'Mañana');
    expect(product.service?.addons.single.options.single.price, 13500);
    expect(product.service?.range.max, 200000);
  });

  test('repara texto de comercio con codificación dañada una o dos veces', () {
    expect(repairCommerceText('D\u00c3\u00ada completo'), 'Día completo');
    expect(
      repairCommerceText('D\u00c3\u0192\u00c2\u00ada completo'),
      'Día completo',
    );
  });

  test('calcula adicionales y anticipo redondeado hacia arriba a mil', () {
    const option = CommerceAddonOption(id: 4, label: 'Canaleta', price: 13500);
    const selection = CommerceServiceSelection(
      date: '2026-08-10',
      slot: 'am',
      slotLabel: 'MaÃ±ana',
      payChoice: 'deposit',
      depositPct: 50,
      addons: <String, List<int>>{
        'extras': <int>[4],
      },
      selectedAddons: <CommerceSelectedAddon>[
        CommerceSelectedAddon(
          groupId: 'extras',
          groupLabel: 'Extras',
          options: <CommerceAddonOption>[option],
        ),
      ],
    );

    expect(selection.addonsTotal, 13500);
    expect(selection.payNowFor(133500), 67000);
    expect(selection.signature, contains('extras:4'));
  });
}
