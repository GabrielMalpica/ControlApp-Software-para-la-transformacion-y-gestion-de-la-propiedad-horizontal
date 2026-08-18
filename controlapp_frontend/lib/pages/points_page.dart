import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/points_api.dart';
import 'package:flutter_application_1/model/points_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

class PointsPage extends StatefulWidget {
  const PointsPage({
    super.key,
    this.initialConjuntoId,
    this.conjuntos = const <String, String>{},
    this.canConfigure = false,
    this.canAdjust = false,
  });

  final String? initialConjuntoId;
  final Map<String, String> conjuntos;
  final bool canConfigure;
  final bool canAdjust;

  @override
  State<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends State<PointsPage> {
  final _api = PointsApi();
  final _date = DateFormat('dd/MM/yyyy · HH:mm');
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: 'COP ');

  PointsSummary? _summary;
  String? _selectedConjuntoId;
  String? _error;
  bool _loading = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _selectedConjuntoId =
        widget.initialConjuntoId ??
        (widget.conjuntos.isNotEmpty ? widget.conjuntos.keys.first : null);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _api.obtenerResumen(
        conjuntoId: _selectedConjuntoId,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _selectedConjuntoId = summary.conjuntoId;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(error);
        _loading = false;
      });
    }
  }

  Future<void> _redeem(PointsBenefit benefit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar canje'),
        content: Text(
          'Canjearás ${benefit.puntosCosto} puntos por ${benefit.nombre}. Esta operación no se puede deshacer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Canjear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _acting = true);
    try {
      await _api.redimir(
        beneficioId: benefit.id,
        conjuntoId: _summary!.conjuntoId,
      );
      await _load();
      if (!mounted) return;
      AppFeedback.showInfo(
        context,
        title: 'Canje registrado',
        message: 'Tu beneficio ${benefit.nombre} ya está disponible.',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _configure() async {
    final config = _summary!.config;
    final benefits = List<PointsBenefit>.from(config.beneficios);
    final residentController = TextEditingController(
      text: config.montoPorPuntoResidente.toStringAsFixed(0),
    );
    final conjuntoController = TextEditingController(
      text: config.montoPorPuntoConjunto.toStringAsFixed(0),
    );
    final minimumController = TextEditingController(
      text: config.minimoRedencionPuntos.toString(),
    );
    var active = config.activo;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reglas de puntos'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Programa activo'),
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
                TextField(
                  controller: residentController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'COP por punto · residente',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: conjuntoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'COP por punto · conjunto',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minimumController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Mínimo para canjear',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Beneficios (${benefits.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final benefit = await _promptBenefit(context);
                        if (benefit != null) {
                          setDialogState(() => benefits.add(benefit));
                        }
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Agregar'),
                    ),
                  ],
                ),
                ...benefits.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value.nombre),
                    subtitle: Text('${entry.value.puntosCosto} puntos'),
                    trailing: IconButton(
                      tooltip: 'Desactivar beneficio',
                      onPressed: () =>
                          setDialogState(() => benefits.removeAt(entry.key)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final resident = double.tryParse(residentController.text);
      final conjunto = double.tryParse(conjuntoController.text);
      final minimum = int.tryParse(minimumController.text);
      if (resident == null ||
          resident <= 0 ||
          conjunto == null ||
          conjunto <= 0 ||
          minimum == null ||
          minimum < 0) {
        if (mounted) {
          AppFeedback.showError(
            context,
            message: 'Revisa los valores de la configuración.',
          );
        }
      } else {
        setState(() => _acting = true);
        try {
          await _api.guardarConfiguracion(
            PointsConfig(
              conjuntoId: config.conjuntoId,
              activo: active,
              montoPorPuntoResidente: resident,
              montoPorPuntoConjunto: conjunto,
              minimoRedencionPuntos: minimum,
              beneficios: benefits,
            ),
          );
          await _load();
        } catch (error) {
          if (mounted) {
            AppFeedback.showError(context, message: AppError.messageOf(error));
          }
        } finally {
          if (mounted) setState(() => _acting = false);
        }
      }
    }
    residentController.dispose();
    conjuntoController.dispose();
    minimumController.dispose();
  }

  Future<PointsBenefit?> _promptBenefit(BuildContext parentContext) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final costController = TextEditingController();
    final discountController = TextEditingController(text: '0');
    final accepted = await showDialog<bool>(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo beneficio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: costController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Costo en puntos'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: discountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Valor del beneficio en COP',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final description = descriptionController.text.trim();
    final cost = int.tryParse(costController.text);
    final discount = double.tryParse(discountController.text);
    nameController.dispose();
    descriptionController.dispose();
    costController.dispose();
    discountController.dispose();
    if (accepted != true) return null;
    if (name.length < 2 ||
        cost == null ||
        cost <= 0 ||
        discount == null ||
        discount < 0) {
      if (mounted) {
        AppFeedback.showError(
          context,
          message: 'Completa el nombre, costo y valor del beneficio.',
        );
      }
      return null;
    }
    return PointsBenefit(
      id: 0,
      nombre: name,
      descripcion: description,
      puntosCosto: cost,
      valorDescuento: discount,
      disponible: false,
      activo: true,
    );
  }

  Future<void> _adjust() async {
    final userController = TextEditingController();
    final pointsController = TextEditingController();
    final descriptionController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajuste administrativo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: userController,
                decoration: const InputDecoration(
                  labelText: 'Cédula del usuario',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pointsController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Puntos (+ o -)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la corrección',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    final userId = userController.text.trim();
    final points = int.tryParse(pointsController.text);
    final description = descriptionController.text.trim();
    userController.dispose();
    pointsController.dispose();
    descriptionController.dispose();
    if (accepted != true) return;
    if (userId.isEmpty ||
        points == null ||
        points == 0 ||
        description.length < 5) {
      if (mounted) {
        AppFeedback.showError(
          context,
          message: 'Completa el usuario, los puntos y un motivo claro.',
        );
      }
      return;
    }
    setState(() => _acting = true);
    try {
      await _api.ajustar(
        conjuntoId: _summary!.conjuntoId,
        usuarioId: userId,
        puntos: points,
        descripcion: description,
      );
      await _load();
      if (mounted) {
        AppFeedback.showInfo(
          context,
          title: 'Ajuste registrado',
          message: 'El movimiento quedó auditado en el libro de puntos.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.showError(context, message: AppError.messageOf(error));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Puntos y beneficios'),
        actions: <Widget>[
          if (widget.canAdjust && _summary != null)
            IconButton(
              tooltip: 'Ajustar puntos',
              onPressed: _acting ? null : _adjust,
              icon: const Icon(Icons.rule_rounded),
            ),
          if (widget.canConfigure && _summary != null)
            IconButton(
              tooltip: 'Configurar reglas',
              onPressed: _acting ? null : _configure,
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: _loading
          ? const SkeletonList()
          : _error != null
          ? Center(
              child: CommerceClayCard(
                margin: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _buildSummary(_summary!),
    );
  }

  Widget _buildSummary(PointsSummary summary) {
    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (widget.conjuntos.length > 1) ...<Widget>[
                CommerceClayCard(
                  padding: const EdgeInsets.all(14),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedConjuntoId,
                    decoration: const InputDecoration(labelText: 'Conjunto'),
                    items: widget.conjuntos.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedConjuntoId = value);
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x22084D31),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(summary.conjuntoNombre),
                    const SizedBox(height: 8),
                    Text(
                      '${summary.saldo} puntos',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: AppTheme.primaryDark,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      summary.config.activo
                          ? 'Acumulas al entregar pedidos y puedes canjear sin dejar saldo negativo.'
                          : 'El programa de este conjunto aún no está activo.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Beneficios', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (summary.beneficios.isEmpty)
                const CommerceClayCard(
                  child: Text(
                    'Aún no hay beneficios activos para este conjunto.',
                  ),
                )
              else
                ...summary.beneficios.map(
                  (benefit) => CommerceClayCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceSoft,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.redeem_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                benefit.nombre,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (benefit.descripcion.isNotEmpty)
                                Text(benefit.descripcion),
                              Text(
                                benefit.valorDescuento > 0
                                    ? '${benefit.puntosCosto} puntos · ${_money.format(benefit.valorDescuento)}'
                                    : '${benefit.puntosCosto} puntos',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: benefit.disponible && !_acting
                              ? () => _redeem(benefit)
                              : null,
                          child: const Text('Canjear'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text('Historial', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              CommerceClayCard(
                child: summary.movimientos.isEmpty
                    ? const Text('Todavía no tienes movimientos de puntos.')
                    : Column(
                        children: summary.movimientos
                            .map(
                              (movement) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: movement.puntos >= 0
                                      ? const Color(0xFFE4F5EB)
                                      : const Color(0xFFFFE9E5),
                                  child: Icon(
                                    movement.puntos >= 0
                                        ? Icons.add_rounded
                                        : Icons.remove_rounded,
                                    color: movement.puntos >= 0
                                        ? AppTheme.green
                                        : AppTheme.red,
                                  ),
                                ),
                                title: Text(
                                  movement.descripcion.isEmpty
                                      ? movement.tipo
                                      : movement.descripcion,
                                ),
                                subtitle: movement.creadoEn == null
                                    ? null
                                    : Text(
                                        _date.format(
                                          movement.creadoEn!.toLocal(),
                                        ),
                                      ),
                                trailing: Text(
                                  '${movement.puntos > 0 ? '+' : ''}${movement.puntos}',
                                  style: TextStyle(
                                    color: movement.puntos >= 0
                                        ? AppTheme.green
                                        : AppTheme.red,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        if (_acting)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x22000000),
              // Overlay de accion en curso (no de carga de contenido): un
              // spinner comunica "procesando" mejor que un skeleton, que
              // sugeriria que va a aparecer contenido nuevo con esa forma.
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
