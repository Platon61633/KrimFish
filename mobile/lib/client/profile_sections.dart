import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'address_dialog.dart';

/// Телефон поддержки: замените на настоящий перед выпуском приложения.
const kSupportPhone = '+7 (800) 555-35-35';
const kSupportHours = 'Ежедневно с 9:00 до 21:00';
const kAppVersion = '1.0.0';

Widget _page(BuildContext context, String title, List<Widget> children) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: children,
    ),
  );
}

/// Адрес доставки: хранится на устройстве и подставляется в корзину.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(profileProvider).address;
    return _page(context, 'Адреса доставки', [
      AppCard(
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, color: AppColors.teal),
            const SizedBox(width: 12),
            Expanded(
              child: address.isEmpty
                  ? const MutedText('Адрес пока не указан')
                  : Text(
                      address,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => editAddress(context, ref),
        child: Text(address.isEmpty ? 'Добавить адрес' : 'Изменить адрес'),
      ),
      const SizedBox(height: 12),
      const MutedText(
        'Этот адрес подставляется при оформлении заказа. '
        'Перед заказом его всегда можно поменять в корзине.',
      ),
    ]);
  }
}

/// Включение и выключение push-уведомлений о статусах заказов.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(notificationsProvider);
    return _page(context, 'Уведомления', [
      MenuCard(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: (v) => ref.read(notificationsProvider.notifier).set(v),
            title: const Text(
              'Статусы заказов',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Сообщим, когда заказ собирают, везут, доставили или отменили',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const MutedText(
        'Если уведомления не приходят, проверьте, что они разрешены '
        'для приложения в настройках телефона.',
      ),
    ]);
  }
}

/// Контакты поддержки.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Поддержка', [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MutedText('Телефон поддержки'),
            const SizedBox(height: 4),
            const Text(
              kSupportPhone,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const MutedText(kSupportHours),
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () async {
          await Clipboard.setData(const ClipboardData(text: kSupportPhone));
          if (context.mounted) showSnack(context, 'Номер скопирован');
        },
        icon: const Icon(Icons.copy_outlined),
        label: const Text('Скопировать номер'),
      ),
      const SizedBox(height: 12),
      const MutedText(
        'Позвоните нам, если нужно уточнить заказ, изменить время доставки '
        'или сообщить о проблеме.',
      ),
    ]);
  }
}

/// Информация о сервисе.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _page(context, 'О сервисе', [
      const SizedBox(height: 12),
      const Center(child: AppLogo(size: 96)),
      const SizedBox(height: 12),
      const Center(
        child: Text(
          'Карасик',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
      ),
      const Center(child: MutedText('Версия $kAppVersion')),
      const SizedBox(height: 20),
      const AppCard(
        child: Text(
          'Карасик — доставка свежей рыбы и морепродуктов. '
          'Выбирайте товары в каталоге, указывайте вес и удобное время, '
          'а мы бережно привезём заказ по вашему адресу.\n\n'
          'Следить за статусом заказа можно прямо в приложении, '
          'а о каждом изменении мы сообщим уведомлением.',
          style: TextStyle(fontSize: 15, height: 1.4),
        ),
      ),
    ]);
  }
}
