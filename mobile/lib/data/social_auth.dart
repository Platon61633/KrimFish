import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api.dart';

/// Вход через Google и VK. Сами ключи приложение берёт у сервера (GET /auth/providers).

class VkAuthResult {
  const VkAuthResult({
    required this.code,
    required this.codeVerifier,
    required this.deviceId,
    required this.state,
    required this.redirectUri,
  });
  final String code;
  final String codeVerifier;
  final String deviceId;
  final String state;
  final String redirectUri;
}

String _randomString(int length) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final rnd = Random.secure();
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}

/// idToken Google или null, если пользователь закрыл окно выбора аккаунта.
Future<String?> googleIdToken(String serverClientId) async {
  final google = GoogleSignIn(
    scopes: const ['email'],
    serverClientId: serverClientId,
  );
  try {
    // Чтобы каждый раз можно было выбрать другой аккаунт.
    await google.signOut();
    final account = await google.signIn();
    if (account == null) return null;
    final token = (await account.authentication).idToken;
    if (token == null) {
      throw const ApiException(0, 'Google не вернул данные для входа');
    }
    return token;
  } on PlatformException catch (e) {
    throw ApiException(
      0,
      'Не удалось войти через Google (${e.code}): ${e.message ?? ''}. '
      'Проверьте SHA-1 ключа и идентификаторы в Google Cloud.',
    );
  }
}

/// Открывает окно входа VK ID (OAuth + PKCE) и возвращает код для сервера.
/// null — пользователь отменил вход.
Future<VkAuthResult?> vkAuthorize({
  required String clientId,
  required String redirectUri,
}) async {
  final verifier = _randomString(64);
  final challenge = base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');
  final state = _randomString(32);

  final url = Uri.https('id.vk.com', '/authorize', {
    'response_type': 'code',
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'state': state,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
  });

  final String callback;
  try {
    callback = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: Uri.parse(redirectUri).scheme,
    );
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') return null;
    throw ApiException(0, 'Не удалось открыть вход через VK (${e.code})');
  }

  final params = Uri.parse(callback).queryParameters;
  if (params['error'] != null) {
    throw ApiException(0, 'VK отклонил вход: ${params['error']}');
  }
  final code = params['code'];
  final deviceId = params['device_id'];
  if (params['state'] != state || code == null || deviceId == null) {
    throw const ApiException(0, 'VK вернул неполный ответ, попробуйте ещё раз');
  }
  return VkAuthResult(
    code: code,
    codeVerifier: verifier,
    deviceId: deviceId,
    state: state,
    redirectUri: redirectUri,
  );
}

/// При выходе из аккаунта забываем выбранный Google-аккаунт.
Future<void> socialSignOut() async {
  try {
    await GoogleSignIn().signOut();
  } catch (_) {}
}
