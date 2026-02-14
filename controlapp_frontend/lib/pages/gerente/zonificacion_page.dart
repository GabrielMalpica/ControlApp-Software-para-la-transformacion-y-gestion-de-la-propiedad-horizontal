import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/reporte_api.dart';
import 'package:flutter_application_1/model/reporte_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';

class ZonificacionPage extends StatefulWidget {
  const ZonificacionPage({super.key});

  @override
  State<ZonificacionPage> createState() => _ZonificacionPageState();
}

class _ZonificacionPageState extends State<ZonificacionPage> {
  final _api = ReporteApi();

  late DateTime _desde;
  late DateTime _hasta;

  bool _loading = false;
  bool _soloActivas = true;
  String? _error;

  ZonificacionResumen? _resumen;
  List<ZonificacionConjuntoRow> _conjuntos = const [];
  List<ZonificacionInsumoRow> _topInsumosGlobal = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _desde = DateTime(now.year, now.month, 1);
    _hasta = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _cargar();
  }

  Future<void> _pickRango() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 3, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
    );
    if (range == null) return;

    setState(() {
      _desde = DateTime(range.start.year, range.start.month, range.start.day);
      _hasta = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
    });
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await _api.zonificacionPreventivas(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: null,
        soloActivas: _soloActivas,
      );

      setState(() {
        _resumen = resp.resumen;
        _conjuntos = resp.data;
        _topInsumosGlobal = resp.topInsumosGlobal;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _kpi(String title, String value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtArea(double value, String? unidad) {
    final u = (unidad ?? '').trim();
    if (u.isEmpty) return value.toStringAsFixed(2);
    return '${value.toStringAsFixed(2)} $u';
  }

  Widget _insumoItem(ZonificacionInsumoRow i) {
    final rendimientoTxt = i.rendimientoPromedio == null
        ? 'N/D'
        : i.rendimientoPromedio!.toStringAsFixed(3);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              i.nombre,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            '${i.consumoEstimado.toStringAsFixed(2)} ${i.unidad} | usos: ${i.usos} | rinde: $rendimientoTxt',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'es');
    final resumen = _resumen;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Zonificacion por Preventivas',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              children: [
                InkWell(
                  onTap: _pickRango,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                      color: Colors.white,
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 10,
                          color: Color(0x0F000000),
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range, color: AppTheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          '${df.format(_desde)} -> ${df.format(_hasta)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(
                      value: _soloActivas,
                      activeThumbColor: AppTheme.primary,
                      activeTrackColor: AppTheme.primary.withValues(
                        alpha: 0.35,
                      ),
                      onChanged: (v) {
                        setState(() => _soloActivas = v);
                        _cargar();
                      },
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Solo preventivas activas',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : resumen == null || _conjuntos.isEmpty
                ? const Center(
                    child: Text(
                      'Sin datos de zonificacion para el rango seleccionado.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _kpi('Conjuntos', resumen.conjuntos.toString()),
                          _kpi('Ubicaciones', resumen.ubicaciones.toString()),
                          _kpi('Preventivas', resumen.preventivas.toString()),
                          _kpi(
                            'Area total',
                            resumen.areaTotal.toStringAsFixed(2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_topInsumosGlobal.isNotEmpty) ...[
                        const Text(
                          'Top insumos estimados (global)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._topInsumosGlobal.take(12).map(_insumoItem),
                        const SizedBox(height: 14),
                      ],
                      const Text(
                        'Cobertura por conjunto y ubicacion',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._conjuntos.map((c) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.conjuntoNombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID: ${c.conjuntoId} | Preventivas: ${c.preventivas} | Ubicaciones: ${c.ubicaciones} | Area: ${c.areaTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              if (c.topInsumos.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: c.topInsumos.take(4).map((i) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '${i.nombre}: ${i.consumoEstimado.toStringAsFixed(2)} ${i.unidad}',
                                        style: TextStyle(
                                          color: AppTheme.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                              const SizedBox(height: 10),
                              ...c.ubicacionesDetalle.map((u) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFD),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.black12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.ubicacionNombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Preventivas: ${u.preventivas} | Area: ${_fmtArea(u.areaTotal, u.unidadCalculo)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      if (u.topInsumos.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        ...u.topInsumos
                                            .take(3)
                                            .map(
                                              (i) => Text(
                                                '- ${i.nombre}: ${i.consumoEstimado.toStringAsFixed(2)} ${i.unidad}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ),
                                      ],
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
