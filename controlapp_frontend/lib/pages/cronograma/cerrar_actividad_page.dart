import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/evidencia_camara_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/cierre_utils.dart';
import 'package:flutter_application_1/utils/pickers/clipboard_image_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/optimizar_imagen_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';
import 'package:flutter_application_1/utils/uploader_preview/preview_bridge.dart';
import 'package:flutter_application_1/widgets/cerrar_tarea_sheet.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_ui.dart';

/// Cierre guiado de una actividad en tres pasos cortos:
/// 1) ¿Pudiste hacerla? 2) Fotos, insumos y comentario (o el motivo si no se
/// pudo) 3) Revisar y enviar.
///
/// Devuelve el mismo [CerrarTareaResult] que la hoja de cierre, así que el
/// envío, las validaciones del servidor y la cola sin conexión no cambian.
class CerrarActividadPage extends StatefulWidget {
  final TareaModel tarea;
  final List<InventarioItemResponse> inventario;

  /// Quien cierra (para decir "compartida con …" sin incluirse).
  final String? usuarioActualId;

  const CerrarActividadPage({
    super.key,
    required this.tarea,
    this.inventario = const [],
    this.usuarioActualId,
  });

  @override
  State<CerrarActividadPage> createState() => _CerrarActividadPageState();
}

class _FilaInsumo {
  int? insumoId;
  final TextEditingController cantidad = TextEditingController();
}

class _CerrarActividadPageState extends State<CerrarActividadPage> {
  int _paso = 1;
  bool? _laHizo;
  bool? _usoInsumos;
  final List<EvidenciaAdjunto> _fotos = [];
  final List<_FilaInsumo> _filas = [];
  final TextEditingController _comentario = TextEditingController();
  final TextEditingController _motivo = TextEditingController();
  String? _motivoRapido;
  String? _errorMotivo;
  String? _errorInsumos;
  ClipboardImageDispose? _soltarPegado;

  bool get _esMovil =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // En web (celular o tableta desde el navegador) el <input capture> abre la
  // cámara; en iPad Safari defaultTargetPlatform dice macOS, por eso web
  // siempre ofrece "Tomar foto".
  bool get _puedeTomarFoto => kIsWeb || _esMovil;

  bool _puedePegar(BuildContext context) =>
      kIsWeb &&
      ClipboardImageCapture.isSupported &&
      MediaQuery.sizeOf(context).width >= 900;

  bool get _hayCambios =>
      _laHizo != null ||
      _fotos.isNotEmpty ||
      _comentario.text.trim().isNotEmpty ||
      _motivo.text.trim().isNotEmpty ||
      _filas.isNotEmpty;

  List<TrabajadorRef> get _companeros => trabajadoresDe([
    widget.tarea,
  ]).where((t) => t.id != widget.usuarioActualId).toList();

  @override
  void initState() {
    super.initState();
    // La hora y el GPS de cada foto van en su marca de agua de auditoría.
    EvidenciaCamara.precalentarUbicacion();
    if (kIsWeb && ClipboardImageCapture.isSupported) {
      _soltarPegado = ClipboardImageCapture.registerPasteListener(
        (archivo) async => _agregar(
          evidenciasDesdeArchivos([await OptimizadorImagen.optimizar(archivo)]),
        ),
      );
    }
  }

  @override
  void dispose() {
    _soltarPegado?.call();
    _comentario.dispose();
    _motivo.dispose();
    for (final f in _filas) {
      f.cantidad.dispose();
    }
    super.dispose();
  }

  void _agregar(List<EvidenciaAdjunto> nuevas) {
    if (!mounted) return;
    if (nuevas.isEmpty) {
      _avisar('No se pudo leer la foto. Intenta de nuevo.');
      return;
    }
    setState(() {
      for (final e in nuevas) {
        if (!_fotos.any((x) => mismaEvidencia(x, e))) _fotos.add(e);
      }
    });
    _avisar(
      nuevas.length == 1
          ? 'Foto agregada.'
          : '${nuevas.length} fotos agregadas.',
    );
  }

