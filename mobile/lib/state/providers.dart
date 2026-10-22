import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/messenger.dart';
import '../data/api.dart';
import '../data/firebase_setup.dart';
import '../data/social_auth.dart';
import '../data/models.dart';

// ---------------------------------------------------------------- сервер

/// Подставляется в main() после чтения SharedPreferences.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider не задан'),
);

final apiProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(prefsProvider)),
);

// ---------------------------------------------------------------- вход

enum AppRole { client, admin }

class AuthState {
  const AuthState({this.loading = false, this.user, this.error});
  final bool loading;
  final AuthUser? user;

  /// Не удалось восстановить сессию из-за сети (показываем «Повторить»).
  final String? error;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    if (ref.read(apiProvider).hasSession) {
      Future.microtask(restore);
      return const AuthState(loading: true);
    }
    return const AuthState();
  }

  Future<void> restore() async {
    state = const AuthState(loading: true);
    try {
      state = AuthState(user: await ref.read(apiProvider).me());
    } on ApiException catch (e) {
      state = e.status == 0 ? AuthState(error: e.message) : const AuthState();
    }
  }

  /// Тихо обновляет профиль (бонусы, имя) без экрана загрузки.
  Future<void> refreshUser() async {
    if (state.user == null) return;
    try {
      state = AuthState(user: await ref.read(apiProvider).me());
    } catch (_) {}
  }

  void _signedIn(AuthUser user) {
    ref.read(clientTabProvider.notifier).set(0);
    ref.read(adminTabProvider.notifier).set(0);
    state = AuthState(user: user);
  }

  Future<PendingEmail> register(String email, String password, String name) =>
      ref.read(apiProvider).register(email, password, name);

  Future<void> verifyEmail(String email, String code) async =>
      _signedIn(await ref.read(apiProvider).verifyEmail(email, code));

  Future<PendingEmail> resendCode(String email) =>
      ref.read(apiProvider).resendCode(email);

  Future<void> loginWithPassword(String email, String password) async =>
      _signedIn(await ref.read(apiProvider).login(email, password));

  Future<void> loginWithGoogle(String idToken) async =>
      _signedIn(await ref.read(apiProvider).loginWithGoogle(idToken));

  Future<void> loginWithVk(VkAuthResult r) async =>
      _signedIn(
        await ref.read(apiProvider).loginWithVk(
              code: r.code,
              codeVerifier: r.codeVerifier,
              deviceId: r.deviceId,
              state: r.state,
              redirectUri: r.redirectUri,
            ),
      );

  Future<void> updateName(String name) async {
    try {
      state = AuthState(user: await ref.read(apiProvider).updateName(name));
    } catch (e) {
      reportError(e);
    }
  }

  Future<void> logout() async {
    await forgetPushToken();
    await ref.read(apiProvider).logout();
    await socialSignOut();
    ref.read(cartProvider.notifier).clear();
    ref.read(nameSkipProvider.notifier).reset();
    state = const AuthState();
  }
}

/// Пользователь нажал «Пропустить» на шаге ввода имени при регистрации.
class NameSkipNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void skip() => state = true;
  void reset() => state = false;
}

final nameSkipProvider = NotifierProvider<NameSkipNotifier, bool>(
  NameSkipNotifier.new,
);

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Способы входа, включённые на сервере. При ошибке сети остаются только email и пароль.
final authProvidersProvider = FutureProvider.autoDispose<AuthProviders>((
  ref,
) async {
  try {
    return await ref.read(apiProvider).authProviders();
  } catch (_) {
    return AuthProviders.none;
  }
});

/// Меняется только при входе/выходе — по нему данные перезагружаются.
final sessionUserProvider = Provider<String?>(
  (ref) => ref.watch(authProvider.select((a) => a.user?.id)),
);

final roleProvider = Provider<AppRole?>((ref) {
  final user = ref.watch(authProvider.select((a) => a.user));
  if (user == null) return null;
  return user.isAdmin ? AppRole.admin : AppRole.client;
});

bool _isAdmin(Ref ref) => ref.read(authProvider).user?.isAdmin ?? false;

class TabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int index) => state = index;
}

final clientTabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);
final adminTabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);

