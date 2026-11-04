import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_application_1/model/auth_models.dart';
import 'package:flutter_application_1/pages/cronograma/mis_actividades_repo.dart';

/// Al abrir la app con señal deja guardado en el teléfono lo que el operario
/// necesita para trabajar sin ella: su agenda (dos semanas atrás y dos
/// adelante, como "Mis actividades") y el inventario de cada conjunto de esa
/// agenda (para registrar insumos al cerrar). Usa ETag: si nada cambió, el
/// servidor responde 304 y no se descarga de nuevo.
class PrecargaSinSenal {
  PrecargaSinSenal._();

  static Future<void>? _enCurso;

  static Future<void> ejecutar(AuthUser usuario, {MisActividadesRepo? repo}) {
    if (kIsWeb) return Future.value();
    if (usuario.rol.trim().toLowerCase() != 'operario') return Future.value();
    return _enCurso ??= _precargar(
      usuario,
      repo ?? MisActividadesRepo(),
    ).whenComplete(() => _enCurso = null);
  }

  static Future<void> _precargar(AuthUser u, MisActividadesRepo repo) async {
    try {
      final s = await repo.sesion();
      if (s == null) return;
      final rango = MisActividadesRepo.rangoPorDefecto(DateTime.now());
      final r = await repo.cargar(s, desde: rango.desde, hasta: rango.hasta);
      // Sin señal se está viendo la copia: no hay nada nuevo que guardar.
      if (r.copiaDel != null) return;
      final conjuntos = <String>{
        if (u.conjuntoId.trim().isNotEmpty) u.conjuntoId.trim(),
        for (final t in r.tareas)
          if ((t.conjuntoId ?? '').trim().isNotEmpty) t.conjuntoId!.trim(),
      };
      for (final nit in conjuntos) {
        await repo.inventario(nit);
      }
    } catch (_) {
      // Mejor esfuerzo: se intenta de nuevo la próxima vez que abra la app.
    }
  }
}
