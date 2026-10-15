import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/refresh.dart';

class AdminMoreScreen extends ConsumerWidget {
  const AdminMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    final now = DateTime.now();
    final today = orders.where(
      (o) =>
          o.createdAt.year == now.year &&
          o.createdAt.month == now.month &&
          o.createdAt.day == now.day,
    );

    final newCount = orders
        .where((o) => o.status == OrderStatus.newOrder)
        .length;
    final onTheWay = orders
        .where((o) => o.status == OrderStatus.onTheWay)
        .length;
    final revenue = today
        .where((o) => o.status != OrderStatus.canceled)
        .fold<int>(0, (s, o) => s + o.totalKop);

    Widget stat(String label, String value) => Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MutedText(label),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: PullToRefresh(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                stat('Новые', '$newCount'),
                const SizedBox(width: 12),
                stat('В доставке', '$onTheWay'),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [stat('Выручка за день', formatKop(revenue))]),
            const SizedBox(height: 16),
            MenuCard(
              children: [
                ListTile(
                  title: const Text(
                    'Промокоды',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.muted,
                  ),
                  onTap: () => showSnack(context, 'Этот раздел появится позже'),
                ),
                ListTile(
                  title: const Text(
                    'Слоты доставки',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.muted,
                  ),
                  onTap: () => showSnack(context, 'Этот раздел появится позже'),
                ),
                ListTile(
                  title: const Text(
                    'Аналитика',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.muted,
                  ),
                  onTap: () => showSnack(context, 'Этот раздел появится позже'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () {
                  ref.read(adminTabProvider.notifier).set(0);
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
