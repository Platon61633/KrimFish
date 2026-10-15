import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.phone,
    required this.name,
    required this.role,
    this.bonus = 0,
  });

  final String id;
  final String phone;
  final String name;
  final String role; // CUSTOMER | ADMIN
  final int bonus;

  bool get isAdmin => role == 'ADMIN';

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'] as String,
    phone: j['phone'] as String,
    name: (j['name'] as String?) ?? '',
    role: (j['role'] as String?) ?? 'CUSTOMER',
    bonus: (j['bonus'] as num?)?.toInt() ?? 0,
  );
}

class Quote {
  const Quote({
    required this.itemsKop,
    required this.discountKop,
    required this.deliveryKop,
    required this.totalKop,
  });
  final int itemsKop;
  final int discountKop;
  final int deliveryKop;
  final int totalKop;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
    itemsKop: (j['itemsKop'] as num).toInt(),
    discountKop: (j['discountKop'] as num).toInt(),
    deliveryKop: (j['deliveryKop'] as num).toInt(),
    totalKop: (j['totalKop'] as num).toInt(),
  );
}

class UploadTicket {
  const UploadTicket({
    required this.uploadUrl,
    required this.headers,
    required this.imageUrl,
  });
  final String uploadUrl;
  final Map<String, String> headers;
  final String imageUrl;
}

/// Тонкая обёртка над HTTP: токены, автообновление access-токена, ошибки сервера.
class ApiClient {
  ApiClient(this._prefs, {http.Client? client})
    : _http = client ?? http.Client();

  final SharedPreferences _prefs;
  final http.Client _http;

  static const _kAccess = 'accessToken';
  static const _kRefresh = 'refreshToken';

  Future<void>? _refreshing;

  bool get hasSession => _prefs.getString(_kRefresh) != null;

  Future<void> _saveTokens(Map<String, dynamic> j) async {
    await _prefs.setString(_kAccess, j['accessToken'] as String);
    await _prefs.setString(_kRefresh, j['refreshToken'] as String);
  }

