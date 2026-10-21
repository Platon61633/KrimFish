import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/api.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'profile_button.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  int _slot = 0;
  String? _promo; // применённый промокод
  String? _promoError;
  Quote? _quote; // расчёт сервера (скидка, доставка, итог)
  bool _busy = false;
  String? _attemptKey; // защита от дубля заказа при повторной отправке
  final _promoCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  bool _addressTouched = false;
  bool _phoneTouched = false;

  @override
  void initState() {
    super.initState();
    // Слоты и остатки могли устареть, пока приложение было открыто.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(slotsProvider.notifier).load();
      _requote();
    });
  }

  @override
  void dispose() {
    _promoCtl.dispose();
    _addressCtl.dispose();
    _phoneCtl.dispose();
    super.dispose();
  }

  /// Пересчитывает корзину на сервере (скидка и итог считаются там).
  Future<void> _requote() async {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty) {
      if (mounted) setState(() => _quote = null);
      return;
    }
    try {
      final q = await ref.read(apiProvider).quote(lines, promoCode: _promo);
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Промокод перестал подходить (например, сумма стала меньше минимальной).
      if (_promo != null && e.status == 400) {
        setState(() {
          _promo = null;
          _promoError = e.message;
        });
        _requote();
      }
    }
  }

  Future<void> _applyPromo() async {
    final code = _promoCtl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    try {
      final q = await ref
          .read(apiProvider)
          .quote(ref.read(cartProvider), promoCode: code);
      if (!mounted) return;
      setState(() {
        _promo = code;
        _promoError = null;
        _quote = q;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _promo = null;
        _promoError = e.message;
      });
    }
  }

  Future<void> _checkout(List<CartLine> lines, List<DeliverySlot> slots) async {
    final address = _addressCtl.text.trim();
    if (slots.isEmpty) {
      showSnack(context, 'Нет свободного времени доставки');
      return;
    }
    if (address.length < 3) {
      showSnack(context, 'Укажите адрес доставки');
      return;
    }
    final phone = _phoneCtl.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      showSnack(context, 'Укажите номер телефона для связи с курьером');
      return;
    }
    final slot = slots[_slot < slots.length ? _slot : 0];
    _attemptKey ??=
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
    setState(() => _busy = true);
    final order = await ref
        .read(ordersProvider.notifier)
        .place(
          lines: lines,
          slot: slot,
          addressLine: address,
          phone: phone,
          promoCode: _promo,
          idempotencyKey: _attemptKey!,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (order == null) {
      // Ключ сохраняем только при обрыве связи: заказ мог создаться.
      if (!ref.read(ordersProvider.notifier).lastErrorWasNetwork) {
        _attemptKey = null;
      }
      _requote();
      return;
    }
    _attemptKey = null;
    ref.read(cartProvider.notifier).clear();
    ref.read(authProvider.notifier).refreshUser(); // номер сохранён в профиле
    setState(() {
      _promo = null;
      _promoError = null;
      _quote = null;
      _promoCtl.clear();
    });
    ref
        .read(clientTabProvider.notifier)
        .set(0); // заказ виден на главном экране
    showSnack(context, 'Заказ №${order.number} оформлен');
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    final slots = ref.watch(slotsProvider);
    final slotIndex = _slot < slots.length ? _slot : 0;
    ref.listen(cartProvider, (_, _) => _requote());

    // Адрес подставляем из последнего заказа, пока пользователь его не менял.
    final savedAddress = ref.watch(profileProvider).address;
    if (!_addressTouched &&
        _addressCtl.text.isEmpty &&
        savedAddress.isNotEmpty) {
      _addressCtl.text = savedAddress;
    }
    // Телефон подставляем из профиля, пока пользователь его не менял.
    final savedPhone = ref.watch(profileProvider).phone;
    if (!_phoneTouched && _phoneCtl.text.isEmpty && savedPhone.isNotEmpty) {
      _phoneCtl.text = savedPhone;
    }

    final itemsKop = lines.fold<int>(0, (s, l) => s + l.lineKop);
    final discountKop = _quote?.discountKop ?? 0;
    final deliveryKop = _quote?.deliveryKop ?? kDeliveryKop;
    final totalKop = _quote?.totalKop ?? itemsKop + deliveryKop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Корзина'),
        actions: const [ProfileButton(), SizedBox(width: 12)],
      ),
      body: lines.isEmpty
          ? EmptyState(
              icon: Icons.shopping_basket_outlined,
              title: 'Корзина пуста',
              text: 'Добавьте свежие морепродукты из каталога',
              action: FilledButton(
                onPressed: () => ref.read(clientTabProvider.notifier).set(1),
                child: const Text('В каталог'),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: [
                      for (final l in lines) ...[
                        AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ProductImage(
                                product: l.product,
                                height: 64,
                                width: 64,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    MutedText(formatKop(l.lineKop)),
                                  ],
                                ),
                              ),
                              QtyStepper(
                                label: l.product.qtyLabel(l.qty),
                                onMinus: () => ref
                                    .read(cartProvider.notifier)
                                    .change(l.product.id, -l.product.cartStep),
                                onPlus: () {
                                  if (l.qty + l.product.cartStep >
                                      l.product.maxQty) {
                                    showSnack(context, l.product.limitMessage);
                                    return;
                                  }
                                  ref
                                      .read(cartProvider.notifier)
                                      .change(l.product.id, l.product.cartStep);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Время доставки',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < slots.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: AppChoiceChip(
                                  label: slots[i].label,
                                  selected: i == slotIndex,
                                  onSelected: () => setState(() => _slot = i),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneCtl,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        onChanged: (_) => _phoneTouched = true,
                        decoration: const InputDecoration(
                          labelText: 'Телефон для связи',
                          hintText: '+7 900 000-00-00',
                          helperText: 'Курьер позвонит, если понадобится',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _addressCtl,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => _addressTouched = true,
                        decoration: const InputDecoration(
                          labelText: 'Адрес доставки',
                          hintText: 'Улица, дом, квартира',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _promoCtl,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _applyPromo(),
                        decoration: InputDecoration(
                          hintText: 'Промокод',
                          errorText: _promoError,
                          helperText: _promo == null
                              ? null
                              : 'Промокод $_promo применён',
                          suffixIcon: TextButton(
                            onPressed: _applyPromo,
                            child: const Text('Применить'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          children: [
                            _row('Товары', formatKop(itemsKop)),
                            if (discountKop > 0)
                              _row('Скидка', '−${formatKop(discountKop)}'),
                            _row('Доставка', formatKop(deliveryKop)),
                            const SizedBox(height: 4),
                            _row('Итого', formatKop(totalKop), bold: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: AppColors.bg,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _checkout(lines, slots),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('Оформить заказ · ${formatKop(totalKop)}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
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
