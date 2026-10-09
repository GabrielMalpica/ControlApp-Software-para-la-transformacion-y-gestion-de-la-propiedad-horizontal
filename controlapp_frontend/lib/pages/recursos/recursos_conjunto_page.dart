// lib/pages/recursos/recursos_conjunto_page.dart
import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/recursos_api.dart';
import 'package:flutter_application_1/model/recurso_agenda_model.dart';
import 'package:flutter_application_1/pages/recursos/centro_recursos_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/permission_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/recursos/necesidad_recurso_card.dart';
import 'package:flutter_application_1/widgets/recursos/recurso_estilos.dart';
import 'package:flutter_application_1/widgets/recursos/reserva_acciones.dart';

/// Recursos de UN conjunto, semana a semana: qué necesitan sus tareas, qué
/// maquinaria/herramienta propia tiene y qué recursos de la empresa le llegan
/// y cuándo (logística).
class RecursosConjuntoPage extends StatefulWidget {
  const RecursosConjuntoPage({
    super.key,
    required this.conjuntoId,
    this.conjuntoNombre,
    this.empresaNit,
    this.api,
  });

  /// Para pruebas: permite inyectar un cliente falso.
  final RecursosApi? api;

  final String conjuntoId;
  final String? conjuntoNombre;
  final String? empresaNit;

  @override
  State<RecursosConjuntoPage> createState() => _RecursosConjuntoPageState();
}

class _RecursosConjuntoPageState extends State<RecursosConjuntoPage> {
  late final RecursosApi _api = widget.api ?? RecursosApi();
  late DateTime _lunes;
  SemanaConjuntoResponse? _data;
  bool _cargando = true;
  String? _error;

  bool get _puedeAsignarAlgo => PermissionService.instance.canAny(const [
    'maquinaria.asignar',
    'herramientas.asignar',
  ]);

