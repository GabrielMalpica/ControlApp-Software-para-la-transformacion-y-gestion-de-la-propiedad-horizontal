import 'package:flutter/material.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../model/usuario_model.dart';
import '../../repositories/usuario_repository.dart';
import '../../service/theme.dart';
import '../../widgets/searchable_select_field.dart';
import 'crear_usuario_page.dart';
import 'editar_usuario_page.dart';
import 'detalle_usuario_page.dart';

import '../../service/app_error.dart';
import '../../service/app_feedback.dart';

class ListaUsuariosPage extends StatefulWidget {
  final String nit; // para crear admin vinculados al conjunto/empresa

  const ListaUsuariosPage({super.key, required this.nit});

  @override
  State<ListaUsuariosPage> createState() => _ListaUsuariosPageState();
}

class _ListaUsuariosPageState extends State<ListaUsuariosPage> {
  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  final GerenteApi _gerenteApi = GerenteApi();
  final TextEditingController _busquedaCtrl = TextEditingController();

  List<Usuario> _usuarios = [];
  List<Conjunto> _conjuntos = [];
  bool _cargando = true;
  String? _error;

  // Filtro por rol
  String _filtroRol = 'todos';
  String _busqueda = '';
  Conjunto? _filtroConjunto;

  // Roles disponibles (los mismos del enum del back)
  final List<String> _rolesDisponibles = [
    'todos',
    'gerente',
    'administrador',
    'jefe_operaciones',
    'supervisor',
    'operario',
  ];

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarUsuarios() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _usuarioRepository.obtenerUsuarios(),
        _gerenteApi.listarConjuntos(),
      ]);
      final lista = results[0] as List<Usuario>;
      final conjuntos = results[1] as List<Conjunto>;
      setState(() {
        _usuarios = lista;
        _conjuntos = conjuntos;
      });
    } catch (e) {
      setState(() {
        _error = AppError.messageOf(e);
      });
    } finally {
      setState(() {
        _cargando = false;
      });
    }
  }

  // Filtra en memoria por rol
  List<Usuario> get _usuariosFiltrados {
    return _usuarios.where((u) {
      final coincideRol = _filtroRol == 'todos' || u.rol == _filtroRol;
      if (!coincideRol) return false;

      if (_filtroConjunto != null) {
        final conjunto = _filtroConjunto!;
        final pertenece =
            conjunto.administradorId == u.cedula ||
            conjunto.operarios.any((operario) => operario.cedula == u.cedula);
        if (!pertenece) return false;
      }

      final q = _busqueda.trim().toLowerCase();
      if (q.isEmpty) return true;

      return [
        u.nombre,
        u.cedula,
        u.correo,
        _prettyRol(u.rol),
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  String _prettyRol(String rol) {
    if (rol.isEmpty) return rol;
    final withSpaces = rol.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  Future<void> _irACrearUsuario() async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CrearUsuarioPage(nit: widget.nit)),
    );

    if (resultado == true) {
      _cargarUsuarios();
    }
  }

  Future<void> _irAEditarUsuario(Usuario usuario) async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditarUsuarioPage(usuario: usuario)),
    );

    if (resultado == true) {
      _cargarUsuarios();
    }
  }

  Future<void> _confirmarEliminarUsuario(Usuario usuario) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Eliminar usuario"),
        content: Text(
          "¿Seguro que deseas eliminar al usuario ${usuario.nombre} (${usuario.cedula})?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _usuarioRepository.eliminarUsuario(usuario.cedula);
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text("✅ Usuario eliminado correctamente"),
          backgroundColor: Colors.green,
        ),
      );
      _cargarUsuarios();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text("❌ Error al eliminar usuario: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Gestión de usuarios",
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.person_add),
        label: const Text("Nuevo usuario"),
        onPressed: _irACrearUsuario,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ───────── Filtro por rol ─────────
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list),
                    const SizedBox(width: 8),
                    const Text(
                      "Filtrar por rol:",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _rolesDisponibles.map((rol) {
                            final seleccionado = _filtroRol == rol;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: Text(
                                  rol == 'todos' ? "Todos" : _prettyRol(rol),
                                ),
                                selected: seleccionado,
                                onSelected: (_) {
                                  setState(() {
                                    _filtroRol = rol;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SearchableSelectField<Conjunto>(
              label: 'Filtrar por conjunto',
              value: _filtroConjunto,
              prefixIcon: const Icon(Icons.apartment_rounded),
              searchHint: 'Buscar conjunto o NIT',
              clearLabel: 'Todos los conjuntos',
              options: _conjuntos
                  .map(
                    (conjunto) => SearchableSelectOption<Conjunto>(
                      value: conjunto,
                      label: conjunto.nombre,
                      subtitle: 'NIT: ${conjunto.nit}',
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _filtroConjunto = value),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar usuario',
                hintText: 'Nombre, cédula, correo o rol',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _busqueda.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() => _busqueda = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (value) => setState(() => _busqueda = value),
            ),
            const SizedBox(height: 8),

            // ───────── Contenido ─────────
            Expanded(child: _cuerpo()),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          "Error cargando usuarios:\n$_error",
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_usuariosFiltrados.isEmpty) {
      return const Center(
        child: Text("No hay usuarios para el filtro seleccionado."),
      );
    }

    return ListView.separated(
      itemCount: _usuariosFiltrados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final u = _usuariosFiltrados[index];

        // ✅ si el backend no manda activo (por compatibilidad), lo consideramos true
        final bool isActivo = (u.activo);

        final Color avatarBg = isActivo
            ? AppTheme.primary.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.2);

        final Color avatarTextColor = isActivo ? AppTheme.primary : Colors.grey;

        final Color titleColor = isActivo ? Colors.black87 : Colors.grey;
        final Color subtitleColor = isActivo ? Colors.black54 : Colors.grey;

        return Opacity(
          opacity: isActivo ? 1.0 : 0.55, // ✅ efecto apagado
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetalleUsuarioPage(usuario: u),
                ),
              );
            },
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: avatarBg,
                  child: Text(
                    u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : '?',
                    style: TextStyle(color: avatarTextColor),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        u.nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),
                    ),
                    if (!isActivo)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Chip(
                          label: Text(
                            "Inactivo",
                            style: TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  "Cédula: ${u.cedula} · Rol: ${_prettyRol(u.rol)}\nCorreo: ${u.correo}",
                  style: TextStyle(color: subtitleColor),
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: "Editar",
                      icon: Icon(
                        Icons.edit,
                        color: isActivo ? Colors.blueGrey : Colors.grey,
                      ),
                      onPressed: () => _irAEditarUsuario(u),
                    ),
                    IconButton(
                      tooltip: "Eliminar",
                      icon: Icon(
                        Icons.delete_outline,
                        color: isActivo ? Colors.red : Colors.grey,
                      ),
                      onPressed: () => _confirmarEliminarUsuario(u),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
