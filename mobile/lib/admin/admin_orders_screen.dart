import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/refresh.dart';
import 'admin_order_screen.dart';

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  /// Вкладки: «Все», «Активные» (новые, собираются, в пути) и по одному статусу.
  static const _names = [
    'Все',
    'Активные',
    'Новые',
    'Собираются',
    'В пути',
    'Доставлены',
  ];

  static bool _matches(int tab, OrderStatus s) => switch (tab) {
    0 => true,
    1 =>
      s == OrderStatus.newOrder ||
          s == OrderStatus.preparing ||
          s == OrderStatus.onTheWay,
    2 => s == OrderStatus.newOrder,
    3 => s == OrderStatus.preparing,
    4 => s == OrderStatus.onTheWay,
    _ => s == OrderStatus.delivered,
  };

  int _f = 0; // открываем на «Все»

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider);
    int count(int tab) => orders.where((o) => _matches(tab, o.status)).length;
    final shown = orders.where((o) => _matches(_f, o.status)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Заказы')),
      body: Column(
        children: [
          ChipsRow(
            labels: [
              for (var i = 0; i < _names.length; i++)
                '${_names[i]} (${count(i)})',
            ],
            selected: _f,
            onSelected: (i) => setState(() => _f = i),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PullToRefresh(
              child: shown.isEmpty
                  ? ScrollableEmpty(
                      child: const EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'Здесь пока пусто',
                      ),
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),

                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _OrderCard(order: shown[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = order.status.actionLabel;
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AdminOrderScreen(orderNumber: order.number),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '№${order.number}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              OrderStatusPill(order.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(order.items.map((e) => e.name).join(', ')),
          const SizedBox(height: 2),
          MutedText('${order.slot.label} · ${order.customerName}'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatKop(order.totalKop),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              if (action != null)
                FilledButton(
                  style: darkButtonStyle(),
                  onPressed: () =>
                      ref.read(ordersProvider.notifier).advance(order.number),
                  child: Text(action),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
