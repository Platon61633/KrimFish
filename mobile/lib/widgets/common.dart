import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme.dart';
import '../data/models.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Белая карточка со списком строк и разделителями.
class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, color: AppColors.line));
      rows.add(children[i]);
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: rows),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, this.background, {super.key});
  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

Color orderStatusColor(OrderStatus s) => switch (s) {
  OrderStatus.newOrder => AppColors.newBg,
  OrderStatus.preparing => AppColors.warnBg,
  OrderStatus.onTheWay => AppColors.mist,
  OrderStatus.delivered => AppColors.okBg,
  OrderStatus.canceled => AppColors.line,
};

Color productStatusColor(ProductStatus s) => switch (s) {
  ProductStatus.onSale => AppColors.okBg,
  ProductStatus.low => AppColors.warnBg,
  ProductStatus.outOfStock => AppColors.newBg,
  ProductStatus.hidden => AppColors.line,
};

class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill(this.status, {super.key});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) =>
      Pill(status.label, orderStatusColor(status));
}

/// Пока вместо фото — заглушка. Когда появится загрузка в S3, заработает imageUrl.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.product,
    this.height = 96,
    this.width = double.infinity,
    this.radius = 12,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final Product product;
  final double height;
  final double width;
  final double radius;

  /// cover — заполнить рамку с обрезкой (в списках); contain — показать фото целиком.
  final BoxFit fit;

  /// Положение фото внутри рамки (например, bottomCenter — прижать к низу).
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppColors.mist,
      child: Center(
        child: Icon(
          Icons.set_meal_outlined,
          color: AppColors.teal,
          size: height > 120 ? 64 : 30,
        ),
      ),
    );
    final url = product.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: width,
        child: url == null
            ? fallback
            : ColoredBox(
                color: AppColors.mist,
                child: Image.network(
                  url,
                  fit: fit,
                  alignment: alignment,
                  width: width,
                  height: height,
                  errorBuilder: (_, _, _) => fallback,
                ),
              ),
      ),
    );
  }
}

class ChipsRow extends StatelessWidget {
  const ChipsRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppChoiceChip(
                label: labels[i],
                selected: i == selected,
                onSelected: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.ink,
      backgroundColor: Colors.white,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.ink,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.label,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onMinus,
          tooltip: 'Меньше',
          icon: const Icon(Icons.remove_circle_outline),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 52),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          tooltip: 'Больше',
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(
                text!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13));
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Логотип Карасика (lib/assets/logo.svg).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'lib/assets/logo.svg',
      width: size,
      height: size,
      semanticsLabel: 'Карасик',
    );
  }
}
