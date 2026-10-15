import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/refresh.dart';
import '../widgets/order_widgets.dart';

class AdminOrderScreen extends ConsumerWidget {
  const AdminOrderScreen({super.key, required this.orderNumber});
  final int orderNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(ordersProvider);
    final i = all.indexWhere((o) => o.number == orderNumber);
    if (i == -1) {
      return Scaffold(
        appBar: AppBar(title: const Text('Заказ')),
        body: const EmptyState(
          icon: Icons.error_outline,
          title: 'Заказ не найден',
        ),
      );
    }
    final o = all[i];
    final action = o.status.actionLabel;

    return Scaffold(
      appBar: AppBar(title: Text('Заказ №${o.number}')),
      body: PullToRefresh(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        o.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      OrderStatusPill(o.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  MutedText(o.phone),
                  const SizedBox(height: 8),
                  Text(o.addressLine),
                  const SizedBox(height: 2),
                  MutedText('Доставка: ${o.slot.label}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OrderSummaryCard(order: o),
            const SizedBox(height: 16),
            const Text('Статус', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            OrderTimeline(status: o.status),
            if (o.status.canCancel) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  onPressed: () {
                    ref.read(ordersProvider.notifier).cancel(o.number);
                    showSnack(context, 'Заказ №${o.number} отменён');
                  },
                  child: const Text('Отменить заказ'),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              FilledButton(
                style: lightButtonStyle(),
                onPressed: () => showSnack(
                  context,
                  'Звонок появится после подключения телефонии',
                ),
                child: const Text('Позвонить'),
              ),
              if (action != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        ref.read(ordersProvider.notifier).advance(o.number),
                    child: Text(action),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
