import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show Canvas, Color, Colors, IconData, Icons, Offset, TextDirection;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:flutter_application_1/pdf/pdf_actions.dart';
import 'package:flutter_application_1/utils/cronograma/hoja_impresion.dart';

/// Genera el PDF del cronograma (portada + hojas por operario, ver
/// [construirPlanImpresion]) y lo descarga (web) o abre el diálogo de
/// impresión.
Future<void> imprimirCronograma(PlanImpresion plan) async {
  final bytes = await generarPdfCronograma(plan);
  await openOrDownloadPdf(bytes, plan.nombreArchivo);
}

Future<Uint8List> generarPdfCronograma(
  PlanImpresion plan, {
  DateTime? generado,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final negrita = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/logo.png')).buffer.asUint8List(),
  );

  final iconos = _Iconos();
  await iconos.preparar(_iconosDelPlan(plan));

  final r = _Recursos(
    logo: logo,
    iconos: iconos,
    generado: generado ?? DateTime.now(),
  );
  final doc = pw.Document(
    title: plan.nombreArchivo.replaceAll('.pdf', ''),
    author: 'ControlApp',
    theme: pw.ThemeData.withFont(base: regular, bold: negrita),
  );
  const formato = PdfPageFormat(
    MedidasHoja.ancho,
    MedidasHoja.alto,
    marginAll: 0,
  );

  final portada = plan.portada;
  if (portada != null) {
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: formato,
          margin: const pw.EdgeInsets.fromLTRB(
            MedidasHoja.margen,
            MedidasHoja.franjaSuperior + MedidasHoja.espacioSuperior,
            MedidasHoja.margen,
            MedidasHoja.margen,
          ),
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Container(
                height: MedidasHoja.franjaSuperior,
                color: _c(ColoresHoja.marca),
              ),
            ),
          ),
        ),
        build: (_) => _portada(portada, r),
      ),
    );
  }

  for (final hoja in plan.hojas) {
    doc.addPage(
      pw.Page(pageFormat: formato, build: (ctx) => _hoja(hoja, ctx, r)),
    );
  }
  return doc.save();
}

/* ============================== Recursos ============================== */

PdfColor _c(Color c) => PdfColor(c.r, c.g, c.b);

class _Recursos {
  final pw.MemoryImage logo;
  final _Iconos iconos;
  final DateTime generado;

  const _Recursos({
    required this.logo,
    required this.iconos,
    required this.generado,
  });

  String get generadoTexto =>
      '${generado.day.toString().padLeft(2, '0')}/${generado.month.toString().padLeft(2, '0')}/${generado.year}';
}

/// Íconos de la app (los mismos de la pantalla) dibujados por Flutter como
/// imagen: la fuente de íconos de Flutter es CFF y el paquete pdf no la lee.
class _Iconos {
  static const double _px = 72;
  final _cache = <String, pw.MemoryImage>{};

  static String _clave(IconData i, Color c) =>
      '${i.fontFamily}-${i.codePoint}-${c.toARGB32()}';

  Future<void> preparar(Iterable<(IconData, Color)> pares) async {
    for (final (icono, color) in pares) {
      final k = _clave(icono, color);
      if (_cache.containsKey(k)) continue;
      try {
        _cache[k] = pw.MemoryImage(await _rasterizar(icono, color));
      } catch (_) {
        // Sin el ícono la hoja sigue siendo legible (texto y colores).
      }
    }
  }

  static Future<Uint8List> _rasterizar(IconData icono, Color color) async {
    final grabadora = ui.PictureRecorder();
    final canvas = Canvas(grabadora);
    final texto = painting.TextPainter(textDirection: TextDirection.ltr)
      ..text = painting.TextSpan(
        text: String.fromCharCode(icono.codePoint),
        style: painting.TextStyle(
          fontFamily: icono.fontFamily,
          package: icono.fontPackage,
          fontSize: _px,
          height: 1,
          color: color,
        ),
      )
      ..layout();
    texto.paint(
      canvas,
      Offset((_px - texto.width) / 2, (_px - texto.height) / 2),
    );
    final imagen = await grabadora.endRecording().toImage(
      _px.toInt(),
      _px.toInt(),
    );
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    imagen.dispose();
    return datos!.buffer.asUint8List();
  }

