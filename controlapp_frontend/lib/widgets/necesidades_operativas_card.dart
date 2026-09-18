import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';

const _diasSemanaNecesidad = <String>[
  'LUNES',
  'MARTES',
  'MIERCOLES',
  'JUEVES',
  'VIERNES',
  'SABADO',
  'DOMINGO',
];

const _rolesNecesidad = <String>[
  'TODERO',
  'SALVAVIDAS',
  'ASEO',
  'PISCINERO',
  'JARDINERO',
];

const _etiquetaRol = <String, String>{
  'TODERO': 'Todero',
  'SALVAVIDAS': 'Salvavidas',
  'ASEO': 'Aseo',
  'PISCINERO': 'Piscinero',
  'JARDINERO': 'Jardinero',
};

/// "Todero-Salvavidas" para una plaza combinada; "Todero" para una sola.
String _etiquetaRoles(Iterable<String> roles) =>
    roles.map((r) => _etiquetaRol[r] ?? r).join('-');

/// Sección "Necesidades de operarios" del detalle del conjunto: lista las
/// plazas/cargos (ConjuntoNecesidadOperario), permite crearlas, editarlas,
/// eliminarlas y asignar/liberar al operario que las ocupa. Ver la sección
/// E del plan de necesidades operativas.
class NecesidadesOperativasCard extends StatefulWidget {
  final String conjuntoNit;
  final List<Usuario> operariosCatalogo;

  const NecesidadesOperativasCard({
    super.key,
    required this.conjuntoNit,
    required this.operariosCatalogo,
  });

  @override
  State<NecesidadesOperativasCard> createState() =>
      _NecesidadesOperativasCardState();
}