// ---------------------------------------------------------------- каталог

class CatalogNotifier extends Notifier<List<Product>> {
  @override
  List<Product> build() {
    if (ref.watch(sessionUserProvider) != null) Future.microtask(load);
    return const [];
  }

  Future<void> load() async {
    try {
      state = await ref.read(apiProvider).products(admin: _isAdmin(ref));
    } catch (e) {
      reportError(e);
    }
  }

  /// Удалить товар (админ). true — успешно.
  Future<bool> remove(String id) async {
    try {
      await ref.read(apiProvider).deleteProduct(id);
    } catch (e) {
      reportError(e);
      return false;
    }
    await load();
    return true;
  }

  /// Создать или изменить товар (админ). true — успешно.
  Future<bool> save(Product p, {required bool isNew}) async {
    final api = ref.read(apiProvider);
    try {
      if (isNew) {
        await api.createProduct(p);
      } else {
        await api.updateProduct(p);
      }
    } catch (e) {
      reportError(e);
      return false;
    }
    await load();
    ref.read(serverCategoriesProvider.notifier).load();
    return true;
  }
}

final catalogProvider = NotifierProvider<CatalogNotifier, List<Product>>(
  CatalogNotifier.new,
);

class ServerCategoriesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    if (ref.watch(sessionUserProvider) != null) Future.microtask(load);
    return const [];
  }

  Future<void> load() async {
    try {
      state = await ref.read(apiProvider).categories();
    } catch (_) {
      // Список категорий не критичен: останутся категории из товаров.
    }
  }
}

final serverCategoriesProvider =
    NotifierProvider<ServerCategoriesNotifier, List<String>>(
      ServerCategoriesNotifier.new,
    );

final categoriesProvider = Provider<List<String>>((ref) {
  final all = <String>{
    ...ref.watch(serverCategoriesProvider),
    ...ref.watch(catalogProvider).map((p) => p.category),
  };
  return all.toList();
});

// ---------------------------------------------------------------- слоты

class SlotsNotifier extends Notifier<List<DeliverySlot>> {
  @override
  List<DeliverySlot> build() {
    if (ref.watch(sessionUserProvider) != null && !_isAdmin(ref)) {
      Future.microtask(load);
    }
    return const [];
  }

  Future<void> load() async {
    try {
      state = await ref.read(apiProvider).slots();
    } catch (e) {
      reportError(e);
    }
  }
}

final slotsProvider = NotifierProvider<SlotsNotifier, List<DeliverySlot>>(
  SlotsNotifier.new,
);

// ---------------------------------------------------------------- корзина

class CartNotifier extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  void add(Product p, int qty) {
    if (qty <= 0 || !p.canBuy) return;
    final i = state.indexWhere((l) => l.product.id == p.id);
    if (i == -1) {
      state = [...state, CartLine(p, math.min(qty, p.maxQty))];
    } else {
      final q = math.min(state[i].qty + qty, p.maxQty);
      state = [
        for (var j = 0; j < state.length; j++)
          j == i ? CartLine(p, q) : state[j],
      ];
    }
  }

  /// Изменить количество; если стало <= 0, позиция удаляется.
  void change(String productId, int delta) {
    final next = <CartLine>[];
    for (final l in state) {
      if (l.product.id != productId) {
        next.add(l);
        continue;
      }
      final q = math.min(l.qty + delta, l.product.maxQty);
      // Весовой товар: ниже 300 г позиция убирается из корзины.
      final tooSmall = l.product.unit == Unit.kg && q < kMinWeight;
      if (q > 0 && !tooSmall) next.add(CartLine(l.product, q));
    }
    state = next;
  }

  void clear() => state = const [];
}

final cartProvider = NotifierProvider<CartNotifier, List<CartLine>>(
  CartNotifier.new,
);

// ---------------------------------------------------------------- заказы

class OrdersNotifier extends Notifier<List<Order>> {
  /// Последняя неудачная попытка оформления оборвалась из-за связи (заказ мог создаться).
  bool lastErrorWasNetwork = false;

