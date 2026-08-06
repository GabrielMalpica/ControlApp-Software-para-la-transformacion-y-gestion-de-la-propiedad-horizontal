import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/commerce_api.dart';
import 'package:flutter_application_1/model/commerce_models.dart';
import 'package:flutter_application_1/pages/conjunto_cart_page.dart';
import 'package:flutter_application_1/pages/resident_cart_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/conjunto_cart_service.dart';
import 'package:flutter_application_1/service/resident_cart_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:intl/intl.dart';

enum CommerceCatalogScope { todos, residente, conjunto, servicios }

class CommerceCatalogPage extends StatefulWidget {
  const CommerceCatalogPage({
    super.key,
    this.initialScope = CommerceCatalogScope.todos,
    this.title = 'Tienda',
    this.enableCart = false,
    this.initialConjuntoId,
    this.initialConjuntoNombre,
  });

  final CommerceCatalogScope initialScope;
  final String title;
  final bool enableCart;
  final String? initialConjuntoId;
  final String? initialConjuntoNombre;

  @override
  State<CommerceCatalogPage> createState() => _CommerceCatalogPageState();
}

class _CommerceCatalogPageState extends State<CommerceCatalogPage> {
  final _api = CommerceApi();
  final _searchCtrl = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );

  bool _loading = true;
  String? _error;
  CommerceCatalogResponse? _catalog;
  CommerceCatalogScope _scope = CommerceCatalogScope.todos;
  String _categorySlug = '';
  Timer? _searchDebounce;
  int _loadSequence = 0;

  bool get _usesConjuntoCart =>
      widget.initialScope == CommerceCatalogScope.conjunto;

  Listenable get _cartListenable => _usesConjuntoCart
      ? ConjuntoCartService.instance
      : ResidentCartService.instance;

  int get _cartCount => _usesConjuntoCart
      ? ConjuntoCartService.instance.unitsCount
      : ResidentCartService.instance.items.fold(
          0,
          (sum, item) => sum + item.quantity,
        );

  double get _cartTotal => _usesConjuntoCart
      ? ConjuntoCartService.instance.total
      : ResidentCartService.instance.total;

  List<CommerceCatalogScope> get _availableScopes {
    if (_usesConjuntoCart) {
      return const <CommerceCatalogScope>[CommerceCatalogScope.conjunto];
    }
    if (widget.initialScope == CommerceCatalogScope.residente &&
        widget.enableCart) {
      return const <CommerceCatalogScope>[
        CommerceCatalogScope.residente,
        CommerceCatalogScope.servicios,
      ];
    }
    return CommerceCatalogScope.values;
  }

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _scopeApiValue => switch (_scope) {
    CommerceCatalogScope.residente => 'residente',
    CommerceCatalogScope.conjunto => 'conjunto',
    CommerceCatalogScope.servicios => 'servicios',
    CommerceCatalogScope.todos => 'todos',
  };

  String _scopeLabel(CommerceCatalogScope scope) => switch (scope) {
    CommerceCatalogScope.todos => 'Todo',
    CommerceCatalogScope.residente => 'Productos',
    CommerceCatalogScope.conjunto => 'Insumos',
    CommerceCatalogScope.servicios => 'Servicios',
  };

  IconData _scopeIcon(CommerceCatalogScope scope) => switch (scope) {
    CommerceCatalogScope.todos => Icons.grid_view_rounded,
    CommerceCatalogScope.residente => Icons.shopping_bag_rounded,
    CommerceCatalogScope.conjunto => Icons.inventory_2_rounded,
    CommerceCatalogScope.servicios => Icons.home_repair_service_rounded,
  };

  Future<void> _load() async {
    if (!mounted) return;
    final sequence = ++_loadSequence;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final catalog = await _api.listarCatalogo(
        target: _scopeApiValue,
        q: _searchCtrl.text.trim(),
        category: _categorySlug,
      );
      if (!mounted || sequence != _loadSequence) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || sequence != _loadSequence) return;
      setState(() {
        _error = AppError.messageOf(
          error,
          fallback: 'No pudimos cargar la tienda en este momento.',
        );
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), _load);
  }

  Future<void> _openProduct(CommerceProduct item) async {
    try {
      final detail = await _api.obtenerProducto(item.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _ProductDetailSheet(
          product: detail,
          money: _money,
          enableCart: widget.enableCart,
          useConjuntoCart: _usesConjuntoCart,
          onAdd: (quantity, service) {
            Navigator.pop(sheetContext);
            _addProduct(detail, quantity: quantity, service: service);
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(error));
    }
  }

  void _openCart() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _usesConjuntoCart
            ? ConjuntoCartPage(
                initialConjuntoId: widget.initialConjuntoId,
                initialConjuntoNombre: widget.initialConjuntoNombre,
              )
            : const ResidentCartPage(),
      ),
    );
  }

  void _addProduct(
    CommerceProduct product, {
    int quantity = 1,
    CommerceServiceSelection? service,
  }) {
    if (!product.purchasable || product.stockStatus == 'outofstock') {
      AppFeedback.showError(
        context,
        message: 'Este artículo no está disponible por el momento.',
      );
      return;
    }
    if (_usesConjuntoCart) {
      if (!product.audience.paraConjunto) {
        AppFeedback.showError(
          context,
          message:
              'Este artículo no está habilitado para compras del conjunto.',
        );
        return;
      }
      ConjuntoCartService.instance.addProduct(
        product,
        quantity: quantity,
        service: service,
      );
    } else {
      ResidentCartService.instance.addProduct(
        product,
        quantity: quantity,
        service: service,
      );
    }

    AppFeedback.showInfo(
      context,
      title: 'Agregado al carrito',
      message: '$quantity × ${product.name}',
    );
  }

  void _selectScope(CommerceCatalogScope scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _categorySlug = '';
    });
    _load();
  }

  void _selectCategory(String slug) {
    if (_categorySlug == slug) return;
    setState(() => _categorySlug = slug);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final categories = catalog?.categories ?? const <CommerceCategory>[];

    return ListenableBuilder(
      listenable: _cartListenable,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: CommerceClayTokens.canvas,
          appBar: AppBar(
            backgroundColor: CommerceClayTokens.canvas,
            foregroundColor: CommerceClayTokens.ink,
            surfaceTintColor: Colors.transparent,
            title: Text(
              widget.title,
              style: const TextStyle(
                color: CommerceClayTokens.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            actions: <Widget>[
              if (widget.enableCart)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton.filled(
                    tooltip: _usesConjuntoCart
                        ? 'Carrito del conjunto'
                        : 'Mi carrito',
                    style: IconButton.styleFrom(
                      backgroundColor: CommerceClayTokens.surfaceStrong,
                      foregroundColor: AppTheme.primary,
                    ),
                    onPressed: _openCart,
                    icon: Badge.count(
                      count: _cartCount,
                      isLabelVisible: _cartCount > 0,
                      backgroundColor: CommerceClayTokens.orange,
                      child: const Icon(Icons.shopping_bag_outlined),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: widget.enableCart && _cartCount > 0
              ? CommerceCheckoutBar(
                  caption:
                      '$_cartCount ${_cartCount == 1 ? 'artículo' : 'artículos'}',
                  total: _money.format(_cartTotal),
                  actionLabel: 'Ver carrito',
                  icon: Icons.shopping_bag_rounded,
                  onPressed: _openCart,
                )
              : null,
          body: CommerceClayBackground(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1100
                    ? 5
                    : width >= 780
                    ? 4
                    : width >= 520
                    ? 3
                    : 2;
                final horizontalPadding = width >= 900 ? 28.0 : 14.0;
                return RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          8,
                          horizontalPadding,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _CatalogHero(
                            controller: _searchCtrl,
                            useConjunto: _usesConjuntoCart,
                            conjuntoNombre: widget.initialConjuntoNombre,
                            onChanged: _onSearchChanged,
                            onSubmitted: (_) => _load(),
                            onClear: () {
                              _searchCtrl.clear();
                              _load();
                            },
                          ),
                        ),
                      ),
                      if (_availableScopes.length > 1)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 78,
                            child: ListView.separated(
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                                vertical: 14,
                              ),
                              scrollDirection: Axis.horizontal,
                              itemCount: _availableScopes.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 9),
                              itemBuilder: (_, index) {
                                final scope = _availableScopes[index];
                                return _ScopeChip(
                                  label: _scopeLabel(scope),
                                  icon: _scopeIcon(scope),
                                  selected: _scope == scope,
                                  onTap: () => _selectScope(scope),
                                );
                              },
                            ),
                          ),
                        )
                      else
                        const SliverToBoxAdapter(child: SizedBox(height: 14)),
                      if (categories.isNotEmpty)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 58,
                            child: ListView.separated(
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                              ),
                              scrollDirection: Axis.horizontal,
                              itemCount: categories.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, index) {
                                if (index == 0) {
                                  return _CategoryChip(
                                    label: 'Todas',
                                    icon: Icons.apps_rounded,
                                    selected: _categorySlug.isEmpty,
                                    onTap: () => _selectCategory(''),
                                  );
                                }
                                final category = categories[index - 1];
                                return _CategoryChip(
                                  label: category.name,
                                  icon: _categoryIcon(category),
                                  selected: _categorySlug == category.slug,
                                  onTap: () => _selectCategory(category.slug),
                                );
                              },
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          categories.isEmpty ? 2 : 16,
                          horizontalPadding,
                          12,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: CommerceSectionHeader(
                            title: _sectionTitle,
                            subtitle: _loading
                                ? 'Buscando lo mejor para ti…'
                                : '${catalog?.pagination.total ?? 0} opciones disponibles',
                          ),
                        ),
                      ),
                      if (_loading)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            0,
                            horizontalPadding,
                            32,
                          ),
                          sliver: _CatalogLoading(columns: columns),
                        )
                      else if (_error != null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: CommerceStateView(
                            icon: Icons.wifi_off_rounded,
                            title: 'La tienda no cargó',
                            message: _error!,
                            actionLabel: 'Intentar de nuevo',
                            onAction: _load,
                          ),
                        )
                      else if (catalog == null || catalog.items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: CommerceStateView(
                            icon: Icons.search_off_rounded,
                            title: 'No encontramos resultados',
                            message:
                                'Prueba otra búsqueda o cambia la categoría para seguir explorando.',
                            actionLabel: 'Limpiar filtros',
                            onAction: () {
                              _searchCtrl.clear();
                              setState(() => _categorySlug = '');
                              _load();
                            },
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            0,
                            horizontalPadding,
                            36,
                          ),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 14,
                                  mainAxisExtent: columns == 2 ? 310 : 325,
                                ),
                            delegate: SliverChildBuilderDelegate((_, index) {
                              final item = catalog.items[index];
                              return _ProductCard(
                                item: item,
                                money: _money,
                                onTap: () => _openProduct(item),
                                enableCart: widget.enableCart,
                                onAddToCart: widget.enableCart
                                    ? item.service?.enabled == true
                                          ? () => _openProduct(item)
                                          : () => _addProduct(item)
                                    : null,
                              );
                            }, childCount: catalog.items.length),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String get _sectionTitle {
    if (_searchCtrl.text.trim().isNotEmpty) return 'Resultados para ti';
    return switch (_scope) {
      CommerceCatalogScope.servicios => 'Servicios destacados',
      CommerceCatalogScope.conjunto => 'Insumos para tu operación',
      _ => 'Recomendados para ti',
    };
  }

  IconData _categoryIcon(CommerceCategory category) {
    final value = '${category.slug} ${category.name}'.toLowerCase();
    if (value.contains('limpieza')) return Icons.cleaning_services_rounded;
    if (value.contains('jardin')) return Icons.yard_rounded;
    if (value.contains('piscina')) return Icons.pool_rounded;
    if (value.contains('ferreter')) return Icons.handyman_rounded;
    if (value.contains('servicio')) return Icons.home_repair_service_rounded;
    if (value.contains('hogar')) return Icons.home_rounded;
    return Icons.category_rounded;
  }
}

