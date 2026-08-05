import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_excel_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';

class CargaConjuntoPage extends StatefulWidget {
  const CargaConjuntoPage({super.key});

  @override
  State<CargaConjuntoPage> createState() => _CargaConjuntoPageState();
}

class _CargaConjuntoPageState extends State<CargaConjuntoPage> {
  final GerenteApi _api = GerenteApi();

  PlatformFile? _file;
  CargaConjuntoResult? _result;
  String? _error;
  bool _uploading = false;
  bool _downloading = false;
  bool _created = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() {
      _file = result.files.single;
      _result = null;
      _error = null;
    });
  }

  Future<void> _downloadTemplate() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final bytes = await _api.descargarPlantillaConjunto();
      await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar plantilla del conjunto',
        fileName: 'plantilla_conjunto.xlsx',
        bytes: bytes,
      );
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('Plantilla descargada correctamente.'),
          backgroundColor: AppTheme.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(
          error,
          fallback: 'No se pudo descargar la plantilla.',
        );
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null) {
      setState(() => _error = 'Selecciona una plantilla .xlsx.');
      return;
    }

    setState(() {
      _uploading = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await _api.cargarConjuntoMasivo(file: file);
      if (!mounted) return;
      setState(() {
        _result = result;
        _created = result.creado;
      });
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            result.creado
                ? 'Conjunto cargado correctamente.'
                : 'La plantilla contiene errores y no se realizaron cambios.',
          ),
          backgroundColor: result.creado ? AppTheme.green : AppTheme.red,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(
          error,
          fallback: 'No se pudo procesar la plantilla del conjunto.',
        );
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openPdfReport() async {
    final result = _result;
    if (result == null) return;
    final bytes = await _buildPdfReport(result);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<Uint8List> _buildPdfReport(CargaConjuntoResult result) async {
    final doc = pw.Document();
    final resumen = result.resumen;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'Reporte de carga masiva de conjunto',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Conjunto: ${result.conjuntoNombre} (${result.conjuntoNit})'),
          pw.Text('Archivo: ${_file?.name ?? 'plantilla_conjunto.xlsx'}'),
          pw.Text(
            'Estado: ${result.creado ? 'Creado' : 'Rechazado sin cambios'}',
          ),
          pw.SizedBox(height: 12),
          pw.Text('Horarios: ${resumen.horarios}'),
          pw.Text('Ubicaciones: ${resumen.ubicaciones}'),
          pw.Text(
            'Operarios creados/reutilizados: ${resumen.operariosCreados}/${resumen.operariosReutilizados}',
          ),
          pw.Text(
            'Preventivas creadas/fallidas: ${resumen.preventivasCreadas}/${resumen.preventivasFallidas}',
          ),
          pw.Text('Definiciones creadas: ${resumen.definicionesCreadas}'),
          pw.Text(
            'Recursos (insumos/maquinaria/herramientas): ${resumen.insumosPreventivas}/${resumen.maquinariaPreventivas}/${resumen.herramientasPreventivas}',
          ),
          pw.SizedBox(height: 18),
          if (result.errores.isEmpty)
            pw.Text('No hubo errores en el cargue.')
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: const ['Fila', 'Sección', 'Código', 'Motivo'],
              data: result.errores
                  .map(
                    (error) => [
                      error.fila,
                      error.seccion,
                      error.codigo ?? '',
                      error.motivo,
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );
    return doc.save();
  }

  void _close() => Navigator.pop(context, _created);

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Cargar conjunto desde Excel',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crea el conjunto completo desde una plantilla',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La plantilla incluye datos del conjunto, operarios, disponibilidades, preventivas y recursos. Las listas múltiples aceptan coma o punto y coma.',
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _downloading || _uploading
                        ? null
                        : _downloadTemplate,
                    icon: _downloading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      _downloading ? 'Descargando...' : 'Descargar plantilla',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      _file == null
                          ? 'Seleccionar archivo .xlsx'
                          : '${_file!.name} (${(_file!.size / 1024).toStringAsFixed(1)} KB)',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: const TextStyle(color: AppTheme.red)),
                  ],
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      _uploading ? 'Procesando...' : 'Cargar conjunto',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.creado
                          ? 'Resultado del cargue'
                          : 'Plantilla rechazada sin cambios',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MetricChip(
                          label: 'Horarios',
                          value: result.resumen.horarios,
                        ),
                        _MetricChip(
                          label: 'Ubicaciones',
                          value: result.resumen.ubicaciones,
                        ),
                        _MetricChip(
                          label: 'Operarios creados',
                          value: result.resumen.operariosCreados,
                          color: AppTheme.green,
                        ),
                        _MetricChip(
                          label: 'Operarios reutilizados',
                          value: result.resumen.operariosReutilizados,
                        ),
                        _MetricChip(
                          label: 'Preventivas creadas',
                          value: result.resumen.preventivasCreadas,
                          color: AppTheme.green,
                        ),
                        _MetricChip(
                          label: 'Preventivas fallidas',
                          value: result.resumen.preventivasFallidas,
                          color: AppTheme.red,
                        ),
                        _MetricChip(
                          label: 'Definiciones creadas',
                          value: result.resumen.definicionesCreadas,
                        ),
                        _MetricChip(
                          label: 'Insumos planeados',
                          value: result.resumen.insumosPreventivas,
                        ),
                        _MetricChip(
                          label: 'Maquinaria planeada',
                          value: result.resumen.maquinariaPreventivas,
                        ),
                        _MetricChip(
                          label: 'Herramientas planeadas',
                          value: result.resumen.herramientasPreventivas,
                        ),
                      ],
                    ),
                    if (result.errores.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: _openPdfReport,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Abrir reporte PDF de fallidos'),
                      ),
                      const SizedBox(height: 10),
                      ...result.errores
                          .take(10)
                          .map(
                            (error) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.red.withValues(
                                  alpha: 0.12,
                                ),
                                foregroundColor: AppTheme.red,
                                child: Text('${error.fila}'),
                              ),
                              title: Text(
                                error.codigo == null || error.codigo!.isEmpty
                                    ? error.seccion
                                    : '${error.seccion} · ${error.codigo}',
                              ),
                              subtitle: Text(error.motivo),
                            ),
                          ),
                      if (result.errores.length > 10)
                        const Text(
                          'Se muestran 10 errores. El PDF contiene el detalle completo.',
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.color = AppTheme.primary,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
