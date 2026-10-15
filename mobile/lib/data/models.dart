import '../core/format.dart';

/// Стоимость доставки (копейки). Один человек доставляет, поэтому фиксированная.
const int kDeliveryKop = 39000;

enum Unit { kg, piece, set }

/// Весовой товар продаётся кратно 100 г, минимум 300 г.
const kMinWeight = 300;
const kWeightStep = 100;
bool isValidWeight(int grams) =>
    grams >= kMinWeight && grams % kWeightStep == 0;

extension UnitX on Unit {
  String get apiName => name; // kg | piece | set

  static Unit fromApi(String s) =>
      Unit.values.firstWhere((u) => u.name == s, orElse: () => Unit.piece);

  String get label => switch (this) {
    Unit.kg => 'За кг',
    Unit.piece => 'За штуку',
    Unit.set => 'Набор',
  };

  String get stockLabel => switch (this) {
    Unit.kg => 'Остаток, кг',
    Unit.piece => 'Остаток, шт',
    Unit.set => 'Остаток, наборов',
  };

  String get priceLabel => switch (this) {
    Unit.kg => 'Цена за кг, ₽',
    Unit.piece => 'Цена за штуку, ₽',
    Unit.set => 'Цена за набор, ₽',
  };

  String get priceSuffix => switch (this) {
    Unit.kg => ' / кг',
    Unit.piece => ' / шт',
    Unit.set => '',
  };
}

/// Сумма строки: для весового товара количество в граммах, цена за кг.
int lineTotal(Unit unit, int priceKop, int qty) =>
    unit == Unit.kg ? (priceKop * qty + 500) ~/ 1000 : priceKop * qty;

String qtyText(Unit unit, int qty) => switch (unit) {
  Unit.kg => formatWeight(qty),
  Unit.piece => '$qty шт',
  Unit.set => '$qty × набор',
};

enum ProductStatus { onSale, low, outOfStock, hidden }

extension ProductStatusX on ProductStatus {
  String get label => switch (this) {
    ProductStatus.onSale => 'В продаже',
    ProductStatus.low => 'Мало',
    ProductStatus.outOfStock => 'Нет в наличии',
    ProductStatus.hidden => 'Скрыт',
  };
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.priceKop,
    this.description = '',
    this.imageUrl,
    this.weightSteps = const [300, 500, 1000],
    this.stock = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String category;
  final Unit unit;

  /// Цена за кг / штуку / набор, в копейках.
  final int priceKop;
  final String description;
  final String? imageUrl;

  /// Для весового товара: доступные порции в граммах.
  final List<int> weightSteps;

