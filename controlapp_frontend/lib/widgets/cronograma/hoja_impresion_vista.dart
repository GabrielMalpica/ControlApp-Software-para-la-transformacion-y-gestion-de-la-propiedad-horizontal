import 'package:flutter/material.dart';

import 'package:flutter_application_1/utils/cronograma/hoja_impresion.dart';

/// Vista previa de las hojas del PDF del cronograma (ver
/// `lib/pdf/cronograma_pdf.dart`). Se dibujan con las mismas medidas, en
/// puntos de una hoja A4 horizontal, y se escalan al ancho disponible: lo
/// que se ve aquí es lo que sale impreso.

TextStyle _estilo(
  double tam, {
  bool negrita = false,
  Color color = ColoresHoja.texto,
  double? espaciado,
}) => TextStyle(
  fontSize: tam,
  fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
  color: color,
  letterSpacing: espaciado,
  height: TextosHoja.factorLinea,
);

/// Una hoja de papel con sombra, escalada al ancho disponible. Al tocarla
/// se abre en pantalla completa con zoom.
class PapelImpresion extends StatelessWidget {
  final Widget hoja;
  final String etiqueta;

  const PapelImpresion({super.key, required this.hoja, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    final contenido = MediaQuery(
      // La hoja replica el PDF: no crece con el tamaño de letra de la app.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: hoja,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ColoresHoja.textoSuave,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: '$etiqueta. Toca para verla en grande.',
          child: Material(
            color: Colors.white,
            elevation: 2,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _abrir(context, contenido),
              child: FittedBox(fit: BoxFit.fitWidth, child: contenido),
            ),
          ),
        ),
      ],
    );
  }

  void _abrir(BuildContext context, Widget contenido) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF3A3F3C),
          appBar: AppBar(title: Text(etiqueta)),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FittedBox(
                  child: Material(
                    color: Colors.white,
                    elevation: 4,
                    child: contenido,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _avatar(OperarioImpresion o, double tam) => Container(
  width: tam,
  height: tam,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: o.color,
    borderRadius: BorderRadius.circular(tam * 0.2),
  ),
  child: Text(
    o.inicial,
    style: _estilo(
      tam * 0.55,
      negrita: true,
      color: ColoresHoja.textoSobre(o.color),
    ).copyWith(height: 1),
  ),
);

Widget _casilla(MarcaCierre marca, double tam) {
  if (marca == MarcaCierre.pendiente) {
    return Container(
      width: tam,
      height: tam,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: ColoresHoja.casilla, width: 0.7),
        borderRadius: BorderRadius.circular(1.4),
      ),
    );
  }
  final hecha = marca == MarcaCierre.hecha;
  return Container(
    width: tam,
    height: tam,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: hecha ? ColoresHoja.hecha : ColoresHoja.noHecha,
      borderRadius: BorderRadius.circular(1.4),
    ),
    child: Icon(
      hecha ? Icons.check : Icons.close,
      size: tam * 0.9,
      color: Colors.white,
    ),
  );
}

class _Rayado extends CustomPainter {
  final Color fondo;
  final Color raya;

  const _Rayado(this.fondo, this.raya);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fondo);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final p = Paint()
      ..color = raya
      ..strokeWidth = 1.1;
    for (var x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Rayado old) => old.fondo != fondo || old.raya != raya;
}

/* =============================== Hoja =============================== */

class HojaImpresionVista extends StatelessWidget {
  final HojaCronograma hoja;
  final int pagina;
  final int paginas;
  final DateTime generado;

