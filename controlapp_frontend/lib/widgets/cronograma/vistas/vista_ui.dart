// Piezas visuales compartidas por las vistas Mensual, Semanal y Diaria del
// cronograma (borrador y definitivo).

import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/vistas_cronograma.dart';

/// Colores de un operario: fondo claro, borde y texto oscuro (contraste
/// mayor a 4,5:1 sobre el fondo).
class ColoresOperario {
  final Color fondo;
  final Color borde;
  final Color texto;

  const ColoresOperario(this.fondo, this.borde, this.texto);
}

const List<ColoresOperario> _paleta = [
  ColoresOperario(Color(0xFFDCE8FB), Color(0xFFB4CBF2), Color(0xFF1E3A8A)),
  ColoresOperario(Color(0xFFEAE4FB), Color(0xFFCFC2F2), Color(0xFF5B21B6)),
  ColoresOperario(Color(0xFFD3F1E8), Color(0xFFA3DCCB), Color(0xFF115E59)),
  ColoresOperario(Color(0xFFFDE4D2), Color(0xFFF4C3A0), Color(0xFF9A3412)),
  ColoresOperario(Color(0xFFFBE1EC), Color(0xFFEFB7CE), Color(0xFF9D174D)),
  ColoresOperario(Color(0xFFD6EEF6), Color(0xFFA6D6E7), Color(0xFF155E75)),
  ColoresOperario(Color(0xFFF2EBCB), Color(0xFFDFD08E), Color(0xFF713F12)),
  ColoresOperario(Color(0xFFE1E4FA), Color(0xFFBCC2EF), Color(0xFF3730A3)),
  ColoresOperario(Color(0xFFE4F1D3), Color(0xFFBFDD9E), Color(0xFF3F6212)),
  ColoresOperario(Color(0xFFF5DEF7), Color(0xFFE2B2E8), Color(0xFF86198F)),
  ColoresOperario(Color(0xFFF1E4DC), Color(0xFFDBC0B0), Color(0xFF7C2D12)),
  ColoresOperario(Color(0xFFE6EAF0), Color(0xFFC8D0DB), Color(0xFF334155)),
];

const ColoresOperario coloresSinOperario = ColoresOperario(
  Color(0xFFEFF1F4),
  Color(0xFFD3D8E0),
  Color(0xFF475569),
);

ColoresOperario coloresDeOperario(OperarioVista? o) =>
    o == null ? coloresSinOperario : _paleta[o.indiceColor % _paleta.length];

/// Colores de la vista (fondo de domingo, festivo, hoy...).
abstract final class ColoresVista {
  static const Color fondoPagina = Color(0xFFF3F5F3);
  static const Color borde = Color(0xFFE3E7E4);
  static const Color bordeSuave = Color(0xFFEDF0EE);
  static const Color texto = Color(0xFF1B2620);
  static const Color textoSuave = Color(0xFF5F6B64);
  static const Color domingo = Color(0xFFFBF5E4);
  static const Color domingoTexto = Color(0xFF7A5B12);
  static const Color festivo = Color(0xFFFCE9E9);
  static const Color festivoTexto = Color(0xFFB42318);
  static const Color grupo = Color(0xFFE9F3EC);
  static const Color grupoTexto = Color(0xFF14532D);
  static const Color vencida = Color(0xFFEA7A12);
  static const Color alerta = Color(0xFFB45309);

  static const ColoresOperario ejecutada = ColoresOperario(
    Color(0xFFD9F2E1),
    Color(0xFF97D3AC),
    Color(0xFF166534),
  );
  static const ColoresOperario noEjecutada = ColoresOperario(
    Color(0xFFFDE1DF),
    Color(0xFFF2ADA7),
    Color(0xFFB42318),
  );
  static const ColoresOperario excluida = ColoresOperario(
    Color(0xFFEDEFF2),
    Color(0xFFC9CED6),
    Color(0xFF4B5563),
  );
}

/// Colores con los que se pinta una tarea: los del operario mientras está
/// abierta; verde si se ejecutó y rojo si no.
ColoresOperario coloresDeTarea(TareaModel t, OperarioVista? o) {
  switch (tonoDeTarea(t)) {
    case TonoTarea.ejecutada:
      return ColoresVista.ejecutada;
    case TonoTarea.noEjecutada:
      return ColoresVista.noEjecutada;
    case TonoTarea.abierta:
      return coloresDeOperario(o);
  }
}

