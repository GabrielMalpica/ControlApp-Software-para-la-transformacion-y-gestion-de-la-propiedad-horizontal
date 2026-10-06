import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/catalogo_operativo_api.dart';
import 'package:flutter_application_1/model/catalogo_operativo_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';

const List<String> _rolesPerfil = [
  'TODERO',
  'SALVAVIDAS',
  'ASEO',
  'PISCINERO',
  'JARDINERO',
];

const List<String> _coloresCategoria = [
  '#0288D1',
  '#558B2F',
  '#2E7D32',
  '#8E24AA',
  '#EF6C00',
  '#D32F2F',
  '#455A64',
  '#00897B',
];

Color _colorDe(String? hex, {Color fallback = AppTheme.primary}) {
  final limpio = hex?.replaceFirst('#', '');
  if (limpio != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(limpio)) {
    return Color(int.parse('FF$limpio', radix: 16));
  }
  return fallback;
}

/// Catálogo operativo de la empresa: categorías de tarea (orden de
/// programación del día) y perfiles con las categorías que pueden ejecutar.
class CatalogoOperativoPage extends StatefulWidget {
  const CatalogoOperativoPage({super.key});

  @override
  State<CatalogoOperativoPage> createState() => _CatalogoOperativoPageState();
}

class _CatalogoOperativoPageState extends State<CatalogoOperativoPage> {
  final CatalogoOperativoApi _api = CatalogoOperativoApi();

