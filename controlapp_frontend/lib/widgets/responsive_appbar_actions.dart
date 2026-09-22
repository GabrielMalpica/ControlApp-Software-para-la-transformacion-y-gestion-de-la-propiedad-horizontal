import 'package:flutter/material.dart';

/// Envuelve la lista de acciones de un [AppBar] (normalmente varios
/// [IconButton] con íconos blancos, pensados para verse sobre el color
/// primario del AppBar) y, en pantallas angostas, las colapsa detrás de un
/// único botón de "más opciones" para evitar que la fila desborde
/// horizontalmente (RenderFlex overflow) en celulares de 360-390px.
///
/// Las acciones se reutilizan tal cual (mismos widgets, mismo `onPressed`),
/// solo cambia su contenedor: en desktop/tablet ancho van en una `Row`
/// horizontal normal; en móvil aparecen en una hoja inferior con el mismo
/// color de fondo que el AppBar para que los íconos blancos sigan siendo
/// visibles.
class ResponsiveAppBarActions extends StatelessWidget {
  final List<Widget> actions;
  final Color background;
  final double breakpoint;

  const ResponsiveAppBarActions({
    super.key,
    required this.actions,
    required this.background,
    this.breakpoint = 420,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= breakpoint) {
      return Row(mainAxisSize: MainAxisSize.min, children: actions);
    }

    return IconButton(
      tooltip: 'Más opciones',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: background,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 4,
              children: actions,
            ),
          ),
        ),
      ),
    );
  }
}
