import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'track_screen.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои заказы')),
      body: orders.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Заказов пока нет',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final o = orders[i];
                return AppCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TrackScreen(orderNumber: o.number),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '№${o.number}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          OrderStatusPill(o.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(o.items.map((e) => e.name).join(', ')),
                      const SizedBox(height: 4),
                      MutedText(
                        '${o.slot.label} · ${formatKop(o.totalKop)}',
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
