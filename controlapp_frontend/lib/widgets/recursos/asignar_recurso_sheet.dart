// lib/widgets/recursos/asignar_recurso_sheet.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/recursos_api.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/service/api_exception.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_conflict_dialog.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';

/// Hoja para cubrir una necesidad de recurso (o cambiar la unidad de una
/// reserva si [reemplazarReservaId] viene dado).
///
/// La asignación es manual: el sistema ordena los candidatos (primero los del
/// conjunto, luego los que ya están prestados allí y por último los de la
/// empresa), pre-selecciona los sugeridos y bloquea los que no sirven
/// mostrando el motivo. La persona confirma.
///
/// Devuelve true si se reservó/cambió algo.
Future<bool> mostrarAsignarRecursoSheet(
  BuildContext context, {
  required int necesidadId,
  String? empresaNit,
  int? reemplazarReservaId,
  String? reemplazarEtiqueta,
  RecursosApi? api,
}) async {
  final out = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppTheme.background,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: AsignarRecursoSheet(
        necesidadId: necesidadId,
        empresaNit: empresaNit,
        reemplazarReservaId: reemplazarReservaId,
        reemplazarEtiqueta: reemplazarEtiqueta,
        api: api ?? RecursosApi(),
      ),
    ),
  );
  return out == true;
}

class AsignarRecursoSheet extends StatefulWidget {
  const AsignarRecursoSheet({
    super.key,
    required this.necesidadId,
    required this.api,
    this.empresaNit,
    this.reemplazarReservaId,
    this.reemplazarEtiqueta,
  });

  final int necesidadId;
  final String? empresaNit;
  final int? reemplazarReservaId;
  final String? reemplazarEtiqueta;
  final RecursosApi api;

  @override
  State<AsignarRecursoSheet> createState() => _AsignarRecursoSheetState();
}

class _AsignarRecursoSheetState extends State<AsignarRecursoSheet> {
  CandidatosResponse? _data;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  final Set<int> _seleccion = {};
  bool _aplicarAGrupo = false;
  bool _verNoDisponibles = false;

  bool get _modoReemplazo => widget.reemplazarReservaId != null;

