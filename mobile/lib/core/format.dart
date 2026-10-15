/// Деньги хранятся в копейках (целые числа), чтобы не копились ошибки округления.
String _group(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

String formatKop(int kop) {
  final neg = kop < 0;
  final v = kop.abs();
  final rub = v ~/ 100;
  final k = v % 100;
  final tail = k == 0 ? '' : ',${k.toString().padLeft(2, '0')}';
  return '${neg ? '−' : ''}${_group(rub)}$tail ₽';
}

String formatWeight(int grams) {
  if (grams < 1000) return '$grams г';
  if (grams % 1000 == 0) return '${grams ~/ 1000} кг';
  var s = (grams / 1000).toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
  return '$s кг';
}

double? parseNumber(String input) {
  final t = input.trim().replaceAll(',', '.').replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;
  final d = double.tryParse(t);
  if (d == null || d < 0) return null;
  return d;
}

/// Рубли из поля ввода → копейки.
int? parseKop(String input) {
  final d = parseNumber(input);
  if (d == null) return null;
  return (d * 100).round();
}

/// Для подстановки в поле ввода: 1290 → "1290", 12.5 → "12,5".
String numberToInput(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  var s = value.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
  return s;
}
