import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pages/cronograma/mis_actividades_page.dart';
import 'package:flutter_application_1/pages/cronograma/mis_actividades_repo.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';

/// Tarjeta "Hoy" del panel del operario: su avance del día y lo que toca
/// ahora, con un botón grande a "Mis actividades".
class HoyOperarioCard extends StatefulWidget {
  final String nit;

  const HoyOperarioCard({super.key, required this.nit});

  @override
  State<HoyOperarioCard> createState() => _HoyOperarioCardState();
}

class _HoyOperarioCardState extends State<HoyOperarioCard> {
  final _repo = MisActividadesRepo();
  List<TareaModel>? _hoy;
  Set<int> _sinEnviar = const {};
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final s = await _repo.sesion();
      if (s == null) {
        if (mounted) setState(() => _error = true);
        return;
      }
      final hoy = soloFecha(DateTime.now());
      final r = await _repo.cargar(
        s,
        desde: hoy,
        hasta: hoy.add(const Duration(days: 1)),
        guardarCopia: false,
      );
      final p = await _repo.cierresSinEnviar(s.usuarioId);
      if (!mounted) return;
      setState(() {
        _hoy = r.tareas.where((t) => mismoDia(t.fechaInicio, hoy)).toList()
          ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
        _sinEnviar = p;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _abrir() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MisActividadesPage(nit: widget.nit)),
    );
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final hoy = _hoy;
    final progreso = hoy == null
        ? null
        : progresoDelDia(hoy, cierresPendientesEnvio: _sinEnviar, ahora: ahora);
    TareaModel? actual;
    if (hoy != null) {
      for (final t in hoy) {
        final cerrada =
            _sinEnviar.contains(t.id) ||
            EstadoVisual.de(t, ahora: ahora).cerrada;
        if (!cerrada && t.fechaFin.isAfter(ahora)) {
          actual = t;
          break;
        }
      }
    }
    final hm = DateFormat('HH:mm');
    final enCurso = actual != null && !actual.fechaInicio.isAfter(ahora);

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _capitalizar(DateFormat("EEEE d 'de' MMMM", 'es').format(ahora)),
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              progreso == null
                  ? (_error
                        ? 'Tus actividades de hoy'
                        : 'Cargando tus actividades…')
                  : 'Llevas ${progreso.cerradas} de ${cantidadActividades(progreso.total)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (progreso != null && progreso.total > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progreso.fraccion,
                  minHeight: 14,
                  color: AppTheme.accent,
                  backgroundColor: Colors.white24,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                progreso.mensaje,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
            if (actual != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${enCurso ? 'Ahora' : 'Lo siguiente'}: ${actual.descripcion} · ${hm.format(actual.fechaInicio.toLocal())}–${hm.format(actual.fechaFin.toLocal())}${(actual.ubicacionNombre ?? '').isNotEmpty ? ' · ${actual.ubicacionNombre}' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _abrir,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: const Color(0xFF3A2600),
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.checklist),
              label: const Text('Ver mis actividades de hoy'),
            ),
          ],
        ),
      ),
    );
  }
}

String _capitalizar(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
