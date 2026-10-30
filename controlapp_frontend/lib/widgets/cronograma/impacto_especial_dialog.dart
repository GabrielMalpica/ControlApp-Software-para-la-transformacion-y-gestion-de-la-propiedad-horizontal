import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/impacto_correctiva_model.dart';

/// Lo que eligió el usuario al revisar el impacto de una actividad especial.
class DecisionImpactoEspecial {
  /// Programar en el horario sugerido (libre para todos) en vez del pedido.
  final bool usarSugerencia;

  /// Motivo del reemplazo (vacío si no se escribió).
  final String motivo;

  const DecisionImpactoEspecial.programar({this.motivo = ''})
    : usarSugerencia = false;

  const DecisionImpactoEspecial.sugerencia()
    : usarSugerencia = true,
      motivo = '';
}

const _rojo = Color(0xFFB91C1C);
const _rojoSuave = Color(0xFFFEF2F2);
const _ambar = Color(0xFFB45309);
const _ambarSuave = Color(0xFFFFFBEB);
const _azul = Color(0xFF1D4ED8);
const _azulSuave = Color(0xFFEFF6FF);
const _verde = Color(0xFF15803D);
const _morado = Color(0xFF6D28D9);

String _hora(DateTime d) => DateFormat('HH:mm').format(d.toLocal());

String _rango(DateTime a, DateTime b) => '${_hora(a)} – ${_hora(b)}';

