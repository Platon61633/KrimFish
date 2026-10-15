import 'server_address.dart';

/// Адрес сервера берётся из `server_address.dart`.
/// Для разового запуска можно переопределить:
///   flutter run --dart-define=API_URL=http://192.168.1.10:3000
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment('API_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  return 'http://$kServerHost:$kServerPort';
}