  pw.Widget call(IconData icono, Color color, double tam) {
    final img = _cache[_clave(icono, color)];
    if (img == null) return pw.SizedBox(width: tam, height: tam);
    return pw.Image(img, width: tam, height: tam);
  }
}

Iterable<(IconData, Color)> _iconosDelPlan(PlanImpresion plan) sync* {
  yield (Icons.check, Colors.white);
  yield (Icons.close, Colors.white);
  yield (Icons.group, ColoresHoja.textoSuave);
  yield (Icons.north, ColoresHoja.textoSuave);
  yield (Icons.south, ColoresHoja.textoSuave);
  final portada = plan.portada;
  if (portada != null) {
    for (final c in portada.categorias) {
      yield (c.visual.icono, Colors.white);
    }
    for (final o in portada.operarios) {
      for (final v in o.categorias) {
        yield (v.icono, v.acento);
      }
    }
  }
  for (final h in plan.hojas) {
    for (final v in h.operario.categorias) {
      yield (v.icono, v.acento);
    }
    for (final t in h.tarjetas) {
      yield (t.visual.icono, t.visual.acento);
    }
  }
}

pw.TextStyle _estilo(
  double tam, {
  bool negrita = false,
  Color color = ColoresHoja.texto,
  double? espaciado,
}) => pw.TextStyle(
  fontSize: tam,
  fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
  color: _c(color),
  letterSpacing: espaciado,
  lineSpacing: 0,
);

pw.Widget _avatar(OperarioImpresion o, double tam) => pw.Container(
  width: tam,
  height: tam,
  alignment: pw.Alignment.center,
  decoration: pw.BoxDecoration(
    color: _c(o.color),
    borderRadius: pw.BorderRadius.circular(tam * 0.2),
  ),
  child: pw.Text(
    o.inicial,
    style: _estilo(
      tam * 0.55,
      negrita: true,
      color: ColoresHoja.textoSobre(o.color),
    ),
  ),
);

pw.Widget _casilla(MarcaCierre marca, double tam, _Recursos r) {
  switch (marca) {
    case MarcaCierre.pendiente:
      return pw.Container(
        width: tam,
        height: tam,
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: _c(ColoresHoja.casilla), width: 0.7),
          borderRadius: pw.BorderRadius.circular(1.4),
        ),
      );
    case MarcaCierre.hecha:
    case MarcaCierre.noHecha:
      final hecha = marca == MarcaCierre.hecha;
      return pw.Container(
        width: tam,
        height: tam,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: _c(hecha ? ColoresHoja.hecha : ColoresHoja.noHecha),
          borderRadius: pw.BorderRadius.circular(1.4),
        ),
        child: r.iconos(
          hecha ? Icons.check : Icons.close,
          Colors.white,
          tam * 0.9,
        ),
      );
  }
}

/// Fondo con rayas diagonales (días fuera del mes y descanso).
pw.Widget _rayado(double ancho, double alto, Color fondo, Color raya) {
  return pw.CustomPaint(
    size: PdfPoint(ancho, alto),
    painter: (canvas, size) {
      canvas
        ..setFillColor(_c(fondo))
        ..drawRect(0, 0, size.x, size.y)
        ..fillPath()
        ..saveContext()
        ..drawRect(0, 0, size.x, size.y)
        ..clipPath()
        ..setStrokeColor(_c(raya))
        ..setLineWidth(1.1);
      for (var x = -size.y; x < size.x; x += 7) {
        canvas
          ..moveTo(x, 0)
          ..lineTo(x + size.y, size.y);
      }
      canvas
        ..strokePath()
        ..restoreContext();
    },
  );
}

/* =============================== Hoja =============================== */