  /// Cuántas unidades se pueden elegir en esta operación.
  int get _cupo {
    final d = _data;
    if (d == null) return 0;
    return _modoReemplazo ? 1 : d.pendientes;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await widget.api.candidatos(empresaNit: widget.empresaNit, necesidadId: widget.necesidadId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _seleccion
          ..clear()
          ..addAll(
            data.candidatos
                .where((c) => c.disponible)
                .take(_modoReemplazo ? 1 : data.pendientes)
                .map((c) => c.unidadId),
          );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _toggle(CandidatoRecursoModel c) {
    if (!c.disponible) return;
    setState(() {
      if (_seleccion.contains(c.unidadId)) {
        _seleccion.remove(c.unidadId);
      } else {
        if (_cupo == 1) _seleccion.clear();
        if (_seleccion.length < _cupo) _seleccion.add(c.unidadId);
      }
    });
  }

  Future<void> _confirmar() async {
    final data = _data;
    if (data == null || _seleccion.isEmpty) return;
    setState(() => _guardando = true);
    try {
      if (_modoReemplazo) {
        await widget.api.reemplazarUnidad(
          empresaNit: widget.empresaNit,
          reservaId: widget.reemplazarReservaId!,
          unidadId: _seleccion.first,
          motivo: 'Cambio de unidad desde la agenda de recursos',
        );
      } else {
        final elegidas = data.candidatos.where((c) => _seleccion.contains(c.unidadId)).toList();
        final omitidas = await widget.api.reservar(
          empresaNit: widget.empresaNit,
          necesidadId: data.necesidadId,
          unidades: elegidas,
          aplicarAGrupo: _aplicarAGrupo,
        );
        if (omitidas.isNotEmpty && mounted) {
          AppFeedback.showInfo(
            context,
            title: 'Reserva parcial del grupo',
            message:
                'Se reservó la tarea seleccionada. En algunos días del grupo no se pudo:\n• ${omitidas.join('\n• ')}',
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (esConflictoRecurso(e)) {
        await mostrarConflictoDesdeError(context, e);
        await _cargar();
      } else {
        AppFeedback.showError(context, message: e.message);
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return _ErrorConReintento(mensaje: _error!, onRetry: _cargar);
    }
    final data = _data!;
    final disponibles = data.candidatos.where((c) => c.disponible).toList();
    final noDisponibles = data.candidatos.where((c) => !c.disponible).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _Encabezado(data: data, modoReemplazo: _modoReemplazo, reemplazarEtiqueta: widget.reemplazarEtiqueta),
              const SizedBox(height: 12),
              if (data.candidatos.isEmpty)
                const _Aviso(
                  icono: Icons.inventory_2_outlined,
                  texto:
                      'No hay unidades de este tipo registradas en el inventario de la empresa ni del conjunto.',
                )
              else if (disponibles.isEmpty)
                const _Aviso(
                  icono: Icons.event_busy_outlined,
                  texto: 'Ninguna unidad está libre en ese horario. Revisa abajo por qué no lo están.',
                ),
              for (final grupo in GrupoCandidato.values) ...[
                if (disponibles.any((c) => c.grupo == grupo)) ...[
                  _TituloGrupo(grupo: grupo, cantidad: disponibles.where((c) => c.grupo == grupo).length),
                  for (final c in disponibles.where((c) => c.grupo == grupo))
                    _CandidatoTile(
                      candidato: c,
                      seleccionado: _seleccion.contains(c.unidadId),
                      habilitado: _seleccion.contains(c.unidadId) || _seleccion.length < _cupo || _cupo == 1,
                      onTap: () => _toggle(c),
                    ),
                ],
              ],
              if (noDisponibles.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _verNoDisponibles = !_verNoDisponibles),
                  icon: Icon(_verNoDisponibles ? Icons.expand_less : Icons.expand_more),
                  label: Text('No disponibles (${noDisponibles.length})'),
                ),
                if (_verNoDisponibles)
                  for (final c in noDisponibles)
                    _CandidatoTile(candidato: c, seleccionado: false, habilitado: false, onTap: null),
              ],
            ],
          ),
        ),
        _BarraConfirmar(
          cupo: _cupo,
          seleccionadas: _seleccion.length,
          guardando: _guardando,
          modoReemplazo: _modoReemplazo,
          tareasGrupo: _modoReemplazo ? 0 : data.tareasDelGrupoConPendiente,
          aplicarAGrupo: _aplicarAGrupo,
          onAplicarAGrupo: (v) => setState(() => _aplicarAGrupo = v),
          onConfirmar: _seleccion.isEmpty || _guardando ? null : _confirmar,
        ),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.data, required this.modoReemplazo, this.reemplazarEtiqueta});

  final CandidatosResponse data;
  final bool modoReemplazo;
  final String? reemplazarEtiqueta;

  @override
  Widget build(BuildContext context) {
    final t = data.tarea;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RecursoEstilos.iconoClase(data.clase), color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  modoReemplazo
                      ? 'Cambiar ${reemplazarEtiqueta ?? 'unidad'}'
                      : '${data.tipoNombre} · necesita ${data.cantidad}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (!modoReemplazo)
                EstadoPill(
                  texto: '${data.asignadas}/${data.cantidad} asignadas',
                  color: data.pendientes == 0 ? AppTheme.green : const Color(0xFFB7791F),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(t.descripcion, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Dato(icono: Icons.apartment_outlined, texto: t.conjuntoNombre),
              _Dato(
                icono: Icons.schedule,
                texto: RecursoEstilos.capitalizar(RecursoEstilos.rangoUso(t.fechaInicio, t.fechaFin)),
              ),
              if (t.operarios.isNotEmpty) _Dato(icono: Icons.person_outline, texto: t.operarios.join(', ')),
              if (!data.obligatorio) const _Dato(icono: Icons.info_outline, texto: 'Opcional'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 15, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Flexible(child: Text(texto, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted))),
      ],
    );
  }
}

class _TituloGrupo extends StatelessWidget {
  const _TituloGrupo({required this.grupo, required this.cantidad});
  final GrupoCandidato grupo;
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        '${grupo.etiqueta} ($cantidad)',
        style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryDark),
      ),
    );
  }
}

class _CandidatoTile extends StatelessWidget {
  const _CandidatoTile({
    required this.candidato,
    required this.seleccionado,
    required this.habilitado,
    required this.onTap,
  });