  const HojaImpresionVista({
    super.key,
    required this.hoja,
    required this.pagina,
    required this.paginas,
    required this.generado,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MedidasHoja.ancho,
      height: MedidasHoja.alto,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: MedidasHoja.franjaSuperior,
            color: ColoresHoja.marca,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MedidasHoja.margen,
              MedidasHoja.espacioSuperior,
              MedidasHoja.margen,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MedidasHoja.encabezado, child: _encabezado()),
                const SizedBox(height: MedidasHoja.separacion),
                SizedBox(height: MedidasHoja.titulosDias, child: _titulos()),
                SizedBox(height: MedidasHoja.altoGrilla, child: _grilla()),
                const SizedBox(height: MedidasHoja.separacion),
                SizedBox(height: MedidasHoja.pie, child: _pie()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado() {
    final o = hoja.operario;
    return Row(
      children: [
        SizedBox(
          width: 96,
          height: 42,
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hoja.etiquetaSuperior,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: _estilo(
                  7.8,
                  negrita: true,
                  color: ColoresHoja.marca,
                  espaciado: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _avatar(o, 22),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      o.ref.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: _estilo(
                        16,
                        negrita: true,
                        color: ColoresHoja.tinta,
                      ),
                    ),
                  ),
                  for (final v in o.iconos.take(5)) ...[
                    const SizedBox(width: 6),
                    Icon(v.icono, size: 11, color: v.acento),
                  ],
                ],
              ),
              if (o.subtitulo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 29, top: 1),
                  child: Text(
                    o.subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: _estilo(8.4, color: ColoresHoja.textoSuave),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Programado en la semana',
              style: _estilo(7.8, color: ColoresHoja.textoSuave),
            ),
            Text(
              hoja.programadoTexto,
              style: _estilo(17, negrita: true, color: ColoresHoja.tinta),
            ),
            if (hoja.parteTexto.isNotEmpty) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ColoresHoja.aclarar(ColoresHoja.marca, 0.88),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hoja.parteTexto,
                  style: _estilo(7, negrita: true, color: ColoresHoja.tinta),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _titulos() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: MedidasHoja.anchoHoras,
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            'Hora',
            style: _estilo(6.8, color: ColoresHoja.textoSuave),
          ),
        ),
        for (final d in hoja.dias)
          Container(
            width: d.ancho,
            padding: const EdgeInsets.only(right: 1),
            child: Container(
              decoration: BoxDecoration(
                color: d.fueraDelMes
                    ? ColoresHoja.fueraMes
                    : (d.festivo ? ColoresHoja.festivo : ColoresHoja.cabecera),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    d.nombreCorto,
                    style: _estilo(
                      6.6,
                      negrita: true,
                      color: d.fueraDelMes
                          ? Colors.white
                          : ColoresHoja.aclarar(ColoresHoja.cabecera, 0.7),
                      espaciado: 0.6,
                    ).copyWith(height: 1.1),
                  ),
                  Text(
                    '${d.fecha.day}',
                    style: _estilo(
                      13,
                      negrita: true,
                      color: Colors.white,
                    ).copyWith(height: 1.1),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _grilla() {
    const alto = MedidasHoja.altoGrilla;
    const ancho = MedidasHoja.anchoGrilla;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: MedidasHoja.anchoHoras,
          height: alto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final l in hoja.lineas.where((l) => l.principal))
                Positioned(
                  top: (l.y - 4).clamp(0, alto - 8).toDouble(),
                  right: 5,
                  child: Text(
                    l.texto!,
                    style: _estilo(
                      6.8,
                      color: ColoresHoja.textoSuave,
                    ).copyWith(height: 1),
                  ),
                ),
            ],
          ),
        ),
        Container(
          width: ancho,
          height: alto,
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: ColoresHoja.borde, width: 0.7),
          ),
          child: Stack(
            children: [
              for (final d in hoja.dias)
                Positioned(
                  left: d.x,
                  top: 0,
                  width: d.ancho,
                  height: alto,
                  child: d.fueraDelMes
                      ? const CustomPaint(
                          painter: _Rayado(
                            ColoresHoja.fondoSuave,
                            ColoresHoja.rayado,
                          ),
                        )
                      : ColoredBox(
                          color: d.festivo
                              ? ColoresHoja.festivoFondo
                              : Colors.white,
                        ),
                ),
              for (final l in hoja.lineas)
                Positioned(
                  left: 0,
                  top: l.y,
                  width: ancho,
                  height: l.principal ? 0.6 : 0.4,
                  child: ColoredBox(
                    color: l.principal
                        ? ColoresHoja.linea
                        : ColoresHoja.lineaMedia,
                  ),
                ),
              for (final d in hoja.dias.skip(1))
                Positioned(
                  left: d.x,
                  top: 0,
                  width: 0.6,
                  height: alto,
                  child: const ColoredBox(color: ColoresHoja.borde),
                ),
              for (final f in hoja.franjas)
                Positioned(
                  left: f.x,
                  top: f.y,
                  width: f.ancho,
                  height: f.alto,
                  child: _Franja(f),
                ),
              for (final t in hoja.tarjetas)
                Positioned(
                  left: t.x,
                  top: t.y,
                  width: t.ancho,
                  height: t.alto,
                  child: _Tarjeta(t),
                ),
              for (final d in hoja.dias)
                if (d.aviso != null)
                  Positioned(
                    left: d.x + 4,
                    top: 6,
                    width: d.ancho - 8,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: d.fueraDelMes
                              ? ColoresHoja.fueraMes
                              : ColoresHoja.festivo,
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        d.aviso!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: _estilo(
                          6.8,
                          negrita: true,
                          color: d.fueraDelMes
                              ? ColoresHoja.textoSuave
                              : ColoresHoja.festivo,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pie() {
    Widget item(Widget marca, String texto) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marca,
        const SizedBox(width: 3),
        Text(texto, style: _estilo(6.8)),
      ],
    );
    Widget firma(String texto) => Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.7, color: ColoresHoja.texto),
          const SizedBox(height: 2),
          Text(texto, style: _estilo(6.6, color: ColoresHoja.textoSuave)),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final v in hoja.categorias)
                    item(Icon(v.icono, size: 8, color: v.acento), v.nombre),
                  item(
                    _casilla(MarcaCierre.pendiente, 7),
                    'Marcar al terminar',
                  ),
                  item(_casilla(MarcaCierre.hecha, 7), 'Terminada'),
                  if (hoja.hayNoHechas)
                    item(_casilla(MarcaCierre.noHecha, 7), 'No se hizo'),
                  if (hoja.hayLibres)
                    item(
                      Container(
                        width: 11,
                        height: 7,
                        decoration: BoxDecoration(
                          color: ColoresHoja.libreFondo,
                          border: Border.all(
                            color: ColoresHoja.libreBorde,
                            width: 0.6,
                          ),
                        ),
                      ),
                      'Libre: espacio para actividades especiales',
                    ),
                  if (hoja.hayCompartidas)
                    item(
                      const Icon(
                        Icons.group,
                        size: 8,
                        color: ColoresHoja.textoSuave,
                      ),
                      'Compartida',
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Generado el ${_fecha(generado)} · ControlApp',
                style: _estilo(6, color: ColoresHoja.textoSuave),
              ),
            ],
          ),
        ),
        if (hoja.ultimaParte) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: 280,
            height: MedidasHoja.pie,
            child: Row(
              children: [
                firma('Firma de quien recibe'),
                const SizedBox(width: 16),
                firma('Firma de quien entrega'),
              ],
            ),
          ),
        ],
        const SizedBox(width: 12),
        Text(
          'Página $pagina de $paginas',
          style: _estilo(6.6, color: ColoresHoja.textoSuave),
        ),
      ],
    );
  }
}