pw.Widget _hoja(HojaCronograma h, pw.Context ctx, _Recursos r) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        height: MedidasHoja.franjaSuperior,
        color: _c(ColoresHoja.marca),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(
          MedidasHoja.margen,
          MedidasHoja.espacioSuperior,
          MedidasHoja.margen,
          0,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              height: MedidasHoja.encabezado,
              child: _encabezado(h, r),
            ),
            pw.SizedBox(height: MedidasHoja.separacion),
            pw.SizedBox(
              height: MedidasHoja.titulosDias,
              child: _titulosDias(h),
            ),
            pw.SizedBox(height: MedidasHoja.altoGrilla, child: _grilla(h, r)),
            pw.SizedBox(height: MedidasHoja.separacion),
            pw.SizedBox(
              height: MedidasHoja.pie,
              child: _pie(h, ctx.pageNumber, ctx.pagesCount, r),
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _encabezado(HojaCronograma h, _Recursos r) {
  final o = h.operario;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: 96,
        height: 42,
        child: pw.Image(r.logo, fit: pw.BoxFit.contain),
      ),
      pw.SizedBox(width: 16),
      pw.Expanded(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              h.etiquetaSuperior,
              maxLines: 1,
              style: _estilo(
                7.8,
                negrita: true,
                color: ColoresHoja.marca,
                espaciado: 0.8,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                _avatar(o, 22),
                pw.SizedBox(width: 7),
                pw.Flexible(
                  child: pw.Text(
                    o.ref.nombre,
                    maxLines: 1,
                    style: _estilo(16, negrita: true, color: ColoresHoja.tinta),
                  ),
                ),
                for (final v in o.iconos.take(5)) ...[
                  pw.SizedBox(width: 6),
                  r.iconos(v.icono, v.acento, 11),
                ],
              ],
            ),
            if (o.subtitulo.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 29, top: 1),
                child: pw.Text(
                  o.subtitulo,
                  maxLines: 1,
                  style: _estilo(8.4, color: ColoresHoja.textoSuave),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'Programado en la semana',
            style: _estilo(7.8, color: ColoresHoja.textoSuave),
          ),
          pw.Text(
            h.programadoTexto,
            style: _estilo(17, negrita: true, color: ColoresHoja.tinta),
          ),
          if (h.parteTexto.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: pw.BoxDecoration(
                color: _c(ColoresHoja.aclarar(ColoresHoja.marca, 0.88)),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                h.parteTexto,
                style: _estilo(7, negrita: true, color: ColoresHoja.tinta),
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

pw.Widget _titulosDias(HojaCronograma h) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        width: MedidasHoja.anchoHoras,
        alignment: pw.Alignment.bottomLeft,
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(
          'Hora',
          style: _estilo(6.8, color: ColoresHoja.textoSuave),
        ),
      ),
      for (final d in h.dias)
        pw.Container(
          width: d.ancho,
          padding: const pw.EdgeInsets.only(right: 1),
          child: pw.Container(
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _c(
                d.fueraDelMes
                    ? ColoresHoja.fueraMes
                    : (d.festivo ? ColoresHoja.festivo : ColoresHoja.cabecera),
              ),
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(4),
                topRight: pw.Radius.circular(4),
              ),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  d.nombreCorto,
                  style: _estilo(
                    6.6,
                    negrita: true,
                    color: d.fueraDelMes
                        ? Colors.white
                        : ColoresHoja.aclarar(ColoresHoja.cabecera, 0.7),
                    espaciado: 0.6,
                  ),
                ),
                pw.Text(
                  '${d.fecha.day}',
                  style: _estilo(13, negrita: true, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

pw.Widget _grilla(HojaCronograma h, _Recursos r) {
  const alto = MedidasHoja.altoGrilla;
  const ancho = MedidasHoja.anchoGrilla;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: MedidasHoja.anchoHoras,
        height: alto,
        child: pw.Stack(
          overflow: pw.Overflow.visible,
          children: [
            for (final l in h.lineas.where((l) => l.principal))
              pw.Positioned(
                top: (l.y - 4).clamp(0, alto - 8).toDouble(),
                right: 5,
                child: pw.Text(
                  l.texto!,
                  style: _estilo(6.8, color: ColoresHoja.textoSuave),
                ),
              ),
          ],
        ),
      ),
      pw.Container(
        width: ancho,
        height: alto,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _c(ColoresHoja.borde), width: 0.7),
        ),
        child: pw.Stack(
          children: [
            for (final d in h.dias)
              pw.Positioned(
                left: d.x,
                top: 0,
                child: d.fueraDelMes
                    ? _rayado(
                        d.ancho,
                        alto,
                        ColoresHoja.fondoSuave,
                        ColoresHoja.rayado,
                      )
                    : pw.Container(
                        width: d.ancho,
                        height: alto,
                        color: d.festivo
                            ? _c(ColoresHoja.festivoFondo)
                            : PdfColors.white,
                      ),
              ),
            for (final l in h.lineas)
              pw.Positioned(
                left: 0,
                top: l.y,
                child: pw.Container(
                  width: ancho,
                  height: l.principal ? 0.6 : 0.4,
                  color: _c(
                    l.principal ? ColoresHoja.linea : ColoresHoja.lineaMedia,
                  ),
                ),
              ),
            for (final d in h.dias.skip(1))
              pw.Positioned(
                left: d.x,
                top: 0,
                child: pw.Container(
                  width: 0.6,
                  height: alto,
                  color: _c(ColoresHoja.borde),
                ),
              ),
            for (final f in h.franjas)
              pw.Positioned(left: f.x, top: f.y, child: _franja(f)),
            for (final t in h.tarjetas)
              pw.Positioned(left: t.x, top: t.y, child: _tarjeta(t, r)),
            for (final d in h.dias)
              if (d.aviso != null)
                pw.Positioned(
                  left: d.x + 4,
                  top: 6,
                  child: pw.Container(
                    width: d.ancho - 8,
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(
                        color: _c(
                          d.fueraDelMes
                              ? ColoresHoja.fueraMes
                              : ColoresHoja.festivo,
                        ),
                        width: 0.6,
                      ),
                    ),
                    child: pw.Text(
                      d.aviso!,
                      textAlign: pw.TextAlign.center,
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

pw.Widget _franja(FranjaHoja f) {
  final texto = f.alto >= 9
      ? pw.Text(
          f.texto,
          maxLines: 1,
          style: _estilo(
            6.2,
            negrita: f.tipo == TipoFranja.libre,
            color: f.tipo == TipoFranja.libre
                ? ColoresHoja.libreTexto
                : ColoresHoja.textoSuave,
          ),
        )
      : null;
  if (f.tipo == TipoFranja.descanso) {
    return pw.SizedBox(
      width: f.ancho,
      height: f.alto,
      child: pw.Stack(
        alignment: pw.Alignment.center,
        children: [
          _rayado(
            f.ancho,
            f.alto,
            ColoresHoja.descansoFondo,
            ColoresHoja.rayado,
          ),
          if (texto != null)
            pw.Container(
              color: _c(ColoresHoja.descansoFondo),
              padding: const pw.EdgeInsets.symmetric(horizontal: 3),
              child: texto,
            ),
        ],
      ),
    );
  }
  return pw.Container(
    width: f.ancho,
    height: f.alto,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4),
    alignment: f.alto >= 18 ? pw.Alignment.topLeft : pw.Alignment.centerLeft,
    decoration: pw.BoxDecoration(
      color: _c(ColoresHoja.libreFondo),
      border: pw.Border.all(color: _c(ColoresHoja.libreBorde), width: 0.6),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: f.alto >= 18
        ? pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: texto)
        : texto,
  );
}

pw.Widget _tarjeta(TarjetaHoja t, _Recursos r) {
  final v = t.visual;
  final pw.Widget contenido;

  switch (t.tamano) {
    case TamanoTarjeta.grande:
      final lineasDetalle = t.lineasDetalle;
      contenido = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            height: TextosHoja.filaHora,
            child: pw.Row(
              children: [
                r.iconos(v.icono, v.acento, 8.5),
                pw.SizedBox(width: 2.5),
                if (t.continuaAntes) ...[
                  r.iconos(Icons.north, ColoresHoja.textoSuave, 6.5),
                  pw.SizedBox(width: 1),
                ],
                pw.Expanded(
                  child: pw.Text(
                    t.rango,
                    maxLines: 1,
                    style: _estilo(
                      TextosHoja.hora,
                      negrita: true,
                      color: ColoresHoja.tinta,
                    ),
                  ),
                ),
                if (t.personas > 1) ...[
                  r.iconos(Icons.group, ColoresHoja.textoSuave, 7.5),
                  pw.Text('${t.personas}', style: _estilo(6.4, negrita: true)),
                  pw.SizedBox(width: 2.5),
                ],
                _casilla(t.marca, 8, r),
              ],
            ),
          ),
          pw.SizedBox(height: TextosHoja.separacionFila),
          pw.Text(
            t.titulo,
            maxLines: t.lineasTitulo,
            overflow: pw.TextOverflow.clip,
            style: _estilo(
              TextosHoja.titulo,
              negrita: true,
              color: ColoresHoja.tinta,
            ),
          ),
          if (lineasDetalle > 0)
            pw.Text(
              t.detalle,
              maxLines: lineasDetalle,
              overflow: pw.TextOverflow.clip,
              style: _estilo(TextosHoja.detalle, color: ColoresHoja.textoSuave),
            ),
          if (t.continuaDespues) ...[
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'sigue ',
                  style: _estilo(5.8, color: ColoresHoja.textoSuave),
                ),
                r.iconos(Icons.south, ColoresHoja.textoSuave, 6),
              ],
            ),
          ],
        ],
      );
    case TamanoTarjeta.mediana:
      contenido = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Row(
            children: [
              r.iconos(v.icono, v.acento, 8),
              pw.SizedBox(width: 2.5),
              pw.Expanded(
                child: pw.Text(
                  t.rango,
                  maxLines: 1,
                  style: _estilo(6.9, negrita: true, color: ColoresHoja.tinta),
                ),
              ),
              _casilla(t.marca, 7.5, r),
            ],
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            t.titulo,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: _estilo(6.9, negrita: true, color: ColoresHoja.tinta),
          ),
        ],
      );
    case TamanoTarjeta.chica:
      final diminuta = t.alto < 10;
      contenido = pw.Row(
        children: [
          r.iconos(v.icono, v.acento, diminuta ? 5.5 : 7),
          pw.SizedBox(width: 2),
          pw.Expanded(
            child: pw.RichText(
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '${t.horaInicio}  ',
                    style: _estilo(
                      diminuta ? 5.4 : 6.5,
                      negrita: true,
                      color: ColoresHoja.tinta,
                    ),
                  ),
                  pw.TextSpan(
                    text: t.titulo,
                    style: _estilo(
                      diminuta ? 5.4 : 6.5,
                      color: ColoresHoja.tinta,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 1.5),
          _casilla(t.marca, diminuta ? 5.5 : 7, r),
        ],
      );
  }

  return pw.Container(
    width: t.ancho,
    height: t.alto,
    decoration: pw.BoxDecoration(
      color: _c(v.fondo),
      border: pw.Border(
        left: pw.BorderSide(color: _c(v.acento), width: TextosHoja.barra),
        top: pw.BorderSide(
          color: _c(ColoresHoja.aclarar(v.acento, 0.55)),
          width: 0.5,
        ),
        right: pw.BorderSide(
          color: _c(ColoresHoja.aclarar(v.acento, 0.55)),
          width: 0.5,
        ),
        bottom: pw.BorderSide(
          color: _c(ColoresHoja.aclarar(v.acento, 0.55)),
          width: 0.5,
        ),
      ),
    ),
    padding: pw.EdgeInsets.symmetric(
      horizontal: TextosHoja.padH,
      vertical: t.tamano == TamanoTarjeta.chica ? 0.5 : TextosHoja.padV,
    ),
    child: pw.ClipRect(child: contenido),
  );
}

