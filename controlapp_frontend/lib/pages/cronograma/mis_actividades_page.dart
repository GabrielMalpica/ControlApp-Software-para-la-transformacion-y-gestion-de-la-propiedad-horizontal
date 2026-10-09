import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pages/cronograma/cerrar_actividad_page.dart';
import 'package:flutter_application_1/pages/cronograma/mis_actividades_repo.dart';
import 'package:flutter_application_1/pages/cronograma/secciones_actividades.dart';
import 'package:flutter_application_1/pages/cronograma/semana_trabajador_view.dart';
import 'package:flutter_application_1/pages/tareas_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/offline/tarea_sync_engine.dart';
import 'package:flutter_application_1/service/tarea_cierre_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/widgets/cerrar_tarea_sheet.dart';
import 'package:flutter_application_1/widgets/cierres_pendientes_sheet.dart';
import 'package:flutter_application_1/widgets/cronograma/actividad_card.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_ui.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

/// "Mis actividades de hoy" del operario: progreso del día, lo que toca
/// ahora, lo que sigue y lo terminado, con un cierre guiado.
class MisActividadesPage extends StatefulWidget {
  final String nit;

  const MisActividadesPage({super.key, required this.nit});

  @override
  State<MisActividadesPage> createState() => _MisActividadesPageState();
}

class _MisActividadesPageState extends State<MisActividadesPage> {
  final _repo = MisActividadesRepo();
  final _cierreService = TareaCierreService();
  StreamSubscription<void>? _sync;