class _NecesidadesOperativasCardState
    extends State<NecesidadesOperativasCard> {
  final ConjuntoApi _api = ConjuntoApi();
  late Future<List<NecesidadOperario>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.listarNecesidades(widget.conjuntoNit);
  }

  void _reload() {
    setState(() {
      _future = _api.listarNecesidades(widget.conjuntoNit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4ECE8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Necesidades de operarios',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'agregar') _mostrarFormulario();
                  if (value == 'migrar') _migrarDesdeOperarios();
                  if (value == 'vincular') _vincularDefiniciones();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'agregar',
                    child: Text('Agregar necesidad'),
                  ),
                  PopupMenuItem(
                    value: 'migrar',
                    child: Text('1. Crear plazas desde operarios actuales'),
                  ),
                  PopupMenuItem(
                    value: 'vincular',
                    child: Text('2. Vincular preventivas existentes a esas plazas'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Cargos que necesita el conjunto (ej. Todero #1, Salvavidas #1). '
            'El operario que la ocupa se asigna aquí; las preventivas que '
            'apunten a esta plaza seguirán resolviendo a quien la ocupe.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<NecesidadOperario>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'No se pudieron cargar las necesidades: ${AppError.messageOf(snapshot.error)}',
                  style: const TextStyle(color: Colors.red),
                );
              }
              final necesidades = snapshot.data ?? const [];
              if (necesidades.isEmpty) {
                return Text(
                  'Este conjunto todavía no tiene necesidades configuradas.',
                  style: TextStyle(color: Colors.grey.shade600),
                );
              }
              return Column(
                children: necesidades
                    .map((n) => _necesidadTile(n, necesidades))
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _necesidadTile(NecesidadOperario n, List<NecesidadOperario> todas) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6EEEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      n.etiqueta,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _etiquetaRoles(n.roles),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (n.horarioEspecial) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Tiene horario especial propio',
                        child: Icon(
                          Icons.schedule,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _mostrarFormulario(existente: n),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _confirmarEliminar(n),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                n.ocupada ? Icons.person : Icons.person_off_outlined,
                size: 16,
                color: n.ocupada ? AppTheme.primary : Colors.grey,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  n.ocupada ? (n.operarioNombre ?? n.operarioId!) : 'Vacante',
                  style: TextStyle(
                    color: n.ocupada ? Colors.black87 : Colors.grey.shade600,
                    fontStyle: n.ocupada ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
              if (n.ocupada) ...[
                TextButton(
                  onPressed: () => _cambiarVacante(n, todas),
                  child: const Text('Cambiar vacante'),
                ),
                TextButton(
                  onPressed: () => _liberar(n),
                  child: const Text('Liberar'),
                ),
              ] else
                TextButton(
                  onPressed: () => _mostrarAsignarOperario(n, todas),
                  child: const Text('Asignar'),
                ),
            ],
          ),
          if (n.horarioEspecial && n.horarios.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: n.horarios
                  .map(
                    (h) => Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${h.dia.substring(0, 3)} ${h.horaApertura}-${h.horaCierre}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _liberar(NecesidadOperario n) async {
    try {
      await _api.liberarNecesidad(
        conjuntoNit: widget.conjuntoNit,
        necesidadId: n.id,
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudo liberar la plaza: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _mostrarAsignarOperario(
    NecesidadOperario n,
    List<NecesidadOperario> todas,
  ) async {
    // La plaza puede exigir varios roles combinados: el candidato debe
    // tenerlos TODOS (igual que valida el backend).
    final candidatos = widget.operariosCatalogo
        .where(
          (o) => n.roles.every((r) => (o.tipoFunciones ?? const []).contains(r)),
        )
        .toList();

    if (candidatos.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Ningún operario tiene el rol ${_etiquetaRoles(n.roles)}.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Si un candidato ya ocupa otra plaza de este conjunto, elegirlo aquí lo
    // MUEVE (el backend libera su plaza anterior automáticamente): se avisa
    // en la etiqueta para que quede claro antes de confirmar.
    final ocupacionActual = <String, String>{
      for (final otra in todas)
        if (otra.id != n.id && otra.operarioId != null)
          otra.operarioId!: otra.etiqueta,
    };

    String? seleccionado;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Asignar operario a ${n.etiqueta}'),
          content: DropdownButtonFormField<String>(
            initialValue: seleccionado,
            items: candidatos
                .map(
                  (o) => DropdownMenuItem(
                    value: o.cedula,
                    child: Text(
                      ocupacionActual.containsKey(o.cedula)
                          ? '${o.nombre} (${o.cedula}) — mover desde ${ocupacionActual[o.cedula]}'
                          : '${o.nombre} (${o.cedula})',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setDialogState(() => seleccionado = v),
            decoration: const InputDecoration(
              labelText: 'Operario',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: seleccionado == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || seleccionado == null) return;
    try {
      await _api.asignarOperarioNecesidad(
        conjuntoNit: widget.conjuntoNit,
        necesidadId: n.id,
        operarioId: seleccionado!,
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudo asignar el operario: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Mueve al operario que ocupa [actual] a otra plaza vacante compatible
  /// del mismo conjunto, en un solo paso (sin liberar y volver a asignar a
  /// mano). Reutiliza asignarOperarioNecesidad: el backend libera la plaza
  /// de origen automáticamente al asignar la de destino.
  Future<void> _cambiarVacante(
    NecesidadOperario actual,
    List<NecesidadOperario> todas,
  ) async {
    final operarioId = actual.operarioId;
    if (operarioId == null) return;

    Usuario? operario;
    for (final o in widget.operariosCatalogo) {
      if (o.cedula == operarioId) {
        operario = o;
        break;
      }
    }
    final rolesOperario = operario?.tipoFunciones ?? actual.roles;

    final destinos = todas
        .where(
          (n) =>
              n.id != actual.id &&
              !n.ocupada &&
              n.roles.every(rolesOperario.contains),
        )
        .toList();

    if (destinos.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'No hay otra plaza vacante compatible con '
            '${actual.operarioNombre ?? operarioId} en este conjunto.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    int? seleccionado;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Cambiar de plaza a ${actual.operarioNombre ?? operarioId}',
          ),
          content: DropdownButtonFormField<int>(
            initialValue: seleccionado,
            items: destinos
                .map(
                  (n) => DropdownMenuItem(
                    value: n.id,
                    child: Text('${n.etiqueta} (${_etiquetaRoles(n.roles)})'),
                  ),
                )
                .toList(),
            onChanged: (v) => setDialogState(() => seleccionado = v),
            decoration: const InputDecoration(
              labelText: 'Nueva plaza',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: seleccionado == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Mover'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || seleccionado == null) return;
    try {
      await _api.asignarOperarioNecesidad(
        conjuntoNit: widget.conjuntoNit,
        necesidadId: seleccionado!,
        operarioId: operarioId,
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudo cambiar de plaza: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmarEliminar(NecesidadOperario n) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar ${n.etiqueta}'),
        content: const Text(
          '¿Eliminar esta necesidad? Si está ocupada o tiene preventivas '
          'vinculadas, se pedirá confirmación adicional.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _api.eliminarNecesidad(
        conjuntoNit: widget.conjuntoNit,
        necesidadId: n.id,
      );
      _reload();
    } on EliminarNecesidadConfirmationRequired catch (e) {
      if (!mounted) return;
      final reconfirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar eliminación'),
          content: Text(e.mensaje),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Eliminar de todas formas'),
            ),
          ],
        ),
      );
      if (reconfirmar != true) return;
      try {
        await _api.eliminarNecesidad(
          conjuntoNit: widget.conjuntoNit,
          necesidadId: n.id,
          confirmar: true,
        );
        _reload();
      } catch (e2) {
        if (!mounted) return;
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(
            content: Text('No se pudo eliminar: $e2'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudo eliminar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _migrarDesdeOperarios() async {
    try {
      final creadas = await _api.migrarNecesidadesDesdeOperarios(
        widget.conjuntoNit,
      );
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            creadas.isEmpty
                ? 'No había operarios sin plaza asignada.'
                : 'Se crearon ${creadas.length} plaza(s): ${creadas.join(', ')}.',
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudo migrar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Paso 2 de la migración: conecta las preventivas que todavía resuelven
  /// por operarios directos a la plaza que ese mismo operario ya ocupa
  /// (normalmente después de "Crear plazas desde operarios actuales").
  Future<void> _vincularDefiniciones() async {
    try {
      final resultado = await _api.vincularDefinicionesConNecesidades(
        widget.conjuntoNit,
      );
      if (!mounted) return;
      if (resultado.vinculadas.isEmpty && resultado.saltadas.isEmpty) {
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text(
              'No había preventivas por vincular (ya usan plazas, o no tienen operarios directos).',
            ),
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vincular preventivas a las plazas'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (resultado.vinculadas.isNotEmpty) ...[
                  Text(
                    'Vinculadas (${resultado.vinculadas.length}):',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ...resultado.vinculadas.map((d) => Text('• $d')),
                ],
                if (resultado.saltadas.isNotEmpty) ...[
                  if (resultado.vinculadas.isNotEmpty)
                    const SizedBox(height: 12),
                  Text(
                    'Saltadas (${resultado.saltadas.length}) — asigna la plaza '
                    'que falta y vuelve a intentar:',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ...resultado.saltadas.map((d) => Text('• $d')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudieron vincular las preventivas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _mostrarFormulario({NecesidadOperario? existente}) async {
    final etiquetaCtrl = TextEditingController(
      text: existente?.etiqueta ?? '',
    );
    final roles = <String>{...(existente?.roles ?? [_rolesNecesidad[0]])};
    bool horarioEspecial = existente?.horarioEspecial ?? false;
    final horariosPorDia = <String, _DiaHorarioEdit>{
      for (final d in _diasSemanaNecesidad) d: _DiaHorarioEdit(),
    };
    for (final h in existente?.horarios ?? const <HorarioConjunto>[]) {
      final entry = horariosPorDia[h.dia];
      if (entry == null) continue;
      entry.activo = true;
      entry.apertura = _parseHora(h.horaApertura);
      entry.cierre = _parseHora(h.horaCierre);
      entry.descansoInicio = h.descansoInicio != null
          ? _parseHora(h.descansoInicio!)
          : null;
      entry.descansoFin = h.descansoFin != null
          ? _parseHora(h.descansoFin!)
          : null;
    }

    final guardado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existente == null ? 'Agregar necesidad' : 'Editar necesidad'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rol(es): puedes combinar varios (ej. Todero + Salvavidas)',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _rolesNecesidad.map((r) {
                    final selected = roles.contains(r);
                    return FilterChip(
                      label: Text(_etiquetaRol[r] ?? r),
                      selected: selected,
                      onSelected: (v) {
                        if (v) {
                          roles.add(r);
                        } else if (roles.length > 1) {
                          roles.remove(r);
                        } else {
                          return; // al menos un rol debe quedar seleccionado
                        }
                        setDialogState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: etiquetaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Etiqueta (ej. "Todero #1")',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Horario especial'),
                  value: horarioEspecial,
                  onChanged: (v) => setDialogState(() => horarioEspecial = v),
                ),
                if (horarioEspecial)
                  ..._diasSemanaNecesidad.map((dia) {
                    final h = horariosPorDia[dia]!;
                    Future<void> elegir({
                      required TimeOfDay? actual,
                      required TimeOfDay defecto,
                      required void Function(TimeOfDay) aplicar,
                    }) async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: actual ?? defecto,
                      );
                      if (picked != null) setDialogState(() => aplicar(picked));
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: h.activo,
                                onChanged: (v) => setDialogState(
                                  () => h.activo = v ?? false,
                                ),
                              ),
                              Text(dia, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          if (h.activo)
                            Padding(
                              padding: const EdgeInsets.only(left: 28),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => elegir(
                                        actual: h.apertura,
                                        defecto: const TimeOfDay(
                                          hour: 8,
                                          minute: 0,
                                        ),
                                        aplicar: (t) => h.apertura = t,
                                      ),
                                      child: Text(
                                        h.apertura == null
                                            ? 'Entrada'
                                            : _formatHora(h.apertura!),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => elegir(
                                        actual: h.descansoInicio,
                                        defecto: const TimeOfDay(
                                          hour: 12,
                                          minute: 0,
                                        ),
                                        aplicar: (t) => h.descansoInicio = t,
                                      ),
                                      child: Text(
                                        h.descansoInicio == null
                                            ? 'Desc. ini'
                                            : _formatHora(h.descansoInicio!),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => elegir(
                                        actual: h.descansoFin,
                                        defecto: const TimeOfDay(
                                          hour: 13,
                                          minute: 0,
                                        ),
                                        aplicar: (t) => h.descansoFin = t,
                                      ),
                                      child: Text(
                                        h.descansoFin == null
                                            ? 'Desc. fin'
                                            : _formatHora(h.descansoFin!),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => elegir(
                                        actual: h.cierre,
                                        defecto: const TimeOfDay(
                                          hour: 17,
                                          minute: 0,
                                        ),
                                        aplicar: (t) => h.cierre = t,
                                      ),
                                      child: Text(
                                        h.cierre == null
                                            ? 'Salida'
                                            : _formatHora(h.cierre!),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardado != true) return;
    final etiqueta = etiquetaCtrl.text.trim();
    if (etiqueta.isEmpty) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('La etiqueta es obligatoria.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final horarios = horarioEspecial
        ? horariosPorDia.entries
              .where((e) => e.value.activo && e.value.apertura != null && e.value.cierre != null)
              .map(
                (e) => HorarioConjunto(
                  dia: e.key,
                  horaApertura: _formatHora(e.value.apertura!),
                  horaCierre: _formatHora(e.value.cierre!),
                  descansoInicio: e.value.descansoCompleto
                      ? _formatHora(e.value.descansoInicio!)
                      : null,
                  descansoFin: e.value.descansoCompleto
                      ? _formatHora(e.value.descansoFin!)
                      : null,
                ),
              )
              .toList()
        : const <HorarioConjunto>[];

    try {
      if (existente == null) {
        await _api.crearNecesidad(
          conjuntoNit: widget.conjuntoNit,
          roles: roles.toList(),
          etiqueta: etiqueta,
          horarioEspecial: horarioEspecial,
          horarios: horarios,
        );
      } else {
        await _api.editarNecesidad(
          conjuntoNit: widget.conjuntoNit,
          necesidadId: existente.id,
          roles: roles.toList(),
          etiqueta: etiqueta,
          horarioEspecial: horarioEspecial,
          horarios: horarios,
        );
      }
      _reload();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudo guardar la necesidad: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  TimeOfDay? _parseHora(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatHora(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _DiaHorarioEdit {
  bool activo = false;
  TimeOfDay? apertura;
  TimeOfDay? cierre;
  TimeOfDay? descansoInicio;
  TimeOfDay? descansoFin;

  bool get descansoCompleto => descansoInicio != null && descansoFin != null;
}
