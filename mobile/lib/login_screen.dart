import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/messenger.dart';
import 'core/theme.dart';
import 'state/providers.dart';
import 'widgets/common.dart';

/// Вход по номеру телефона и коду из SMS.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _devCode;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.length < 5) {
      setState(() => _error = 'Введите номер телефона');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dev = await ref.read(authProvider.notifier).requestCode(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _devCode = dev;
        _code.text = dev ?? ''; // заглушка SMS: в режиме разработки код подставляется сам
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Введите код из 6 цифр');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).verify(_phone.text.trim(), code);
      // Дальше RootGate сам покажет нужный экран.
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.set_meal_outlined,
                      size: 64, color: AppColors.teal),
                  const SizedBox(height: 16),
                  const Text(
                    'KrimFish',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Доставка свежих морепродуктов',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 16),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _phone,
                    enabled: !_codeSent && !_busy,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    onSubmitted: (_) => _sendCode(),
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      hintText: '+7 900 000-00-00',
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      onSubmitted: (_) => _verify(),
                      decoration: const InputDecoration(
                        labelText: 'Код из SMS',
                        counterText: '',
                      ),
                    ),
                    if (_devCode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: MutedText('Заглушка SMS (режим разработки): код $_devCode подставлен сам'),
                      ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_codeSent ? 'Войти' : 'Получить код'),
                  ),
                  if (_codeSent)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _error = null;
                                _devCode = null;
                              }),
                      child: const Text('Изменить номер'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
