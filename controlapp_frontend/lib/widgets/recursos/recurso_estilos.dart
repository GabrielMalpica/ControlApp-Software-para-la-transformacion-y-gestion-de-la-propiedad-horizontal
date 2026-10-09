// lib/widgets/recursos/recurso_estilos.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/theme.dart';

/// Colores, iconos y textos compartidos por las vistas de la agenda de recursos.
class RecursoEstilos {
  RecursoEstilos._();

  static final DateFormat hora = DateFormat('h:mm a', 'es');
  static final DateFormat diaCorto = DateFormat('EEE d', 'es');
  static final DateFormat diaLargo = DateFormat("EEEE d 'de' MMMM", 'es');
  static final DateFormat fechaCorta = DateFormat('d MMM', 'es');
  static final DateFormat fechaHora = DateFormat("d MMM, h:mm a", 'es');

  static String rangoHoras(DateTime a, DateTime b) => '${hora.format(a)} – ${hora.format(b)}';

  /// "lun 12, 7:00 a. m. – 10:00 a. m." o con días distintos si cruza fecha.
  static String rangoUso(DateTime a, DateTime b) {
    final mismoDia = a.year == b.year && a.month == b.month && a.day == b.day;
    return mismoDia
        ? '${diaCorto.format(a)} · ${rangoHoras(a, b)}'
        : '${fechaHora.format(a)} → ${fechaHora.format(b)}';
  }

  static String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static IconData iconoClase(ClaseRecurso clase) =>
      clase == ClaseRecurso.maquinaria ? Icons.precision_manufacturing_outlined : Icons.handyman_outlined;

  static Color colorDia(EstadoDiaRecurso e) {
    switch (e) {
      case EstadoDiaRecurso.disponible:
        return const Color(0xFFE6F4EA);
      case EstadoDiaRecurso.reservado:
        return AppTheme.primary;
      case EstadoDiaRecurso.enTraslado:
        return const Color(0xFF9CCFB6);
      case EstadoDiaRecurso.prestado:
        return const Color(0xFF5B8DEF);
      case EstadoDiaRecurso.mantenimiento:
        return AppTheme.accent;
      case EstadoDiaRecurso.noOperativa:
        return AppTheme.red;
    }
  }

  static Color colorActual(EstadoActualRecurso e) {
    switch (e) {
      case EstadoActualRecurso.disponible:
        return AppTheme.green;
      case EstadoActualRecurso.enUso:
      case EstadoActualRecurso.reservado:
        return AppTheme.primary;
      case EstadoActualRecurso.enTraslado:
        return AppTheme.secondary;
      case EstadoActualRecurso.prestado:
        return const Color(0xFF3F6FD8);
      case EstadoActualRecurso.mantenimiento:
        return const Color(0xFFB7791F);
      case EstadoActualRecurso.noOperativa:
        return AppTheme.red;
    }
  }

  static Color colorCobertura(CoberturaNecesidad c) {
    switch (c) {
      case CoberturaNecesidad.cubierta:
        return AppTheme.green;
      case CoberturaNecesidad.parcial:
        return const Color(0xFFB7791F);
      case CoberturaNecesidad.pendiente:
        return AppTheme.red;
    }
  }

  static Color colorSeveridad(String s) {
    switch (s) {
      case 'ALTA':
        return AppTheme.red;
      case 'MEDIA':
        return const Color(0xFFB7791F);
      default:
        return AppTheme.textMuted;
    }
  }

  static const List<Color> _paleta = [
    Color(0xFF0C6B43),
    Color(0xFF3F6FD8),
    Color(0xFF8E44AD),
    Color(0xFFD35400),
    Color(0xFF16A085),
    Color(0xFFC0392B),
    Color(0xFF2C3E50),
    Color(0xFF7F8C1A),
    Color(0xFFB03A7A),
    Color(0xFF1F7A8C),
  ];

  /// Color estable por conjunto, para reconocerlo de un vistazo en la línea de tiempo.
  static Color colorConjunto(String? clave) {
    if (clave == null || clave.isEmpty) return AppTheme.textMuted;
    var h = 0;
    for (final c in clave.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _paleta[h % _paleta.length];
  }

  static String etiquetaEstadoInventario(String estado) {
    switch (estado) {
      case 'OPERATIVA':
        return 'Operativa';
      case 'EN_REPARACION':
        return 'En reparación';
      case 'EN_MANTENIMIENTO':
        return 'En mantenimiento';
      case 'DANADA':
        return 'Dañada';
      case 'FUERA_DE_SERVICIO':
        return 'Fuera de servicio';
      case 'PERDIDA':
        return 'Perdida';
      case 'BAJA':
        return 'De baja';
      case 'RETIRADA':
        return 'Retirada';
      default:
        return estado;
    }
  }
}

/// Píldora de estado pequeña.
class EstadoPill extends StatelessWidget {
  const EstadoPill({super.key, required this.texto, required this.color, this.icono});

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
