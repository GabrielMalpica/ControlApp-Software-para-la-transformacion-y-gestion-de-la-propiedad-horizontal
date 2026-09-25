import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/model/commerce_models.dart';
import 'package:flutter_application_1/model/resident_order_models.dart';

class ResidentCartService extends ChangeNotifier {
  ResidentCartService._();

  static final ResidentCartService instance = ResidentCartService._();

  final Map<String, ResidentCartItem> _items = <String, ResidentCartItem>{};

  List<ResidentCartItem> get items => _items.values.toList(growable: false);

  int get itemCount => _items.length;

  double get total => _items.values.fold(0, (sum, item) => sum + item.subtotal);
  double get payNowTotal {
    for (final item in _items.values) {
      if (item.service != null) return item.service!.payNowFor(total);
    }
    return 0;
  }

  void addProduct(
    CommerceProduct product, {
    int quantity = 1,
    CommerceServiceSelection? service,
    CommerceVariation? variation,
  }) {
    if (product.service?.enabled == true && service == null) return;
    if (product.isVariable && variation == null) return;

    final cartKey =
        '${product.id}|${variation?.id ?? 'base'}|${service?.signature ?? 'product'}';
    final current = _items[cartKey];
    final imageUrl = variation?.image.isNotEmpty == true
        ? variation!.image
        : product.images.isNotEmpty
        ? product.images.first.src
        : '';
    if (current == null) {
      _items[cartKey] = ResidentCartItem(
        cartKey: cartKey,
        productId: product.id,
        variationId: variation?.id,
        name: variation != null ? '${product.name} (${variation.label})' : product.name,
        sku: variation != null && variation.sku.isNotEmpty ? variation.sku : product.sku,
        imageUrl: imageUrl,
        unitPrice:
            (variation?.price.current ?? product.price.current) +
            (service?.addonsTotal ?? 0),
        quantity: quantity,
        type: product.type,
        service: service,
      );
    } else {
      _items[cartKey] = current.copyWith(quantity: current.quantity + quantity);
    }
    notifyListeners();
  }

  void setQuantity(String cartKey, int quantity) {
    final current = _items[cartKey];
    if (current == null) return;
    if (quantity <= 0) {
      _items.remove(cartKey);
    } else {
      _items[cartKey] = current.copyWith(quantity: quantity);
    }
    notifyListeners();
  }

  void removeProduct(String cartKey) {
    _items.remove(cartKey);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
