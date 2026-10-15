import 'package:flutter/material.dart';

import '../data/api.dart';

/// Позволяет показывать сообщения об ошибках из любого места (в том числе из провайдеров).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

String errorText(Object e) =>
    e is ApiException ? e.message : 'Что-то пошло не так. Попробуйте ещё раз.';

void reportError(Object e) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorText(e))));
}
