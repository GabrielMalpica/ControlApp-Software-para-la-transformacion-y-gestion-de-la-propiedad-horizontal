import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _usuarioJson() => {
  'id': '123456789',
  'nombre': 'Operario de prueba',
  'correo': 'operario@example.com',
  'rol': 'operario',
  'telefono': '3001234567',
  'fechaNacimiento': '1990-01-15',
};

void main() {
  group('Usuario.fromJson', () {
    test('carga combinaciones de funciones desde el perfil del operario', () {
      final json = _usuarioJson()
        ..['operario'] = {
          'funciones': ['TODERO', 'SALVAVIDAS', 'JARDINERO'],
          'conjuntos': [
            {'nit': '900123456-7', 'nombre': 'Conjunto Central'},
          ],
        };

      final usuario = Usuario.fromJson(json);

      expect(
        usuario.tipoFunciones,
        equals(['TODERO', 'SALVAVIDAS', 'JARDINERO']),
      );
      expect(usuario.conjuntoNit, '900123456-7');
      expect(usuario.conjuntoNombre, 'Conjunto Central');
    });

    test('conserva compatibilidad con tipoFunciones en la raiz', () {
      final json = _usuarioJson()..['tipoFunciones'] = ['ASEO', 'TODERO'];

      final usuario = Usuario.fromJson(json);

      expect(usuario.tipoFunciones, equals(['ASEO', 'TODERO']));
    });
  });
}
