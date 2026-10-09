import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_iconos.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';

final _ahora = DateTime(2026, 10, 8, 9, 40);

TareaModel tarea(
  int id, {
  String desc = 'Barrido general',
  String ini = '07:00',
  String fin = '09:00',
  int dia = 8,
  String? estado = 'ASIGNADA',
  String tipo = 'PREVENTIVA',
  List<String> ids = const ['1'],
  List<String> nombres = const ['Juan Pérez'],
  String? catNombre,
  String? catColor,
  String? catIcono,
}) {
  DateTime at(String hm) {
    final p = hm.split(':');
    return DateTime(2026, 10, dia, int.parse(p[0]), int.parse(p[1]));
  }

  return TareaModel(
    id: id,
    descripcion: desc,
    fechaInicio: at(ini),
    fechaFin: at(fin),
    duracionMinutos: at(fin).difference(at(ini)).inMinutes,
    borrador: false,
    estado: estado,
    tipo: tipo,
    ubicacionId: 1,
    elementoId: 1,
    operariosIds: ids,
    operariosNombres: nombres,
    categoriaNombre: catNombre,
    categoriaColorHex: catColor,
    categoriaIcono: catIcono,
  );
}

void main() {
  group('Estado en lenguaje de operación', () {
    test('estados cerrados del servidor', () {
      expect(EstadoVisual.de(tarea(1, estado: 'APROBADA'), ahora: _ahora).etiqueta, 'Terminada');
      expect(EstadoVisual.de(tarea(1, estado: 'COMPLETADA'), ahora: _ahora).etiqueta, 'Terminada');
      expect(EstadoVisual.de(tarea(1, estado: 'PENDIENTE_APROBACION'), ahora: _ahora).etiqueta, 'En revisión');
      expect(EstadoVisual.de(tarea(1, estado: 'NO_COMPLETADA'), ahora: _ahora).etiqueta, 'No se hizo');
      expect(EstadoVisual.de(tarea(1, estado: 'RECHAZADA'), ahora: _ahora).etiqueta, 'Devuelta');
      expect(
        EstadoVisual.de(tarea(1, estado: 'PENDIENTE_REPROGRAMACION'), ahora: _ahora).etiqueta,
        'Por reprogramar',
      );
    });

    test('abiertas según la hora', () {
      // 07:00–09:00 ya pasó a las 9:40 y sigue abierta.
      expect(EstadoVisual.de(tarea(1), ahora: _ahora), same(EstadoVisual.atrasada));
      // 09:10–10:30 está en su horario.
      final enHora = tarea(2, ini: '09:10', fin: '10:30');
      expect(EstadoVisual.de(enHora, ahora: _ahora), same(EstadoVisual.leTocaAhora));
      expect(EstadoVisual.de(enHora, ahora: _ahora).calculado, isTrue);
      // Iniciada de verdad.
      final iniciada = tarea(3, ini: '09:10', fin: '10:30', estado: 'EN_PROCESO');
      expect(EstadoVisual.de(iniciada, ahora: _ahora), same(EstadoVisual.enCurso));
      // De un día anterior y sin cierre.
      expect(EstadoVisual.de(tarea(5, dia: 7), ahora: _ahora), same(EstadoVisual.sinCerrar));
      // Futura.
      expect(
        EstadoVisual.de(tarea(4, ini: '13:00', fin: '14:00'), ahora: _ahora),
        same(EstadoVisual.pendiente),
      );
    });

    test('cierre guardado sin conexión cuenta como cerrado', () {
      final e = EstadoVisual.de(tarea(1), ahora: _ahora, cierrePendienteEnvio: true);
      expect(e.etiqueta, 'Se enviará con señal');
      expect(e.cerrada, isTrue);
    });
  });

  group('Categoría: color e ícono', () {
    test('las especiales (correctivas) son moradas y se marcan', () {
      final v = CategoriaVisual.deTarea(tarea(1, tipo: 'CORRECTIVA', catColor: '#1F6FB2'));
      expect(v.esEspecial, isTrue);
      expect(v.acento, CategoriaVisual.especialAcento);
    });

    test('usa el color guardado y lo oscurece si no contrasta con blanco', () {
      // #F2B84B (amarillo) no cumple 4,5:1 con texto blanco.
      final v = CategoriaVisual.deTarea(tarea(1, catNombre: 'Fumigación', catColor: '#F2B84B'));
      expect(contraste(v.acento, Colors.white), greaterThanOrEqualTo(4.5));
      // Un color que ya cumple no se toca.
      final azul = CategoriaVisual.deTarea(tarea(2, catNombre: 'Aseo', catColor: '#1F6FB2'));
      expect(azul.acento, const Color(0xFF1F6FB2));
    });

    test('ícono configurado o sugerido por el nombre', () {
      final conIcono = CategoriaVisual.deTarea(
        tarea(1, catNombre: 'Cualquiera', catColor: '#1F6FB2', catIcono: 'piscina'),
      );
      expect(conIcono.icono, Icons.pool);
      final sugerido = CategoriaVisual.deTarea(
        tarea(2, catNombre: 'Salvamento acuático', catColor: '#D32F2F'),
      );
      expect(sugerido.icono, Icons.support);
      expect(sugerirIconoCategoria('Mantenimiento de piscinas'), 'piscina');
      expect(sugerirIconoCategoria('Aseo'), 'limpieza');
      expect(sugerirIconoCategoria('Poda'), 'arboles');
      expect(sugerirIconoCategoria(''), isNull);
    });

    test('sin categoría dice "Sin categoría"', () {
      expect(CategoriaVisual.deTarea(tarea(1)).nombre, 'Sin categoría');
    });
  });

  group('Simultáneas, compartidas y conteos', () {
    final juanBanos = tarea(1, desc: 'Lavar baños', ini: '07:00', fin: '08:00');
    final juanBarrido = tarea(2, desc: 'Barrido', ini: '07:00', fin: '09:00');
    final mariaTorres = tarea(
      3,
      desc: 'Aseo en torres',
      ini: '07:00',
      fin: '09:00',
      ids: const ['2'],
      nombres: const ['María Gómez'],
    );
    final compartida = tarea(
      4,
      desc: 'Lavado de lobby',
      ini: '10:40',
      fin: '11:30',
      ids: const ['1', '2'],
      nombres: const ['Juan Pérez', 'María Gómez'],
    );
    final dia = [juanBanos, juanBarrido, mariaTorres, compartida];

    test('a la vez = misma persona; otra persona en paralelo no cuenta', () {
      expect(simultaneasDe(juanBanos, dia).map((t) => t.id), [2]);
      expect(simultaneasDe(mariaTorres, dia), isEmpty);
    });

    test('una compartida repetida en dos filas se cuenta una sola vez', () {
      final filas = [...dia, compartida];
      final r = contarPorGrupo(filas, ahora: _ahora);
      expect(r.total, 4);
    });

    test('agrupar por hora de inicio no encadena todo el día', () {
      final grupos = agruparPorHoraInicio(dia);
      expect(grupos.map((g) => g.$1), [7, 10]);
      expect(grupos.first.$2.length, 3);
    });

    test('grupos de simultáneas por persona', () {
      final juan = dia.where((t) => tareaEsDe(t, '1'));
      final franjas = agruparSimultaneas(juan);
      expect(franjas.length, 2);
      expect(franjas.first.simultaneas, isTrue);
    });

    test('trabajadores sin repetir y con iniciales', () {
      final ts = trabajadoresDe(dia);
      expect(ts.map((t) => t.nombre), ['Juan Pérez', 'María Gómez']);
      expect(ts.first.iniciales, 'JP');
    });
  });

  group('Progreso del operario', () {
    test('cuenta cerradas (terminadas + no se hizo) y cierres sin señal', () {
      final dia = [
        tarea(1, estado: 'APROBADA'),
        tarea(2, estado: 'NO_COMPLETADA'),
        tarea(3, ini: '09:10', fin: '10:30'),
        tarea(4, ini: '13:00', fin: '14:00'),
      ];
      final p = progresoDelDia(dia, cierresPendientesEnvio: {3}, ahora: _ahora);
      expect(p.total, 4);
      expect(p.hechas, 2);
      expect(p.noSeHicieron, 1);
      expect(p.enviando, 1);
      expect(p.cerradas, 3);
      expect(p.porcentaje, 75);
      expect(p.mensaje, contains('Te queda 1 actividad'));
    });

    test('mensajes al empezar y al terminar', () {
      expect(progresoDelDia([tarea(1, ini: '13:00', fin: '14:00')], ahora: _ahora).mensaje, contains('¡Vamos!'));
      expect(
        progresoDelDia([tarea(1, estado: 'APROBADA')], ahora: _ahora).mensaje,
        contains('Terminaste todas'),
      );
      expect(progresoDelDia(const [], ahora: _ahora).mensaje, contains('no tienes actividades'));
    });
  });

  test('duración en palabras', () {
    expect(duracionLegible(30), '30 min');
    expect(duracionLegible(60), '1 h');
    expect(duracionLegible(125), '2 h 5 min');
  });

  group('Búsqueda', () {
    test('ignora tildes y mayúsculas y busca en trabajador y lugar', () {
      final t = tarea(1, desc: 'Lavar y desinfectar piscina', nombres: const ['María Gómez']);
      expect(coincideBusqueda(t, 'PISCINA'), isTrue);
      expect(coincideBusqueda(t, 'maria gomez'), isTrue);
      expect(coincideBusqueda(t, 'piscína marí'), isTrue);
      expect(coincideBusqueda(t, 'jardin'), isFalse);
      expect(normalizarTexto('Árbol Ñandú'), 'arbol nandu');
    });
  });
}