  List<CategoriaTarea> _categorias = [];
  List<PerfilOperativo> _perfiles = [];
  bool _cargando = true;
  String? _error;
  bool _guardandoOrden = false;

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
      final resultados = await Future.wait([
        _api.listarCategorias(),
        _api.listarPerfiles(),
      ]);
      if (!mounted) return;
      setState(() {
        _categorias = resultados[0] as List<CategoriaTarea>;
        _perfiles = resultados[1] as List<PerfilOperativo>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppError.messageOf(
          e,
          fallback: 'No se pudo cargar el catálogo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(Object e, String fallback) {
    if (!mounted) return;
    AppFeedback.showError(
      context,
      message: AppError.messageOf(e, fallback: fallback),
    );
  }

  /* ============================ CATEGORÍAS ============================ */

  Future<void> _reordenar(int oldIndex, int newIndex) async {
    if (_guardandoOrden) return;
    if (oldIndex == newIndex) return;
    final anterior = List<CategoriaTarea>.from(_categorias);
    final nuevo = List<CategoriaTarea>.from(_categorias);
    final movida = nuevo.removeAt(oldIndex);
    nuevo.insert(newIndex, movida);
    setState(() {
      _categorias = nuevo;
      _guardandoOrden = true;
    });
    try {
      final guardadas = await _api.reordenarCategorias(
        nuevo.map((c) => c.id).toList(),
      );
      if (!mounted) return;
      setState(() => _categorias = guardadas);
    } catch (e) {
      if (!mounted) return;
      setState(() => _categorias = anterior);
      _mostrarError(e, 'No se pudo guardar el orden de las categorías.');
    } finally {
      if (mounted) setState(() => _guardandoOrden = false);
    }
  }

  Future<void> _editarCategoria([CategoriaTarea? existente]) async {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final clavesCtrl = TextEditingController(
      text: existente?.palabrasClave.join(', ') ?? '',
    );
    String color = existente?.colorHex ?? _coloresCategoria.first;
    bool activa = existente?.activa ?? true;
    String? errorNombre;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existente == null ? 'Nueva categoría' : 'Editar categoría'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nombre',
                      errorText: errorNombre,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 14),
                  const Text('Color'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _coloresCategoria.map((hex) {
                      final seleccionado =
                          color.toUpperCase() == hex.toUpperCase();
                      return InkWell(
                        onTap: () => setLocal(() => color = hex),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _colorDe(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: seleccionado
                                  ? AppTheme.text
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: clavesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Palabras clave (separadas por coma)',
                      helperText:
                          'Se usan para sugerir esta categoría a las preventivas.',
                      helperMaxLines: 2,
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  if (existente != null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activa'),
                      subtitle: const Text(
                        'Una categoría inactiva no se puede elegir en preventivas nuevas.',
                      ),
                      value: activa,
                      onChanged: (v) => setLocal(() => activa = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (nombreCtrl.text.trim().isEmpty) {
                  setLocal(() => errorNombre = 'El nombre es obligatorio');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final nombre = nombreCtrl.text.trim();
    final claves = clavesCtrl.text
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    nombreCtrl.dispose();
    clavesCtrl.dispose();
    if (guardar != true) return;

    try {
      if (existente == null) {
        await _api.crearCategoria(
          nombre: nombre,
          colorHex: color,
          palabrasClave: claves,
        );
      } else {
        await _api.editarCategoria(
          existente.id,
          nombre: nombre,
          colorHex: color,
          palabrasClave: claves,
          activa: activa,
        );
      }
      await _cargar();
    } catch (e) {
      _mostrarError(e, 'No se pudo guardar la categoría.');
    }
  }

  Future<void> _eliminarCategoria(CategoriaTarea c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Eliminar ${c.nombre}'),
        content: Text(
          c.preventivas > 0
              ? 'La usan ${c.preventivas} preventiva(s): no se puede eliminar. '
                    'Puedes desactivarla en su lugar.'
              : 'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          if (c.preventivas == 0)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.eliminarCategoria(c.id);
      await _cargar();
    } catch (e) {
      _mostrarError(e, 'No se pudo eliminar la categoría.');
    }
  }

  /* ============================== PERFILES ============================== */

  Future<void> _editarPerfil([PerfilOperativo? existente]) async {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final descripcionCtrl = TextEditingController(
      text: existente?.descripcion ?? '',
    );
    final roles = <String>{...(existente?.roles ?? [_rolesPerfil.first])};
    final categoriasSel = <int>{...(existente?.categoriasIds ?? const [])};
    bool activo = existente?.activo ?? true;
    String? errorNombre;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existente == null ? 'Nuevo perfil' : 'Editar perfil'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nombre del perfil',
                      hintText: 'Ej. Todero-Salvavidas',
                      errorText: errorNombre,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Roles que debe tener quien ocupe una plaza de este perfil',
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _rolesPerfil.map((r) {
                      return FilterChip(
                        label: Text(kEtiquetaRolFuncion[r] ?? r),
                        selected: roles.contains(r),
                        onSelected: (sel) => setLocal(() {
                          if (sel) {
                            roles.add(r);
                          } else if (roles.length > 1) {
                            roles.remove(r);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('Categorías de tarea que puede ejecutar'),
                  const SizedBox(height: 4),
                  Text(
                    'Es la única fuente de verdad: el cronograma solo le asigna '
                    'tareas de estas categorías.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_categorias.isEmpty)
                    const Text('Aún no hay categorías.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _categorias
                          .where(
                            (c) => c.activa || categoriasSel.contains(c.id),
                          )
                          .map((c) {
                            return FilterChip(
                              label: Text(
                                c.activa ? c.nombre : '${c.nombre} (inactiva)',
                              ),
                              selected: categoriasSel.contains(c.id),
                              onSelected: (sel) => setLocal(() {
                                if (sel) {
                                  categoriasSel.add(c.id);
                                } else {
                                  categoriasSel.remove(c.id);
                                }
                              }),
                            );
                          })
                          .toList(),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descripcionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                    ),
                    maxLines: 2,
                  ),
                  if (existente != null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activo'),
                      subtitle: const Text(
                        'Un perfil inactivo no recibe tareas reasignadas ni se puede elegir en plazas nuevas.',
                      ),
                      value: activo,
                      onChanged: (v) => setLocal(() => activo = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (nombreCtrl.text.trim().isEmpty) {
                  setLocal(() => errorNombre = 'El nombre es obligatorio');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final nombre = nombreCtrl.text.trim();
    final descripcion = descripcionCtrl.text.trim();
    nombreCtrl.dispose();
    descripcionCtrl.dispose();
    if (guardar != true) return;

    try {
      if (existente == null) {
        await _api.crearPerfil(
          nombre: nombre,
          roles: roles.toList(),
          descripcion: descripcion,
          categoriasIds: categoriasSel.toList(),
        );
      } else {
        await _api.editarPerfil(
          existente.id,
          nombre: nombre,
          roles: roles.toList(),
          descripcion: descripcion,
          activo: activo,
          categoriasIds: categoriasSel.toList(),
        );
      }
      await _cargar();
    } catch (e) {
      _mostrarError(e, 'No se pudo guardar el perfil.');
    }
  }

  Future<void> _eliminarPerfil(PerfilOperativo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Eliminar ${p.nombre}'),
        content: Text(
          p.plazas > 0
              ? 'Lo usan ${p.plazas} plaza(s): no se puede eliminar. '
                    'Puedes desactivarlo en su lugar.'
              : 'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          if (p.plazas == 0)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.eliminarPerfil(p.id);
      await _cargar();
    } catch (e) {
      _mostrarError(e, 'No se pudo eliminar el perfil.');
    }
  }

  /* ================================ UI ================================ */

  Widget _estado({
    required IconData icono,
    required String mensaje,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 44, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            if (accion != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAccion, child: Text(accion)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabCategorias() {
    if (_categorias.isEmpty) {
      return _estado(
        icono: Icons.category_outlined,
        mensaje: 'Aún no hay categorías de tarea.',
        accion: 'Crear categoría',
        onAccion: _editarCategoria,
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Arrastra para ordenar el día: la primera se programa primero. '
                  'Esto no cambia qué tareas entran al mes (eso lo decide la '
                  'prioridad 1/2/3).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _editarCategoria(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: _categorias.length,
            onReorderItem: _reordenar,
            itemBuilder: (context, i) {
              final c = _categorias[i];
              return Card(
                key: ValueKey('categoria_${c.id}'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _colorDe(c.colorHex),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.nombre,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: c.activa ? null : AppTheme.textMuted,
                          ),
                        ),
                      ),
                      if (!c.activa) ...[
                        const SizedBox(width: 8),
                        const Chip(
                          label: Text('Inactiva'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${c.preventivas} preventiva(s)'
                    '${c.palabrasClave.isEmpty ? '' : ' · ${c.palabrasClave.take(4).join(', ')}${c.palabrasClave.length > 4 ? '…' : ''}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editarCategoria(c),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _eliminarCategoria(c),
                      ),
                      const SizedBox(width: 24), // espacio para el asa de arrastre
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tabPerfiles() {
    if (_perfiles.isEmpty) {
      return _estado(
        icono: Icons.badge_outlined,
        mensaje:
            'Aún no hay perfiles. Se crean automáticamente al crear plazas, o puedes crear uno aquí.',
        accion: 'Crear perfil',
        onAccion: _editarPerfil,
      );
    }
    final nombrePorCategoria = {for (final c in _categorias) c.id: c.nombre};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Un perfil define qué categorías puede ejecutar quien ocupe '
                  'la plaza. Un perfil sin categorías no recibe tareas '
                  'reasignadas.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _editarPerfil(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: _perfiles.length,
            itemBuilder: (context, i) {
              final p = _perfiles[i];
              final capacidades = p.categoriasIds
                  .map((id) => nombrePorCategoria[id])
                  .whereType<String>()
                  .toList();
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.nombre,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: p.activo ? null : AppTheme.textMuted,
                              ),
                            ),
                          ),
                          if (!p.activo)
                            const Chip(
                              label: Text('Inactivo'),
                              visualDensity: VisualDensity.compact,
                            ),
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editarPerfil(p),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _eliminarPerfil(p),
                          ),
                        ],
                      ),
                      Text(
                        'Roles: ${p.etiquetaRoles} · ${p.plazas} plaza(s)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (capacidades.isEmpty)
                        Text(
                          'Sin categorías configuradas: no recibe tareas reasignadas.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.red),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: capacidades
                              .map(
                                (n) => Chip(
                                  label: Text(n),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Categorías y perfiles'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.category_outlined), text: 'Categorías'),
              Tab(icon: Icon(Icons.badge_outlined), text: 'Perfiles'),
            ],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _estado(
                icono: Icons.wifi_off_rounded,
                mensaje: _error!,
                accion: 'Reintentar',
                onAccion: _cargar,
              )
            : TabBarView(children: [_tabCategorias(), _tabPerfiles()]),
      ),
    );
  }
}