/// Texto del estado para chips y detalle.
String etiquetaEstadoTarea(TareaModel t, {required bool borrador}) {
  if (borrador) return 'Borrador';
  switch ((t.estado ?? '').trim().toUpperCase()) {
    case 'ASIGNADA':
      return 'Asignada';
    case 'EN_PROCESO':
      return 'En proceso';
    case 'COMPLETADA':
      return 'Ejecutada';
    case 'APROBADA':
      return 'Aprobada';
    case 'PENDIENTE_APROBACION':
      return 'En revisión';
    case 'NO_COMPLETADA':
      return 'No ejecutada';
    case 'RECHAZADA':
      return 'Devuelta';
    case 'PENDIENTE_REPROGRAMACION':
      return 'Por reprogramar';
    default:
      final e = (t.estado ?? '').trim();
      return e.isEmpty ? 'Sin estado' : e;
  }
}

/// Tarjeta blanca con borde suave (las "cajas" de las vistas).
class CajaVista extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const CajaVista({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresVista.borde),
      ),
      child: child,
    );
  }
}

/// Indicador de resumen: etiqueta, número grande y una línea de contexto.
class IndicadorVista extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final String? sufijo;
  final String detalle;
  final Color? colorValor;
  final VoidCallback? onTap;

  const IndicadorVista({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.detalle,
    this.sufijo,
    this.colorValor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            color: ColoresVista.textoSuave,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: valor,
                style: TextStyle(
                  fontSize: 26,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: colorValor ?? ColoresVista.texto,
                ),
              ),
              if (sufijo != null)
                TextSpan(
                  text: ' $sufijo',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ColoresVista.textoSuave,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          detalle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: ColoresVista.textoSuave),
        ),
      ],
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ColoresVista.borde),
          ),
          child: contenido,
        ),
      ),
    );
  }
}

/// Fila de indicadores que se acomoda: 4 columnas en pantalla ancha, 2 en
/// tablet y 1 en celular.
class FilaIndicadores extends StatelessWidget {
  final List<Widget> indicadores;

  const FilaIndicadores({super.key, required this.indicadores});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = c.maxWidth >= 900
            ? indicadores.length
            : c.maxWidth >= 330
            ? 2
            : 1;
        const sep = 12.0;
        final ancho = (c.maxWidth - sep * (columnas - 1)) / columnas;
        return Wrap(
          spacing: sep,
          runSpacing: sep,
          children: [
            for (final i in indicadores) SizedBox(width: ancho, child: i),
          ],
        );
      },
    );
  }
}

/// Círculo/pastilla con las iniciales del operario en su color.
class AvatarOperario extends StatelessWidget {
  final OperarioVista? operario;
  final double tamano;

  const AvatarOperario({super.key, required this.operario, this.tamano = 30});

