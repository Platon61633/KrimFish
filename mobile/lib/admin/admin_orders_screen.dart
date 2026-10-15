import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'admin_order_screen.dart';

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  /// null — показать все заказы.
  static const List<OrderStatus?> _filters = [
    null,
    OrderStatus.newOrder,
    OrderStatus.preparing,
    OrderStatus.onTheWay,
    OrderStatus.delivered,
  ];
  static const _names = ['Все', 'Новые', 'Собираются', 'В пути', 'Доставлены'];

  int _f = 1; // открываем на «Новые»

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider);
    int count(OrderStatus? s) =>
        s == null ? orders.length : orders.where((o) => o.status == s).length;
    final shown = _filters[_f] == null
        ? orders
        : orders.where((o) => o.status == _filters[_f]).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Заказы')),
      body: Column(
        children: [
          ChipsRow(
            labels: [
              for (var i = 0; i < _filters.length; i++)
                '${_names[i]} (${count(_filters[i])})',
            ],
            selected: _f,
            onSelected: (i) => setState(() => _f = i),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: shown.isEmpty
                ? const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Здесь пока пусто',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _OrderCard(order: shown[i]),
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