pw.Widget _leyendaItem(pw.Widget marca, String texto) => pw.Row(
  mainAxisSize: pw.MainAxisSize.min,
  children: [
    marca,
    pw.SizedBox(width: 3),
    pw.Text(texto, style: _estilo(6.8)),
  ],
);

pw.Widget _pie(HojaCronograma h, int pagina, int paginas, _Recursos r) {
  pw.Widget firma(String texto) => pw.Expanded(
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(height: 0.7, color: _c(ColoresHoja.texto)),
        pw.SizedBox(height: 2),
        pw.Text(texto, style: _estilo(6.6, color: ColoresHoja.textoSuave)),
      ],
    ),
  );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Expanded(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Wrap(
              spacing: 10,
              runSpacing: 3,
              crossAxisAlignment: pw.WrapCrossAlignment.center,
              children: [
                for (final v in h.categorias)
                  _leyendaItem(r.iconos(v.icono, v.acento, 8), v.nombre),
                _leyendaItem(
                  _casilla(MarcaCierre.pendiente, 7, r),
                  'Marcar al terminar',
                ),
                _leyendaItem(_casilla(MarcaCierre.hecha, 7, r), 'Terminada'),
                if (h.hayNoHechas)
                  _leyendaItem(
                    _casilla(MarcaCierre.noHecha, 7, r),
                    'No se hizo',
                  ),
                if (h.hayLibres)
                  _leyendaItem(
                    pw.Container(
                      width: 11,
                      height: 7,
                      decoration: pw.BoxDecoration(
                        color: _c(ColoresHoja.libreFondo),
                        border: pw.Border.all(
                          color: _c(ColoresHoja.libreBorde),
                          width: 0.6,
                        ),
                      ),
                    ),
                    'Libre: espacio para actividades especiales',
                  ),
                if (h.hayCompartidas)
                  _leyendaItem(
                    r.iconos(Icons.group, ColoresHoja.textoSuave, 8),
                    'Compartida',
                  ),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Generado el ${r.generadoTexto} · ControlApp',
              style: _estilo(6, color: ColoresHoja.textoSuave),
            ),
          ],
        ),
      ),
      if (h.ultimaParte) ...[
        pw.SizedBox(width: 16),
        pw.SizedBox(
          width: 280,
          height: MedidasHoja.pie,
          child: pw.Row(
            children: [
              firma('Firma de quien recibe'),
              pw.SizedBox(width: 16),
              firma('Firma de quien entrega'),
            ],
          ),
        ),
      ],
      pw.SizedBox(width: 12),
      pw.Text(
        'Página $pagina de $paginas',
        style: _estilo(6.6, color: ColoresHoja.textoSuave),
      ),
    ],
  );
}