  @override
  List<Order> build() {
    if (ref.watch(sessionUserProvider) != null) {
      Future.microtask(load);
      // Статусы меняет администратор — подтягиваем изменения раз в 20 секунд.
      final timer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => load(silent: true),
      );
      ref.onDispose(timer.cancel);
    }
    return const [];
  }

  Future<void> load({bool silent = false}) async {
    try {
      state = await ref.read(apiProvider).orders(admin: _isAdmin(ref));
    } catch (e) {
      if (!silent) reportError(e);
    }
  }

  /// Оформляет заказ. null — не получилось (ошибка уже показана пользователю).
  Future<Order?> place({
    required List<CartLine> lines,
    required DeliverySlot slot,
    required String addressLine,
    required String phone,
    required String idempotencyKey,
    String? promoCode,
  }) async {
    try {
      final order = await ref
          .read(apiProvider)
          .placeOrder(
            lines: lines,
            slot: slot,
            addressLine: addressLine,
            phone: phone,
            promoCode: promoCode,
            idempotencyKey: idempotencyKey,
          );
      state = [order, ...state.where((o) => o.number != order.number)];
      _refreshStockAndSlots();
      return order;
    } catch (e) {
      lastErrorWasNetwork = e is ApiException && e.status == 0;
      reportError(e);
      // Остатки или слоты могли измениться — обновляем.
      _refreshStockAndSlots();
      return null;
    }
  }

  /// Переход вперёд по цепочке статусов (админ). Остальные переходы запрещены.
  Future<void> advance(int number) async {
    final i = state.indexWhere((o) => o.number == number);
    final next = i == -1 ? null : state[i].status.next;
    if (next == null) return;
    await _run(() => ref.read(apiProvider).transitionOrder(number, next));
  }

  Future<void> cancel(int number) async {
    final api = ref.read(apiProvider);
    await _run(
      () => _isAdmin(ref)
          ? api.transitionOrder(number, OrderStatus.canceled)
          : api.cancelOrder(number),
    );
    _refreshStockAndSlots();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      reportError(e);
    }
    await load(silent: true);
  }

  void _refreshStockAndSlots() {
    ref.read(catalogProvider.notifier).load();
    if (!_isAdmin(ref)) ref.read(slotsProvider.notifier).load();
  }
}

final ordersProvider = NotifierProvider<OrdersNotifier, List<Order>>(
  OrdersNotifier.new,
);

final myOrdersProvider = Provider<List<Order>>(
  (ref) => ref.watch(ordersProvider).where((o) => o.isMine).toList(),
);

/// Адрес доставки, который клиент указал сам (хранится на устройстве).
class AddressNotifier extends Notifier<String?> {
  String get _key => 'address:${ref.read(sessionUserProvider)}';

  @override
  String? build() {
    final user = ref.watch(sessionUserProvider);
    if (user == null) return null;
    final v = ref.read(prefsProvider).getString('address:$user');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> set(String address) async {
    state = address;
    await ref.read(prefsProvider).setString(_key, address);
  }
}

final addressProvider =
    NotifierProvider<AddressNotifier, String?>(AddressNotifier.new);

/// Включены ли push-уведомления о заказах (настройка хранится на устройстве).
class NotificationsNotifier extends Notifier<bool> {
  String get _key => 'notifications:${ref.read(sessionUserProvider)}';

  @override
  bool build() {
    final user = ref.watch(sessionUserProvider);
    if (user == null) return true;
    return ref.read(prefsProvider).getBool('notifications:$user') ?? true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref.read(prefsProvider).setBool(_key, enabled);
    // Выключили: забываем токен, чтобы сервер перестал слать на это устройство.
    // Включили: PushNotifier увидит изменение и зарегистрирует устройство заново.
    if (!enabled) await forgetPushToken();
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, bool>(NotificationsNotifier.new);

final profileProvider = Provider<UserProfile>((ref) {
  final user = ref.watch(authProvider.select((a) => a.user));
  final orders = ref.watch(myOrdersProvider);
  return UserProfile(
    name: user?.name ?? '',
    phone: user?.phone ?? '',
    email: user?.email ?? '',
    // Свой адрес, а если не задан — из последнего заказа.
    address: ref.watch(addressProvider) ??
        (orders.isEmpty ? '' : orders.first.addressLine),
    bonus: user?.bonus ?? 0,
  );
});
