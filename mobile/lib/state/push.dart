import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/messenger.dart';
import '../data/firebase_setup.dart';
import 'providers.dart';

/// Регистрирует устройство для push после входа и реагирует на сообщения,
/// пока приложение открыто. В фоне уведомления показывает сама система.
class PushNotifier extends Notifier<void> {
  @override
  void build() {
    if (ref.watch(sessionUserProvider) == null || !firebaseReady) return;

    final messaging = FirebaseMessaging.instance;
    final subs = <StreamSubscription<Object?>>[
      FirebaseMessaging.onMessage.listen(_onMessage),
      messaging.onTokenRefresh.listen(_send),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    Future.microtask(_register);
  }

  Future<void> _register() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await _send(token);
    } catch (e) {
      debugPrint('Push: не удалось зарегистрировать устройство: $e');
    }
  }

  Future<void> _send(String token) async {
    try {
      await ref.read(apiProvider).registerDevice(token, pushOs);
    } catch (e) {
      debugPrint('Push: сервер не принял токен: $e');
    }
  }

  void _onMessage(RemoteMessage message) {
    final n = message.notification;
    if (n != null) {
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text([n.title, n.body].whereType<String>().join('\n')),
          ),
        );
    }
    // Статус или список заказов изменился — сразу обновляем.
    ref.read(ordersProvider.notifier).load(silent: true);
  }
}

final pushProvider = NotifierProvider<PushNotifier, void>(PushNotifier.new);