  /// Остаток: граммы для кг, штуки для остальных.
  final int stock;
  final bool isActive;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'] as String,
    name: j['name'] as String,
    category: j['category'] as String,
    unit: UnitX.fromApi(j['unit'] as String),
    priceKop: (j['priceKop'] as num).toInt(),
    description: (j['description'] as String?) ?? '',
    imageUrl: j['imageUrl'] as String?,
    weightSteps: [
      for (final v in (j['weightSteps'] as List? ?? const []))
        (v as num).toInt(),
    ],
    stock: (j['stock'] as num).toInt(),
    isActive: (j['isActive'] as bool?) ?? true,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'unit': unit.apiName,
    'priceKop': priceKop,
    'stock': stock,
    'description': description,
    'weightSteps': unit == Unit.kg ? weightSteps : const <int>[],
    'imageUrl': imageUrl,
    'isActive': isActive,
  };

  Product copyWith({
    String? name,
    String? category,
    Unit? unit,
    int? priceKop,
    String? description,
    String? imageUrl,
    int? stock,
    bool? isActive,
  }) => Product(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    unit: unit ?? this.unit,
    priceKop: priceKop ?? this.priceKop,
    description: description ?? this.description,
    imageUrl: imageUrl ?? this.imageUrl,
    weightSteps: weightSteps,
    stock: stock ?? this.stock,
    isActive: isActive ?? this.isActive,
  );

  bool get inStock => stock > 0;
  bool get isLow => inStock && (unit == Unit.kg ? stock < 3000 : stock < 5);

  ProductStatus get status {
    if (!isActive) return ProductStatus.hidden;
    if (!inStock) return ProductStatus.outOfStock;
    if (isLow) return ProductStatus.low;
    return ProductStatus.onSale;
  }

  int lineKop(int qty) => lineTotal(unit, priceKop, qty);

  String get priceLabel => '${formatKop(priceKop)}${unit.priceSuffix}';

  String qtyLabel(int qty) => qtyText(unit, qty);

  String get stockText => switch (unit) {
    Unit.kg => formatWeight(stock),
    Unit.piece => '$stock шт',
    Unit.set => '$stock наб.',
  };

  /// Сколько можно положить в корзину максимум (для кг: кратно 100 г).
  int get maxQty => unit == Unit.kg ? stock - stock % kWeightStep : stock;

  /// Можно ли вообще купить (для кг: остатка хватает хотя бы на 300 г).
  bool get canBuy => unit == Unit.kg ? maxQty >= kMinWeight : stock > 0;

  /// Подсказка, когда «+» уже некуда увеличивать.
  String get limitMessage => 'На складе осталось только $stockText';

  /// Порции, которые можно выбрать на экране товара (только для кг).
  List<int> get selectableQty {
    if (unit != Unit.kg || !canBuy) return const [];
    final steps = weightSteps
        .where((s) => isValidWeight(s) && s <= maxQty)
        .toList()
      ..sort();
    return steps.isEmpty ? [kMinWeight] : steps;
  }

  /// Подходит ли это количество для заказа.
  bool isValidQty(int qty) => unit == Unit.kg
      ? isValidWeight(qty) && qty <= maxQty
      : qty >= 1 && qty <= stock;

  int get defaultQty {
    if (!canBuy) return 0;
    if (unit != Unit.kg) return 1;
    final s = selectableQty;
    return s.contains(500) ? 500 : s.first;
  }

  /// Шаг кнопок +/- в корзине.
  int get cartStep => unit == Unit.kg ? 100 : 1;
}

class CartLine {
  const CartLine(this.product, this.qty);
  final Product product;
  final int qty;

  int get lineKop => product.lineKop(qty);
}

class DeliverySlot {
  const DeliverySlot({
    required this.id,
    required this.date,
    required this.fromHour,
    required this.toHour,
  });

  /// id шаблона слота на сервере и дата доставки (ГГГГ-ММ-ДД).
  final String id;
  final String date;
  final int fromHour;
  final int toHour;

  factory DeliverySlot.fromJson(Map<String, dynamic> j) => DeliverySlot(
    id: (j['slotId'] ?? j['id']) as String,
    date: j['date'] as String,
    fromHour: (j['fromHour'] as num).toInt(),
    toHour: (j['toHour'] as num).toInt(),
  );

  int get dayOffset {
    final d = DateTime.tryParse(date);
    if (d == null) return 0;
    final now = DateTime.now();
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  String get label {
    final offset = dayOffset;
    final d = DateTime.tryParse(date);
    final day = switch (offset) {
      0 => 'Сегодня',
      1 => 'Завтра',
      _ =>
        d == null
            ? date
            : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}',
    };
    return '$day $fromHour–$toHour';
  }
}

enum OrderStatus { newOrder, preparing, onTheWay, delivered, canceled }

extension OrderStatusX on OrderStatus {
  String get apiName => switch (this) {
    OrderStatus.newOrder => 'NEW',
    OrderStatus.preparing => 'PREPARING',
    OrderStatus.onTheWay => 'ON_THE_WAY',
    OrderStatus.delivered => 'DELIVERED',
    OrderStatus.canceled => 'CANCELED',
  };

  static OrderStatus fromApi(String s) => OrderStatus.values.firstWhere(
    (v) => v.apiName == s,
    orElse: () => OrderStatus.newOrder,
  );