/* ============================== Portada ============================== */

pw.Widget _tituloSeccion(String texto) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Text(
    texto,
    style: _estilo(12.5, negrita: true, color: ColoresHoja.tinta),
  ),
);

pw.BoxDecoration get _tarjetaPortada => pw.BoxDecoration(
  color: PdfColors.white,
  borderRadius: pw.BorderRadius.circular(8),
  border: pw.Border.all(color: _c(ColoresHoja.borde), width: 0.8),
);

pw.Widget _categoriaPortada(CategoriaResumen c, _Recursos r) => pw.Container(
  height: 32,
  margin: const pw.EdgeInsets.only(bottom: 6),
  padding: const pw.EdgeInsets.symmetric(horizontal: 9),
  decoration: _tarjetaPortada,
  child: pw.Row(
    children: [
      pw.Container(
        width: 20,
        height: 20,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: _c(c.visual.acento),
          shape: pw.BoxShape.circle,
        ),
        child: r.iconos(c.visual.icono, Colors.white, 11.5),
      ),
      pw.SizedBox(width: 9),
      pw.Expanded(
        child: pw.Text(
          c.visual.nombre,
          maxLines: 1,
          style: _estilo(9.5, negrita: true, color: ColoresHoja.tinta),
        ),
      ),
      pw.Text(
        '${c.actividades} ${c.actividades == 1 ? 'actividad' : 'actividades'} · ${duracionTexto(c.minutos)}',
        style: _estilo(7.4, color: ColoresHoja.textoSuave),
      ),
    ],
  ),
);

