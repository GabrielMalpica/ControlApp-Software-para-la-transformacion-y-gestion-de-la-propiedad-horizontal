import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/tarea_labels.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';

/// Piezas visuales compartidas por el cronograma (administrador) y "Mis
/// actividades" (operario). Todas comunican con ícono + texto.

class EstadoChip extends StatelessWidget {
  final EstadoVisual estado;
  final bool compacto;

  const EstadoChip({super.key, required this.estado, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    return _Pastilla(
      icono: estado.icono,
      texto: estado.etiqueta,
      color: estado.color,
      fondo: estado.fondo,
      compacto: compacto,
    );
  }
}

/// "Compartida · 2" (o "con Juan" cuando se ve desde la fila de una persona).
class CompartidaBadge extends StatelessWidget {
  final int personas;
  final String? texto;
  final bool compacto;

  const CompartidaBadge({
    super.key,
    required this.personas,
    this.texto,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    return _Pastilla(
      icono: Icons.group,
      texto: texto ?? 'Compartida · $personas',
      color: const Color(0xFF5A4100),
      fondo: const Color(0xFFFFF4D1),
      borde: const Color(0xFFE5C25F),
      compacto: compacto,
    );
  }
}

/// Etiqueta de actividad especial (tipo CORRECTIVA): morado propio.
class EspecialBadge extends StatelessWidget {
  final bool compacto;

  const EspecialBadge({super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final texto = esVistaAdministrador ? 'Especial' : etiquetaCorrectiva();
    return _Pastilla(
      icono: CategoriaVisual.iconoEspecial,
      texto: texto,
      color: Colors.white,
      fondo: CategoriaVisual.especialAcento,
      compacto: compacto,
    );
  }
}

/// La misma persona tiene otra(s) actividad(es) a la vez.
class SimultaneaBadge extends StatelessWidget {
  final int cantidad;
  final bool compacto;

  const SimultaneaBadge({
    super.key,
    required this.cantidad,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    return _Pastilla(
      icono: Icons.layers,
      texto: '$cantidad a la vez',
      color: const Color(0xFF1E3A8A),
      fondo: const Color(0xFFE5EDFD),
      borde: const Color(0xFFA9BDF3),
      compacto: compacto,
    );
  }
}

class _Pastilla extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  final Color fondo;
  final Color? borde;
  final bool compacto;

  const _Pastilla({
    required this.icono,
    required this.texto,
    required this.color,
    required this.fondo,
    this.borde,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    final fs = compacto ? 12.5 : 13.5;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compacto ? 6 : 8,
        compacto ? 2 : 3,
        compacto ? 8 : 10,
        compacto ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        border: borde == null ? null : Border.all(color: borde!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: fs + 3, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fs,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuadro con el ícono de la categoría sobre su color.
class CategoriaTile extends StatelessWidget {
  final CategoriaVisual visual;
  final double tamano;

  const CategoriaTile({super.key, required this.visual, this.tamano = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: visual.acento,
        borderRadius: BorderRadius.circular(tamano * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(visual.icono, color: Colors.white, size: tamano * 0.58),
    );
  }
}

/// Chip con ícono y nombre de la categoría (en el detalle y la leyenda).
class CategoriaChip extends StatelessWidget {
  final CategoriaVisual visual;

  const CategoriaChip({super.key, required this.visual});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: visual.fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoriaTile(visual: visual, tamano: 26),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              visual.nombre,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrabajadorAvatar extends StatelessWidget {
  final TrabajadorRef trabajador;
  final double tamano;
  final bool invertido;

  const TrabajadorAvatar({
    super.key,
    required this.trabajador,
    this.tamano = 34,
    this.invertido = false,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(
          color: invertido ? Colors.white : AppTheme.surfaceSoft,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          trabajador.iniciales,
          style: TextStyle(
            fontSize: tamano * 0.36,
            fontWeight: FontWeight.w800,
            color: AppTheme.primaryDark,
          ),
        ),
      ),
    );
  }
}

/// Avatares encimados de los trabajadores de una actividad.
class AvataresTrabajadores extends StatelessWidget {
  final List<TrabajadorRef> trabajadores;
  final double tamano;

  const AvataresTrabajadores({
    super.key,
    required this.trabajadores,
    this.tamano = 28,
  });

  @override
  Widget build(BuildContext context) {
    final visibles = trabajadores.take(3).toList();
    if (visibles.isEmpty) return const SizedBox.shrink();
    final paso = tamano * 0.68;
    return SizedBox(
      width: tamano + paso * (visibles.length - 1),
      height: tamano,
      child: Stack(
        children: [
          for (var i = 0; i < visibles.length; i++)
            Positioned(
              left: paso * i,
              child: TrabajadorAvatar(trabajador: visibles[i], tamano: tamano),
            ),
        ],
      ),
    );
  }
}

/// Trabajadores de una tarea como referencias (id, nombre, cargo).
List<TrabajadorRef> trabajadoresDeTarea(TareaModel t) => trabajadoresDe([t]);

/// "Juan Pérez", "Juan Pérez y María Gómez", "A, B y C".
String nombresEnLista(Iterable<String> nombres) {
  final l = nombres.where((n) => n.trim().isNotEmpty).toList();
  if (l.isEmpty) return 'Sin asignar';
  if (l.length == 1) return l.first;
  return '${l.sublist(0, l.length - 1).join(', ')} y ${l.last}';
}

/* ======================= Tamaño de letra de la app ======================= */

/// Tamaño de letra elegido dentro de la app (Normal / Grande / Muy grande),
/// guardado en el dispositivo. Se suma al tamaño que ya tenga el sistema.
class TamanoTexto {
  TamanoTexto._();

  static const _clave = 'cronograma_tamano_texto';
  static const List<double> niveles = [1.0, 1.15, 1.3];
  static final ValueNotifier<double> factor = ValueNotifier<double>(1.0);
  static bool _cargado = false;

  static Future<void> cargar() async {
    if (_cargado) return;
    _cargado = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_clave);
      if (v != null && niveles.contains(v)) factor.value = v;
    } catch (_) {}
  }

  static Future<void> siguiente() async {
    final i = niveles.indexOf(factor.value);
    factor.value = niveles[(i + 1) % niveles.length];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_clave, factor.value);
    } catch (_) {}
  }

  static String get etiqueta {
    if (factor.value >= 1.3) return 'Muy grande';
    if (factor.value >= 1.15) return 'Grande';
    return 'Normal';
  }
}

/// Aplica el tamaño de letra elegido a [child].
class EscalaTexto extends StatelessWidget {
  final Widget child;

  const EscalaTexto({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: TamanoTexto.factor,
      builder: (context, factor, _) {
        if (factor == 1.0) return child;
        final mq = MediaQuery.of(context);
        final base = mq.textScaler.scale(16) / 16;
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(base * factor)),
          child: child,
        );
      },
    );
  }
}

/// Botón de la barra superior para cambiar el tamaño de letra.
class TamanoTextoBoton extends StatelessWidget {
  final Color color;

  const TamanoTextoBoton({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: TamanoTexto.factor,
      builder: (context, _, __) {
        final angosto = MediaQuery.sizeOf(context).width < 600;
        final etiqueta = TamanoTexto.etiqueta;
        return Semantics(
          button: true,
          label: 'Tamaño de letra: $etiqueta. Toca para cambiar',
          excludeSemantics: true,
          child: TextButton.icon(
            onPressed: TamanoTexto.siguiente,
            style: TextButton.styleFrom(
              foregroundColor: color,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.format_size),
            label: Text(angosto ? etiqueta : 'Letra: $etiqueta'),
          ),
        );
      },
    );
  }
}
