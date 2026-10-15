import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  int? _qty;

  @override
  Widget build(BuildContext context) {
    final product = ref
        .watch(catalogProvider)
        .firstWhere((p) => p.id == widget.productId);

    // Выбранное количество должно оставаться допустимым при изменении остатка.
    var qty = _qty ?? product.defaultQty;
    if (product.unit == Unit.kg) {
      final steps = product.selectableQty;
      if (!steps.contains(qty)) qty = steps.isEmpty ? 0 : steps.first;
    } else {
      if (qty > product.stock) qty = product.stock;
      if (qty < 1 && product.inStock) qty = 1;
    }

    return Scaffold(
      body: Column(
        children: [
          Stack(
            children: [
              ProductImage(product: product, height: 300, radius: 0),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: IconButton.filled(
                  tooltip: 'Назад',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size(44, 44),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MutedText('${product.category} · ${product.priceLabel}'),
                  const SizedBox(height: 20),
                  if (!product.inStock)
                    const Pill('Нет в наличии', AppColors.newBg)
                  else if (product.unit == Unit.kg)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in product.selectableQty)
                          AppChoiceChip(
                            label: formatWeight(s),
                            selected: s == qty,
                            onSelected: () => setState(() => _qty = s),
                          ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        const Text(
                          'Количество',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        QtyStepper(
                          label: '$qty',
                          onMinus:
                              qty > 1 ? () => setState(() => _qty = qty - 1) : null,
                          onPlus: qty < product.stock
                              ? () => setState(() => _qty = qty + 1)
                              : null,
                        ),
                      ],
                    ),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    AppCard(
                      child: Text(
                        product.description,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(
                        child: AppCard(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MutedText('Хранение'),
                              Text(
                                '0…+2 °C',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: AppCard(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MutedText('Доставка'),
                              Text(
                                'от 90 мин',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Text(
                    formatKop(product.lineKop(qty)),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: product.inStock && qty > 0
                          ? () {
                              final messenger = ScaffoldMessenger.of(context);
                              ref.read(cartProvider.notifier).add(product, qty);
                              Navigator.of(context).pop();
                              messenger
                                ..hideCurrentSnackBar()
                                ..showSnackBar(const SnackBar(
                                    content: Text('Добавлено в корзину')));
                            }
                          : null,
                      child: const Text('В корзину'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