  Future<void> clearSession() async {
    await _prefs.remove(_kAccess);
    await _prefs.remove(_kRefresh);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool auth = true,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    if (headers != null) req.headers.addAll(headers);
    final access = _prefs.getString(_kAccess);
    if (auth && access != null) req.headers['Authorization'] = 'Bearer $access';

    http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 20)),
      );
    } on TimeoutException {
      throw ApiException(
        0,
        'Сервер не отвечает ($apiBaseUrl). Он запущен? Проверьте адрес и сеть.',
      );
    } on Exception catch (e) {
      final cause = e.toString().replaceAll('\n', ' ');
      throw ApiException(
        0,
        'Нет связи с сервером $apiBaseUrl. '
        '${cause.length > 160 ? cause.substring(0, 160) : cause}',
      );
    }

    if (res.statusCode == 401 && auth && !retried && hasSession) {
      if (await _refresh()) {
        return _request(
          method,
          path,
          body: body,
          query: query,
          headers: headers,
          auth: auth,
          retried: true,
        );
      }
      await clearSession();
      throw const ApiException(401, 'Сессия истекла, войдите снова');
    }

    final text = utf8.decode(res.bodyBytes);
    final json = text.isEmpty ? null : _tryDecode(text);
    if (res.statusCode >= 400) {
      final msg = json is Map && json['error'] is String
          ? json['error'] as String
          : 'Ошибка сервера (${res.statusCode})';
      throw ApiException(res.statusCode, msg);
    }
    return json;
  }

  dynamic _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// Обновление токенов; параллельные запросы ждут один и тот же вызов.
  Future<bool> _refresh() async {
    final existing = _refreshing;
    if (existing != null) {
      await existing;
      return _prefs.getString(_kAccess) != null;
    }
    final completer = Completer<void>();
    _refreshing = completer.future;
    try {
      final token = _prefs.getString(_kRefresh);
      if (token == null) return false;
      final j =
          await _request(
                'POST',
                '/auth/refresh',
                body: {'refreshToken': token},
                auth: false,
              )
              as Map<String, dynamic>;
      await _saveTokens(j);
      return true;
    } on ApiException catch (e) {
      // Сеть недоступна — сессию не сбрасываем; сервер отклонил токен — сбрасываем.
      if (e.status != 0) await clearSession();
      return false;
    } finally {
      completer.complete();
      _refreshing = null;
    }
  }

  // ------------------------------------------------------------- вход

  /// Возвращает devCode, если сервер в режиме разработки.
  Future<String?> requestCode(String phone) async {
    final j =
        await _request(
              'POST',
              '/auth/request-code',
              body: {'phone': phone},
              auth: false,
            )
            as Map<String, dynamic>;
    return j['devCode'] as String?;
  }

  Future<AuthUser> verifyCode(String phone, String code) async {
    final j =
        await _request(
              'POST',
              '/auth/verify',
              body: {'phone': phone, 'code': code},
              auth: false,
            )
            as Map<String, dynamic>;
    await _saveTokens(j);
    return AuthUser.fromJson(j['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final token = _prefs.getString(_kRefresh);
    try {
      if (token != null) {
        await _request('POST', '/auth/logout', body: {'refreshToken': token});
      }
    } on ApiException {
      // Выходим локально в любом случае.
    }
    await clearSession();
  }

  /// Привязывает токен push-уведомлений этого устройства к пользователю.
  Future<void> registerDevice(String token, String os) =>
      _request('POST', '/me/devices', body: {'token': token, 'os': os});

  // ------------------------------------------------------------- профиль

  Future<AuthUser> me() async =>
      AuthUser.fromJson(await _request('GET', '/me') as Map<String, dynamic>);

  Future<AuthUser> updateName(String name) async => AuthUser.fromJson(
    await _request('PATCH', '/me', body: {'name': name})
        as Map<String, dynamic>,
  );

  // ------------------------------------------------------------- каталог

  Future<List<String>> categories() async =>
      (await _request('GET', '/categories', auth: false) as List)
          .cast<String>();

  Future<List<Product>> products({bool admin = false}) async {
    final list =
        await _request(
              'GET',
              admin ? '/admin/products' : '/products',
              auth: admin,
            )
            as List;
    return [for (final j in list) Product.fromJson(j as Map<String, dynamic>)];
  }

  Future<Product> createProduct(Product p) async => Product.fromJson(
    await _request('POST', '/admin/products', body: p.toJson())
        as Map<String, dynamic>,
  );

  Future<Product> updateProduct(Product p) async => Product.fromJson(
    await _request('PATCH', '/admin/products/${p.id}', body: p.toJson())
        as Map<String, dynamic>,
  );

  Future<void> deleteProduct(String id) =>
      _request('DELETE', '/admin/products/$id');

  Future<List<DeliverySlot>> slots() async {
    final list = await _request('GET', '/slots', auth: false) as List;
    return [
      for (final j in list) DeliverySlot.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<Quote> quote(List<CartLine> lines, {String? promoCode}) async {
    final j = await _request(
      'POST',
      '/cart/quote',
      auth: false,
      body: {
        'items': [
          for (final l in lines) {'productId': l.product.id, 'qty': l.qty},
        ],
        if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
      },
    );
    return Quote.fromJson(j as Map<String, dynamic>);
  }

  // ------------------------------------------------------------- заказы

  Future<List<Order>> orders({required bool admin}) async {
    final list =
        await _request(
              'GET',
              admin ? '/admin/orders' : '/orders',
              query: {'limit': admin ? '200' : '50'},
            )
            as List;
    return [
      for (final j in list)
        Order.fromJson(j as Map<String, dynamic>, isMine: !admin),
    ];
  }

  Future<Order> placeOrder({
    required List<CartLine> lines,
    required DeliverySlot slot,
    required String addressLine,
    String? promoCode,
    required String idempotencyKey,
  }) async {
    final j = await _request(
      'POST',
      '/orders',
      headers: {'Idempotency-Key': idempotencyKey},
      body: {
        'items': [
          for (final l in lines) {'productId': l.product.id, 'qty': l.qty},
        ],
        'slotId': slot.id,
        'slotDate': slot.date,
        'address': {'line': addressLine},
        if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
      },
    );
    return Order.fromJson(j as Map<String, dynamic>, isMine: true);
  }

  Future<void> cancelOrder(int number) =>
      _request('POST', '/orders/$number/cancel');

  Future<void> transitionOrder(int number, OrderStatus to) => _request(
    'POST',
    '/admin/orders/$number/transition',
    body: {'to': to.apiName},
  );

  // ------------------------------------------------------------- фото

  Future<UploadTicket> requestUpload(String contentType) async {
    final j =
        await _request(
              'POST',
              '/admin/uploads',
              body: {'contentType': contentType},
            )
            as Map<String, dynamic>;
    return UploadTicket(
      uploadUrl: j['uploadUrl'] as String,
      headers: (j['headers'] as Map).cast<String, String>(),
      imageUrl: j['imageUrl'] as String,
    );
  }

  /// Кладёт файл прямо в хранилище (S3) по временной ссылке.
  Future<void> putFile(UploadTicket t, List<int> bytes) async {
    try {
      final res = await _http
          .put(Uri.parse(t.uploadUrl), headers: t.headers, body: bytes)
          .timeout(const Duration(seconds: 60));
      if (res.statusCode >= 300) {
        throw ApiException(
          res.statusCode,
          'Не удалось загрузить фото (${res.statusCode})',
        );
      }
    } on TimeoutException {
      throw const ApiException(0, 'Фото не загрузилось: хранилище не отвечает');
    } on ApiException {
      rethrow;
    } on Exception {
      throw const ApiException(0, 'Фото не загрузилось: хранилище недоступно');
    }
  }
}
