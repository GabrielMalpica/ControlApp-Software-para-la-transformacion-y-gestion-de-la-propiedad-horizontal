import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_ui.dart';

/// "‹ Día anterior | Hoy | Día siguiente ›" con la fecha completa. En
/// pantallas angostas las flechas quedan solo con ícono (con etiqueta para
/// lector de pantalla) y la fecha pasa arriba.
class FechaNavegador extends StatelessWidget {
  final String titulo;
  final String unidad; // Día, Semana, Mes
  final VoidCallback onAnterior;
  final VoidCallback onHoy;
  final VoidCallback onSiguiente;
  final bool esActual;

  const FechaNavegador({
    super.key,
    required this.titulo,
    required this.unidad,
    required this.onAnterior,
    required this.onHoy,
    required this.onSiguiente,
    this.esActual = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final angosto = c.maxWidth < 640;
        final botones = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _boton(
              icono: Icons.chevron_left,
              texto: angosto ? null : '$unidad anterior',
              semantica: '$unidad anterior',
              onTap: onAnterior,
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: esActual ? null : onHoy,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.today),
              label: const Text('Hoy'),
            ),
            const SizedBox(width: 8),
            _boton(
              icono: Icons.chevron_right,
              texto: angosto ? null : '$unidad siguiente',
              semantica: '$unidad siguiente',
              onTap: onSiguiente,
              iconoAlFinal: true,
            ),
          ],
        );
        final tituloW = Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: angosto ? 19 : 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.text,
              letterSpacing: -0.2,
            ),
          ),
        );
        if (angosto) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [tituloW, const SizedBox(height: 8), botones],
          );
        }
        return Row(
          children: [
            Expanded(child: tituloW),
            const SizedBox(width: 12),
            botones,
          ],
        );
      },
    );
  }

  Widget _boton({
    required IconData icono,
    required String? texto,
    required String semantica,
    required VoidCallback onTap,
    bool iconoAlFinal = false,
  }) {
    final hijos = <Widget>[
      if (!iconoAlFinal) Icon(icono),
      if (texto != null) ...[
        if (!iconoAlFinal) const SizedBox(width: 4),
        Text(texto),
        if (iconoAlFinal) const SizedBox(width: 4),
      ],
      if (iconoAlFinal) Icon(icono),
    ];
    return Semantics(
      button: true,
      label: semantica,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(horizontal: texto == null ? 8 : 14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: hijos),
      ),
    );
  }
}

//// Hace aparecer un control con un deslizamiento corto desde la izquierda,
/// para que se note que salió al elegir una opción (p. ej. el selector de
/// trabajador al tocar "Por trabajador").
class EntradaSuave extends StatelessWidget {
  final Widget child;

