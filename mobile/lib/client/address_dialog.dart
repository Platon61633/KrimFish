import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// Диалог смены адреса доставки. Сохраняется на устройстве и подставляется в корзину.
Future<void> editAddress(BuildContext context, WidgetRef ref) async {
  final current = ref.read(profileProvider).address;
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _AddressDialog(initial: current),
  );
  final trimmed = result?.trim() ?? '';
  if (trimmed.length < 3 || trimmed == current) return;
  await ref.read(addressProvider.notifier).set(trimmed);
}

/// Контроллер живёт внутри диалога и освобождается вместе с ним.
class _AddressDialog extends StatefulWidget {
  const _AddressDialog({required this.initial});
  final String initial;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    final text = _ctl.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Введите адрес: улица, дом, квартира');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Адрес доставки'),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        maxLength: 200,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Улица, дом, квартира',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}
