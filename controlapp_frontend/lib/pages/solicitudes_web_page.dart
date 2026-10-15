import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/solicitudes_web_api.dart';
import 'package:flutter_application_1/model/solicitud_web_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/permission_service.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:flutter_application_1/widgets/evidencia_gallery.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Solicitudes que llegan desde la página web: trabajadores que se postulan y
/// conjuntos que se registran, con sus fotos y documentos en Google Drive.
/// Las postulaciones se pueden marcar como revisadas o borrar (permiso
/// web.solicitudes.gestionar); aprobar o rechazar se sigue haciendo en
/// WordPress.
class SolicitudesWebPage extends StatelessWidget {
  const SolicitudesWebPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: CommerceClayTokens.canvas,
        appBar: AppBar(
          backgroundColor: CommerceClayTokens.canvas,
          foregroundColor: CommerceClayTokens.ink,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Solicitudes de la web',
            style: TextStyle(
              color: CommerceClayTokens.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          bottom: const TabBar(
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: <Widget>[
              Tab(icon: Icon(Icons.badge_outlined), text: 'Trabajadores'),
              Tab(icon: Icon(Icons.apartment_rounded), text: 'Conjuntos'),
            ],
          ),
        ),
        body: const CommerceClayBackground(
          child: TabBarView(
            children: <Widget>[_PostulacionesTab(), _ConjuntosTab()],
          ),
        ),
      ),
    );
  }
}

final _fecha = DateFormat('dd/MM/yyyy · h:mm a');
final _api = SolicitudesWebApi();

/* -------------------------------------------------------------------------- */
/* Pestañas                                                                    */
/* -------------------------------------------------------------------------- */

class _PostulacionesTab extends StatelessWidget {
  const _PostulacionesTab();

  @override
  Widget build(BuildContext context) {
    return _ListaSolicitudes<PostulacionWeb>(
      heroEyebrow: 'Página web',
      heroTitulo: 'Personas que quieren trabajar',
      heroSubtitulo:
          'Postulaciones de "Trabaja con nosotros" con su foto y documentos.',
      heroIcono: Icons.badge_outlined,
      filtroInicial: 'sin_revisar',
      filtros: const <String, String>{
        'sin_revisar': 'Sin revisar',
        'revisadas': 'Revisadas',
        '': 'Todas',
      },
      cargar: (filtro, pagina) => _api.listarPostulaciones(
        revision: switch (filtro) {
          'sin_revisar' => 'pendientes',
          'revisadas' => 'revisadas',
          _ => null,
        },
        pagina: pagina,
      ),
      vacioTitulo: 'Sin postulaciones',
      vacioMensaje:
          'Cuando alguien se postule desde la página web aparecerá aquí.',
      vacioPorFiltro: const <String, String>{
        'sin_revisar': 'Al día: no hay postulaciones sin revisar.',
        'revisadas': 'Todavía no han marcado ninguna como revisada.',
      },
      itemBuilder: (context, p, alCambiar) =>
          _PostulacionCard(postulacion: p, alCambiar: alCambiar),
    );
  }
}

class _ConjuntosTab extends StatelessWidget {
  const _ConjuntosTab();

  @override
  Widget build(BuildContext context) {
    return _ListaSolicitudes<RegistroConjuntoWeb>(
      heroEyebrow: 'Página web',
      heroTitulo: 'Conjuntos que se registran',
      heroSubtitulo:
          'Registros de "¿Quieres ser aliado?" con su RUT y documentos.',
      heroIcono: Icons.apartment_rounded,
      filtros: const <String, String>{
        '': 'Todos',
        'pending': 'Pendientes',
        'approved': 'Aprobados',
        'rejected': 'Rechazados',
      },
      cargar: (estado, pagina) =>
          _api.listarConjuntos(estado: estado, pagina: pagina),
      vacioTitulo: 'Sin conjuntos registrados',
      vacioMensaje:
          'Cuando un conjunto o empresa se registre en la página aparecerá aquí.',
      itemBuilder: (context, c, _) => _ConjuntoCard(registro: c),
    );
  }
}