  String get label => switch (this) {
    OrderStatus.newOrder => 'Новый',
    OrderStatus.preparing => 'Собирается',
    OrderStatus.onTheWay => 'В пути',
    OrderStatus.delivered => 'Доставлен',
    OrderStatus.canceled => 'Отменён',
  };

  /// Разрешённые переходы: NEW → PREPARING → ON_THE_WAY → DELIVERED.
  OrderStatus? get next => switch (this) {
    OrderStatus.newOrder => OrderStatus.preparing,
    OrderStatus.preparing => OrderStatus.onTheWay,
    OrderStatus.onTheWay => OrderStatus.delivered,
    _ => null,
  };

  String? get actionLabel => switch (this) {
    OrderStatus.newOrder => 'Принять в работу',
    OrderStatus.preparing => 'Выехал к клиенту',
    OrderStatus.onTheWay => 'Доставлен',
    _ => null,
  };

  bool get canCancel =>
      this == OrderStatus.newOrder || this == OrderStatus.preparing;

  /// Позиция на шкале статусов (-1 для отменённого).
  int get step => switch (this) {
    OrderStatus.newOrder => 0,
    OrderStatus.preparing => 1,
    OrderStatus.onTheWay => 2,
    OrderStatus.delivered => 3,
    OrderStatus.canceled => -1,
  };
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.priceKop,
    required this.qty,
  });

  final String productId;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    productId: (j['productId'] as String?) ?? '',
    name: j['name'] as String,
    unit: UnitX.fromApi(j['unit'] as String),
    priceKop: (j['priceKop'] as num).toInt(),
    qty: (j['qty'] as num).toInt(),
  );

  /// Название и цена копируются на момент заказа.
  final String name;
  final Unit unit;
  final int priceKop;
  final int qty;

  int get lineKop => lineTotal(unit, priceKop, qty);
  String get qtyLabel => qtyText(unit, qty);
}

class Order {
  const Order({
    required this.number,
    required this.customerName,
    required this.phone,
    required this.addressLine,
    required this.slot,
    required this.items,
    required this.itemsKop,
    required this.discountKop,
    required this.deliveryKop,
    required this.status,
    required this.createdAt,
    this.isMine = false,
  });

  factory Order.fromJson(Map<String, dynamic> j, {required bool isMine}) =>
      Order(
        number: (j['number'] as num).toInt(),
        customerName: (j['customerName'] as String?) ?? '',
        phone: (j['customerPhone'] as String?) ?? '',
        addressLine: (j['addressLine'] as String?) ?? '',
        slot: DeliverySlot.fromJson(j['slot'] as Map<String, dynamic>),
        items: [
          for (final i in j['items'] as List)
            OrderItem.fromJson(i as Map<String, dynamic>),
        ],
        itemsKop: (j['itemsKop'] as num).toInt(),
        discountKop: (j['discountKop'] as num).toInt(),
        deliveryKop: (j['deliveryKop'] as num).toInt(),
        status: OrderStatusX.fromApi(j['status'] as String),
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
        isMine: isMine,
      );

  final int number;
  final String customerName;
  final String phone;
  final String addressLine;
  final DeliverySlot slot;
  final List<OrderItem> items;
  final int itemsKop;
  final int discountKop;
  final int deliveryKop;
  final OrderStatus status;
  final DateTime createdAt;

  /// Заказ текущего клиента (в списке клиента все заказы его).
  final bool isMine;

  int get totalKop => itemsKop - discountKop + deliveryKop;

  Order copyWith({OrderStatus? status}) => Order(
    number: number,
    customerName: customerName,
    phone: phone,
    addressLine: addressLine,
    slot: slot,
    items: items,
    itemsKop: itemsKop,
    discountKop: discountKop,
    deliveryKop: deliveryKop,
    status: status ?? this.status,
    createdAt: createdAt,
    isMine: isMine,
  );
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.phone,
    required this.address,
    this.bonus = 0,
  });

  final String name;
  final String phone;
  final String address;
  final int bonus;
}
