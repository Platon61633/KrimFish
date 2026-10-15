import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// true, если Firebase подключён и push можно использовать (Android/iOS).
bool firebaseReady = false;

bool get _pushPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Запускается в main(). Если Firebase не настроен, приложение работает без уведомлений.
Future<void> initFirebase() async {
  if (!_pushPlatform) return;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase не настроен, уведомления выключены: $e');
  }
}

String get pushOs =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

/// При выходе забываем токен устройства, чтобы следующий пользователь получил новый.
Future<void> forgetPushToken() async {
  if (!firebaseReady) return;
  try {
    await FirebaseMessaging.instance.deleteToken();
  } catch (e) {
    debugPrint('Не удалось удалить push-токен: $e');
  }
}
