import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';

/// Шкала статусов заказа: принят → собираем → в пути → доставлен.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.status});
  final OrderStatus status;

  static const _labels = [
    'Заказ принят',
    'Собираем заказ',
    'Заказ в пути',
    'Доставлен',
  ];

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.canceled) {
      return const AppCard(
        child: Text(
          'Заказ отменён',
          style: TextStyle(
            color: AppColors.danger,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      );
    }
    final cur = status.step;
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(
                    i < cur
                        ? Icons.check_circle
                        : i == cur
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                    size: 22,
                    color: i <= cur ? AppColors.teal : AppColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: i == cur ? FontWeight.w800 : FontWeight.w600,
                      color: i <= cur ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 18 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold ? style : const TextStyle(color: AppColors.muted),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Состав заказа и итоги.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({super.key, required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        MutedText(it.qtyLabel),
                      ],
                    ),
                  ),
                  Text(
                    formatKop(it.lineKop),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          const Divider(height: 20, color: AppColors.line),
          _KeyValue('Товары', formatKop(order.itemsKop)),
          if (order.discountKop > 0)
            _KeyValue('Скидка', '−${formatKop(order.discountKop)}'),
          _KeyValue('Доставка', formatKop(order.deliveryKop)),
          const SizedBox(height: 4),
          _KeyValue('Итого', formatKop(order.totalKop), bold: true),
        ],
      ),
    );
  }
}
