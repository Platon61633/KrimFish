import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../widgets/common.dart';
import 'product_screen.dart';

void openProduct(BuildContext context, Product p) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ProductScreen(productId: p.id)),
  );
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(8),
      onTap: () => openProduct(context, product),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductImage(product: product, height: 96),
          const SizedBox(height: 8),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          MutedText(product.category),
          const Spacer(),
          Text(
            product.inStock ? product.priceLabel : 'Нет в наличии',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: product.inStock ? AppColors.ink : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
