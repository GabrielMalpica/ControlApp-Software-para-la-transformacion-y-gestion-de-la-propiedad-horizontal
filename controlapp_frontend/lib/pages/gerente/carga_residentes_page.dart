import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/api/residentes_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/residente_admin_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CargaResidentesPage extends StatefulWidget {
  const CargaResidentesPage({
    super.key,
    this.conjuntoFijoNit,
    this.conjuntoFijoNombre,
  });

  final String? conjuntoFijoNit;
  final String? conjuntoFijoNombre;

  @override
  State<CargaResidentesPage> createState() => _CargaResidentesPageState();
}

class _CargaResidentesPageState extends State<CargaResidentesPage> {
  final _residentesApi = ResidentesApi();
  final _gerenteApi = GerenteApi();

  List<Conjunto> _conjuntos = const [];
  String? _conjuntoNit;
  bool _loadingConjuntos = false;
  bool _uploading = false;
  String? _error;
  PlatformFile? _file;
  CargaResidentesResult? _result;

  bool get _conjuntoBloqueado =>
      widget.conjuntoFijoNit != null &&
      widget.conjuntoFijoNit!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_conjuntoBloqueado) {
      _conjuntoNit = widget.conjuntoFijoNit!.trim();
    } else {
      _cargarConjuntos();
    }
  }

  Future<void> _cargarConjuntos() async {
    setState(() {
      _loadingConjuntos = true;
      _error = null;
    });

    try {
      final conjuntos = await _gerenteApi.listarConjuntos();
      if (!mounted) return;
      setState(() {
        _conjuntos = conjuntos;
        _conjuntoNit = conjuntos.isNotEmpty ? conjuntos.first.nit : null;
        _loadingConjuntos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingConjuntos = false;
        _error = AppError.messageOf(
          e,
          fallback: 'No se pudieron cargar los conjuntos.',
        );
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _file = result.files.single;
      _error = null;
    });
  }

  Future<void> _upload() async {
    if ((_conjuntoNit ?? '').isEmpty) {
      setState(
        () => _error = 'Selecciona un conjunto antes de cargar el archivo.',
      );
      return;
    }
    if (_file == null) {
      setState(() => _error = 'Selecciona un archivo Excel o CSV.');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _residentesApi.cargarResidentesMasivo(
        conjuntoId: _conjuntoNit!,
        file: _file!,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = AppError.messageOf(
          e,
          fallback: 'No se pudo procesar el archivo de residentes.',
        );
      });
    }
  }

  Future<void> _openPdfReport() async {
    if (_result == null) return;
    final bytes = await _buildPdfReport(_result!);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<Uint8List> _buildPdfReport(CargaResidentesResult result) async {
    final doc = pw.Document();
    final rows = result.errores;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'Reporte de cargue de residentes',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Conjunto: ${result.conjuntoNombre} (${result.conjuntoNit})'),
          pw.Text('Archivo: ${result.resumen.archivo}'),
          pw.Text('Total filas: ${result.resumen.totalFilas}'),
          pw.Text('Creados: ${result.resumen.creados}'),
          pw.Text('Fallidos: ${result.resumen.fallidos}'),
          pw.SizedBox(height: 18),
          if (rows.isEmpty)
            pw.Text('No hubo errores en el cargue.')
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: const ['Fila', 'Cedula', 'Nombre', 'Correo', 'Motivo'],
              data: rows
                  .map(
                    (e) => [
                      '${e.fila}',
                      e.cedula,
                      e.nombre,
                      e.correo,
                      e.motivo,
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cargue masivo de residentes')),
      body: _loadingConjuntos
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Importa residentes desde Excel o CSV',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Columnas recomendadas: cédula, nombre, correo, teléfono, tipoUnidad, sector, unidad. También soporta torre/apartamento o casa.',
                        ),
                        const SizedBox(height: 18),
                        if (_conjuntoBloqueado)
                          TextFormField(
                            initialValue:
                                widget.conjuntoFijoNombre ?? _conjuntoNit ?? '',
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'Conjunto',
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _conjuntoNit,
                            decoration: const InputDecoration(
                              labelText: 'Conjunto',
                            ),
                            items: _conjuntos
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.nit,
                                    child: Text(c.nombre),
                                  ),
                                )
                                .toList(),
                            onChanged: _uploading
                                ? null
                                : (value) =>
                                      setState(() => _conjuntoNit = value),
                          ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _uploading ? null : _pickFile,
                          icon: const Icon(Icons.upload_file),
                          label: Text(
                            _file == null ? 'Seleccionar archivo' : _file!.name,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(color: AppTheme.red),
                          ),
                        ],
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: _uploading ? null : _upload,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            _uploading ? 'Procesando...' : 'Cargar residentes',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resultado del cargue',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _MetricChip(
                                label: 'Filas',
                                value: '${_result!.resumen.totalFilas}',
                              ),
                              _MetricChip(
                                label: 'Creados',
                                value: '${_result!.resumen.creados}',
                                color: AppTheme.green,
                              ),
                              _MetricChip(
                                label: 'Fallidos',
                                value: '${_result!.resumen.fallidos}',
                                color: AppTheme.red,
                              ),
                            ],
                          ),
                          if (_result!.errores.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _openPdfReport,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text(
                                'Abrir reporte PDF de fallidos',
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._result!.errores
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
                                      error.nombre.isEmpty
                                          ? 'Fila ${error.fila}'
                                          : error.nombre,
                                    ),
                                    subtitle: Text(error.motivo),
                                  ),
                                ),
                            if (_result!.errores.length > 10)
                              Text(
                                'Se muestran 10 errores. El reporte PDF incluye el detalle completo.',
                                style: Theme.of(context).textTheme.bodySmall,
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
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
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
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
