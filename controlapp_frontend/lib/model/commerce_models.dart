class CommerceCategory {
  final int id;
  final String name;
  final String slug;

  const CommerceCategory({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory CommerceCategory.fromJson(Map<String, dynamic> json) {
    return CommerceCategory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
    );
  }
}

class CommercePrice {
  final String currencyCode;
  final String currencySymbol;
  final double current;
  final double regular;
  final double sale;

  const CommercePrice({
    required this.currencyCode,
    required this.currencySymbol,
    required this.current,
    required this.regular,
    required this.sale,
  });

  factory CommercePrice.fromJson(Map<String, dynamic> json) {
    return CommercePrice(
      currencyCode: json['currencyCode']?.toString() ?? 'COP',
      currencySymbol: json['currencySymbol']?.toString() ?? '\$',
      current: (json['current'] as num?)?.toDouble() ?? 0,
      regular: (json['regular'] as num?)?.toDouble() ?? 0,
      sale: (json['sale'] as num?)?.toDouble() ?? 0,
    );
  }
}

double roundUpCommerceService(double amount, {int multiple = 1000}) {
  final safeMultiple = multiple < 1 ? 1 : multiple;
  return (amount / safeMultiple).ceil() * safeMultiple.toDouble();
}

class CommerceServiceSlot {
  const CommerceServiceSlot({
    required this.id,
    required this.label,
    required this.capacity,
  });

  final String id;
  final String label;
  final int capacity;

  factory CommerceServiceSlot.fromJson(Map<String, dynamic> json) {
    return CommerceServiceSlot(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      capacity: (json['capacity'] as num?)?.toInt() ?? 1,
    );
  }
}

class CommerceAddonOption {
  const CommerceAddonOption({
    required this.id,
    required this.label,
    required this.price,
  });

  final int id;
  final String label;
  final double price;

  factory CommerceAddonOption.fromJson(Map<String, dynamic> json) {
    return CommerceAddonOption(
      id: (json['id'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CommerceAddonGroup {
  const CommerceAddonGroup({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    required this.options,
  });

  final String id;
  final String label;
  final String type;
  final bool required;
  final List<CommerceAddonOption> options;

  bool get isCheckbox => type == 'checkbox';

  factory CommerceAddonGroup.fromJson(Map<String, dynamic> json) {
    final optionsJson = json['group'] ?? json['options'];
    return CommerceAddonGroup(
      id: json['id']?.toString() ?? json['group_id']?.toString() ?? '',
      label: json['label']?.toString() ?? json['title']?.toString() ?? '',
      type: json['type']?.toString() == 'checkbox' ? 'checkbox' : 'radio',
      required: json['required'] == true,
      options: (optionsJson as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CommerceAddonOption.fromJson)
          .toList(),
    );
  }
}

class CommerceServiceRange {
  const CommerceServiceRange({required this.min, required this.max});

  final double min;
  final double max;

  factory CommerceServiceRange.fromJson(Map<String, dynamic> json) {
    return CommerceServiceRange(
      min: (json['min'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CommerceServiceConfig {
  const CommerceServiceConfig({
    required this.enabled,
    required this.depositPct,
    required this.allowFull,
    required this.minDays,
    required this.daysAllowed,
    required this.maxPerDay,
    required this.slots,
    required this.showRange,
    required this.range,
    required this.addons,
  });

  final bool enabled;
  final double depositPct;
  final bool allowFull;
  final int minDays;
  final List<int> daysAllowed;
  final int maxPerDay;
  final List<CommerceServiceSlot> slots;
  final bool showRange;
  final CommerceServiceRange range;
  final List<CommerceAddonGroup> addons;

  List<CommerceServiceSlot> get effectiveSlots => slots.isNotEmpty
      ? slots
      : <CommerceServiceSlot>[
          CommerceServiceSlot(
            id: 'full',
            label: 'Día completo',
            capacity: maxPerDay,
          ),
        ];

  factory CommerceServiceConfig.fromJson(Map<String, dynamic> json) {
    final parsedDays =
        (json['daysAllowed'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<num>()
            .map((day) => day.toInt())
            .where((day) => day >= 1 && day <= 7)
            .toSet()
            .toList();
    return CommerceServiceConfig(
      enabled: json['enabled'] == true,
      depositPct: (json['depositPct'] as num?)?.toDouble() ?? 50,
      allowFull: json['allowFull'] == true,
      minDays: (json['minDays'] as num?)?.toInt() ?? 0,
      daysAllowed: parsedDays.isEmpty
          ? const <int>[1, 2, 3, 4, 5, 6, 7]
          : parsedDays,
      maxPerDay: (json['maxPerDay'] as num?)?.toInt() ?? 1,
      slots: (json['slots'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CommerceServiceSlot.fromJson)
          .toList(),
      showRange: json['showRange'] == true,
      range: CommerceServiceRange.fromJson(
        json['range'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      addons: (json['addons'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CommerceAddonGroup.fromJson)
          .toList(),
    );
  }
}

class CommerceSelectedAddon {
  const CommerceSelectedAddon({
    required this.groupId,
    required this.groupLabel,
    required this.options,
  });

  final String groupId;
  final String groupLabel;
  final List<CommerceAddonOption> options;
}

class CommerceServiceSelection {
  const CommerceServiceSelection({
    required this.date,
    required this.slot,
    required this.slotLabel,
    required this.payChoice,
    required this.depositPct,
    required this.addons,
    required this.selectedAddons,
  });

  final String date;
  final String slot;
  final String slotLabel;
  final String payChoice;
  final double depositPct;
  final Map<String, List<int>> addons;
  final List<CommerceSelectedAddon> selectedAddons;

  double get addonsTotal => selectedAddons.fold<double>(
    0,
    (sum, group) =>
        sum +
        group.options.fold<double>(0, (value, option) => value + option.price),
  );

  String get signature {
    final groups = addons.keys.toList()..sort();
    final addonPart = groups
        .map((group) {
          final ids = [...addons[group] ?? const <int>[]]..sort();
          return '$group:${ids.join(',')}';
        })
        .join('|');
    return '$date|$slot|$payChoice|$addonPart';
  }

  double payNowFor(double total) {
    final raw = payChoice == 'full' ? total : total * depositPct / 100;
    return roundUpCommerceService(raw);
  }

  Map<String, dynamic> toRequestJson() => <String, dynamic>{
    'date': date,
    'slot': slot,
    'payChoice': payChoice,
    'addons': addons,
  };
}

class CommerceServiceAvailability {
  const CommerceServiceAvailability({
    required this.date,
    required this.slot,
    required this.capacity,
    required this.booked,
    required this.remaining,
    required this.available,
  });

  final String date;
  final String? slot;
  final int capacity;
  final int booked;
  final int remaining;
  final bool available;

  factory CommerceServiceAvailability.fromJson(Map<String, dynamic> json) {
    return CommerceServiceAvailability(
      date: json['date']?.toString() ?? '',
      slot: json['slot']?.toString(),
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      booked: (json['booked'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      available: json['available'] == true,
    );
  }
}

class CommerceImage {
  final int id;
  final String src;
  final String thumbnail;
  final String alt;

  const CommerceImage({
    required this.id,
    required this.src,
    required this.thumbnail,
    required this.alt,
  });

  factory CommerceImage.fromJson(Map<String, dynamic> json) {
    return CommerceImage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      src: json['src']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      alt: json['alt']?.toString() ?? '',
    );
  }
}

class CommerceAudience {
  final bool paraResidente;
  final bool paraConjunto;
  final bool esServicio;

  const CommerceAudience({
    required this.paraResidente,
    required this.paraConjunto,
    required this.esServicio,
  });

  factory CommerceAudience.fromJson(Map<String, dynamic> json) {
    return CommerceAudience(
      paraResidente: json['paraResidente'] == true,
      paraConjunto: json['paraConjunto'] == true,
      esServicio: json['esServicio'] == true,
    );
  }
}

class CommerceProduct {
  final int id;
  final String name;
  final String slug;
  final String type;
  final String sku;
  final String shortDescription;
  final String description;
  final String permalink;
  final bool onSale;
  final bool purchasable;
  final String stockStatus;
  final int? lowStockRemaining;
  final CommercePrice price;
  final List<CommerceImage> images;
  final List<CommerceCategory> categories;
  final List<CommerceCategory> tags;
  final double averageRating;
  final int reviewCount;
  final CommerceAudience audience;
  final CommerceServiceConfig? service;
  final String source;

  const CommerceProduct({
    required this.id,
    required this.name,
    required this.slug,
    required this.type,
    required this.sku,
    required this.shortDescription,
    required this.description,
    required this.permalink,
    required this.onSale,
    required this.purchasable,
    required this.stockStatus,
    required this.lowStockRemaining,
    required this.price,
    required this.images,
    required this.categories,
    required this.tags,
    required this.averageRating,
    required this.reviewCount,
    required this.audience,
    required this.service,
    required this.source,
  });

  factory CommerceProduct.fromJson(Map<String, dynamic> json) {
    return CommerceProduct(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      type: json['type']?.toString() ?? 'simple',
      sku: json['sku']?.toString() ?? '',
      shortDescription: json['shortDescription']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      permalink: json['permalink']?.toString() ?? '',
      onSale: json['onSale'] == true,
      purchasable: json['purchasable'] != false,
      stockStatus: json['stockStatus']?.toString() ?? 'unknown',
      lowStockRemaining: (json['lowStockRemaining'] as num?)?.toInt(),
      price: CommercePrice.fromJson(
        json['price'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      images: (json['images'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommerceImage.fromJson)
          .toList(),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommerceCategory.fromJson)
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommerceCategory.fromJson)
          .toList(),
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      audience: CommerceAudience.fromJson(
        json['audience'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      service: json['service'] is Map<String, dynamic>
          ? CommerceServiceConfig.fromJson(
              json['service'] as Map<String, dynamic>,
            )
          : null,
      source: json['source']?.toString() ?? '',
    );
  }
}

class CommercePagination {
  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  const CommercePagination({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
  });

  factory CommercePagination.fromJson(Map<String, dynamic> json) {
    return CommercePagination(
      page: (json['page'] as num?)?.toInt() ?? 1,
      perPage: (json['perPage'] as num?)?.toInt() ?? 24,
      total: (json['total'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
    );
  }
}

class CommerceCatalogResponse {
  final String source;
  final String baseUrl;
  final String target;
  final CommercePagination pagination;
  final List<CommerceCategory> categories;
  final List<CommerceProduct> items;

  const CommerceCatalogResponse({
    required this.source,
    required this.baseUrl,
    required this.target,
    required this.pagination,
    required this.categories,
    required this.items,
  });

  factory CommerceCatalogResponse.fromJson(Map<String, dynamic> json) {
    return CommerceCatalogResponse(
      source: json['source']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      target: json['target']?.toString() ?? 'todos',
      pagination: CommercePagination.fromJson(
        json['pagination'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommerceCategory.fromJson)
          .toList(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommerceProduct.fromJson)
          .toList(),
    );
  }
}
