import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/model/commerce_models.dart';
import 'package:flutter_application_1/model/conjunto_order_models.dart';

class ConjuntoCartService extends ChangeNotifier {
  ConjuntoCartService._();

  static final ConjuntoCartService instance = ConjuntoCartService._();

  final Map<String, ConjuntoCartItem> _items = <String, ConjuntoCartItem>{};

  List<ConjuntoCartItem> get items => _items.values.toList(growable: false);

  int get itemCount => _items.length;

  int get unitsCount =>
      _items.values.fold(0, (sum, item) => sum + item.quantity);

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
  }) {
    if (!product.audience.paraConjunto) {
      return;
    }
    if (product.service?.enabled == true && service == null) return;

    final cartKey = '${product.id}|${service?.signature ?? 'product'}';
    final current = _items[cartKey];
    final imageUrl = product.images.isNotEmpty ? product.images.first.src : '';
    if (current == null) {
      _items[cartKey] = ConjuntoCartItem(
        cartKey: cartKey,
        productId: product.id,
        name: product.name,
        sku: product.sku,
        imageUrl: imageUrl,
        unitPrice: product.price.current + (service?.addonsTotal ?? 0),
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