String _fecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _Franja extends StatelessWidget {
  final FranjaHoja f;

  const _Franja(this.f);

  @override
  Widget build(BuildContext context) {
    final libre = f.tipo == TipoFranja.libre;
    final texto = f.alto >= 9
        ? Text(
            f.texto,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: _estilo(
              6.2,
              negrita: libre,
              color: libre ? ColoresHoja.libreTexto : ColoresHoja.textoSuave,
            ).copyWith(height: 1.1),
          )
        : null;
    if (!libre) {
      return CustomPaint(
        painter: const _Rayado(ColoresHoja.descansoFondo, ColoresHoja.rayado),
        child: Center(
          child: texto == null
              ? null
              : ColoredBox(
                  color: ColoresHoja.descansoFondo,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: texto,
                  ),
                ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(4, f.alto >= 18 ? 3 : 0, 4, 0),
      alignment: f.alto >= 18 ? Alignment.topLeft : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: ColoresHoja.libreFondo,
        border: Border.all(color: ColoresHoja.libreBorde, width: 0.6),
        borderRadius: BorderRadius.circular(3),
      ),
      child: texto,
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final TarjetaHoja t;

  const _Tarjeta(this.t);

  @override
  Widget build(BuildContext context) {
    final v = t.visual;
    final borde = ColoresHoja.aclarar(v.acento, 0.55);
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: v.fondo,
        border: Border(
          left: BorderSide(color: v.acento, width: TextosHoja.barra),
          top: BorderSide(color: borde, width: 0.5),
          right: BorderSide(color: borde, width: 0.5),
          bottom: BorderSide(color: borde, width: 0.5),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: TextosHoja.padH,
        vertical: t.tamano == TamanoTarjeta.chica ? 0.5 : TextosHoja.padV,
      ),
      child: switch (t.tamano) {
        TamanoTarjeta.grande => _grande(),
        TamanoTarjeta.mediana => _mediana(),
        TamanoTarjeta.chica => _chica(),
      },
    );
  }

  Widget _grande() {
    final v = t.visual;
    final lineasDetalle = t.lineasDetalle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: TextosHoja.filaHora,
          child: Row(
            children: [
              Icon(v.icono, size: 8.5, color: v.acento),
              const SizedBox(width: 2.5),
              if (t.continuaAntes) ...[
                const Icon(
                  Icons.north,
                  size: 6.5,
                  color: ColoresHoja.textoSuave,
                ),
                const SizedBox(width: 1),
              ],
              Expanded(
                child: Text(
                  t.rango,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: _estilo(
                    TextosHoja.hora,
                    negrita: true,
                    color: ColoresHoja.tinta,
                  ).copyWith(height: 1.1),
                ),
              ),
              if (t.personas > 1) ...[
                const Icon(
                  Icons.group,
                  size: 7.5,
                  color: ColoresHoja.textoSuave,
                ),
                Text(
                  '${t.personas}',
                  style: _estilo(6.4, negrita: true).copyWith(height: 1.1),
                ),
                const SizedBox(width: 2.5),
              ],
              _casilla(t.marca, 8),
            ],
          ),
        ),
        const SizedBox(height: TextosHoja.separacionFila),
        Text(
          t.titulo,
          maxLines: t.lineasTitulo,
          overflow: TextOverflow.clip,
          style: _estilo(
            TextosHoja.titulo,
            negrita: true,
            color: ColoresHoja.tinta,
          ),
        ),
        if (lineasDetalle > 0)
          Text(
            t.detalle,
            maxLines: lineasDetalle,
            overflow: TextOverflow.clip,
            style: _estilo(TextosHoja.detalle, color: ColoresHoja.textoSuave),
          ),
        if (t.continuaDespues) ...[
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'sigue ',
                style: _estilo(5.8, color: ColoresHoja.textoSuave),
              ),
              const Icon(Icons.south, size: 6, color: ColoresHoja.textoSuave),
            ],
          ),
        ],
      ],
    );
  }

  Widget _mediana() {
    final v = t.visual;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(v.icono, size: 8, color: v.acento),
            const SizedBox(width: 2.5),
            Expanded(
              child: Text(
                t.rango,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: _estilo(
                  6.9,
                  negrita: true,
                  color: ColoresHoja.tinta,
                ).copyWith(height: 1.1),
              ),
            ),
            _casilla(t.marca, 7.5),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          t.titulo,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: _estilo(
            6.9,
            negrita: true,
            color: ColoresHoja.tinta,
          ).copyWith(height: 1.1),
        ),
      ],
    );
  }

  Widget _chica() {
    final v = t.visual;
    final diminuta = t.alto < 10;
    final tam = diminuta ? 5.4 : 6.5;
    return Row(
      children: [
        Icon(v.icono, size: diminuta ? 5.5 : 7, color: v.acento),
        const SizedBox(width: 2),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${t.horaInicio}  ',
                  style: _estilo(tam, negrita: true, color: ColoresHoja.tinta),
                ),
                TextSpan(
                  text: t.titulo,
                  style: _estilo(tam, color: ColoresHoja.tinta),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(height: 1.1),
          ),
        ),
        const SizedBox(width: 1.5),
        _casilla(t.marca, diminuta ? 5.5 : 7),
      ],
    );
  }
}