pw.Widget _puestoPortada(PuestoImpresion p) => pw.Container(
  height: 32,
  margin: const pw.EdgeInsets.only(bottom: 6),
  padding: const pw.EdgeInsets.symmetric(horizontal: 10),
  decoration: _tarjetaPortada,
  child: pw.Column(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        p.nombre,
        maxLines: 1,
        style: _estilo(9.5, negrita: true, color: ColoresHoja.tinta),
      ),
      if (p.detalle.isNotEmpty)
        pw.Text(
          p.detalle,
          maxLines: 1,
          style: _estilo(7.4, color: ColoresHoja.textoSuave),
        ),
    ],
  ),
);

pw.Widget _operarioPortada(OperarioImpresion o, _Recursos r) => pw.Container(
  height: 52,
  padding: const pw.EdgeInsets.symmetric(horizontal: 9),
  decoration: _tarjetaPortada,
  child: pw.Row(
    children: [
      _avatar(o, 24),
      pw.SizedBox(width: 9),
      pw.Expanded(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              o.ref.nombre,
              maxLines: 2,
              style: _estilo(9.2, negrita: true, color: ColoresHoja.tinta),
            ),
            if (o.subtitulo.isNotEmpty)
              pw.Text(
                o.subtitulo,
                maxLines: 1,
                style: _estilo(7.2, color: ColoresHoja.textoSuave),
              ),
            pw.Text(
              '${o.actividades} ${o.actividades == 1 ? 'actividad' : 'actividades'} · ${duracionTexto(o.minutos)}',
              style: _estilo(7, negrita: true, color: ColoresHoja.marca),
            ),
          ],
        ),
      ),
      for (final v in o.iconos.take(4)) ...[
        pw.SizedBox(width: 4),
        r.iconos(v.icono, v.acento, 11),
      ],
    ],
  ),
);

