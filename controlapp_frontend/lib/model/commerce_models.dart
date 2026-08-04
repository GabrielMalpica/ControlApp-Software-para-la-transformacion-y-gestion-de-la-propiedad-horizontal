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
        json['pagination'] as Map<String, dynamic>? ?? const <String, dynamic>{},
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