  SesionOperario? _sesion;
  List<TareaModel> _tareas = const [];
  Set<int> _sinEnviar = const {};
  int _conError = 0;
  DateTime? _copiaDel;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    TamanoTexto.cargar();
    _iniciar();
    _sync = TareaSyncEngine.instance.onCambios.listen(
      (_) => _recargarPendientes(),
    );
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final s = await _repo.sesion();
    if (!mounted) return;
    if (s == null) {
      setState(() {
        _cargando = false;
        _error =
            'No se pudo identificar tu usuario. Cierra sesión y vuelve a entrar.';
      });
      return;
    }
    _sesion = s;
    await _cargar();
    unawaited(
      TareaSyncEngine.instance.sincronizarAhora(usuarioId: s.usuarioId),
    );
  }

  Future<void> _cargar() async {
    final s = _sesion;
    if (s == null) return;
    setState(() {
      _cargando = _tareas.isEmpty;
      _error = null;
    });
    try {
      final rango = MisActividadesRepo.rangoPorDefecto(DateTime.now());
      final r = await _repo.cargar(s, desde: rango.desde, hasta: rango.hasta);
      final pendientes = await _repo.cierresSinEnviar(s.usuarioId);
      final conError = await _repo.cierresConError(s.usuarioId);
      if (!mounted) return;
      setState(() {
        _tareas = r.tareas;
        _copiaDel = r.copiaDel;
        _sinEnviar = pendientes;
        _conError = conError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppError.messageOf(
          e,
          fallback:
              'No se pudieron cargar tus actividades. Revisa la señal e intenta de nuevo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _recargarPendientes() async {
    final s = _sesion;
    if (s == null) return;
    final p = await _repo.cierresSinEnviar(s.usuarioId);
    final e = await _repo.cierresConError(s.usuarioId);
    if (!mounted) return;
    final antes = _sinEnviar.length;
    setState(() {
      _sinEnviar = p;
      _conError = e;
    });
    // Se enviaron cierres guardados: refrescar estados del servidor.
    if (p.length < antes) unawaited(_cargar());
  }

  bool _puedeCerrar(TareaModel t) {
    final s = _sesion;
    if (s == null || _sinEnviar.contains(t.id)) return false;
    return _cierreService.puedeCerrar(
      rol: s.rol,
      usuarioId: s.usuarioId,
      tarea: t,
    );
  }

  Future<void> _abrir(TareaModel t) async {
    final accion = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ActividadOperarioPage(
          tarea: t,
          usuarioActualId: _sesion?.usuarioId,
          puedeCerrar: _puedeCerrar(t),
          cierreSinEnviar: _sinEnviar.contains(t.id),
          motivoNoCierre: _motivoNoCierre(t),
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'cerrar') await _cerrar(t);
    if (accion == 'iniciar') await _iniciarActividad(t);
  }

  String? _motivoNoCierre(TareaModel t) {
    final s = _sesion;
    if (s == null) return null;
    if (_sinEnviar.contains(t.id)) {
      return 'Ya registraste el cierre y quedó guardado en este teléfono. Se enviará solo cuando haya señal.';
    }
    return _cierreService.motivoNoPuedeCerrar(
      rol: s.rol,
      usuarioId: s.usuarioId,
      tarea: t,
    );
  }

  Future<void> _iniciarActividad(TareaModel t) async {
    final s = _sesion;
    if (s == null) return;
    try {
      await _repo.iniciar(s, t.id);
      if (!mounted) return;
      AppFeedback.showInfo(
        context,
        title: 'Actividad iniciada',
        message:
            'Tu supervisor la verá "En curso". Cuando termines, registra el cierre.',
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        title: 'No se pudo marcar el inicio',
        message:
            '${AppError.messageOf(e, fallback: 'Revisa la señal.')} Igual puedes registrar el cierre cuando termines.',
      );
    }
  }

  Future<void> _cerrar(TareaModel t) async {
    final s = _sesion;
    if (s == null) return;
    final nit = (t.conjuntoId ?? '').isNotEmpty ? t.conjuntoId! : widget.nit;
    final inventario = await _repo.inventario(nit);
    if (!mounted) return;
    final r = await Navigator.of(context).push<CerrarTareaResult>(
      MaterialPageRoute(
        builder: (_) => CerrarActividadPage(
          tarea: t,
          inventario: inventario,
          usuarioActualId: s.usuarioId,
        ),
      ),
    );
    if (r == null || !mounted) return;

    final enviando = _mostrarEnviando();
    CierreTareaResultado? salida;
    Object? error;
    try {
      salida = await _cierreService.cerrarTarea(
        rol: s.rol,
        usuarioId: s.usuarioId,
        tarea: t,
        accion: r.accion,
        observaciones: r.observaciones,
        insumosUsados: r.insumosUsados,
        evidencias: r.evidencias,
      );
    } catch (e) {
      error = e;
    } finally {
      enviando();
    }
    if (!mounted) return;
    if (error != null) {
      AppFeedback.showError(
        context,
        title: 'No se pudo cerrar',
        message: AppError.messageOf(
          error,
          fallback: 'Revisa los datos e intenta de nuevo.',
        ),
      );
      return;
    }
    await _cargar();
    if (!mounted) return;
    final ahora = DateTime.now();
    final hoy = _deHoy(ahora);
    final siguiente = _abiertasOrdenadas(hoy, ahora).firstOrNull;
    final ir = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResultadoCierrePage(
          tarea: t,
          guardadoSinSenal:
              salida == CierreTareaResultado.guardadoLocalPendiente,
          noSeHizo: r.accion == 'NO_COMPLETADA',
          progreso: progresoDelDia(
            hoy,
            cierresPendientesEnvio: _sinEnviar,
            ahora: ahora,
          ),
          siguiente: siguiente,
          usuarioActualId: s.usuarioId,
        ),
      ),
    );
    if (ir == true && siguiente != null && mounted) await _abrir(siguiente);
  }

  /// Muestra "Enviando…" sin poder cerrarlo; devuelve la función para quitarlo.
  VoidCallback _mostrarEnviando() {
    var abierto = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('Enviando el cierre…')),
            ],
          ),
        ),
      ),
    ).then((_) => abierto = false);
    return () {
      if (abierto && mounted) Navigator.of(context, rootNavigator: true).pop();
    };
  }

  List<TareaModel> _deHoy(DateTime ahora) =>
      _tareas.where((t) => mismoDia(t.fechaInicio, ahora)).toList()
        ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

  bool _cerrada(TareaModel t, DateTime ahora) =>
      _sinEnviar.contains(t.id) || EstadoVisual.de(t, ahora: ahora).cerrada;

  List<TareaModel> _abiertasOrdenadas(List<TareaModel> hoy, DateTime ahora) =>
      hoy.where((t) => !_cerrada(t, ahora)).toList();

  @override
  Widget build(BuildContext context) {
    return EscalaTexto(
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Mis actividades'),
          actions: [
            const TamanoTextoBoton(),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const SkeletonList();
    if (_error != null && _tareas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Intentar de nuevo'),
              ),
            ],
          ),
        ),
      );
    }

    final ahora = DateTime.now();
    final hoy = _deHoy(ahora);
    final abiertas = _abiertasOrdenadas(hoy, ahora);
    final hechas = hoy.where((t) => _cerrada(t, ahora)).toList();
    final previas =
        _tareas
            .where(
              (t) =>
                  soloFecha(t.fechaInicio).isBefore(soloFecha(ahora)) &&
                  !_cerrada(t, ahora) &&
                  _puedeCerrar(t),
            )
            .toList()
          ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    var ahoraLista = abiertas
        .where((t) => !t.fechaInicio.isAfter(ahora))
        .toList();
    var despues = abiertas.where((t) => t.fechaInicio.isAfter(ahora)).toList();
    var etiquetaAhora = 'Ahora';
    if (ahoraLista.isEmpty && despues.isNotEmpty) {
      ahoraLista = [despues.first];
      despues = despues.sublist(1);
      etiquetaAhora = 'Lo siguiente';
    }
    final progreso = progresoDelDia(
      hoy,
      cierresPendientesEnvio: _sinEnviar,
      ahora: ahora,
    );
    final s = _sesion;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _capitalizar(
                      DateFormat("EEEE d 'de' MMMM", 'es').format(ahora),
                    ),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 16,
                    ),
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      s == null || s.primerNombre.isEmpty
                          ? 'Tus actividades de hoy'
                          : 'Hola, ${s.primerNombre}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._avisosSinSenal(),
                  TarjetaProgreso(progreso: progreso),
                  if (previas.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _AvisoPrevias(previas: previas, onAbrir: _abrir),
                  ],
                  if (ahoraLista.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _TituloSeccion(
                      icono: Icons.schedule,
                      texto: ahoraLista.length > 1
                          ? '$etiquetaAhora · ${ahoraLista.length} al mismo tiempo'
                          : etiquetaAhora,
                    ),
                    if (ahoraLista.length > 1)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Son actividades distintas en el mismo horario.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    for (final t in ahoraLista)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TarjetaAhora(
                          tarea: t,
                          ahora: ahora,
                          usuarioActualId: s?.usuarioId,
                          puedeCerrar: _puedeCerrar(t),
                          onCerrar: () => _cerrar(t),
                          onAbrir: () => _abrir(t),
                        ),
                      ),
                  ],
                  if (despues.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const _TituloSeccion(
                      icono: Icons.arrow_forward,
                      texto: 'Después',
                    ),
                    for (final franja in agruparSimultaneas(despues)) ...[
                      if (franja.simultaneas)
                        GrupoSimultaneas(
                          franja: franja,
                          construir: (t) => _tarjeta(t, ahora),
                        )
                      else
                        _tarjeta(franja.tareas.first, ahora),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (hoy.isNotEmpty && abiertas.isEmpty) ...[
                    const SizedBox(height: 18),
                    const VacioCronograma(
                      mensaje: 'No te quedan actividades por hoy.',
                      icono: Icons.task_alt,
                    ),
                  ],
                  if (hoy.isEmpty) ...[
                    const SizedBox(height: 18),
                    const VacioCronograma(
                      mensaje: 'Hoy no tienes actividades programadas.',
                    ),
                  ],
                  if (hechas.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          title: Text(
                            'Terminadas hoy (${hechas.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            12,
                          ),
                          children: [
                            for (final t in hechas)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _tarjeta(t, ahora),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: s == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OtrosDiasPage(
                                tareas: _tareas,
                                sinEnviar: _sinEnviar,
                                usuarioActualId: s.usuarioId,
                                onAbrir: _abrir,
                              ),
                            ),
                          ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    icon: const Icon(Icons.calendar_view_week),
                    label: const Text('Ver mis actividades de otros días'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TareasPage(nit: widget.nit),
                      ),
                    ),
                    child: const Text('Ver el historial completo'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(TareaModel t, DateTime ahora) => ActividadCard(
    tarea: t,
    densidad: DensidadTarjeta.grande,
    ahora: ahora,
    trabajadorActualId: _sesion?.usuarioId,
    cierrePendienteEnvio: _sinEnviar.contains(t.id),
    onTap: () => _abrir(t),
  );

  List<Widget> _avisosSinSenal() {
    final out = <Widget>[];
    if (_copiaDel != null) {
      out.add(
        _Banda(
          icono: Icons.cloud_off,
          color: const Color(0xFFEEF1F5),
          texto:
              'Sin conexión: ves tus actividades guardadas el ${DateFormat("d 'de' MMMM 'a las' h:mm a", 'es').format(_copiaDel!)}. Puedes registrar cierres; se enviarán cuando vuelva la señal.',
        ),
      );
    }
    if (_sinEnviar.isNotEmpty) {
      final n = _sinEnviar.length;
      out.add(
        _Banda(
          icono: _conError > 0
              ? Icons.error_outline
              : Icons.cloud_upload_outlined,
          color: _conError > 0
              ? const Color(0xFFFDE8E8)
              : const Color(0xFFFDF0E1),
          texto: _conError > 0
              ? '$n cierre${n == 1 ? '' : 's'} guardado${n == 1 ? '' : 's'} sin enviar; $_conError con un problema. Toca "Ver" para revisarlo.'
              : '$n cierre${n == 1 ? '' : 's'} guardado${n == 1 ? '' : 's'} en el teléfono. Se enviará${n == 1 ? '' : 'n'} solo${n == 1 ? '' : 's'} con señal.',
          accion: 'Ver',
          onAccion: () async {
            final uid = _sesion?.usuarioId;
            if (uid == null) return;
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => CierresPendientesSheet(usuarioId: uid),
            );
            await _recargarPendientes();
          },
        ),
      );
    }
    return out;
  }
}

String _capitalizar(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Progreso del día: "Llevas 3 de 8" con barra y una frase corta.
class TarjetaProgreso extends StatelessWidget {
  final ProgresoDia progreso;

  const TarjetaProgreso({super.key, required this.progreso});

  @override
  Widget build(BuildContext context) {
    final p = progreso;
    return Semantics(
      label:
          'Llevas ${p.cerradas} de ${cantidadActividades(p.total)} cerradas, ${p.porcentaje} por ciento. ${p.mensaje}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'Llevas ${p.cerradas} de ${p.total}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${p.porcentaje}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 18,
                child: Row(
                  children: [
                    if (p.hechas > 0)
                      Expanded(
                        flex: p.hechas,
                        child: Container(color: AppTheme.accent),
                      ),
                    if (p.noSeHicieron > 0)
                      Expanded(
                        flex: p.noSeHicieron,
                        child: Container(color: Colors.white70),
                      ),
                    if (p.pendientes > 0 || p.total == 0)
                      Expanded(
                        flex: p.total == 0 ? 1 : p.pendientes,
                        child: Container(color: Colors.white24),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              p.mensaje,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                height: 1.35,
              ),
            ),
            if (p.noSeHicieron > 0 || p.enviando > 0) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (p.noSeHicieron > 0)
                    '${p.noSeHicieron} no se ${p.noSeHicieron == 1 ? 'pudo' : 'pudieron'} hacer',
                  if (p.enviando > 0)
                    '${p.enviando} se enviará${p.enviando == 1 ? '' : 'n'} con señal',
                ].join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _TituloSeccion({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Icon(icono, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La actividad de ahora, con los botones a la vista.
class _TarjetaAhora extends StatelessWidget {
  final TareaModel tarea;
  final DateTime ahora;
  final String? usuarioActualId;
  final bool puedeCerrar;
  final VoidCallback onCerrar;
  final VoidCallback onAbrir;

  const _TarjetaAhora({
    required this.tarea,
    required this.ahora,
    required this.usuarioActualId,
    required this.puedeCerrar,
    required this.onCerrar,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final visual = CategoriaVisual.deTarea(tarea);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visual.acento, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ActividadCard(
            tarea: tarea,
            densidad: DensidadTarjeta.grande,
            ahora: ahora,
            trabajadorActualId: usuarioActualId,
            onTap: onAbrir,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final botones = <Widget>[
                if (puedeCerrar)
                  FilledButton.icon(
                    onPressed: onCerrar,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    icon: const Icon(Icons.task_alt),
                    label: const Text(
                      'Registrar cierre',
                      style: TextStyle(fontSize: 17),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: onAbrir,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Ver detalle'),
                ),
              ];
              if (c.maxWidth < 520 || botones.length == 1) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < botones.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      botones[i],
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: botones[0]),
                  const SizedBox(width: 10),
                  Expanded(child: botones[1]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AvisoPrevias extends StatelessWidget {
  final List<TareaModel> previas;
  final ValueChanged<TareaModel> onAbrir;

  const _AvisoPrevias({required this.previas, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    final n = previas.length;
    final f = DateFormat("EEEE d 'de' MMMM", 'es');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0E1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3C892)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n == 1
                      ? 'Tienes 1 actividad de días anteriores sin cerrar'
                      : 'Tienes $n actividades de días anteriores sin cerrar',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF5B2C06),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final t in previas.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${t.descripcion} · ${_capitalizar(f.format(t.fechaInicio.toLocal()))}',
              ),
            ),
          if (n > 3) Text('y ${n - 3} más.'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => onAbrir(previas.first),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.white,
            ),
            child: Text(n == 1 ? 'Revisarla y cerrarla' : 'Revisar la primera'),
          ),
        ],
      ),
    );
  }
}

class _Banda extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;
  final String? accion;
  final VoidCallback? onAccion;

  const _Banda({
    required this.icono,
    required this.color,
    required this.texto,
    this.accion,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icono),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
          if (accion != null)
            TextButton(onPressed: onAccion, child: Text(accion!)),
        ],
      ),
    );
  }
}

/// Detalle de una actividad para el operario. Devuelve 'cerrar' o
/// 'iniciar' si la persona elige esa acción.
class ActividadOperarioPage extends StatelessWidget {
  final TareaModel tarea;
  final String? usuarioActualId;
  final bool puedeCerrar;
  final bool cierreSinEnviar;
  final String? motivoNoCierre;

  const ActividadOperarioPage({
    super.key,
    required this.tarea,
    required this.usuarioActualId,
    required this.puedeCerrar,
    required this.cierreSinEnviar,
    this.motivoNoCierre,
  });

  @override
  Widget build(BuildContext context) {
    final t = tarea;
    final ahora = DateTime.now();
    final visual = CategoriaVisual.deTarea(t);
    final estado = EstadoVisual.de(
      t,
      ahora: ahora,
      cierrePendienteEnvio: cierreSinEnviar,
    );
    final hm = DateFormat('HH:mm');
    final companeros = trabajadoresDe([
      t,
    ]).where((p) => p.id != usuarioActualId).toList();
    final puedeIniciar =
        puedeCerrar &&
        (t.estado ?? '').toUpperCase() == 'ASIGNADA' &&
        mismoDia(t.fechaInicio, ahora) &&
        t.fechaFin.isAfter(ahora);
    final recursos = <String>{
      ...t.maquinariasAsignadas.map((m) => m.nombre),
      ...t.herramientasAsignadas.map((h) => h.nombre),
      ...t.recursosPlan.map((r) => r.tipoNombre),
    }.toList();
    final insumos = t.insumosProgramados
        .map((i) => '${i.nombre} (${i.cantidad} ${i.unidad})')
        .toList();
    final cerradoPor = (t.finalizadaPorNombre ?? '').trim();

    return EscalaTexto(
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Actividad'),
          actions: const [TamanoTextoBoton()],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                CategoriaChip(visual: visual),
                                EstadoChip(estado: estado),
                                if (visual.esEspecial) const EspecialBadge(),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Semantics(
                              header: true,
                              child: Text(
                                t.descripcion,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _Bloque(
                              icono: Icons.schedule,
                              titulo:
                                  '${hm.format(t.fechaInicio.toLocal())} a ${hm.format(t.fechaFin.toLocal())}',
                              texto: _capitalizar(
                                DateFormat(
                                  "EEEE d 'de' MMMM",
                                  'es',
                                ).format(t.fechaInicio.toLocal()),
                              ),
                              grande: true,
                            ),
                            _Bloque(
                              icono: Icons.location_on_outlined,
                              titulo: 'Dónde',
                              texto: [
                                (t.ubicacionNombre ?? '').trim(),
                                (t.elementoNombre ?? '').trim(),
                              ].where((x) => x.isNotEmpty).join(' › '),
                            ),
                            if (companeros.isNotEmpty)
                              _Bloque(
                                icono: Icons.group,
                                titulo: 'La haces con',
                                texto:
                                    '${nombresEnLista(companeros.map((c) => c.nombre))}\nEs una sola actividad: cuando uno la cierra, queda cerrada para todos.',
                              ),
                            if (recursos.isNotEmpty)
                              _Bloque(
                                icono: Icons.handyman_outlined,
                                titulo: 'Lleva',
                                texto: recursos.join(', '),
                              ),
                            if (insumos.isNotEmpty)
                              _Bloque(
                                icono: Icons.inventory_2_outlined,
                                titulo: 'Insumos previstos',
                                texto: insumos.join('\n'),
                              ),
                            if ((t.observacionesRechazo ?? '')
                                .trim()
                                .isNotEmpty)
                              _Bloque(
                                icono: Icons.undo,
                                titulo: 'Te la devolvieron por',
                                texto: t.observacionesRechazo!.trim(),
                              ),
                            if ((t.observaciones ?? '').trim().isNotEmpty)
                              _Bloque(
                                icono: Icons.notes,
                                titulo: 'Observación',
                                texto: t.observaciones!.trim(),
                              ),
                            if (cerradoPor.isNotEmpty)
                              _Bloque(
                                icono: Icons.task_alt,
                                titulo: 'Cerrada',
                                texto:
                                    cerradoPor ==
                                        trabajadoresDe([t])
                                            .where(
                                              (p) => p.id == usuarioActualId,
                                            )
                                            .map((p) => p.nombre)
                                            .firstOrNull
                                    ? 'La cerraste tú.'
                                    : 'La cerró $cerradoPor.',
                              ),
                            if (puedeIniciar) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    Navigator.of(context).pop('iniciar'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  backgroundColor: const Color(0xFFFFF4D1),
                                ),
                                icon: const Icon(Icons.play_circle),
                                label: const Text('Iniciar actividad'),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  'Opcional: avisa a tu supervisor que ya empezaste.',
                                  style: TextStyle(color: AppTheme.textMuted),
                                ),
                              ),
                            ],
                            if (!puedeCerrar &&
                                motivoNoCierre != null &&
                                !estado.cerrada) ...[
                              const SizedBox(height: 12),
                              Text(
                                motivoNoCierre!,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                              ),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Volver a mis actividades'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (puedeCerrar)
                Material(
                  color: Colors.white,
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop('cerrar'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                          ),
                          icon: const Icon(Icons.task_alt),
                          label: const Text(
                            'Registrar cierre',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bloque extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  final bool grande;

  const _Bloque({
    required this.icono,
    required this.titulo,
    required this.texto,
    this.grande = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: AppTheme.primary, size: grande ? 30 : 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: grande ? 22 : 15,
                    color: grande ? AppTheme.text : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  texto.isEmpty ? '—' : texto,
                  style: const TextStyle(fontSize: 16, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pantalla de confirmación después de cerrar.
class ResultadoCierrePage extends StatelessWidget {
  final TareaModel tarea;
  final bool guardadoSinSenal;
  final bool noSeHizo;
  final ProgresoDia progreso;
  final TareaModel? siguiente;
  final String? usuarioActualId;

  const ResultadoCierrePage({
    super.key,
    required this.tarea,
    required this.guardadoSinSenal,
    required this.noSeHizo,
    required this.progreso,
    required this.siguiente,
    this.usuarioActualId,
  });

  @override
  Widget build(BuildContext context) {
    final companeros = trabajadoresDe([
      tarea,
    ]).where((p) => p.id != usuarioActualId).toList();
    final hm = DateFormat('HH:mm');
    final titulo = guardadoSinSenal
        ? 'Guardado en tu teléfono'
        : (noSeHizo ? 'Listo. Quedó registrado' : 'Listo. Actividad cerrada');
    final texto = guardadoSinSenal
        ? 'No hay señal. El cierre de "${tarea.descripcion}" se enviará solo cuando vuelva. No tienes que hacer nada más.'
        : (noSeHizo
              ? 'Registraste que "${tarea.descripcion}" no se pudo hacer, con su motivo.'
              : 'Cerraste "${tarea.descripcion}".${companeros.isNotEmpty ? ' También quedó cerrada para ${nombresEnLista(companeros.map((c) => c.nombre))}.' : ''}');
    return EscalaTexto(
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Cierre registrado'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: guardadoSinSenal
                                ? const Color(0xFFFDF0E1)
                                : const Color(0xFFE6F4EA),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            guardadoSinSenal
                                ? Icons.cloud_off
                                : Icons.check_circle,
                            size: 64,
                            color: guardadoSinSenal
                                ? const Color(0xFFB45309)
                                : const Color(0xFF15803D),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          titulo,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        texto,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      TarjetaProgreso(progreso: progreso),
                      const SizedBox(height: 20),
                      if (siguiente != null)
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(60),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(
                            'Ir a la siguiente: ${siguiente!.descripcion} (${hm.format(siguiente!.fechaInicio.toLocal())})',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                        icon: const Icon(Icons.today),
                        label: const Text('Volver a mis actividades'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mis actividades de otros días: franja de la semana y el día elegido.
class OtrosDiasPage extends StatefulWidget {
  final List<TareaModel> tareas;
  final Set<int> sinEnviar;
  final String usuarioActualId;
  final ValueChanged<TareaModel> onAbrir;

  const OtrosDiasPage({
    super.key,
    required this.tareas,
    required this.sinEnviar,
    required this.usuarioActualId,
    required this.onAbrir,
  });

  @override
  State<OtrosDiasPage> createState() => _OtrosDiasPageState();
}

class _OtrosDiasPageState extends State<OtrosDiasPage> {
  late DateTime _dia;
  late DateTime _semana;

  @override
  void initState() {
    super.initState();
    _dia = soloFecha(DateTime.now());
    _semana = inicioSemana(_dia);
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final dias = [for (var i = 0; i < 7; i++) _semana.add(Duration(days: i))];
    final delDia =
        widget.tareas.where((t) => mismoDia(t.fechaInicio, _dia)).toList()
          ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    final rango = MisActividadesRepo.rangoPorDefecto(ahora);
    final puedeAtras = _semana.isAfter(rango.desde);
    final puedeAdelante = _semana
        .add(const Duration(days: 7))
        .isBefore(rango.hasta);
    final f = DateFormat("d 'de' MMMM", 'es');

    return EscalaTexto(
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Otros días'),
          actions: const [TamanoTextoBoton()],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton.outlined(
                          tooltip: 'Semana anterior',
                          onPressed: puedeAtras
                              ? () => setState(() {
                                  _semana = _semana.subtract(
                                    const Duration(days: 7),
                                  );
                                  _dia = _semana;
                                })
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            'Semana del ${f.format(dias.first)} al ${f.format(dias.last)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton.outlined(
                          tooltip: 'Semana siguiente',
                          onPressed: puedeAdelante
                              ? () => setState(() {
                                  _semana = _semana.add(
                                    const Duration(days: 7),
                                  );
                                  _dia = _semana;
                                })
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FranjaDias(
                      dias: dias,
                      seleccionado: _dia,
                      ahora: ahora,
                      conteo: (d) => widget.tareas
                          .where((t) => mismoDia(t.fechaInicio, d))
                          .length,
                      onDia: (d) => setState(() => _dia = d),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _capitalizar(
                        DateFormat("EEEE d 'de' MMMM", 'es').format(_dia),
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (delDia.isEmpty)
                      const VacioCronograma(
                        mensaje: 'No tienes actividades este día.',
                      )
                    else
                      for (final franja in agruparSimultaneas(delDia)) ...[
                        if (franja.simultaneas)
                          GrupoSimultaneas(
                            franja: franja,
                            construir: (t) => _tarjeta(t, ahora),
                          )
                        else
                          _tarjeta(franja.tareas.first, ahora),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(TareaModel t, DateTime ahora) => ActividadCard(
    tarea: t,
    densidad: DensidadTarjeta.grande,
    ahora: ahora,
    trabajadorActualId: widget.usuarioActualId,
    cierrePendienteEnvio: widget.sinEnviar.contains(t.id),
    onTap: () {
      Navigator.of(context).pop();
      widget.onAbrir(t);
    },
  );
}
