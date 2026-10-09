import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/tarea_labels.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_iconos.dart';

/// Cómo se pinta una actividad según su categoría: color de acento (ícono y
/// bordes), fondo claro de la tarjeta e ícono.
///
/// El acento siempre cumple contraste 4,5:1 con blanco (WCAG AA): si el color
/// guardado en la categoría es muy claro, se oscurece solo para pintar, sin
/// cambiar el dato.
class CategoriaVisual {
  final String nombre;
  final Color acento;
  final Color fondo;
  final IconData icono;

  /// Actividad especial (tipo CORRECTIVA): morado propio, nunca el de una
  /// categoría, para distinguirla de las preventivas.
  final bool esEspecial;

  const CategoriaVisual({
    required this.nombre,
    required this.acento,
    required this.fondo,
    required this.icono,
    this.esEspecial = false,
  });

  /// Morado reservado para las actividades especiales.
  static const Color especialAcento = Color(0xFF6D28D9);
  static const Color especialFondo = Color(0xFFF1EAFE);

  static const IconData iconoEspecial = Icons.star_rounded;
  static const IconData iconoSinCategoria = Icons.event_note;

  Color get borde => acento.withValues(alpha: 0.28);

  factory CategoriaVisual.deTarea(TareaModel t) {
    if ((t.tipo ?? '').trim().toUpperCase() == 'CORRECTIVA') {
      return CategoriaVisual(
        nombre: etiquetaCorrectiva(),
        acento: especialAcento,
        fondo: especialFondo,
        icono: categoriaIconoPorClave(t.categoriaIcono)?.icono ?? iconoEspecial,
        esEspecial: true,
      );
    }

    final base =
        colorDesdeHex(t.categoriaColorHex) ??
        colorDesdeHex(t.zonaCronograma?.colorHex) ??
        _colorPorTexto('${t.ubicacionNombre ?? ''} ${t.elementoNombre ?? ''}');
    final clave =
        t.categoriaIcono ??
        sugerirIconoCategoria(t.categoriaNombre) ??
        sugerirIconoCategoria(t.descripcion);
    return CategoriaVisual.desdeColor(
      nombre: (t.categoriaNombre ?? '').trim().isEmpty
          ? 'Sin categoría'
          : t.categoriaNombre!.trim(),
      color: base,
      icono: categoriaIconoPorClave(clave)?.icono ?? iconoSinCategoria,
    );
  }

  /// Para el catálogo: una categoría con su color e ícono guardados.
  factory CategoriaVisual.deCategoria({
    required String nombre,
    String? colorHex,
    String? icono,
  }) {
    final clave = icono ?? sugerirIconoCategoria(nombre);
    return CategoriaVisual.desdeColor(
      nombre: nombre,
      color: colorDesdeHex(colorHex) ?? AppTheme.primary,
      icono: categoriaIconoPorClave(clave)?.icono ?? iconoSinCategoria,
    );
  }

  factory CategoriaVisual.desdeColor({
    required String nombre,
    required Color color,
    required IconData icono,
  }) {
    final acento = conContraste(color, Colors.white);
    return CategoriaVisual(
      nombre: nombre,
      acento: acento,
      fondo: Color.lerp(color, Colors.white, 0.88)!,
      icono: icono,
    );
  }
}

Color? colorDesdeHex(String? hex) {
  final limpio = hex?.trim().replaceFirst('#', '');
  if (limpio == null || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(limpio)) {
    return null;
  }
  return Color(int.parse('FF$limpio', radix: 16));
}

/// Relación de contraste WCAG entre dos colores opacos (1 a 21).
double contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Oscurece [color] (conservando el tono) hasta que contraste [minimo]
/// con [sobre]. Si ya cumple, lo devuelve igual.
Color conContraste(Color color, Color sobre, {double minimo = 4.5}) {
  if (contraste(color, sobre) >= minimo) return color;
  var hsl = HSLColor.fromColor(color);
  for (var i = 0; i < 40 && contraste(hsl.toColor(), sobre) < minimo; i++) {
    hsl = hsl.withLightness(math.max(0, hsl.lightness - 0.025));
  }
  return hsl.toColor();
}

/// Color de respaldo para datos antiguos sin categoría ni zona (misma regla
/// que usaba el cronograma).
Color _colorPorTexto(String texto) {
  final t = texto.toLowerCase();
  if (t.contains('humed') || t.contains('agua')) return Colors.blue.shade700;
  if (t.contains('verde') || t.contains('jardin') || t.contains('cesped')) {
    return Colors.green.shade700;
  }
  if (t.contains('transit') || t.contains('circul')) {
    return Colors.orange.shade800;
  }
  if (t.contains('parque')) return Colors.brown.shade500;
  return AppTheme.primary;
}
