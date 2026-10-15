import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../widgets/common.dart';
import 'product_card.dart';
import 'profile_button.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String _query = '';
  int _cat = 0;

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(catalogProvider).where((p) => p.isActive).toList();
    final cats = ['Все', ...{for (final p in products) p.category}];
    final sel = _cat < cats.length ? _cat : 0;
    final q = _query.trim().toLowerCase();

    final shown = products.where((p) {
      final okCat = sel == 0 || p.category == cats[sel];
      final okQuery = q.isEmpty || p.name.toLowerCase().contains(q);
      return okCat && okQuery;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Каталог'),
        actions: const [ProfileButton(), SizedBox(width: 12)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Поиск по товарам',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          ChipsRow(
            labels: cats,
            selected: sel,
            onSelected: (i) => setState(() => _cat = i),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: shown.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Ничего не найдено',
                    text: 'Попробуйте изменить запрос или категорию',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final p = shown[i];
                      return AppCard(
                        padding: const EdgeInsets.all(12),
                        onTap: () => openProduct(context, p),
                        child: Row(
                          children: [
                            ProductImage(product: p, height: 64, width: 64),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  MutedText(p.category),
                                ],
                              ),
                            ),
                            Text(
                              p.inStock ? p.priceLabel : 'Нет в наличии',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