  @override
  Widget build(BuildContext context) {
    final c = coloresDeOperario(operario);
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.fondo,
        borderRadius: BorderRadius.circular(tamano * 0.32),
        border: Border.all(color: c.borde),
      ),
      child: Text(
        operario?.iniciales ?? '—',
        style: TextStyle(
          fontSize: tamano * 0.36,
          fontWeight: FontWeight.w800,
          color: c.texto,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Barra de carga horizontal (0..1).
class BarraCarga extends StatelessWidget {
  final double valor;
  final Color color;
  final double alto;

  const BarraCarga({
    super.key,
    required this.valor,
    this.color = AppTheme.primary,
    this.alto = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: SizedBox(
        height: alto,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFE7ECE9)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: valor.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastilla de texto (chips del detalle y del avance del día).
class PastillaVista extends StatelessWidget {
  final String texto;
  final Color fondo;
  final Color colorTexto;
  final IconData? icono;

  const PastillaVista({
    super.key,
    required this.texto,
    this.fondo = const Color(0xFFF0F2F1),
    this.colorTexto = ColoresVista.texto,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 14, color: colorTexto),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colorTexto,
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta pequeña "Especial" / "Correctiva".
class MarcaEspecial extends StatelessWidget {
  final String texto;

  const MarcaEspecial({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF6D28D9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Fondo rayado gris para lo excluido.
class RayadoPainter extends CustomPainter {
  final Color color;

  const RayadoPainter({this.color = const Color(0x22000000)});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(RayadoPainter oldDelegate) => oldDelegate.color != color;
}

// ─────────────────────── Barra superior ───────────────────────

/// Selector de período del encabezado verde: "‹ Noviembre 2026 ›".
class SelectorPeriodo extends StatelessWidget {
  final String texto;
  final VoidCallback? onAnterior;
  final VoidCallback? onSiguiente;
  final String tooltipAnterior;
  final String tooltipSiguiente;

  /// true sobre fondo verde (encabezado); false sobre fondo claro.
  final bool sobreVerde;

  const SelectorPeriodo({
    super.key,
    required this.texto,
    required this.onAnterior,
    required this.onSiguiente,
    this.tooltipAnterior = 'Anterior',
    this.tooltipSiguiente = 'Siguiente',
    this.sobreVerde = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorTexto = sobreVerde ? Colors.white : ColoresVista.texto;
    final colorDeshabilitado = sobreVerde
        ? Colors.white38
        : ColoresVista.textoSuave.withValues(alpha: 0.4);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: sobreVerde ? Colors.white.withValues(alpha: 0.12) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: sobreVerde ? null : Border.all(color: ColoresVista.borde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tooltipAnterior,
            onPressed: onAnterior,
            icon: const Icon(Icons.chevron_left),
            color: colorTexto,
            disabledColor: colorDeshabilitado,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorTexto,
              ),
            ),
          ),
          IconButton(
            tooltip: tooltipSiguiente,
            onPressed: onSiguiente,
            icon: const Icon(Icons.chevron_right),
            color: colorTexto,
            disabledColor: colorDeshabilitado,
          ),
        ],
      ),
    );
  }
}

/// Título del encabezado verde: "Cronograma mensual" + "Conjunto · NIT".
class TituloCronograma extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final bool borrador;

  const TituloCronograma({
    super.key,
    required this.titulo,
    required this.subtitulo,
    this.borrador = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                titulo,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (borrador) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'BORRADOR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3B2A05),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (subtitulo.isNotEmpty)
          Text(
            subtitulo,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
      ],
    );
  }
}

/// Grupo de botones tipo segmento ("Mensual | Semanal | Diaria").
class SegmentosVista<T> extends StatelessWidget {
  final List<(T, String)> opciones;
  final T seleccionado;
  final ValueChanged<T> onCambio;
  final bool compacto;

  const SegmentosVista({
    super.key,
    required this.opciones,
    required this.seleccionado,
    required this.onCambio,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ColoresVista.borde),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (valor, texto) in opciones)
            Semantics(
              button: true,
              selected: valor == seleccionado,
              child: Material(
                color: valor == seleccionado
                    ? AppTheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onCambio(valor),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compacto ? 12 : 16,
                      vertical: compacto ? 7 : 9,
                    ),
                    child: Text(
                      texto,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: valor == seleccionado
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: valor == seleccionado
                            ? Colors.white
                            : ColoresVista.texto,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botón-pastilla de la barra de herramientas ("Filtros", "Excluidas: 52").
class BotonPastilla extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final VoidCallback? onTap;
  final bool activo;
  final Color? colorActivo;

  const BotonPastilla({
    super.key,
    required this.texto,
    this.icono,
    this.onTap,
    this.activo = false,
    this.colorActivo,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorActivo ?? AppTheme.primary;
    return Material(
      color: activo ? color.withValues(alpha: 0.10) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: activo
                  ? color.withValues(alpha: 0.45)
                  : ColoresVista.borde,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[
                Icon(
                  icono,
                  size: 16,
                  color: activo ? color : ColoresVista.texto,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                texto,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: activo ? color : ColoresVista.texto,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Elemento de la leyenda: muestra + texto.
class ItemLeyenda extends StatelessWidget {
  final Widget muestra;
  final String texto;

  const ItemLeyenda({super.key, required this.muestra, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        muestra,
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 12.5,
            color: ColoresVista.textoSuave,
          ),
        ),
      ],
    );
  }
}

/// Cuadrito de color para la leyenda.
class MuestraColor extends StatelessWidget {
  final Color fondo;
  final Color? borde;
  final double ancho;

  const MuestraColor({
    super.key,
    required this.fondo,
    this.borde,
    this.ancho = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      height: 16,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borde ?? fondo),
      ),
    );
  }
}

/// Una acción sobre la tarea seleccionada (la decide cada página).
class AccionTareaVista {
  final String texto;
  final IconData icono;
  final VoidCallback onPressed;
  final bool principal;
  final bool peligro;

  const AccionTareaVista({
    required this.texto,
    required this.icono,
    required this.onPressed,
    this.principal = false,
    this.peligro = false,
  });
}

/// Excluidas (preventivas que no cupieron) de la semana o del día, a la
/// vista en Semanal y Diaria: tocar una abre su detalle (programarla,
/// buscarle hueco, cambiar el operario...) y el botón lleva a Planeación
/// para ubicarlas arrastrándolas.
class CajaExcluidas extends StatelessWidget {
  final String titulo;
  final List<PreventivaExcluidaBorradorModel> excluidas;
  final IndiceOperarios operarios;
  final ValueChanged<PreventivaExcluidaBorradorModel>? onTap;
  final VoidCallback? onProgramar;

  const CajaExcluidas({
    super.key,
    required this.titulo,
    required this.excluidas,
    required this.operarios,
    this.onTap,
    this.onProgramar,
  });

  @override
  Widget build(BuildContext context) {
    final ordenadas = [...excluidas]
      ..sort((a, b) => a.fechaObjetivo.compareTo(b.fechaObjetivo));
    return CajaVista(
      color: const Color(0xFFFFFBF3),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event_busy,
                    size: 18,
                    color: ColoresVista.alerta,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$titulo (${excluidas.length})',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: ColoresVista.texto,
                    ),
                  ),
                ],
              ),
              if (onProgramar != null)
                FilledButton.tonalIcon(
                  onPressed: onProgramar,
                  icon: const Icon(Icons.open_with, size: 18),
                  label: const Text('Ubicarlas arrastrando (Planeación)'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Preventivas que no cupieron en el horario. Toca una para '
            'programarla, buscarle hueco o cambiarle el operario.',
            style: TextStyle(fontSize: 12.5, color: ColoresVista.textoSuave),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in ordenadas)
                _ChipExcluida(
                  excluida: e,
                  operario: () {
                    final ops = operarios.deExcluida(e);
                    return ops.isEmpty ? null : ops.first;
                  }(),
                  onTap: onTap == null ? null : () => onTap!(e),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipExcluida extends StatelessWidget {
  final PreventivaExcluidaBorradorModel excluida;
  final OperarioVista? operario;
  final VoidCallback? onTap;

  const _ChipExcluida({
    required this.excluida,
    required this.operario,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = excluida.fechaObjetivo;
    final dia = diaCorto(d);
    final u = (excluida.ubicacionNombre ?? '').trim();
    final el = elementoCorto(excluida.elementoNombre);
    final lugar = [if (u.isNotEmpty) u, if (el.isNotEmpty) el].join(' · ');
    return Tooltip(
      message:
          '${excluida.descripcion.trim()}\n'
          '${operario?.nombreCorto ?? 'Sin operario'} · '
          '${formatoHorasCorto(excluida.duracionMinutos)}'
          '${(excluida.motivoMensaje ?? '').trim().isEmpty ? '' : '\n${excluida.motivoMensaje!.trim()}'}',
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: ColoresVista.excluida.fondo,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: CustomPaint(
            painter: const RayadoPainter(color: Color(0x12000000)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ColoresVista.excluida.borde),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AvatarOperario(operario: operario, tamano: 22),
                  const SizedBox(width: 6),
                  Text(
                    '${dia[0].toUpperCase()}${dia.substring(1)} ${d.day}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ColoresVista.texto,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      lugar.isEmpty ? excluida.descripcion.trim() : lugar,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: ColoresVista.texto,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatoHorasCorto(excluida.duracionMinutos),
                    style: const TextStyle(
                      fontSize: 12,
                      color: ColoresVista.textoSuave,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