/// Lista paginada con filtros, compartida por las dos pestañas.
class _ListaSolicitudes<T> extends StatefulWidget {
  const _ListaSolicitudes({
    required this.heroEyebrow,
    required this.heroTitulo,
    required this.heroSubtitulo,
    required this.heroIcono,
    required this.filtros,
    required this.cargar,
    required this.vacioTitulo,
    required this.vacioMensaje,
    required this.itemBuilder,
    this.filtroInicial = '',
    this.vacioPorFiltro = const <String, String>{},
  });

  final String heroEyebrow;
  final String heroTitulo;
  final String heroSubtitulo;
  final IconData heroIcono;
  final Map<String, String> filtros;
  final String filtroInicial;
  final Future<PaginaWeb<T>> Function(String? filtro, int pagina) cargar;
  final String vacioTitulo;
  final String vacioMensaje;
  final Map<String, String> vacioPorFiltro;

  /// [alCambiar] recarga la lista (p. ej. tras marcar o borrar una solicitud).
  final Widget Function(BuildContext context, T item, VoidCallback alCambiar)
  itemBuilder;

  @override
  State<_ListaSolicitudes<T>> createState() => _ListaSolicitudesState<T>();
}

class _ListaSolicitudesState<T> extends State<_ListaSolicitudes<T>>
    with AutomaticKeepAliveClientMixin {
  late String _estado = widget.filtroInicial;
  List<T> _items = <T>[];
  int _pagina = 1;
  int _total = 0;
  bool _hayMas = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pagina = await widget.cargar(_estado, 1);
      if (!mounted) return;
      setState(() {
        _items = pagina.items;
        _pagina = 1;
        _total = pagina.total;
        _hayMas = pagina.hayMas;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final pagina = await widget.cargar(_estado, _pagina + 1);
      if (!mounted) return;
      setState(() {
        _items = <T>[..._items, ...pagina.items];
        _pagina = pagina.pagina;
        _total = pagina.total;
        _hayMas = pagina.hayMas;
      });
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _filtrar(String estado) {
    if (estado == _estado) return;
    setState(() => _estado = estado);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _items.isEmpty) {
      return CommerceStateView(
        icon: Icons.wifi_off_rounded,
        title: 'No pudimos cargar las solicitudes',
        message: _error!,
        actionLabel: 'Intentar de nuevo',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: <Widget>[
          CommerceHeroCard(
            eyebrow: widget.heroEyebrow,
            title: widget.heroTitulo,
            subtitle: _loading
                ? 'Cargando…'
                : '$_total ${_total == 1 ? 'solicitud' : 'solicitudes'} · ${widget.heroSubtitulo}',
            icon: widget.heroIcono,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.filtros.entries
                .map(
                  (filtro) => ChoiceChip(
                    label: Text(filtro.value),
                    selected: _estado == filtro.key,
                    onSelected: _loading ? null : (_) => _filtrar(filtro.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            CommerceStateView(
              icon: Icons.inbox_outlined,
              title: widget.vacioTitulo,
              message: _estado.isEmpty
                  ? widget.vacioMensaje
                  : widget.vacioPorFiltro[_estado] ??
                        'No hay solicitudes con este filtro.',
              actionLabel: _estado.isEmpty ? null : 'Ver todas',
              onAction: _estado.isEmpty ? null : () => _filtrar(''),
            )
          else ...<Widget>[
            ..._items.map((item) => widget.itemBuilder(context, item, _load)),
            if (_hayMas)
              Center(
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: _loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: const Text('Cargar más'),
                ),
              ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Aprobar o rechazar se sigue haciendo en WordPress → Control SAS.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CommerceClayTokens.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* Tarjetas                                                                    */
/* -------------------------------------------------------------------------- */

class _PostulacionCard extends StatelessWidget {
  const _PostulacionCard({required this.postulacion, required this.alCambiar});

  final PostulacionWeb postulacion;
  final VoidCallback alCambiar;

  Future<void> _abrir(BuildContext context) async {
    final cambios = _Cambios();
    await _abrirDetalle(
      context,
      _DetallePostulacion(postulacion: postulacion, cambios: cambios),
    );
    if (cambios.hubo) alCambiar();
  }

  @override
  Widget build(BuildContext context) {
    final p = postulacion;
    final fecha = p.creadoEn == null ? null : _fecha.format(p.creadoEn!);
    return CommerceClayCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      onTap: () => _abrir(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(foto: p.foto, nombre: p.nombreCompleto),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  p.nombreCompleto.isEmpty ? 'Sin nombre' : p.nombreCompleto,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: CommerceClayTokens.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _RevisionChip(revisada: p.revisada),
                    _EstadoChip(estado: p.estado, etiqueta: p.estadoEtiqueta),
                  ],
                ),
                const SizedBox(height: 6),
                if (p.habilidades.isNotEmpty)
                  Text(
                    p.habilidades.join(' · '),
                    style: const TextStyle(color: CommerceClayTokens.ink),
                  ),
                Text(
                  <String?>[p.telefono, fecha].whereType<String>().join(' · '),
                  style: const TextStyle(color: CommerceClayTokens.muted),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: CommerceClayTokens.muted,
          ),
        ],
      ),
    );
  }
}

class _ConjuntoCard extends StatelessWidget {
  const _ConjuntoCard({required this.registro});

  final RegistroConjuntoWeb registro;

  @override
  Widget build(BuildContext context) {
    final c = registro;
    final fecha = c.registradoEn == null
        ? null
        : _fecha.format(c.registradoEn!);
    return CommerceClayCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      onTap: () => _abrirDetalle(context, _DetalleConjunto(registro: c)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CommerceClayIcon(icon: Icons.apartment_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: CommerceClayTokens.ink,
                  ),
                ),
                const SizedBox(height: 6),
                _EstadoChip(estado: c.estado, etiqueta: c.estadoEtiqueta),
                const SizedBox(height: 6),
                Text(
                  <String?>[
                    c.nit == null ? null : 'NIT ${c.nit}',
                    '${c.documentos.length} documento${c.documentos.length == 1 ? '' : 's'}',
                  ].whereType<String>().join(' · '),
                  style: const TextStyle(color: CommerceClayTokens.ink),
                ),
                Text(
                  <String?>[c.telefono, fecha].whereType<String>().join(' · '),
                  style: const TextStyle(color: CommerceClayTokens.muted),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: CommerceClayTokens.muted,
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.foto, required this.nombre});

  final DocumentoWeb? foto;
  final String nombre;

  @override
  Widget build(BuildContext context) {
    final iniciales = nombre
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .take(2)
        .map((parte) => parte[0].toUpperCase())
        .join();
    final fallback = CircleAvatar(
      radius: 26,
      backgroundColor: CommerceClayTokens.mint,
      foregroundColor: CommerceClayTokens.ink,
      child: Text(
        iniciales.isEmpty ? '?' : iniciales,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
    final id = foto?.driveFileId;
    if (id == null) return fallback;
    return ClipOval(
      child: SizedBox(
        width: 52,
        height: 52,
        child: EvidenceImage(
          urls: <String>[SolicitudesWebApi.urlArchivo(id)],
          fit: BoxFit.cover,
          fallback: fallback,
        ),
      ),
    );
  }
}

class _RevisionChip extends StatelessWidget {
  const _RevisionChip({required this.revisada});

  final bool revisada;

  @override
  Widget build(BuildContext context) {
    final color = revisada ? const Color(0xFF1B7A43) : const Color(0xFF1D4ED8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            revisada ? Icons.task_alt_rounded : Icons.fiber_new_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            revisada ? 'Revisada' : 'Sin revisar',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado, required this.etiqueta});

  final String estado;
  final String etiqueta;

  Color get _color {
    switch (estado) {
      case 'aprobado':
      case 'approved':
        return const Color(0xFF1B7A43);
      case 'rechazado':
      case 'rejected':
      case 'bloqueado':
      case 'suspendido':
        return const Color(0xFFB3261E);
      case 'requiere_documentos':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF8A5A00);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        etiqueta,
        style: TextStyle(
          color: _color,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* Detalle                                                                     */
/* -------------------------------------------------------------------------- */

Future<void> _abrirDetalle(BuildContext context, Widget contenido) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: CommerceClayTokens.surface,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: contenido,
        ),
      ),
    ),
  );
}

/// Lo que se hizo dentro del detalle, para recargar la lista al cerrarlo
/// (aunque se cierre deslizando hacia abajo).
class _Cambios {
  bool hubo = false;
}

class _DetallePostulacion extends StatefulWidget {
  const _DetallePostulacion({required this.postulacion, required this.cambios});

  final PostulacionWeb postulacion;
  final _Cambios cambios;

  @override
  State<_DetallePostulacion> createState() => _DetallePostulacionState();
}

class _DetallePostulacionState extends State<_DetallePostulacion> {
  late PostulacionWeb _p = widget.postulacion;
  bool _guardando = false;

  bool get _puedeGestionar =>
      PermissionService.instance.can('web.solicitudes.gestionar');

  Future<void> _marcar(bool revisada) async {
    setState(() => _guardando = true);
    try {
      final actualizada = await _api.marcarRevision(_p.id, revisada: revisada);
      if (!mounted) return;
      widget.cambios.hubo = true;
      setState(() => _p = actualizada);
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _borrar() async {
    final nombre = _p.nombreCompleto.isEmpty
        ? 'esta persona'
        : _p.nombreCompleto;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar postulación'),
        content: Text(
          'Se borra la cuenta de $nombre en la página web y sus documentos '
          'pasan a la papelera de Google Drive (se pueden recuperar durante '
          '30 días). Desde la app no se puede deshacer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    try {
      final resultado = await _api.eliminarPostulacion(_p.id);
      if (!mounted) return;
      widget.cambios.hubo = true;
      final String mensaje;
      if (resultado.archivosSinMover > 0) {
        mensaje =
            'Se borró la postulación, pero ${resultado.archivosSinMover} '
            'documento(s) no pasaron a la papelera de Drive y siguen en su carpeta.';
      } else if (resultado.archivosEnPapelera > 0) {
        mensaje =
            'Se borró la postulación y sus documentos pasaron a la papelera de Drive.';
      } else {
        mensaje = 'Se borró la postulación.';
      }
      AppFeedback.showInfo(context, title: 'Listo', message: mensaje);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      AppFeedback.showError(context, message: AppError.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final documentos = <DocumentoWeb>[?p.foto, ...p.documentos];
    final revisadaDetalle = <String>[
      if (p.revisadaPor != null) 'por ${p.revisadaPor}',
      if (p.revisadaEn != null) _fecha.format(p.revisadaEn!),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _Avatar(foto: p.foto, nombre: p.nombreCompleto),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                p.nombreCompleto,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: CommerceClayTokens.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            _RevisionChip(revisada: p.revisada),
            _EstadoChip(estado: p.estado, etiqueta: p.estadoEtiqueta),
          ],
        ),
        if (p.revisada && revisadaDetalle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'Revisada $revisadaDetalle',
            style: const TextStyle(color: CommerceClayTokens.muted),
          ),
        ],
        if (_puedeGestionar) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (p.revisada)
                OutlinedButton.icon(
                  onPressed: _guardando ? null : () => _marcar(false),
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Marcar como no revisada'),
                )
              else
                FilledButton.icon(
                  onPressed: _guardando ? null : () => _marcar(true),
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('Marcar como revisada'),
                ),
              TextButton.icon(
                onPressed: _guardando ? null : _borrar,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB3261E),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Borrar postulación'),
              ),
              if (_guardando)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _Dato('Teléfono', p.telefono),
        _Dato('Correo', p.correo),
        _Dato(
          'Documento',
          p.documentoUltimos4 == null
              ? null
              : '${p.documentoTipo ?? ''} •••• ${p.documentoUltimos4}'.trim(),
        ),
        _Dato(
          'Habilidades',
          p.habilidades.isEmpty ? null : p.habilidades.join(', '),
        ),
        _Dato('Zonas', p.zonas.isEmpty ? null : p.zonas.join(', ')),
        _Dato(
          'Recibida',
          p.creadoEn == null ? null : _fecha.format(p.creadoEn!),
        ),
        _Dato('Observaciones', p.observaciones),
        _Contacto(telefono: p.telefono, correo: p.correo),
        _Documentos(documentos: documentos),
      ],
    );
  }
}

class _DetalleConjunto extends StatelessWidget {
  const _DetalleConjunto({required this.registro});

  final RegistroConjuntoWeb registro;

  @override
  Widget build(BuildContext context) {
    final c = registro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          c.nombre,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: CommerceClayTokens.ink,
          ),
        ),
        const SizedBox(height: 10),
        _EstadoChip(estado: c.estado, etiqueta: c.estadoEtiqueta),
        const SizedBox(height: 14),
        _Dato('NIT', c.nit),
        _Dato('Teléfono', c.telefono),
        _Dato('Correo', c.correo),
        _Dato(
          'Registrado',
          c.registradoEn == null ? null : _fecha.format(c.registradoEn!),
        ),
        _Dato('Nota del equipo', c.nota),
        _Contacto(telefono: c.telefono, correo: c.correo),
        _Documentos(documentos: c.documentos),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String? valor;

  @override
  Widget build(BuildContext context) {
    if (valor == null || valor!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              etiqueta,
              style: const TextStyle(
                color: CommerceClayTokens.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              valor!,
              style: const TextStyle(color: CommerceClayTokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _abrir(BuildContext context, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    AppFeedback.showError(context, message: 'No se pudo abrir el enlace.');
  }
}

class _Contacto extends StatelessWidget {
  const _Contacto({required this.telefono, required this.correo});

  final String? telefono;
  final String? correo;

  @override
  Widget build(BuildContext context) {
    final digitos = (telefono ?? '').replaceAll(RegExp(r'\D'), '');
    final whatsapp = digitos.length == 10 ? '57$digitos' : digitos;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          if (digitos.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _abrir(context, 'tel:+$whatsapp'),
              icon: const Icon(Icons.call_outlined),
              label: const Text('Llamar'),
            ),
          if (digitos.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _abrir(context, 'https://wa.me/$whatsapp'),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp'),
            ),
          if (correo != null)
            OutlinedButton.icon(
              onPressed: () => _abrir(context, 'mailto:$correo'),
              icon: const Icon(Icons.mail_outline_rounded),
              label: const Text('Correo'),
            ),
        ],
      ),
    );
  }
}

class _Documentos extends StatelessWidget {
  const _Documentos({required this.documentos});

  final List<DocumentoWeb> documentos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const CommerceSectionHeader(
          title: 'Fotos y documentos',
          subtitle: 'Guardados en Google Drive',
        ),
        const SizedBox(height: 10),
        if (documentos.isEmpty)
          const Text(
            'No adjuntó documentos.',
            style: TextStyle(color: CommerceClayTokens.muted),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: documentos
                .map((documento) => _DocumentoTile(documento: documento))
                .toList(),
          ),
        const SizedBox(height: 10),
        const Text(
          'Los PDF se abren en Google Drive con la cuenta de la empresa.',
          style: TextStyle(color: CommerceClayTokens.muted, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _DocumentoTile extends StatelessWidget {
  const _DocumentoTile({required this.documento});

  final DocumentoWeb documento;

  @override
  Widget build(BuildContext context) {
    final d = documento;
    final id = d.driveFileId;

    final Widget vista;
    VoidCallback? onTap;
    String? accion;
    if (id != null && d.esImagen) {
      final url = SolicitudesWebApi.urlArchivo(id);
      vista = EvidenceImage(
        urls: <String>[url],
        fit: BoxFit.cover,
        fallback: const Icon(Icons.broken_image_outlined),
      );
      onTap = () => mostrarEvidenciaPreview(context, <String>[url]);
    } else {
      final IconData icono;
      if (d.pendiente) {
        icono = Icons.cloud_upload_outlined;
        accion = 'Subiendo a Drive…';
      } else if (id != null) {
        icono = Icons.picture_as_pdf_outlined;
        accion = 'Abrir en Drive';
        onTap = () => _abrir(context, d.urlDrive!);
      } else if (d.urlServidor != null) {
        icono = Icons.description_outlined;
        accion = 'Abrir';
        onTap = () => _abrir(context, d.urlServidor!);
      } else {
        icono = Icons.dns_outlined;
        accion = 'En el servidor de la web';
      }
      vista = Center(
        child: Icon(icono, size: 34, color: CommerceClayTokens.muted),
      );
    }

    return SizedBox(
      width: 110,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 110,
                height: 110,
                color: CommerceClayTokens.mint,
                child: vista,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              d.etiqueta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: CommerceClayTokens.ink,
              ),
            ),
            if (accion != null)
              Text(
                accion,
                style: TextStyle(
                  fontSize: 12,
                  color: onTap == null
                      ? CommerceClayTokens.muted
                      : const Color(0xFF0A5E3D),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