String duracionLegible(int minutos) {
  final h = minutos ~/ 60;
  final m = minutos % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Revisión antes de ubicar una actividad especial (correctiva): qué tareas
/// se reemplazan a cada persona, qué huecos les quedan, qué lo impide y un
/// horario libre sugerido. [etiqueta] es "Actividad especial" o "Correctiva"
/// según el rol.
Future<DecisionImpactoEspecial?> mostrarImpactoEspecialDialog(
  BuildContext context, {
  required String descripcion,
  required String etiqueta,
  required ImpactoCorrectiva impacto,
}) {
  return showDialog<DecisionImpactoEspecial>(
    context: context,
    builder: (_) => ImpactoEspecialDialog(
      descripcion: descripcion,
      etiqueta: etiqueta,
      impacto: impacto,
    ),
  );
}

class ImpactoEspecialDialog extends StatefulWidget {
  final String descripcion;
  final String etiqueta;
  final ImpactoCorrectiva impacto;

  const ImpactoEspecialDialog({
    super.key,
    required this.descripcion,
    required this.etiqueta,
    required this.impacto,
  });

  @override
  State<ImpactoEspecialDialog> createState() => _ImpactoEspecialDialogState();
}

class _ImpactoEspecialDialogState extends State<ImpactoEspecialDialog> {
  final TextEditingController _motivoCtrl = TextEditingController();
  String? _errorMotivo;

  ImpactoCorrectiva get _i => widget.impacto;

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final motivo = _motivoCtrl.text.trim();
    if (motivo.isNotEmpty && motivo.length < 3) {
      setState(
        () => _errorMotivo = 'Escribe al menos 3 caracteres o déjalo vacío.',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(DecisionImpactoEspecial.programar(motivo: motivo));
  }

  String _mensajeBloqueo(TareaImpactada b) {
    final etiquetaMin = widget.etiqueta.toLowerCase();
    switch (b.motivo) {
      case 'NO_ES_PREVENTIVA':
        return 'Ya es una $etiquetaMin: no se reemplaza. Muévela primero o elige otra hora.';
      case 'PRIORIDAD':
        final permitidas = _i.prioridad <= 1
            ? 'P1, P2 y P3'
            : (_i.prioridad == 2 ? 'P2 y P3' : 'P3');
        return 'Es prioridad P${b.prioridad}. Una $etiquetaMin P${_i.prioridad} '
            'solo reemplaza preventivas $permitidas.';
      default:
        return b.mensaje ?? 'No se puede reemplazar.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _i;
    final reemplaza = i.reemplazos.isNotEmpty;
    final Color tono;
    final IconData icono;
    final String titulo;
    if (!i.puedeProgramar) {
      tono = _rojo;
      icono = Icons.block_rounded;
      titulo = 'No se puede programar a esta hora';
    } else if (reemplaza) {
      tono = _ambar;
      icono = Icons.swap_horiz_rounded;
      titulo = 'Se reemplazarán tareas';
    } else {
      tono = _azul;
      icono = Icons.info_outline_rounded;
      titulo = 'Revisa antes de programar';
    }

    final fecha = DateFormat("EEEE d 'de' MMMM", 'es').format(i.fechaInicio);
    final personas = i.operarios
        .where((o) => o.reemplazadasIds.isNotEmpty)
        .length;
    final ancho = MediaQuery.sizeOf(context).width;

    final contenido = <Widget>[
      for (final b in i.bloqueosGenerales)
        _Aviso(
          color: _rojo,
          fondo: _rojoSuave,
          icono: Icons.block_rounded,
          texto: b.mensaje,
        ),
      if (i.bloqueos.isNotEmpty) ...[
        const _Subtitulo('Lo impiden'),
        for (final b in i.bloqueos)
          _FilaTarea(
            color: _rojo,
            icono: Icons.lock_outline_rounded,
            titulo: b.descripcion,
            detalle:
                '${_rango(b.fechaInicio, b.fechaFin)} · ${_nombres(b.operarios)}',
            nota: _mensajeBloqueo(b),
          ),
      ],
      if (reemplazo(i)) ...[
        _Aviso(
          color: _ambar,
          fondo: _ambarSuave,
          icono: Icons.swap_horiz_rounded,
          texto:
              '${i.reemplazos.length == 1 ? 'Se reemplazará 1 tarea' : 'Se reemplazarán ${i.reemplazos.length} tareas'}'
              '${personas > 1 ? ' de $personas personas' : ''}. '
              'Quedarán como "No completada" por este reemplazo.',
        ),
        for (final o in i.operarios) _TarjetaOperario(operario: o, impacto: i),
      ],
      if (i.puedeProgramar && !reemplaza && i.operarios.isNotEmpty)
        _Aviso(
          color: _verde,
          fondo: const Color(0xFFF0FDF4),
          icono: Icons.check_circle_outline_rounded,
          texto: 'Nadie tiene otra tarea a esa hora.',
        ),
      for (final a in i.avisos)
        _Aviso(
          color: _azul,
          fondo: _azulSuave,
          icono: Icons.schedule_rounded,
          texto: a.mensaje,
        ),
      if (i.sugerenciaInicio != null && i.sugerenciaFin != null && !i.libre)
        _Sugerencia(
          texto:
              'Libre para todos de ${_rango(i.sugerenciaInicio!, i.sugerenciaFin!)}, sin reemplazar nada.',
          onUsar: () => Navigator.of(
            context,
          ).pop(const DecisionImpactoEspecial.sugerencia()),
        ),
      if (i.puedeProgramar && reemplaza) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _motivoCtrl,
          maxLines: 2,
          maxLength: 500,
          onChanged: (_) {
            if (_errorMotivo != null) setState(() => _errorMotivo = null);
          },
          decoration: InputDecoration(
            labelText: i.prioridadMasAltaReemplazada == 1
                ? 'Motivo del reemplazo (recomendado: hay prioridad alta)'
                : 'Motivo del reemplazo (opcional)',
            hintText: 'Ej. daño en la bomba que no da espera',
            errorText: _errorMotivo,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    ];

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: ancho < 600 ? 12 : 40,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              decoration: BoxDecoration(
                color: tono.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(color: tono.withValues(alpha: 0.25)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icono, color: tono, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: tono,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.etiqueta}: "${widget.descripcion}"',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${fecha[0].toUpperCase()}${fecha.substring(1)} · '
                          '${_rango(i.fechaInicio, i.fechaFin)} '
                          '(${duracionLegible(i.duracionMinutos)}) · P${i.prioridad}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: contenido,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(i.puedeProgramar ? 'Cancelar' : 'Cerrar'),
                  ),
                  if (i.puedeProgramar)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: reemplaza ? _ambar : _morado,
                      ),
                      onPressed: _confirmar,
                      icon: Icon(
                        reemplaza
                            ? Icons.swap_horiz_rounded
                            : Icons.event_available_rounded,
                        size: 18,
                      ),
                      label: Text(
                        reemplaza
                            ? (i.reemplazos.length == 1
                                  ? 'Reemplazar 1 tarea y programar'
                                  : 'Reemplazar ${i.reemplazos.length} tareas y programar')
                            : 'Programar',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool reemplazo(ImpactoCorrectiva i) =>
      i.reemplazos.isNotEmpty && i.puedeProgramar;
}

String _nombres(List<OperarioDeTarea> operarios) {
  final n = operarios
      .map((o) => o.nombre.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return n.isEmpty ? 'Sin operario' : n.join(', ');
}

class _Subtitulo extends StatelessWidget {
  final String texto;
  const _Subtitulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 6),
    child: Text(
      texto,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
    ),
  );
}

class _Aviso extends StatelessWidget {
  final Color color;
  final Color fondo;
  final IconData icono;
  final String texto;

  const _Aviso({
    required this.color,
    required this.fondo,
    required this.icono,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

class _FilaTarea extends StatelessWidget {
  final Color color;
  final IconData icono;
  final String titulo;
  final String detalle;
  final String? nota;
  final Widget? etiqueta;

  const _FilaTarea({
    required this.color,
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.nota,
    this.etiqueta,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border(left: BorderSide(color: color, width: 4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icono, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: const TextStyle(fontSize: 12.5, color: Colors.black87),
              ),
              if (nota != null) ...[
                const SizedBox(height: 4),
                Text(
                  nota!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (etiqueta != null) ...[const SizedBox(width: 6), etiqueta!],
      ],
    ),
  );
}

class _ChipPrioridad extends StatelessWidget {
  final int prioridad;
  const _ChipPrioridad(this.prioridad);

  @override
  Widget build(BuildContext context) {
    final (texto, color) = switch (prioridad) {
      1 => ('P1 alta', _rojo),
      2 => ('P2 media', _ambar),
      _ => ('P3 baja', const Color(0xFF475569)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _TarjetaOperario extends StatelessWidget {
  final OperarioImpactado operario;
  final ImpactoCorrectiva impacto;

  const _TarjetaOperario({required this.operario, required this.impacto});

  @override
  Widget build(BuildContext context) {
    final o = operario;
    final tareas = impacto.reemplazos
        .where((r) => o.reemplazadasIds.contains(r.tareaId))
        .toList();
    final inicial = o.nombre.trim().isEmpty
        ? '?'
        : o.nombre.trim()[0].toUpperCase();
    final borde = o.huecoGrande ? _ambar : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borde, width: o.huecoGrande ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: o.enLaActividad
                    ? _morado
                    : const Color(0xFF64748B),
                child: Text(
                  inicial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  o.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Text(
                o.enLaActividad ? 'En la actividad' : 'No está en la actividad',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: o.enLaActividad ? _morado : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (tareas.isEmpty)
            const Text(
              'Libre a esa hora: no pierde ninguna tarea.',
              style: TextStyle(color: _verde, fontWeight: FontWeight.w600),
            )
          else
            for (final t in tareas)
              _FilaTarea(
                color: _ambar,
                icono: Icons.remove_circle_outline_rounded,
                titulo: t.descripcion,
                detalle: [
                  _rango(t.fechaInicio, t.fechaFin),
                  if (t.estado.toUpperCase() == 'EN_PROCESO') 'en proceso',
                  if (t.operarios.length > 1)
                    'compartida con ${_nombres(t.operarios.where((x) => x.id != o.operarioId).toList())}',
                ].join(' · '),
                etiqueta: _ChipPrioridad(t.prioridad),
              ),
          if (!o.enLaActividad)
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'Pierde esta tarea porque se reemplaza completa.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ),
          for (final h in o.huecos)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    h.grande
                        ? Icons.warning_amber_rounded
                        : Icons.hourglass_empty_rounded,
                    size: 18,
                    color: h.grande ? _ambar : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      h.grande
                          ? 'Hueco grande: quedará sin tarea de ${_rango(h.fechaInicio, h.fechaFin)} (${duracionLegible(h.minutos)}).'
                          : 'Quedará libre de ${_rango(h.fechaInicio, h.fechaFin)} (${duracionLegible(h.minutos)}).',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: h.grande ? _ambar : Colors.black87,
                        fontWeight: h.grande
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Sugerencia extends StatelessWidget {
  final String texto;
  final VoidCallback onUsar;

  const _Sugerencia({required this.texto, required this.onUsar});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F3FF),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFC4B5FD)),
    ),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lightbulb_outline_rounded,
              color: _morado,
              size: 20,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                texto,
                style: const TextStyle(
                  color: _morado,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        OutlinedButton(
          onPressed: onUsar,
          child: const Text('Usar este horario'),
        ),
      ],
    ),
  );
}
