import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/model/commerce_models.dart';
import 'package:flutter_application_1/model/resident_order_models.dart';

class ResidentCartService extends ChangeNotifier {
  ResidentCartService._();

  static final ResidentCartService instance = ResidentCartService._();

  final Map<int, ResidentCartItem> _items = <int, ResidentCartItem>{};

  List<ResidentCartItem> get items => _items.values.toList(growable: false);

  int get itemCount => _items.length;

  double get total => _items.values.fold(0, (sum, item) => sum + item.subtotal);

  void addProduct(CommerceProduct product, {int quantity = 1}) {
    final current = _items[product.id];
    final imageUrl = product.images.isNotEmpty ? product.images.first.src : '';
    if (current == null) {
      _items[product.id] = ResidentCartItem(
        productId: product.id,
        name: product.name,
        sku: product.sku,
        imageUrl: imageUrl,
        unitPrice: product.price.current,
        quantity: quantity,
        type: product.type,
      );
    } else {
      _items[product.id] = current.copyWith(quantity: current.quantity + quantity);
    }
    notifyListeners();
  }

  void setQuantity(int productId, int quantity) {
    final current = _items[productId];
    if (current == null) return;
    if (quantity <= 0) {
      _items.remove(productId);
    } else {
      _items[productId] = current.copyWith(quantity: quantity);
    }
    notifyListeners();
  }

  void removeProduct(int productId) {
    _items.remove(productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
