import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/order_widgets.dart';
import 'profile_button.dart';

/// Вкладка «Заказ»: последний заказ клиента. С [orderNumber] — конкретный заказ.
class TrackScreen extends ConsumerWidget {
  const TrackScreen({super.key, this.orderNumber});
  final int? orderNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pushed = orderNumber != null;
    final Order? order;
    if (pushed) {
      final all = ref.watch(ordersProvider);
      final i = all.indexWhere((o) => o.number == orderNumber);
      order = i == -1 ? null : all[i];
    } else {
      final mine = ref.watch(myOrdersProvider);
      order = mine.isEmpty ? null : mine.first;
    }

    if (order == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Заказ'),
          actions: pushed ? null : const [ProfileButton(), SizedBox(width: 12)],
        ),
        body: EmptyState(
          icon: Icons.local_shipping_outlined,
          title: 'Пока нет заказов',
          text: 'Оформите первый заказ, и он появится здесь',
          action: FilledButton(
            onPressed: () => ref.read(clientTabProvider.notifier).set(1),
            child: const Text('В каталог'),
          ),
        ),
      );
    }

    final o = order;
    final title = switch (o.status) {
      OrderStatus.newOrder => 'Заказ принят',
      OrderStatus.preparing => 'Собираем заказ',
      OrderStatus.onTheWay => 'Заказ в пути',
      OrderStatus.delivered => 'Заказ доставлен',
      OrderStatus.canceled => 'Заказ отменён',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: pushed ? null : const [ProfileButton(), SizedBox(width: 12)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          MutedText('Заказ №${o.number}'),
          if (o.status.isActiveOrder) ...[
            const SizedBox(height: 4),
            Text(
              'Доставка: ${o.slot.label}',
              style: const TextStyle(
                color: AppColors.teal,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
          const SizedBox(height: 16),
          OrderTimeline(status: o.status),
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.place_outlined, color: AppColors.teal),
                const SizedBox(width: 12),
                Expanded(child: Text(o.addressLine)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OrderSummaryCard(order: o),
          if (o.status.isActiveOrder) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: lightButtonStyle(),
                    onPressed: () => showSnack(
                      context,
                      'Звонок появится после подключения телефонии',
                    ),
                    child: const Text('Позвонить'),
                  ),
                ),
                if (o.status.canCancel) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: lightButtonStyle().copyWith(
                        foregroundColor:
                            const WidgetStatePropertyAll(AppColors.danger),
                      ),
                      onPressed: () {
                        ref.read(ordersProvider.notifier).cancel(o.number);
                        showSnack(context, 'Заказ №${o.number} отменён');
                      },
                      child: const Text('Отменить'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

extension on OrderStatus {
  bool get isActiveOrder =>
      this != OrderStatus.delivered && this != OrderStatus.canceled;
}
