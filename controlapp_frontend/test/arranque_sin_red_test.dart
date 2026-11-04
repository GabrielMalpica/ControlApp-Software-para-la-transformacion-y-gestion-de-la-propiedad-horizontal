import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/api/api_error.dart';
import 'package:flutter_application_1/model/auth_models.dart';
import 'package:flutter_application_1/service/api_exception.dart';
import 'package:flutter_application_1/service/arranque_sesion.dart';

final _servidor = AuthUser(
  id: '7',
  nombre: 'Ana',
  correo: 'ana@x.co',
  rol: 'operario',
  conjuntoId: '900',
  permissions: const ['tareas.ver'],
);

final _guardado = AuthUser(
  id: '7',
  nombre: 'Ana (guardado)',
  correo: 'ana@x.co',
  rol: 'operario',
  conjuntoId: '900',
  permissions: const ['tareas.ver', 'asistencia.marcar'],
);

Future<DecisionArranque> _decidir({
  bool tieneSesion = true,
  Object? errorPerfil,
  AuthUser? guardado,
  bool esWeb = false,
}) {
  return decidirArranque(
    tieneSesion: () async => tieneSesion,
    consultarPerfil: () async {
      if (errorPerfil != null) throw errorPerfil;
      return _servidor;
    },
    perfilGuardado: () async => guardado,
    esWeb: esWeb,
  );
}

void main() {
  test('sin sesión guardada va al login', () async {
    final d = await _decidir(tieneSesion: false);
    expect(d.destino, DestinoArranque.login);
    expect(d.borrarSesion, isFalse);
  });

  test('con señal entra con el perfil del servidor', () async {
    final d = await _decidir(guardado: _guardado);
    expect(d.destino, DestinoArranque.inicio);
    expect(d.usuario, same(_servidor));
    expect(d.sinSenal, isFalse);
  });

  test(
    'sin señal (app) entra con el perfil, rol y permisos guardados',
    () async {
      for (final error in <Object>[
        const SocketException('Failed host lookup'),
        TimeoutException('sin respuesta'),
        ApiException(statusCode: 503, message: 'caído'),
      ]) {
        final d = await _decidir(errorPerfil: error, guardado: _guardado);
        expect(d.destino, DestinoArranque.inicio, reason: '$error');
        expect(d.usuario, same(_guardado));
        expect(d.sinSenal, isTrue);
        expect(
          d.borrarSesion,
          isFalse,
          reason: 'no se borra la sesión sin señal',
        );
      }
    },
  );

  test('sin señal y sin perfil guardado: login, sin borrar nada', () async {
    final d = await _decidir(
      errorPerfil: const SocketException('sin red'),
      guardado: null,
    );
    expect(d.destino, DestinoArranque.login);
    expect(d.borrarSesion, isFalse);
  });

  test('401 (ya intentó renovar): borra la sesión y va al login', () async {
    final d = await _decidir(
      errorPerfil: ApiException(statusCode: 401, message: 'Sesión inválida'),
      guardado: _guardado,
    );
    expect(d.destino, DestinoArranque.login);
    expect(d.borrarSesion, isTrue);
  });

  test('426: pantalla de actualizar, con el perfil guardado detrás', () async {
    final d = await _decidir(
      errorPerfil: ApiError(426, '{"code":"APP_DESACTUALIZADA"}'),
      guardado: _guardado,
    );
    expect(d.destino, DestinoArranque.actualizarApp);
    expect(d.usuario, same(_guardado));
  });

  test('web: cualquier otro error va al login como siempre', () async {
    final d = await _decidir(
      errorPerfil: const SocketException('sin red'),
      guardado: _guardado,
      esWeb: true,
    );
    expect(d.destino, DestinoArranque.login);
  });
}
