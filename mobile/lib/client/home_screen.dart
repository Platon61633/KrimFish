import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/refresh.dart';
import '../widgets/order_widgets.dart';
import 'address_dialog.dart';
import 'product_card.dart';
import 'profile_button.dart';
import 'track_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _cat = 0;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    // Заказы в работе показываем на главном экране, пока они не доставлены или отменены.
    final activeOrders = ref
        .watch(myOrdersProvider)
        .where(
          (o) =>
              o.status != OrderStatus.delivered &&
              o.status != OrderStatus.canceled,
        )
        .toList();
    final products = ref
        .watch(catalogProvider)
        .where((p) => p.isActive)
        .toList();
    final cats = [
      'Все',
      ...{for (final p in products) p.category},
    ];
    final sel = _cat < cats.length ? _cat : 0;
    final shown = sel == 0
        ? products
        : products.where((p) => p.category == cats[sel]).toList();

    return SafeArea(
      bottom: false,
      child: PullToRefresh(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => editAddress(context, ref),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const MutedText('Доставка на адрес'),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      profile.address.isEmpty
                                          ? 'Укажите адрес'
                                          : profile.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: AppColors.teal,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const ProfileButton(),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  onTap: () => ref.read(clientTabProvider.notifier).set(1),
                  child: const Row(
                    children: [
                      Icon(Icons.search, color: AppColors.muted),
                      SizedBox(width: 12),
                      MutedText('Найти креветки, лосось, устрицы…'),
                    ],
                  ),
                ),
              ),
            ),
            if (activeOrders.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    children: [
                      for (final o in activeOrders) _ActiveOrderCard(order: o),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: ChipsRow(
                labels: cats,
                selected: sel,
                onSelected: (i) => setState(() => _cat = i),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Улов сегодня',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Свежее — на столе за 90 минут',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: shown.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: MutedText('В этой категории пусто'),
                        ),
                      ),
                    )
                  : SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 232,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ProductCard(product: shown[i]),
                        childCount: shown.length,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка заказа в работе: статус, время доставки и сумма. По нажатию — подробности.
class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrackScreen(orderNumber: order.number),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Заказ №${order.number}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                OrderStatusPill(order.status),
              ],
            ),
            const SizedBox(height: 4),
            MutedText(
              'Доставка: ${order.slot.label} · ${formatKop(order.totalKop)}',
            ),
            const SizedBox(height: 12),
            OrderTimeline(status: order.status),
          ],
        ),
      ),
    );
  }
}
