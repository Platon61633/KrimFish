import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';

/// Перезагружает с сервера всё, что показывают экраны.
Future<void> refreshAll(WidgetRef ref) {
  final admin = ref.read(authProvider).user?.isAdmin ?? false;
  return Future.wait([
    ref.read(catalogProvider.notifier).load(),
    ref.read(serverCategoriesProvider.notifier).load(),
    ref.read(ordersProvider.notifier).load(),
    ref.read(authProvider.notifier).refreshUser(),
    if (!admin) ref.read(slotsProvider.notifier).load(),
  ]);
}

/// Обновление свайпом вниз. Внутри должен быть прокручиваемый виджет
/// с `physics: AlwaysScrollableScrollPhysics()`, иначе короткий список не потянется.
class PullToRefresh extends ConsumerWidget {
  const PullToRefresh({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.teal,
      onRefresh: () => refreshAll(ref),
      child: child,
    );
  }
}

/// Пустое состояние, которое можно потянуть вниз для обновления.
class ScrollableEmpty extends StatelessWidget {
  const ScrollableEmpty({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