  final CandidatoRecursoModel candidato;
  final bool seleccionado;
  final bool habilitado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = candidato;
    final apagado = !c.disponible;
    final lineas = <String>[
      if (c.marca != null) c.marca!,
      if (c.grupo == GrupoCandidato.empresa && c.bloqueoInicio != null && c.bloqueoFin != null)
        'Sale ${RecursoEstilos.fechaCorta.format(c.bloqueoInicio!)} · vuelve ${RecursoEstilos.fechaCorta.format(c.bloqueoFin!)}',
    ];
    return Opacity(
      opacity: apagado ? 0.6 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        color: seleccionado ? AppTheme.primary.withValues(alpha: 0.07) : AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: seleccionado ? AppTheme.primary : AppTheme.surfaceSoft, width: seleccionado ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: c.disponible && habilitado ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: seleccionado,
                  onChanged: c.disponible && habilitado ? (_) => onTap?.call() : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(c.etiqueta, style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (c.sugerida)
                            const EstadoPill(texto: 'Sugerida', color: AppTheme.primary, icono: Icons.star_rounded),
                          if (c.cercaDelConjunto && c.disponible)
                            const EstadoPill(texto: 'Ya va a estar allí', color: AppTheme.secondary),
                        ],
                      ),
                      if (lineas.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(lineas.join(' · '), style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
                      ],
                      if (!c.disponible && c.motivo != null) ...[
                        const SizedBox(height: 4),
                        Text(c.motivo!, style: const TextStyle(fontSize: 12.5, color: AppTheme.red)),
                      ],
                      if (c.reservaAnterior != null || c.reservaSiguiente != null) ...[
                        const SizedBox(height: 6),
                        if (c.reservaAnterior != null)
                          _Contexto(prefijo: 'Antes', ctx: c.reservaAnterior!),
                        if (c.reservaSiguiente != null)
                          _Contexto(prefijo: 'Después', ctx: c.reservaSiguiente!),
                      ],
                    ],
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

class _Contexto extends StatelessWidget {
  const _Contexto({required this.prefijo, required this.ctx});
  final String prefijo;
  final ContextoReservaModel ctx;

  @override
  Widget build(BuildContext context) {
    final donde = ctx.tipo == 'MANTENIMIENTO' ? 'Mantenimiento' : (ctx.conjuntoNombre ?? 'Otro conjunto');
    return Text(
      '$prefijo: $donde · ${RecursoEstilos.rangoUso(ctx.usoInicio, ctx.usoFin)}',
      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
    );
  }
}

class _BarraConfirmar extends StatelessWidget {
  const _BarraConfirmar({
    required this.cupo,
    required this.seleccionadas,
    required this.guardando,
    required this.modoReemplazo,
    required this.tareasGrupo,
    required this.aplicarAGrupo,
    required this.onAplicarAGrupo,
    required this.onConfirmar,
  });

  final int cupo;
  final int seleccionadas;
  final bool guardando;
  final bool modoReemplazo;
  final int tareasGrupo;
  final bool aplicarAGrupo;
  final ValueChanged<bool> onAplicarAGrupo;
  final VoidCallback? onConfirmar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tareasGrupo > 0)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: aplicarAGrupo,
                  onChanged: (v) => onAplicarAGrupo(v ?? false),
                  title: Text('Usar la misma unidad en los otros $tareasGrupo día(s) de esta tarea'),
                  subtitle: const Text('Evita mover el equipo entre bloques del mismo trabajo.'),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cupo == 0
                          ? 'Esta necesidad ya está cubierta.'
                          : modoReemplazo
                              ? 'Elige la nueva unidad.'
                              : '$seleccionadas de $cupo seleccionada(s)',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: AppTheme.saveButtonStyle,
                    onPressed: onConfirmar,
                    icon: guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.event_available),
                    label: Text(modoReemplazo ? 'Cambiar unidad' : 'Reservar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icono, color: const Color(0xFF8A5A00)),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

class _ErrorConReintento extends StatelessWidget {
  const _ErrorConReintento({required this.mensaje, required this.onRetry});
  final String mensaje;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.red, size: 36),
            const SizedBox(height: 8),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