  void _avisar(String texto) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(texto), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _tomarFoto() async {
    try {
      final foto = await EvidenciaCamara.tomarFoto();
      if (foto == null) return;
      _agregar(evidenciasDesdeArchivos([foto]));
    } catch (_) {
      _avisar('No se pudo abrir la cámara. Usa "Elegir de la galería".');
    }
  }

  Future<void> _elegirArchivos() async {
    final elegidos = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'jfif',
        'png',
        'webp',
        'gif',
        'bmp',
        'heic',
        'heif',
        'pdf',
      ],
    );
    if (elegidos == null) return;
    // En web las fotos se reducen a 1920 px para que el cierre suba rápido.
    final archivos = await OptimizadorImagen.optimizarTodas(
      elegidos.files.map(
        (f) => SelectedUploadFile(
          name: f.name,
          bytes: f.bytes,
          path: kIsWeb ? null : f.path,
        ),
      ),
    );
    _agregar(evidenciasDesdeArchivos(archivos));
  }

  void _siguiente() {
    if (_paso == 2 && _laHizo == false) {
      if (_motivo.text.trim().length < 3) {
        setState(
          () => _errorMotivo = 'Escribe el motivo con al menos una palabra.',
        );
        return;
      }
    }
    if (_paso == 2 && _laHizo == true && _usoInsumos == true) {
      final incompletas = _filas.where(
        (f) =>
            f.insumoId == null ||
            (num.tryParse(f.cantidad.text.replaceAll(',', '.')) ?? 0) <= 0,
      );
      if (incompletas.isNotEmpty) {
        setState(
          () => _errorInsumos =
              'Completa el insumo y la cantidad, o quita la fila.',
        );
        return;
      }
    }
    setState(() {
      _errorMotivo = null;
      _errorInsumos = null;
      _paso++;
    });
  }

  void _atras() {
    setState(() => _paso = _paso <= 1 ? 1 : _paso - 1);
  }

  List<InsumoUsadoEntrada> get _entradasInsumos => [
    for (final f in _filas)
      if (f.insumoId != null)
        InsumoUsadoEntrada(
          f.insumoId!,
          num.tryParse(f.cantidad.text.replaceAll(',', '.')) ?? 0,
        ),
  ];

  void _enviar() {
    final hizo = _laHizo == true;
    final texto = hizo ? _comentario.text.trim() : _motivo.text.trim();
    Navigator.of(context).pop(
      CerrarTareaResult(
        accion: hizo ? 'COMPLETADA' : 'NO_COMPLETADA',
        insumosUsados: hizo && _usoInsumos == true
            ? insumosParaCierre(_entradasInsumos, widget.inventario)
            : const [],
        observaciones: texto.isEmpty ? null : texto,
        evidencias: List.of(_fotos),
      ),
    );
  }

  Future<bool> _confirmarSalida() async {
    if (!_hayCambios) return true;
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin enviar?'),
        content: const Text('Se perderán las fotos y lo que escribiste.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir aquí'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir sin enviar'),
          ),
        ],
      ),
    );
    return salir == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tarea;
    final visual = CategoriaVisual.deTarea(t);
    final hm = DateFormat('HH:mm');

    return PopScope(
      canPop: !_hayCambios,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmarSalida()) nav.pop();
      },
      child: EscalaTexto(
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: const Text('Registrar cierre'),
            leading: IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await _confirmarSalida()) nav.pop();
              },
            ),
            actions: const [TamanoTextoBoton()],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _Pasos(paso: _paso),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              CategoriaTile(visual: visual, tamano: 34),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${t.descripcion} · ${hm.format(t.fechaInicio.toLocal())}–${hm.format(t.fechaFin.toLocal())}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          ..._contenido(),
                        ],
                      ),
                    ),
                  ),
                ),
                _pie(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _contenido() {
    switch (_paso) {
      case 1:
        return [
          const _Titulo('¿Pudiste hacer la actividad?'),
          const SizedBox(height: 14),
          _BotonGrande(
            icono: Icons.check_circle,
            texto: 'Sí, la terminé',
            color: const Color(0xFF14532D),
            fondo: const Color(0xFFF0FAF3),
            borde: const Color(0xFF15803D),
            onTap: () => setState(() {
              _laHizo = true;
              _paso = 2;
            }),
          ),
          const SizedBox(height: 12),
          _BotonGrande(
            icono: Icons.report,
            texto: 'No pude hacerla',
            color: const Color(0xFF7C2D12),
            fondo: const Color(0xFFFFF7ED),
            borde: const Color(0xFFD97706),
            onTap: () => setState(() {
              _laHizo = false;
              _paso = 2;
            }),
          ),
        ];
      case 2:
        return _laHizo == true ? _pasoHecha() : _pasoNoHecha();
      default:
        return _pasoRevisar();
    }
  }

  List<Widget> _pasoHecha() {
    final maquinas = [
      ...widget.tarea.maquinariasAsignadas.map((m) => m.nombre),
      ...widget.tarea.herramientasAsignadas.map((h) => h.nombre),
    ];
    return [
      const _Titulo('Cuéntanos cómo quedó'),
      const SizedBox(height: 14),
      _Seccion(
        titulo: 'Fotos del trabajo terminado',
        icono: Icons.photo_camera_outlined,
        ayuda: 'Recomendado: 1 o 2 fotos donde se vea el lugar.',
        children: [_botonesFotos(), _miniaturas()],
      ),
      const SizedBox(height: 14),
      _Seccion(
        titulo: '¿Usaste insumos de la bodega?',
        icono: Icons.inventory_2_outlined,
        children: [
          if (widget.inventario.isEmpty)
            const Text(
              'No se pudo cargar el inventario. Puedes cerrar sin registrar insumos.',
              style: TextStyle(color: AppTheme.textMuted),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _Opcion(
                    texto: 'No usé',
                    seleccionada: _usoInsumos == false,
                    onTap: () => setState(() => _usoInsumos = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Opcion(
                    texto: 'Sí, registrar',
                    seleccionada: _usoInsumos == true,
                    onTap: () => setState(() {
                      _usoInsumos = true;
                      if (_filas.isEmpty) _filas.add(_FilaInsumo());
                    }),
                  ),
                ),
              ],
            ),
            if (_usoInsumos == true) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < _filas.length; i++) _filaInsumo(i),
              if (_errorInsumos != null) _Error(_errorInsumos!),
              TextButton.icon(
                onPressed: () => setState(() => _filas.add(_FilaInsumo())),
                icon: const Icon(Icons.add),
                label: const Text('Agregar otro insumo'),
              ),
            ],
          ],
        ],
      ),
      if (maquinas.isNotEmpty) ...[
        const SizedBox(height: 14),
        _Seccion(
          titulo: 'Maquinaria y herramientas de esta actividad',
          icono: Icons.handyman_outlined,
          ayuda: 'Al cerrar quedan devueltas.',
          children: [Text(maquinas.join('\n'))],
        ),
      ],
      const SizedBox(height: 14),
      TextField(
        controller: _comentario,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Comentario (opcional)',
          hintText: 'Ej.: quedó un vidrio rayado en la puerta',
          alignLabelWithHint: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  Widget _botonesFotos() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (_puedeTomarFoto)
          FilledButton.icon(
            onPressed: _tomarFoto,
            style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Tomar foto'),
          ),
        OutlinedButton.icon(
          onPressed: _elegirArchivos,
          style: OutlinedButton.styleFrom(minimumSize: const Size(160, 52)),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(
            _puedeTomarFoto ? 'Elegir de la galería' : 'Elegir fotos',
          ),
        ),
        if (_puedePegar(context))
          OutlinedButton.icon(
            onPressed: () => _avisar(
              'Copia la imagen y presiona Ctrl+V con esta pantalla abierta.',
            ),
            style: OutlinedButton.styleFrom(minimumSize: const Size(160, 52)),
            icon: const Icon(Icons.content_paste),
            label: const Text('Pegar imagen'),
          ),
      ],
    );
  }

  Widget _miniaturas() {
    if (_fotos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'Aún no agregas fotos.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < _fotos.length; i++)
            SizedBox(
              width: 110,
              child: Column(
                children: [
                  _Miniatura(foto: _fotos[i], numero: i + 1),
                  TextButton.icon(
                    onPressed: () => setState(() => _fotos.removeAt(i)),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Quitar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaInsumo(int i) {
    final fila = _filas[i];
    InventarioItemResponse? item;
    for (final x in widget.inventario) {
      if (x.insumoId == fila.insumoId) item = x;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: fila.insumoId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Insumo'),
              items: [
                for (final x in widget.inventario)
                  DropdownMenuItem(
                    value: x.insumoId,
                    child: Text(
                      '${x.nombre} (hay ${etiquetaStock(x)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => fila.insumoId = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: fila.cantidad,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: item == null
                    ? 'Cantidad'
                    : 'Cantidad (${unidadEntrada(item)})',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Quitar insumo',
            onPressed: () => setState(() {
              fila.cantidad.dispose();
              _filas.removeAt(i);
            }),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  List<Widget> _pasoNoHecha() {
    return [
      const _Titulo('¿Por qué no pudiste hacerla?'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in kMotivosNoRealizada)
            ChoiceChip(
              label: Text(m),
              selected: _motivoRapido == m,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => setState(() {
                _motivoRapido = m;
                if (m != 'Otro motivo') _motivo.text = '$m.';
                _errorMotivo = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _motivo,
        minLines: 3,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Explica brevemente (obligatorio)',
          alignLabelWithHint: true,
          errorText: _errorMotivo,
        ),
        onChanged: (v) {
          if (_errorMotivo != null && v.trim().length >= 3) {
            setState(() => _errorMotivo = null);
          } else {
            setState(() {});
          }
        },
      ),
      const SizedBox(height: 14),
      _Seccion(
        titulo: 'Foto (opcional)',
        icono: Icons.photo_camera_outlined,
        children: [_botonesFotos(), _miniaturas()],
      ),
    ];
  }

  List<Widget> _pasoRevisar() {
    final hizo = _laHizo == true;
    final companeros = _companeros;
    final insumos = _entradasInsumos;
    String nombreInsumo(int id) {
      for (final x in widget.inventario) {
        if (x.insumoId == id) return '${x.nombre} (${unidadEntrada(x)})';
      }
      return 'Insumo $id';
    }

    return [
      const _Titulo('Revisa antes de enviar'),
      const SizedBox(height: 12),
      if (companeros.isNotEmpty)
        _Aviso(
          icono: Icons.group,
          color: const Color(0xFFFFF4D1),
          borde: const Color(0xFFE5C25F),
          titulo:
              'Esta actividad es compartida con ${nombresEnLista(companeros.map((c) => c.nombre))}',
          texto:
              'Al enviarla, quedará cerrada también para ${companeros.length == 1 ? companeros.first.primerNombre : 'ellos'}.',
        ),
      const SizedBox(height: 8),
      _Resumen(
        etiqueta: 'Resultado',
        valor: hizo ? 'Terminada' : 'No se pudo hacer',
      ),
      _Resumen(
        etiqueta: 'Fotos',
        valor: _fotos.isEmpty
            ? 'Sin fotos'
            : (_fotos.length == 1 ? '1 foto' : '${_fotos.length} fotos'),
      ),
      if (hizo)
        _Resumen(
          etiqueta: 'Insumos',
          valor: _usoInsumos == true && insumos.isNotEmpty
              ? insumos
                    .map((e) => '${e.cantidad} de ${nombreInsumo(e.insumoId)}')
                    .join('\n')
              : 'Ninguno',
        ),
      _Resumen(
        etiqueta: hizo ? 'Comentario' : 'Motivo',
        valor: (hizo ? _comentario.text : _motivo.text).trim().ifEmpty(
          'Sin comentario',
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Si no hay señal, el cierre se guarda en este dispositivo y se envía solo cuando vuelva.',
        style: TextStyle(color: AppTheme.textMuted),
      ),
    ];
  }

  Widget _pie() {
    final botones = <Widget>[];
    if (_paso == 1) {
      botones.add(
        OutlinedButton.icon(
          onPressed: () async {
            final nav = Navigator.of(context);
            if (await _confirmarSalida()) nav.pop();
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
          icon: const Icon(Icons.close),
          label: const Text('Cancelar'),
        ),
      );
    } else {
      botones.add(
        FilledButton.icon(
          onPressed: _paso == 3 ? _enviar : _siguiente,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          icon: Icon(_paso == 3 ? Icons.task_alt : Icons.arrow_forward),
          label: Text(_paso == 3 ? 'Enviar cierre' : 'Siguiente: revisar'),
        ),
      );
      botones.add(const SizedBox(height: 8));
      botones.add(
        OutlinedButton.icon(
          onPressed: _atras,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          icon: Icon(_paso == 3 ? Icons.edit : Icons.arrow_back),
          label: Text(_paso == 3 ? 'Volver y cambiar' : 'Atrás'),
        ),
      );
    }
    return Material(
      color: Colors.white,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(mainAxisSize: MainAxisSize.min, children: botones),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => trim().isEmpty ? otro : this;
}

class _Pasos extends StatelessWidget {
  final int paso;

  const _Pasos({required this.paso});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Paso $paso de 3',
      excludeSemantics: true,
      child: Row(
        children: [
          Text(
            'Paso $paso de 3',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          for (var i = 1; i <= 3; i++)
            Container(
              width: 30,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: i <= paso ? AppTheme.primary : const Color(0xFFD7E4DB),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;

  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

class _BotonGrande extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  final Color fondo;
  final Color borde;
  final VoidCallback onTap;

  const _BotonGrande({
    required this.icono,
    required this.texto,
    required this.color,
    required this.fondo,
    required this.borde,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fondo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borde, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icono, size: 36, color: borde),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    texto,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  final String texto;
  final bool seleccionada;
  final VoidCallback onTap;

  const _Opcion({
    required this.texto,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: seleccionada,
      button: true,
      child: seleccionada
          ? FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.check),
              label: Text(texto),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(texto),
            ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String? ayuda;
  final List<Widget> children;

  const _Seccion({
    required this.titulo,
    required this.icono,
    this.ayuda,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (ayuda != null) ...[
            const SizedBox(height: 4),
            Text(ayuda!, style: const TextStyle(color: AppTheme.textMuted)),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  final EvidenciaAdjunto foto;
  final int numero;

  const _Miniatura({required this.foto, required this.numero});

  @override
  Widget build(BuildContext context) {
    final nombre = foto.nombre.toLowerCase();
    final esPdf = nombre.endsWith('.pdf');
    Widget imagen;
    if (esPdf) {
      imagen = const Icon(
        Icons.picture_as_pdf,
        size: 40,
        color: Color(0xFFB91C1C),
      );
    } else if (foto.bytes != null && foto.bytes!.isNotEmpty) {
      imagen = Image.memory(
        Uint8List.fromList(foto.bytes!),
        fit: BoxFit.cover,
        width: 110,
        height: 110,
        errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 40),
      );
    } else if ((foto.path ?? '').isNotEmpty && !kIsWeb) {
      imagen = PreviewHelper.previewXFile(XFile(foto.path!), size: 110);
    } else {
      imagen = const Icon(Icons.image, size: 40);
    }
    return Semantics(
      image: true,
      label: 'Foto $numero',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 110,
          height: 110,
          color: AppTheme.surfaceSoft,
          alignment: Alignment.center,
          child: imagen,
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final String texto;

  const _Error(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final Color color;
  final Color borde;
  final String titulo;
  final String texto;

  const _Aviso({
    required this.icono,
    required this.color,
    required this.borde,
    required this.titulo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: const Color(0xFF5A4100)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(texto),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  final String etiqueta;
  final String valor;

  const _Resumen({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFD7E4DB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 2),
          Text(
            valor,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