  const EntradaSuave({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(-16 * (1 - v), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Botón compacto "Trabajador: Todos ▾". Aparece junto a la opción
/// "Por trabajador" cuando se elige; la lista de trabajadores se abre justo
/// debajo del botón (no en otra parte de la pantalla), con nombre, cargo y
/// una marca en el que está elegido.
class TrabajadorFiltro extends StatelessWidget {
  final List<TrabajadorRef> trabajadores;
  final String? seleccionadoId;
  final ValueChanged<String?> onChanged;

  /// Ancho del botón (y mínimo de la lista). Si es null, se ajusta al texto.
  final double? ancho;

  const TrabajadorFiltro({
    super.key,
    required this.trabajadores,
    required this.seleccionadoId,
    required this.onChanged,
    this.ancho,
  });

  @override
  Widget build(BuildContext context) {
    TrabajadorRef? elegido;
    for (final t in trabajadores) {
      if (t.id == seleccionadoId) elegido = t;
    }
    final anchoLista = math.max(ancho ?? 0, 300.0);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(6),
        minimumSize: WidgetStatePropertyAll(Size(anchoLista, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(math.max(anchoLista, 420), 460),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        _opcion(
          context,
          id: null,
          titulo: 'Todos los trabajadores',
          subtitulo: '',
          seleccionado: elegido == null,
        ),
        for (final t in trabajadores)
          _opcion(
            context,
            id: t.id,
            trabajador: t,
            titulo: t.nombre,
            subtitulo: t.cargo,
            seleccionado: t.id == elegido?.id,
          ),
      ],
      builder: (context, controller, _) {
        final abierto = controller.isOpen;
        final boton = Semantics(
          button: true,
          expanded: abierto,
          label:
              'Filtrar por trabajador. ${elegido == null ? 'Todos los trabajadores' : elegido.nombre}',
          excludeSemantics: true,
          child: OutlinedButton(
            onPressed: () async {
              if (abierto) {
                controller.close();
                return;
              }
              await _hacerEspacioDebajo(context);
              controller.open();
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
              backgroundColor: elegido != null || abierto
                  ? AppTheme.surfaceSoft
                  : Colors.white,
              alignment: Alignment.centerLeft,
            ),
            child: Row(
              mainAxisSize: ancho == null ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (elegido == null)
                  const Icon(Icons.people_alt_outlined)
                else
                  TrabajadorAvatar(trabajador: elegido, tamano: 30),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Trabajador: ',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: elegido?.nombre ?? 'Todos',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(abierto ? Icons.arrow_drop_up : Icons.arrow_drop_down),
              ],
            ),
          ),
        );
        return ancho == null ? boton : SizedBox(width: ancho, child: boton);
      },
    );
  }

  /// Si la lista no cabe debajo del botón, sube la página lo justo para que
  /// se abra debajo (si no, el menú se voltearía hacia arriba).
  Future<void> _hacerEspacioDebajo(BuildContext context) async {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final abajo = box.localToGlobal(Offset(0, box.size.height)).dy;
    final altoPantalla = MediaQuery.sizeOf(context).height;
    final necesario = math.min(56.0 * (trabajadores.length + 1) + 24, 460.0);
    if (altoPantalla - abajo >= necesario) return;
    await Scrollable.ensureVisible(
      context,
      alignment: 0.15,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _opcion(
    BuildContext context, {
    required String? id,
    TrabajadorRef? trabajador,
    required String titulo,
    required String subtitulo,
    required bool seleccionado,
  }) {
    return MenuItemButton(
      onPressed: () => onChanged(id),
      style: MenuItemButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: seleccionado ? AppTheme.surfaceSoft : null,
      ),
      leadingIcon: trabajador == null
          ? const SizedBox(
              width: 34,
              child: Icon(Icons.people_alt_outlined, color: AppTheme.text),
            )
          : TrabajadorAvatar(trabajador: trabajador, tamano: 34),
      trailingIcon: seleccionado
          ? const Icon(Icons.check, color: AppTheme.primary)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontWeight: seleccionado ? FontWeight.w800 : FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          if (subtitulo.isNotEmpty)
            Text(
              subtitulo,
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
        ],
      ),
    );
  }
}

// Opción de categoría para filtrar (la leyenda de colores también filtra).
class OpcionCategoria {
  final String clave; // nombre de la categoría o kFiltroEspecial
  final CategoriaVisual visual;

  const OpcionCategoria(this.clave, this.visual);
}

const String kFiltroEspecial = '__ESPECIAL__';

class CategoriaFiltroChips extends StatelessWidget {
  final List<OpcionCategoria> opciones;
  final String? seleccionada;
  final ValueChanged<String?> onChanged;

  const CategoriaFiltroChips({
    super.key,
    required this.opciones,
    required this.seleccionada,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in opciones)
          _ChipCategoria(
            opcion: o,
            seleccionada: o.clave == seleccionada,
            onTap: () => onChanged(o.clave == seleccionada ? null : o.clave),
          ),
      ],
    );
  }
}

class _ChipCategoria extends StatelessWidget {
  final OpcionCategoria opcion;
  final bool seleccionada;
  final VoidCallback onTap;

