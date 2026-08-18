import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';

void main() {
  test('la duración de un bloque excluido se presenta en minutos', () {
    final bloque = PreventivaExcluidaBloqueModel.fromJson({
      'id': 'b1',
      'orden': 1,
      'duracionMinutos': 90,
      'estado': 'PENDIENTE',
    });

    expect(bloque.duracionLabel, '90 min');
  });
}