class _CatalogHero extends StatelessWidget {
  const _CatalogHero({
    required this.controller,
    required this.useConjunto,
    required this.conjuntoNombre,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool useConjunto;
  final String? conjuntoNombre;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final destination = conjuntoNombre?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: CommerceClayTokens.heroGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x35084D31),
            blurRadius: 28,
            spreadRadius: -7,
            offset: Offset(0, 17),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          const Positioned(right: -48, top: -60, child: _HeroCircle(size: 190)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.bolt_rounded,
                          size: 15,
                          color: CommerceClayTokens.lime,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          useConjunto ? 'COMPRA OPERATIVA' : 'COMPRA FÁCIL',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                useConjunto
                    ? 'Abastece tu conjunto\nsin complicaciones'
                    : '¿Qué necesitas hoy?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.04,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                useConjunto
                    ? destination?.isNotEmpty == true
                          ? 'Entrega para $destination'
                          : 'Insumos listos para tu operación'
                    : 'Productos y servicios en un solo lugar.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Buscar productos o servicios',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.primary,
                  ),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: onClear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: CommerceClayTokens.lime,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroCircle extends StatelessWidget {
  const _HeroCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: CommerceClayTokens.lime.withValues(alpha: 0.13),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : CommerceClayTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x15193C2C),
            blurRadius: 14,
            offset: Offset(4, 7),
          ),
          BoxShadow(
            color: Color(0xCCFFFFFF),
            blurRadius: 8,
            offset: Offset(-3, -4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 19,
                  color: selected ? Colors.white : AppTheme.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : CommerceClayTokens.ink,
                    fontWeight: FontWeight.w800,
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? AppTheme.primaryDark : CommerceClayTokens.muted,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? AppTheme.primaryDark : CommerceClayTokens.ink,
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: CommerceClayTokens.surfaceStrong,
      side: BorderSide(
        color: selected ? AppTheme.primary : Colors.white,
        width: selected ? 1.4 : 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.money,
    required this.onTap,
    required this.enableCart,
    required this.onAddToCart,
  });

  final CommerceProduct item;
  final NumberFormat money;
  final VoidCallback onTap;
  final bool enableCart;
  final VoidCallback? onAddToCart;

  bool get _available =>
      item.purchasable && item.stockStatus.toLowerCase() != 'outofstock';

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.images.isNotEmpty ? item.images.first.src : '';
    final category = item.categories.isEmpty
        ? item.audience.esServicio
              ? 'Servicio'
              : 'Producto'
        : item.categories.first.name;
    return CommerceClayCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CommerceNetworkImage(url: imageUrl),
                Positioned(
                  left: 9,
                  top: 9,
                  child: _ProductTypeBadge(
                    label: item.onSale
                        ? 'OFERTA'
                        : item.audience.esServicio
                        ? 'SERVICIO'
                        : category.toUpperCase(),
                    color: item.onSale
                        ? CommerceClayTokens.orange
                        : item.audience.esServicio
                        ? AppTheme.secondary
                        : AppTheme.primary,
                  ),
                ),
                if (item.images.length > 1)
                  Positioned(
                    right: 9,
                    top: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.photo_library_rounded, size: 13),
                          const SizedBox(width: 3),
                          Text(
                            '${item.images.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.14,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      Icon(
                        item.audience.esServicio
                            ? Icons.schedule_rounded
                            : Icons.delivery_dining_rounded,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _available
                              ? item.audience.esServicio
                                    ? 'Agenda disponible'
                                    : 'Disponible'
                              : 'Agotado',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _available
                                    ? AppTheme.primary
                                    : AppTheme.red,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (item.onSale && item.price.regular > item.price.current)
                    Text(
                      money.format(item.price.regular),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          money.format(item.price.current),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: CommerceClayTokens.ink,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox.square(
                        dimension: 40,
                        child: IconButton.filled(
                          tooltip: enableCart ? 'Agregar' : 'Ver detalle',
                          onPressed: enableCart
                              ? _available
                                    ? onAddToCart
                                    : null
                              : onTap,
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: CommerceClayTokens.mint,
                          ),
                          icon: Icon(
                            enableCart
                                ? Icons.add_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTypeBadge extends StatelessWidget {
  const _ProductTypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x24000000), blurRadius: 8),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.45,
        ),
      ),
    );
  }
}