  const _ChipCategoria({
    required this.opcion,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v = opcion.visual;
    return Semantics(
      button: true,
      selected: seleccionada,
      label: 'Ver solo ${v.nombre}',
      excludeSemantics: true,
      child: Material(
        color: seleccionada ? v.acento : v.fondo,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 14, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: seleccionada ? Colors.white : v.acento,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      v.icono,
                      size: 18,
                      color: seleccionada ? v.acento : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    v.nombre,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: seleccionada ? Colors.white : AppTheme.text,
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

/// Chips "Todos los estados · Pendientes · Ahora · Terminadas · Con novedad".
class EstadoFiltroChips extends StatelessWidget {
  final GrupoEstado? seleccionado;
  final ValueChanged<GrupoEstado?> onChanged;

  const EstadoFiltroChips({
    super.key,
    required this.seleccionado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final opciones = <(GrupoEstado?, String)>[
      (null, 'Todos los estados'),
      for (final g in GrupoEstado.values) (g, etiquetaGrupoEstado(g)),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (g, texto) in opciones)
          ChoiceChip(
            label: Text(texto),
            selected: seleccionado == g,
            showCheckmark: true,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => onChanged(g),
          ),
      ],
    );
  }
}

/// Resumen del día que también filtra (Programadas, Terminadas, Ahora,
/// Pendientes, Con novedad). Cuenta cada actividad una sola vez.
class ResumenDiaTarjetas extends StatelessWidget {
  final ResumenEstados resumen;
  final GrupoEstado? seleccionado;
  final ValueChanged<GrupoEstado?> onChanged;

  const ResumenDiaTarjetas({
    super.key,
    required this.resumen,
    required this.seleccionado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(GrupoEstado?, String, int, IconData, Color)>[
      (
        null,
        'Programadas',
        resumen.total,
        Icons.calendar_month,
        AppTheme.primary,
      ),
      (
        GrupoEstado.terminada,
        'Terminadas',
        resumen.de(GrupoEstado.terminada),
        Icons.check_circle,
        EstadoVisual.terminada.color,
      ),
      (
        GrupoEstado.ahora,
        'Ahora',
        resumen.de(GrupoEstado.ahora),
        Icons.play_circle,
        EstadoVisual.enCurso.color,
      ),
      (
        GrupoEstado.pendiente,
        'Pendientes',
        resumen.de(GrupoEstado.pendiente),
        Icons.schedule,
        EstadoVisual.pendiente.color,
      ),
      (
        GrupoEstado.novedad,
        'Con novedad',
        resumen.de(GrupoEstado.novedad),
        Icons.warning_rounded,
        EstadoVisual.atrasada.color,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = c.maxWidth >= 760 ? 5 : (c.maxWidth >= 480 ? 3 : 2);
        final ancho = (c.maxWidth - 10 * (columnas - 1)) / columnas;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (g, texto, n, icono, color) in items)
              SizedBox(
                width: ancho,
                child: _TarjetaResumen(
                  texto: texto,
                  numero: n,
                  icono: icono,
                  color: color,
                  seleccionada: seleccionado == g,
                  onTap: () => onChanged(seleccionado == g ? null : g),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  final String texto;
  final int numero;
  final IconData icono;
  final Color color;
  final bool seleccionada;
  final VoidCallback onTap;

  const _TarjetaResumen({
    required this.texto,
    required this.numero,
    required this.icono,
    required this.color,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: seleccionada,
      label: '$numero $texto. Toca para ver solo estas',
      excludeSemantics: true,
      child: Material(
        color: seleccionada ? AppTheme.surfaceSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: seleccionada
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.12),
            width: seleccionada ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$numero',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(icono, size: 18, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        texto,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra amarilla "Mostrando: … [Quitar filtros]".
class FiltrosActivosBar extends StatelessWidget {
  final List<String> partes;
  final VoidCallback onQuitar;

  const FiltrosActivosBar({
    super.key,
    required this.partes,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    if (partes.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF0D6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 6,
        children: [
          const Icon(Icons.filter_list, color: Color(0xFF4A3300)),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Mostrando: '),
                TextSpan(
                  text: partes.join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onQuitar,
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            icon: const Icon(Icons.close),
            label: const Text('Quitar filtros'),
          ),
        ],
      ),
    );
  }
}

/// Guía "Cómo leer el cronograma": se muestra hasta que la persona toca
/// "Entendido" y siempre se puede volver a abrir con el botón Ayuda.
class GuiaCronograma {
  GuiaCronograma._();

  static const _clave = 'cronograma_guia_vista';
  static final ValueNotifier<bool> visible = ValueNotifier<bool>(false);
  static bool _cargada = false;

  static Future<void> cargar() async {
    if (_cargada) return;
    _cargada = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      visible.value = !(prefs.getBool(_clave) ?? false);
    } catch (_) {
      visible.value = true;
    }
  }

  static Future<void> ocultar() async {
    visible.value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clave, true);
    } catch (_) {}
  }

  static void mostrar() => visible.value = true;
}

class GuiaCronogramaCard extends StatelessWidget {
  const GuiaCronogramaCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GuiaCronograma.visible,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();
        Widget punto(IconData icono, String negrita, String resto) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, size: 20, color: const Color(0xFF4A3300)),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: negrita,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: resto),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF0D6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb, color: Color(0xFF8A6500)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Cómo leer el cronograma',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: GuiaCronograma.ocultar,
                    child: const Text('Entendido'),
                  ),
                ],
              ),
              punto(
                Icons.palette_outlined,
                'Color e ícono: ',
                'cada tipo de actividad tiene los suyos (aseo, jardinería, piscina…). Las especiales son moradas.',
              ),
              punto(
                Icons.crop_portrait,
                'Cada tarjeta ',
                'es una actividad: hora, nombre, lugar, quién la hace y su estado.',
              ),
              punto(
                Icons.layers,
                'A la vez: ',
                'actividades distintas que la misma persona tiene en el mismo horario.',
              ),
              punto(
                Icons.group,
                'Compartida: ',
                'una sola actividad que hacen varias personas. Si una la cierra, queda cerrada para todas.',
              ),
            ],
          ),
        );
      },
    );
  }
}