  bool _puedeAsignar(ClaseRecurso c) => PermissionService.instance.can(
    c == ClaseRecurso.maquinaria
        ? 'maquinaria.asignar'
        : 'herramientas.asignar',
  );

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _lunes = DateTime(
      hoy.year,
      hoy.month,
      hoy.day,
    ).subtract(Duration(days: hoy.weekday - DateTime.monday));
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await _api.semanaConjunto(
        conjuntoId: widget.conjuntoId,
        desde: _lunes,
        dias: 7,
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _moverSemana(int delta) {
    setState(() => _lunes = _lunes.add(Duration(days: 7 * delta)));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final nombre = data?.conjuntoNombre ?? widget.conjuntoNombre ?? 'Conjunto';
    final domingo = _lunes.add(const Duration(days: 6));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recursos del conjunto'),
            Text(
              nombre,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          if (_puedeAsignarAlgo && widget.empresaNit != null)
            IconButton(
              tooltip: 'Centro de recursos de la empresa',
              icon: const Icon(Icons.hub_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CentroRecursosPage(
                    empresaNit: widget.empresaNit!,
                    conjuntoIdInicial: widget.conjuntoId,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _moverSemana(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Semana del ${RecursoEstilos.fechaCorta.format(_lunes)} al ${RecursoEstilos.fechaCorta.format(domingo)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => _moverSemana(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () {
                    final hoy = DateTime.now();
                    setState(
                      () => _lunes = DateTime(
                        hoy.year,
                        hoy.month,
                        hoy.day,
                      ).subtract(Duration(days: hoy.weekday - DateTime.monday)),
                    );
                    _cargar();
                  },
                  child: const Text('Hoy'),
                ),
              ],
            ),
            if (_cargando) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _cargar,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (data != null) ...[
              _Seccion(
                titulo: 'Lo que necesitan las tareas',
                icono: Icons.assignment_outlined,
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    if (data.resumenNecesidades.pendientes +
                            data.resumenNecesidades.parciales >
                        0)
                      EstadoPill(
                        texto:
                            '${data.resumenNecesidades.pendientes + data.resumenNecesidades.parciales} por cubrir',
                        color: AppTheme.red,
                      ),
                    EstadoPill(
                      texto: '${data.resumenNecesidades.cubiertas} cubiertas',
                      color: AppTheme.green,
                    ),
                  ],
                ),
                child: data.necesidades.isEmpty
                    ? const _TextoVacio(
                        'Ninguna tarea de esta semana pide maquinaria o herramientas.',
                      )
                    : Column(
                        children: [
                          for (final n in data.necesidades)
                            NecesidadRecursoCard(
                              necesidad: n,
                              api: _api,
                              empresaNit: widget.empresaNit,
                              puedeAsignar: _puedeAsignar(n.clase),
                              onCambio: _cargar,
                              mostrarConjunto: false,
                            ),
                        ],
                      ),
              ),
              _Seccion(
                titulo: 'Llegan de la empresa',
                icono: Icons.local_shipping_outlined,
                child: data.recursosEmpresa.isEmpty
                    ? const _TextoVacio(
                        'Esta semana no llega ningún recurso de la empresa.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final dia in data.recursosEmpresa) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 4),
                              child: Text(
                                RecursoEstilos.capitalizar(
                                  RecursoEstilos.diaLargo.format(dia.fecha),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            for (final r in dia.reservas)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  r.esPrestamo
                                      ? Icons.handshake_outlined
                                      : RecursoEstilos.iconoClase(r.clase),
                                  color: AppTheme.primary,
                                ),
                                title: Text(
                                  r.recursoEtiqueta,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  r.esPrestamo
                                      ? 'Préstamo hasta ${RecursoEstilos.fechaCorta.format(r.bloqueoFin)}'
                                      : '${r.tareaDescripcion ?? ''} · ${RecursoEstilos.rangoHoras(r.usoInicio, r.usoFin)}'
                                            '${r.tieneVentanaLogistica ? '\nEntrega ${RecursoEstilos.fechaCorta.format(r.bloqueoInicio)} · recogida ${RecursoEstilos.fechaCorta.format(r.bloqueoFin)}' : ''}',
                                ),
                                onTap: () async {
                                  final cambio = await mostrarDetalleReserva(
                                    context,
                                    api: _api,
                                    reserva: r,
                                    empresaNit: widget.empresaNit,
                                    puedeAsignar: _puedeAsignar(r.clase),
                                  );
                                  if (cambio) _cargar();
                                },
                              ),
                          ],
                        ],
                      ),
              ),
              _Seccion(
                titulo: 'Recursos propios',
                icono: Icons.inventory_2_outlined,
                child: data.recursosPropios.isEmpty
                    ? const _TextoVacio(
                        'El conjunto no tiene maquinaria ni herramientas propias registradas.',
                      )
                    : Column(
                        children: [
                          for (final u in data.recursosPropios)
                            _UnidadSemana(
                              unidad: u,
                              dias: data.dias,
                              onHistorial: () => mostrarHistorialUnidad(
                                context,
                                api: _api,
                                clase: u.clase,
                                unidadId: u.id,
                                empresaNit: widget.empresaNit,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.icono,
    required this.child,
    this.trailing,
  });
  final String titulo;
  final IconData icono;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Material (no Container con color) para que los ListTile internos
    // pinten su efecto al tocarlos.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppTheme.surfaceSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _TextoVacio extends StatelessWidget {
  const _TextoVacio(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) =>
      Text(texto, style: const TextStyle(color: AppTheme.textMuted));
}

/// Una unidad propia con su semana en 7 celdas de color.
class _UnidadSemana extends StatelessWidget {
  const _UnidadSemana({
    required this.unidad,
    required this.dias,
    required this.onHistorial,
  });
  final UnidadAgendaModel unidad;
  final List<DateTime> dias;
  final VoidCallback onHistorial;

  @override
  Widget build(BuildContext context) {
    final u = unidad;
    return InkWell(
      onTap: onHistorial,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  RecursoEstilos.iconoClase(u.clase),
                  size: 18,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${u.etiqueta} · ${u.tipoNombre}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                EstadoPill(
                  texto: u.estadoActual.etiqueta,
                  color: RecursoEstilos.colorActual(u.estadoActual),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < u.dias.length; i++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${RecursoEstilos.capitalizar(RecursoEstilos.diaCorto.format(u.dias[i].fecha))}: '
                          '${u.dias[i].estado.etiqueta}'
                          '${u.dias[i].conjuntoNombre != null ? ' · ${u.dias[i].conjuntoNombre}' : ''}',
                      child: Container(
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: RecursoEstilos.colorDia(u.dias[i].estado)
                              .withValues(
                                alpha:
                                    u.dias[i].estado ==
                                        EstadoDiaRecurso.disponible
                                    ? 1
                                    : 0.85,
                              ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          RecursoEstilos.diaCorto
                              .format(u.dias[i].fecha)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                u.dias[i].estado == EstadoDiaRecurso.disponible
                                ? AppTheme.textMuted
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (final r in u.reservas.where((r) => r.esTarea && !r.cancelada))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${RecursoEstilos.capitalizar(RecursoEstilos.diaCorto.format(r.usoInicio))} · '
                  '${RecursoEstilos.rangoHoras(r.usoInicio, r.usoFin)} · ${r.tareaDescripcion ?? ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
