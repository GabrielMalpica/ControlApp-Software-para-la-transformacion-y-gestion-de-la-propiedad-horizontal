import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/commerce_api.dart';
import 'package:flutter_application_1/model/commerce_models.dart';
import 'package:flutter_application_1/pages/resident_cart_page.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/resident_cart_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';

enum CommerceCatalogScope { todos, residente, conjunto, servicios }

class CommerceCatalogPage extends StatefulWidget {
  const CommerceCatalogPage({
    super.key,
    this.initialScope = CommerceCatalogScope.todos,
    this.title = 'Catalogo comercial',
    this.enableCart = false,
  });

  final CommerceCatalogScope initialScope;
  final String title;
  final bool enableCart;

  @override
  State<CommerceCatalogPage> createState() => _CommerceCatalogPageState();
}

class _CommerceCatalogPageState extends State<CommerceCatalogPage> {
  final _api = CommerceApi();
  final _searchCtrl = TextEditingController();
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: 'COP ');

  bool _loading = true;
  String? _error;
  CommerceCatalogResponse? _catalog;
  CommerceCatalogScope _scope = CommerceCatalogScope.todos;
  String _categorySlug = '';

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _scopeApiValue {
    switch (_scope) {
      case CommerceCatalogScope.residente:
        return 'residente';
      case CommerceCatalogScope.conjunto:
        return 'conjunto';
      case CommerceCatalogScope.servicios:
        return 'servicios';
      case CommerceCatalogScope.todos:
        return 'todos';
    }
  }

  String _scopeLabel(CommerceCatalogScope scope) {
    switch (scope) {
      case CommerceCatalogScope.todos:
        return 'Todo';
      case CommerceCatalogScope.residente:
        return 'Hogar';
      case CommerceCatalogScope.conjunto:
        return 'Conjunto';
      case CommerceCatalogScope.servicios:
        return 'Servicios';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final catalog = await _api.listarCatalogo(
        target: _scopeApiValue,
        q: _searchCtrl.text,
        category: _categorySlug,
      );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(
          e,
          fallback: 'No se pudo cargar el catalogo comercial.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _openProduct(CommerceProduct item) async {
    try {
      final detail = await _api.obtenerProducto(item.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ProductDetailSheet(
          product: detail,
          money: _money,
          enableCart: widget.enableCart,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _catalog?.categories ?? const <CommerceCategory>[];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.enableCart)
            ListenableBuilder(
              listenable: ResidentCartService.instance,
              builder: (context, _) {
                final count = ResidentCartService.instance.itemCount;
                return IconButton(
                  tooltip: 'Mi carrito',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ResidentCartPage()),
                    );
                  },
                  icon: Badge.count(
                    count: count,
                    isLabelVisible: count > 0,
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catalogo sincronizado desde WooCommerce',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Ya puedes explorar productos fisicos y servicios comerciales desde la app.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, categoria o SKU',
                    suffixIcon: IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: CommerceCatalogScope.values
                      .map(
                        (scope) => ChoiceChip(
                          label: Text(_scopeLabel(scope)),
                          selected: _scope == scope,
                          onSelected: (selected) {
                            if (!selected) return;
                            setState(() => _scope = scope);
                            _load();
                          },
                        ),
                      )
                      .toList(),
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: const Text('Todas las categorias'),
                            selected: _categorySlug.isEmpty,
                            onSelected: (_) {
                              setState(() => _categorySlug = '');
                              _load();
                            },
                          ),
                        ),
                        ...categories.map(
                          (category) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(category.name),
                              selected: _categorySlug == category.slug,
                              onSelected: (_) {
                                setState(() => _categorySlug = category.slug);
                                _load();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _load,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _catalog == null || _catalog!.items.isEmpty
                        ? const Center(
                            child: Text('No hay productos disponibles con esos filtros.'),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                _CatalogSummaryCard(
                                  total: _catalog!.pagination.total,
                                  scopeLabel: _scopeLabel(_scope),
                                ),
                                const SizedBox(height: 14),
                                ..._catalog!.items.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _ProductCard(
                                      item: item,
                                      money: _money,
                                      onTap: () => _openProduct(item),
                                      enableCart: widget.enableCart,
                                      onAddToCart: widget.enableCart
                                          ? () {
                                              ResidentCartService.instance.addProduct(item);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('${item.name} agregado al carrito.'),
                                                ),
                                              );
                                            }
                                          : null,
                                    ),
                                  ),
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

class _CatalogSummaryCard extends StatelessWidget {
  const _CatalogSummaryCard({required this.total, required this.scopeLabel});

  final int total;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.storefront_outlined, color: AppTheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vista: $scopeLabel', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('$total productos disponibles', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.images.isNotEmpty ? item.images.first.src : '';
    final subtitle = item.shortDescription.isNotEmpty
        ? item.shortDescription
        : item.categories.map((e) => e.name).join(', ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                child: imageUrl.isEmpty
                    ? const Icon(Icons.inventory_2_outlined, color: AppTheme.primary)
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: kIsWeb
                            ? WebHtmlElementStrategy.prefer
                            : WebHtmlElementStrategy.never,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppTheme.textMuted,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (item.audience.paraResidente)
                          const _Badge(label: 'Hogar', color: AppTheme.primaryDark),
                        if (item.audience.paraConjunto)
                          const _Badge(label: 'Conjunto', color: AppTheme.secondary),
                        if (item.audience.esServicio)
                          const _Badge(label: 'Servicio', color: AppTheme.accent),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            money.format(item.price.current),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Text(
                          item.stockStatus.toUpperCase(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (enableCart) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: onAddToCart,
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                          label: const Text('Agregar'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ProductDetailSheet extends StatelessWidget {
  const _ProductDetailSheet({
    required this.product,
    required this.money,
    required this.enableCart,
  });

  final CommerceProduct product;
  final NumberFormat money;
  final bool enableCart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.94,
          expand: false,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 260,
                child: product.images.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.storefront_outlined,
                            size: 72,
                            color: AppTheme.primary,
                          ),
                        ),
                      )
                    : _ProductGallery(images: product.images),
              ),
              const SizedBox(height: 18),
              Text(product.name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (product.audience.paraResidente)
                    const _Badge(label: 'Hogar', color: AppTheme.primaryDark),
                  if (product.audience.paraConjunto)
                    const _Badge(label: 'Conjunto', color: AppTheme.secondary),
                  if (product.audience.esServicio)
                    const _Badge(label: 'Servicio', color: AppTheme.accent),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                money.format(product.price.current),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.primary,
                    ),
              ),
              const SizedBox(height: 16),
              if (product.shortDescription.isNotEmpty)
                _DetailSection(title: 'Resumen', content: product.shortDescription),
              if (product.description.isNotEmpty)
                _DetailSection(title: 'Descripcion', content: product.description),
              _DetailSection(
                title: 'Datos comerciales',
                content:
                    'SKU: ${product.sku.isEmpty ? 'No disponible' : product.sku}\nStock: ${product.stockStatus}\nTipo: ${product.type}',
              ),
              if (product.categories.isNotEmpty)
                _DetailSection(
                  title: 'Categorias',
                  content: product.categories.map((e) => e.name).join(', '),
                ),
              if (enableCart) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    ResidentCartService.instance.addProduct(product);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${product.name} agregado al carrito.')),
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: const Text('Agregar al carrito'),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'En la siguiente fase este catalogo se conectara con carrito, checkout y pedidos.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
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
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (_, index) {
                final image = widget.images[index];
                return Image.network(
                  image.src,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: kIsWeb
                      ? WebHtmlElementStrategy.prefer
                      : WebHtmlElementStrategy.never,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: AppTheme.textMuted,
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final image = widget.images[index];
                final selected = index == _index;
                return GestureDetector(
                  onTap: () {
                    _controller.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Container(
                    width: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppTheme.primary : Colors.black12,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.network(
                      image.thumbnail.isNotEmpty ? image.thumbnail : image.src,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: kIsWeb
                          ? WebHtmlElementStrategy.prefer
                          : WebHtmlElementStrategy.never,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: AppTheme.surfaceSoft,
                        child: Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(content, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
