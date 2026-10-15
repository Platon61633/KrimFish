import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _weightCtrl = TextEditingController();
  String? _weightError;

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  /// Ручной ввод веса в граммах: кратно 100 г, от 300 г, не больше остатка.
  void _onWeightTyped(Product product, String text) {
    if (text.isEmpty) {
      setState(() {
        _weightError = null;
        _qty = null;
      });
      return;
    }
    final g = int.tryParse(text) ?? 0;
    String? error;
    if (g < kMinWeight) {
      error = 'Минимум $kMinWeight г';
    } else if (g % kWeightStep != 0) {
      error = 'Вес должен быть кратен $kWeightStep г';
    } else if (g > product.maxQty) {
      error = 'В наличии только ${formatWeight(product.maxQty)}';
    }
    setState(() {
      _weightError = error;
      // Пока в поле ошибка, выбранный вес считается неподходящим (кнопка неактивна).
      _qty = error == null ? g : -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = ref
        .watch(catalogProvider)
        .firstWhere((p) => p.id == widget.productId);

    // Выбранное количество должно оставаться допустимым при изменении остатка.
    var qty = _qty ?? product.defaultQty;
    final typedInvalid = _weightError != null;
    if (product.unit == Unit.kg) {
      if (typedInvalid) {
        qty = 0;
      } else if (!product.isValidQty(qty)) {
        qty = product.defaultQty;
      }
    } else {
      if (qty > product.stock) qty = product.stock;
      if (qty < 1 && product.inStock) qty = 1;
    }

    return Scaffold(
      body: Column(
        children: [
          Stack(
            children: [
              ProductImage(
                product: product,
                height: 300,
                radius: 0,
                fit: BoxFit.contain, // фото целиком, без обрезки
                alignment: Alignment.bottomCenter, // прижать к низу рамки
              ),
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
                  else if (!product.canBuy)
                    Pill(
                      'Осталось меньше $kMinWeight г',
                      AppColors.newBg,
                    )
                  else if (product.unit == Unit.kg)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in product.selectableQty)
                              AppChoiceChip(
                                label: formatWeight(s),
                                selected: !typedInvalid &&
                                    _weightCtrl.text.isEmpty &&
                                    s == qty,
                                onSelected: () => setState(() {
                                  _weightCtrl.clear();
                                  _weightError = null;
                                  _qty = s;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _weightCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          onChanged: (t) => _onWeightTyped(product, t),
                          decoration: InputDecoration(
                            labelText: 'Свой вес, г',
                            hintText: 'Например, 700',
                            helperText:
                                'Кратно $kWeightStep г, минимум $kMinWeight г',
                            errorText: _weightError,
                            suffixText: 'г',
                          ),
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
                          onMinus: qty > 1
                              ? () => setState(() => _qty = qty - 1)
                              : null,
                          onPlus: () {
                            if (qty >= product.stock) {
                              showSnack(context, product.limitMessage);
                              return;
                            }
                            setState(() => _qty = qty + 1);
                          },
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
                      onPressed: product.canBuy && qty > 0
                          ? () {
                              final messenger = ScaffoldMessenger.of(context);
                              ref.read(cartProvider.notifier).add(product, qty);
                              Navigator.of(context).pop();
                              messenger
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('Добавлено в корзину'),
                                  ),
                                );
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