/* ============================== Portada ============================== */

class PortadaImpresionVista extends StatelessWidget {
  final PortadaCronograma portada;

  const PortadaImpresionVista({super.key, required this.portada});

  static final _tarjeta = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: ColoresHoja.borde, width: 0.8),
  );

  @override
  Widget build(BuildContext context) {
    final p = portada;
    final filas = p.categorias.length > p.puestos.length
        ? p.categorias.length
        : p.puestos.length;
    return Container(
      width: MedidasHoja.ancho,
      constraints: const BoxConstraints(minHeight: MedidasHoja.alto),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: MedidasHoja.franjaSuperior,
            color: ColoresHoja.marca,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MedidasHoja.margen,
              MedidasHoja.espacioSuperior,
              MedidasHoja.margen,
              MedidasHoja.margen,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 112,
                      height: 48,
                      child: Image.asset('assets/logo.png'),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.etiquetaSuperior,
                            style: _estilo(
                              9,
                              negrita: true,
                              color: ColoresHoja.marca,
                              espaciado: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Cronograma de actividades por operario',
                            style: _estilo(
                              22,
                              negrita: true,
                              color: ColoresHoja.tinta,
                            ),
                          ),
                          if (p.semanaTexto.isNotEmpty)
                            Text(
                              p.semanaTexto,
                              style: _estilo(10, color: ColoresHoja.textoSuave),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _titulo('Categorías de actividad')),
                    const SizedBox(width: 18),
                    Expanded(child: _titulo('Puestos')),
                  ],
                ),
                for (var i = 0; i < filas; i++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: i < p.categorias.length
                            ? _categoria(p.categorias[i])
                            : const SizedBox(),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: i < p.puestos.length
                            ? _puesto(p.puestos[i])
                            : const SizedBox(),
                      ),
                    ],
                  ),
                if (filas == 0)
                  Text(
                    'No hay actividades en el período elegido.',
                    style: _estilo(9, color: ColoresHoja.textoSuave),
                  ),
                const SizedBox(height: 12),
                _titulo('Operarios asignados'),
                for (var i = 0; i < p.operarios.length; i += 3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        for (var k = i; k < i + 3; k++) ...[
                          if (k > i) const SizedBox(width: 10),
                          Expanded(
                            child: k < p.operarios.length
                                ? _operario(p.operarios[k])
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      texto,
      style: _estilo(12.5, negrita: true, color: ColoresHoja.tinta),
    ),
  );

  Widget _categoria(CategoriaResumen c) => Container(
    height: 32,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: _tarjeta,
    child: Row(
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.visual.acento,
            shape: BoxShape.circle,
          ),
          child: Icon(c.visual.icono, size: 11.5, color: Colors.white),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            c.visual.nombre,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: _estilo(9.5, negrita: true, color: ColoresHoja.tinta),
          ),
        ),
        Text(
          '${c.actividades} ${c.actividades == 1 ? 'actividad' : 'actividades'} · ${duracionTexto(c.minutos)}',
          style: _estilo(7.4, color: ColoresHoja.textoSuave),
        ),
      ],
    ),
  );

  Widget _puesto(PuestoImpresion p) => Container(
    height: 32,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: _tarjeta,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.nombre,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: _estilo(9.5, negrita: true, color: ColoresHoja.tinta),
        ),
        if (p.detalle.isNotEmpty)
          Text(
            p.detalle,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: _estilo(7.4, color: ColoresHoja.textoSuave),
          ),
      ],
    ),
  );

  Widget _operario(OperarioImpresion o) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: _tarjeta,
    child: Row(
      children: [
        _avatar(o, 24),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                o.ref.nombre,
                maxLines: 2,
                overflow: TextOverflow.clip,
                style: _estilo(
                  9.2,
                  negrita: true,
                  color: ColoresHoja.tinta,
                ).copyWith(height: 1.1),
              ),
              if (o.subtitulo.isNotEmpty)
                Text(
                  o.subtitulo,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: _estilo(7.2, color: ColoresHoja.textoSuave),
                ),
              Text(
                '${o.actividades} ${o.actividades == 1 ? 'actividad' : 'actividades'} · ${duracionTexto(o.minutos)}',
                style: _estilo(7, negrita: true, color: ColoresHoja.marca),
              ),
            ],
          ),
        ),
        for (final v in o.iconos.take(4)) ...[
          const SizedBox(width: 4),
          Icon(v.icono, size: 11, color: v.acento),
        ],
      ],
    ),
  );
}