List<pw.Widget> _portada(PortadaCronograma p, _Recursos r) {
  final filas = p.categorias.length > p.puestos.length
      ? p.categorias.length
      : p.puestos.length;
  final operarios = p.operarios;
  return [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 112,
          height: 48,
          child: pw.Image(r.logo, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 18),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                p.etiquetaSuperior,
                style: _estilo(
                  9,
                  negrita: true,
                  color: ColoresHoja.marca,
                  espaciado: 1,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Cronograma de actividades por operario',
                style: _estilo(22, negrita: true, color: ColoresHoja.tinta),
              ),
              if (p.semanaTexto.isNotEmpty)
                pw.Text(
                  p.semanaTexto,
                  style: _estilo(10, color: ColoresHoja.textoSuave),
                ),
            ],
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 18),
    pw.Row(
      children: [
        pw.Expanded(child: _tituloSeccion('Categorías de actividad')),
        pw.SizedBox(width: 18),
        pw.Expanded(child: _tituloSeccion('Puestos')),
      ],
    ),
    // Una fila por par (categoría, puesto): así la portada puede seguir en
    // otra página si el conjunto tiene muchas.
    for (var i = 0; i < filas; i++)
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: i < p.categorias.length
                ? _categoriaPortada(p.categorias[i], r)
                : pw.SizedBox(),
          ),
          pw.SizedBox(width: 18),
          pw.Expanded(
            child: i < p.puestos.length
                ? _puestoPortada(p.puestos[i])
                : pw.SizedBox(),
          ),
        ],
      ),
    if (filas == 0)
      pw.Text(
        'No hay actividades en el período elegido.',
        style: _estilo(9, color: ColoresHoja.textoSuave),
      ),
    pw.SizedBox(height: 12),
    _tituloSeccion('Operarios asignados'),
    for (var i = 0; i < operarios.length; i += 3)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          children: [
            for (var k = i; k < i + 3; k++) ...[
              if (k > i) pw.SizedBox(width: 10),
              pw.Expanded(
                child: k < operarios.length
                    ? _operarioPortada(operarios[k], r)
                    : pw.SizedBox(),
              ),
            ],
          ],
        ),
      ),
  ];
}
