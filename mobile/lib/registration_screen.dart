import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'widgets/common.dart';

/// Шаг после входа: новый клиент (например, через VK без имени) называет имя.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    await ref.read(authProvider.notifier).updateName(name);
    // После сохранения RootGate сам откроет приложение.
    if (mounted) setState(() => _busy = false);
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
                  const Center(child: AppLogo(size: 80)),
                  const SizedBox(height: 16),
                  const Text(
                    'Давайте познакомимся',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: MutedText('Так курьер будет к вам обращаться'),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      labelText: 'Как к вам обращаться',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Продолжить'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => ref.read(nameSkipProvider.notifier).skip(),
                    child: const Text('Пропустить'),
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