class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        mainAxisExtent: columns == 2 ? 310 : 325,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, __) => CommerceClayCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              const Expanded(
                flex: 5,
                child: ColoredBox(color: CommerceClayTokens.mint),
              ),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SkeletonLine(width: double.infinity),
                      const SizedBox(height: 8),
                      const _SkeletonLine(width: 86),
                      const Spacer(),
                      const _SkeletonLine(width: 105, height: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        childCount: columns * 2,
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, this.height = 12});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFDCE6DE),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ProductDetailSheet extends StatefulWidget {
  const _ProductDetailSheet({
    required this.product,
    required this.money,
    required this.enableCart,
    required this.useConjuntoCart,
    required this.onAdd,
  });

  final CommerceProduct product;
  final NumberFormat money;
  final bool enableCart;
  final bool useConjuntoCart;
  final void Function(int quantity, CommerceServiceSelection? service) onAdd;

  @override
  State<_ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<_ProductDetailSheet> {
  int _quantity = 1;
  final CommerceApi _api = CommerceApi();
  final Map<String, Set<int>> _selectedAddons = <String, Set<int>>{};
  DateTime? _serviceDate;
  String? _slotId;
  String _payChoice = 'deposit';
  CommerceServiceAvailability? _availability;
  bool _checkingAvailability = false;
  String? _serviceError;

  CommerceServiceConfig? get _service =>
      widget.product.service?.enabled == true ? widget.product.service : null;

  @override
  void initState() {
    super.initState();
    final service = _service;
    if (service != null) {
      _slotId = service.effectiveSlots.first.id;
      for (final addon in service.addons) {
        _selectedAddons[addon.id] = <int>{};
      }
    }
  }

  bool get _canAdd {
    final product = widget.product;
    if (!widget.enableCart || !product.purchasable) return false;
    if (product.stockStatus.toLowerCase() == 'outofstock') return false;
    if (widget.useConjuntoCart && !product.audience.paraConjunto) {
      return false;
    }
    return true;
  }

  double get _serviceAddonsTotal {
    final service = _service;
    if (service == null) return 0;
    var total = 0.0;
    for (final group in service.addons) {
      final selected = _selectedAddons[group.id] ?? const <int>{};
      for (final option in group.options) {
        if (selected.contains(option.id)) total += option.price;
      }
    }
    return total;
  }

  double get _configuredUnitPrice =>
      widget.product.price.current + _serviceAddonsTotal;

  CommerceServiceSelection? _buildServiceSelection({bool showErrors = false}) {
    final service = _service;
    if (service == null) return null;
    if (_serviceDate == null || _slotId == null) {
      if (showErrors) {
        _serviceError = 'Selecciona la fecha y el turno del servicio.';
      }
      return null;
    }

    final selectedGroups = <CommerceSelectedAddon>[];
    final requestAddons = <String, List<int>>{};
    for (final group in service.addons) {
      final ids = (_selectedAddons[group.id] ?? const <int>{}).toList()..sort();
      if (group.required && ids.isEmpty) {
        if (showErrors) {
          _serviceError = 'Selecciona una opción en ${group.label}.';
        }
        return null;
      }
      final options = group.options
          .where((option) => ids.contains(option.id))
          .toList(growable: false);
      requestAddons[group.id] = ids;
      if (options.isNotEmpty) {
        selectedGroups.add(
          CommerceSelectedAddon(
            groupId: group.id,
            groupLabel: group.label,
            options: options,
          ),
        );
      }
    }
    final slot = service.effectiveSlots.firstWhere(
      (item) => item.id == _slotId,
    );
    return CommerceServiceSelection(
      date: DateFormat('yyyy-MM-dd').format(_serviceDate!),
      slot: slot.id,
      slotLabel: slot.label,
      payChoice: _payChoice,
      depositPct: service.depositPct,
      addons: requestAddons,
      selectedAddons: selectedGroups,
    );
  }

  DateTime _firstSelectableDate(CommerceServiceConfig service) {
    final now = DateTime.now();
    var date = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: service.minDays));
    for (
      var i = 0;
      i < 14 && !service.daysAllowed.contains(date.weekday);
      i++
    ) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  Future<void> _pickServiceDate() async {
    final service = _service;
    if (service == null) return;
    final firstDate = _firstSelectableDate(service);
    final selected = await showDatePicker(
      context: context,
      initialDate: _serviceDate ?? firstDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
      selectableDayPredicate: (date) =>
          service.daysAllowed.contains(date.weekday),
      helpText: 'Fecha del servicio',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _serviceDate = selected;
      _availability = null;
      _serviceError = null;
    });
    await _checkAvailability(showFeedback: false);
  }

  Future<bool> _checkAvailability({required bool showFeedback}) async {
    final selection = _buildServiceSelection(showErrors: showFeedback);
    if (selection == null) {
      if (showFeedback && mounted) setState(() {});
      return false;
    }
    setState(() {
      _checkingAvailability = true;
      _serviceError = null;
    });
    try {
      final availability = await _api.obtenerDisponibilidad(
        productId: widget.product.id,
        date: selection.date,
        slot: selection.slot,
      );
      if (!mounted) return false;
      setState(() => _availability = availability);
      if (!availability.available || availability.remaining < _quantity) {
        setState(() {
          _serviceError =
              'Este turno está lleno o no tiene cupos para la cantidad seleccionada.';
        });
        return false;
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _serviceError = AppError.messageOf(
          error,
          fallback: 'No se pudo confirmar la disponibilidad.',
        );
      });
      return false;
    } finally {
      if (mounted) setState(() => _checkingAvailability = false);
    }
  }

  Future<void> _addConfiguredProduct() async {
    if (_service == null) {
      widget.onAdd(_quantity, null);
      return;
    }
    final selection = _buildServiceSelection(showErrors: true);
    if (selection == null) {
      setState(() {});
      return;
    }
    if (!await _checkAvailability(showFeedback: true) || !mounted) return;
    widget.onAdd(_quantity, selection);
  }

  Widget _buildServiceConfiguration() {
    final service = _service!;
    final selection = _buildServiceSelection();
    final total = _configuredUnitPrice * _quantity;
    final payNow =
        selection?.payNowFor(total) ??
        roundUpCommerceService(total * service.depositPct / 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 22),
        const CommerceSectionHeader(
          title: 'Configura tu servicio',
          subtitle: 'Adicionales, fecha, turno y forma de pago',
        ),
        const SizedBox(height: 10),
        ...service.addons.map(
          (group) => CommerceClayCard(
            margin: const EdgeInsets.only(bottom: 12),
            depth: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${group.label}${group.required ? ' · Obligatorio' : ''}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                if (group.isCheckbox)
                  ...group.options.map((option) {
                    final selected =
                        _selectedAddons[group.id]?.contains(option.id) == true;
                    final title = option.price > 0
                        ? '${option.label} (+${widget.money.format(option.price)})'
                        : option.label;
                    return CheckboxListTile(
                      value: selected,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(title),
                      onChanged: (checked) => setState(() {
                        final values = _selectedAddons[group.id]!;
                        checked == true
                            ? values.add(option.id)
                            : values.remove(option.id);
                        _serviceError = null;
                      }),
                    );
                  })
                else
                  RadioGroup<int>(
                    groupValue: (_selectedAddons[group.id]?.isEmpty ?? true)
                        ? null
                        : _selectedAddons[group.id]!.first,
                    onChanged: (value) => setState(() {
                      _selectedAddons[group.id] = <int>{
                        if (value != null) value,
                      };
                      _serviceError = null;
                    }),
                    child: Column(
                      children: group.options
                          .map(
                            (option) => RadioListTile<int>(
                              value: option.id,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                option.price > 0
                                    ? '${option.label} (+${widget.money.format(option.price)})'
                                    : option.label,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        CommerceClayCard(
          margin: const EdgeInsets.only(bottom: 12),
          depth: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Fecha del servicio'),
                subtitle: Text(
                  _serviceDate == null
                      ? 'Selecciona una fecha disponible'
                      : DateFormat('dd/MM/yyyy').format(_serviceDate!),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickServiceDate,
              ),
              const Divider(),
              Text('Turno', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: service.effectiveSlots
                    .map(
                      (slot) => ChoiceChip(
                        selected: _slotId == slot.id,
                        label: Text('${slot.label} · ${slot.capacity} cupos'),
                        onSelected: (_) {
                          setState(() {
                            _slotId = slot.id;
                            _availability = null;
                            _serviceError = null;
                          });
                          if (_serviceDate != null) {
                            _checkAvailability(showFeedback: false);
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
              if (_checkingAvailability) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ] else if (_availability != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _availability!.available
                      ? '${_availability!.remaining} cupo(s) disponible(s)'
                      : 'Turno sin cupos',
                  style: TextStyle(
                    color: _availability!.available
                        ? AppTheme.primary
                        : AppTheme.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
        CommerceClayCard(
          margin: const EdgeInsets.only(bottom: 12),
          depth: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Pago', style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<String>(
                groupValue: _payChoice,
                onChanged: (value) => setState(() => _payChoice = value!),
                child: Column(
                  children: <Widget>[
                    RadioListTile<String>(
                      value: 'deposit',
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Anticipo ${service.depositPct.toStringAsFixed(0)}%',
                      ),
                    ),
                    if (service.allowFull)
                      const RadioListTile<String>(
                        value: 'full',
                        contentPadding: EdgeInsets.zero,
                        title: Text('Pagar 100%'),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Text('Subtotal con adicionales: ${widget.money.format(total)}'),
              const SizedBox(height: 4),
              Text(
                'Pagar ahora: ${widget.money.format(payNow)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        if (_serviceError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _serviceError!,
              style: const TextStyle(
                color: AppTheme.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final description = _plainText(
      product.description.isNotEmpty
          ? product.description
          : product.shortDescription,
    );
    final configuredTotal = _configuredUnitPrice * _quantity;
    final serviceSelection = _buildServiceSelection();
    final payNow = serviceSelection?.payNowFor(configuredTotal);
    final total = widget.money.format(configuredTotal);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      decoration: const BoxDecoration(
        color: CommerceClayTokens.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: _canAdd
            ? CommerceCheckoutBar(
                caption: payNow == null
                    ? '$_quantity ${_quantity == 1 ? 'unidad' : 'unidades'}'
                    : 'Pagar ahora ${widget.money.format(payNow)}',
                total: total,
                actionLabel: 'Agregar',
                icon: Icons.shopping_bag_rounded,
                loading: _checkingAvailability,
                onPressed: _addConfiguredProduct,
              )
            : null,
        body: CommerceClayBackground(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: <Widget>[
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CommerceClayTokens.muted.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 300,
                child: product.images.isEmpty
                    ? const CommerceClayCard(
                        child: Center(
                          child: CommerceClayIcon(
                            icon: Icons.storefront_outlined,
                            size: 82,
                            iconSize: 42,
                          ),
                        ),
                      )
                    : _ProductGallery(images: product.images),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (product.categories.isNotEmpty)
                          Text(
                            product.categories.first.name.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.9,
                                ),
                          ),
                        const SizedBox(height: 5),
                        Text(
                          product.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (product.onSale &&
                            product.price.regular > product.price.current)
                          Text(
                            widget.money.format(product.price.regular),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: CommerceClayTokens.muted,
                                ),
                          ),
                        Text(
                          widget.money.format(_configuredUnitPrice),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppTheme.primaryDark,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (_canAdd)
                    CommerceQuantityStepper(
                      quantity: _quantity,
                      onDecrease: _quantity > 1
                          ? () => setState(() {
                              _quantity--;
                              _availability = null;
                            })
                          : null,
                      onIncrease: () => setState(() {
                        _quantity++;
                        _availability = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _AvailabilityCard(product: product),
              if (_service != null) _buildServiceConfiguration(),
              if (description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                const CommerceSectionHeader(title: 'Acerca de esta opción'),
                const SizedBox(height: 9),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: CommerceClayTokens.muted,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              CommerceClayCard(
                depth: 0,
                color: CommerceClayTokens.mint,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (product.audience.paraResidente)
                      const _InfoPill(
                        icon: Icons.home_rounded,
                        label: 'Para el hogar',
                      ),
                    if (product.audience.paraConjunto)
                      const _InfoPill(
                        icon: Icons.apartment_rounded,
                        label: 'Para conjuntos',
                      ),
                    if (product.audience.esServicio)
                      const _InfoPill(
                        icon: Icons.home_repair_service_rounded,
                        label: 'Servicio',
                      ),
                    if (product.sku.isNotEmpty)
                      _InfoPill(
                        icon: Icons.qr_code_rounded,
                        label: 'SKU ${product.sku}',
                      ),
                  ],
                ),
              ),
              if (widget.enableCart && !_canAdd) ...<Widget>[
                const SizedBox(height: 16),
                CommerceStateView(
                  icon: Icons.info_outline_rounded,
                  title: 'No disponible para este carrito',
                  message: 'Este artículo no se puede comprar en este momento.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.product});

  final CommerceProduct product;

  @override
  Widget build(BuildContext context) {
    final available =
        product.purchasable &&
        product.stockStatus.toLowerCase() != 'outofstock';
    return CommerceClayCard(
      depth: 0,
      color: available
          ? CommerceClayTokens.orangeSoft
          : AppTheme.red.withValues(alpha: 0.1),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Icon(
            available
                ? product.audience.esServicio
                      ? Icons.event_available_rounded
                      : Icons.delivery_dining_rounded
                : Icons.inventory_2_outlined,
            color: available ? CommerceClayTokens.orange : AppTheme.red,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              available
                  ? product.audience.esServicio
                        ? 'Disponible para solicitar y coordinar'
                        : 'Disponible para agregar al carrito'
                  : 'Sin disponibilidad en este momento',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ProductGallery extends StatefulWidget {
  const _ProductGallery({required this.images});

  final List<CommerceImage> images;

  @override
  State<_ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<_ProductGallery> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommerceClayCard(
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (_, index) => CommerceNetworkImage(
              url: widget.images[index].src,
              fit: BoxFit.contain,
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(
                  widget.images.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == _index ? 22 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index == _index
                          ? AppTheme.primary
                          : Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _plainText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
