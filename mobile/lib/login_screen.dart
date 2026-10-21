import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/messenger.dart';
import 'core/theme.dart';
import 'data/api.dart';
import 'data/social_auth.dart';
import 'state/providers.dart';
import 'widgets/common.dart';

/// Вход и регистрация: email + пароль, а также Google и VK (если включены на сервере).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  PendingEmail? _pending;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Выполняет вход и показывает ошибку. После успеха RootGate сам откроет нужный экран.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      setState(() => _error = 'Введите email, например name@mail.ru');
      return;
    }
    if (_register && password.length < 8) {
      setState(() => _error = 'Пароль должен быть не короче 8 символов');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Введите пароль');
      return;
    }
    final auth = ref.read(authProvider.notifier);
    await _run(() async {
      if (_register) {
        final pending = await auth.register(email, password, _name.text.trim());
        if (mounted) setState(() => _pending = pending);
        return;
      }
      try {
        await auth.loginWithPassword(email, password);
      } on ApiException catch (e) {
        if (e.code != 'EMAIL_NOT_VERIFIED') rethrow;
        // Почта не подтверждена: высылаем код заново и открываем ввод кода.
        PendingEmail pending;
        try {
          pending = await auth.resendCode(email);
        } on ApiException catch (r) {
          if (r.status != 429) rethrow;
          pending = PendingEmail(email: email, resendAfter: 60);
        }
        if (mounted) setState(() => _pending = pending);
      }
    });
  }

  Future<void> _google(AuthProviders p) => _run(() async {
    final token = await googleIdToken(p.googleClientId!);
    if (token == null) return; // окно закрыли
    await ref.read(authProvider.notifier).loginWithGoogle(token);
  });

  Future<void> _vk(AuthProviders p) => _run(() async {
    final result = await vkAuthorize(
      clientId: p.vkClientId!,
      redirectUri: p.vkRedirectUri!,
    );
    if (result == null) return;
    await ref.read(authProvider.notifier).loginWithVk(result);
  });

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (pending != null) {
      return _VerifyEmailScreen(
        pending: pending,
        onBack: () => setState(() => _pending = null),
      );
    }
    final providers =
        ref.watch(authProvidersProvider).valueOrNull ?? AuthProviders.none;
    final social = providers.hasGoogle || providers.hasVk;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!keyboard) ...[
                      const Center(child: AppLogo(size: 96)),
                      const SizedBox(height: 16),
                      const Text(
                        'KrimFish',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Доставка свежих морепродуктов',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 16),
                      ),
                      const SizedBox(height: 32),
                    ],
                    if (_register) ...[
                      TextField(
                        controller: _name,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.givenName],
                        decoration: const InputDecoration(
                          labelText: 'Имя',
                          hintText: 'Как к вам обращаться',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      textInputAction: TextInputAction.done,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      obscureText: !_showPassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        helperText: _register ? 'Не короче 8 символов' : null,
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Скрыть пароль'
                              : 'Показать пароль',
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
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
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Зарегистрироваться' : 'Войти'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _error = null;
                            }),
                      child: Text(
                        _register
                            ? 'Уже есть аккаунт? Войти'
                            : 'Нет аккаунта? Зарегистрироваться',
                      ),
                    ),
                    if (social) ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: MutedText('или'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (providers.hasGoogle)
                        OutlinedButton(
                          onPressed: _busy ? null : () => _google(providers),
                          child: const Text('Продолжить через Google'),
                        ),
                      if (providers.hasGoogle && providers.hasVk)
                        const SizedBox(height: 12),
                      if (providers.hasVk)
                        OutlinedButton(
                          onPressed: _busy ? null : () => _vk(providers),
                          child: const Text('Продолжить через VK'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ввод 6-значного кода из письма. После успеха RootGate сам откроет приложение.
class _VerifyEmailScreen extends ConsumerStatefulWidget {
  const _VerifyEmailScreen({required this.pending, required this.onBack});

  final PendingEmail pending;
  final VoidCallback onBack;

  @override
  ConsumerState<_VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<_VerifyEmailScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  late final String _email = widget.pending.email;
  int _left = 0;
  bool _busy = false;
  String? _error;
  String? _devCode;

  @override
  void initState() {
    super.initState();
    _startCooldown(widget.pending);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(PendingEmail p) {
    _devCode = p.devCode;
    _left = p.resendAfter;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Введите 6 цифр из письма');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).verifyEmail(_email, code);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ref.read(authProvider.notifier).resendCode(_email);
      if (mounted) {
        _code.clear();
        setState(() => _startCooldown(p));
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _busy ? null : widget.onBack),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 64,
                    color: AppColors.teal,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Подтвердите почту',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Мы отправили 6-значный код на $_email. '
                    'Проверьте также папку «Спам».',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (_devCode != null) ...[
                    const SizedBox(height: 12),
                    ActionChip(
                      avatar: const Icon(Icons.bug_report_outlined, size: 18),
                      label: Text('Тестовый режим: код $_devCode'),
                      onPressed: () => _code.text = _devCode!,
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 28, letterSpacing: 8),
                    onChanged: (v) {
                      if (v.length == 6 && !_busy) _verify();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Код из письма',
                      counterText: '',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Подтвердить'),
                  ),
                  TextButton(
                    onPressed: _busy || _left > 0 ? null : _resend,
                    child: Text(
                      _left > 0
                          ? 'Отправить код ещё раз через $_left с'
                          : 'Отправить код ещё раз',
                    ),
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
