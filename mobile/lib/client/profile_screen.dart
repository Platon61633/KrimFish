import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/refresh.dart';
import 'orders_screen.dart';

Future<void> _editName(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(initial: current),
  );
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == current) return;
  await ref.read(authProvider.notifier).updateName(trimmed);
}

/// Контроллер живёт внутри диалога и освобождается вместе с ним
/// (иначе при закрытии диалога возникает ошибка `_dependents.isEmpty`).
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ваше имя'),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Как к вам обращаться'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctl.text),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    Widget row(String title, VoidCallback onTap) => ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
      onTap: onTap,
    );

    void soon() => showSnack(context, 'Этот раздел появится позже');

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: PullToRefresh(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.mist,
                  child: Icon(Icons.person, size: 36, color: AppColors.teal),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isEmpty ? 'Без имени' : profile.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      MutedText(
                        profile.phone.isNotEmpty ? profile.phone : profile.email,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Бонусы',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        Text(
                          '${profile.bonus} баллов',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: lightButtonStyle(height: 44),
                    onPressed: soon,
                    child: const Text('История'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MenuCard(
              children: [
                row(
                  'Мои заказы',
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OrdersScreen(),
                    ),
                  ),
                ),
                row(
                  'Изменить имя',
                  () => _editName(context, ref, profile.name),
                ),
                row('Адреса доставки', soon),
                row('Способы оплаты', soon),
                row('Уведомления', soon),
              ],
            ),
            const SizedBox(height: 16),
            MenuCard(
              children: [row('Поддержка', soon), row('О сервисе', soon)],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  ref.read(clientTabProvider.notifier).set(0);
                  ref.read(authProvider.notifier).logout();
                },
                child: const Text('Выйти'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
