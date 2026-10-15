import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/format.dart';
import '../core/messenger.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Добавление (product == null) и редактирование товара.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product});
  final Product? product;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _desc;
  late Unit _unit;
  late String _category;
  late bool _active;
  String? _imageUrl;
  Uint8List? _preview; // выбранное фото до сохранения товара
  bool _uploading = false;
  bool _saving = false;

  bool get _isNew => widget.product == null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(
      text: p == null ? '' : numberToInput(p.priceKop / 100),
    );
    _stock = TextEditingController(
      text: p == null
          ? ''
          : (p.unit == Unit.kg
              ? numberToInput(p.stock / 1000)
              : '${p.stock}'),
    );
    _desc = TextEditingController(text: p?.description ?? '');
    _unit = p?.unit ?? Unit.kg;
    final cats = ref.read(categoriesProvider);
    _category = p?.category ?? (cats.isEmpty ? 'Рыба' : cats.first);
    _imageUrl = p?.imageUrl;
    // Новый товар по умолчанию скрыт, пока админ не включит показ.
    _active = p?.isActive ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _desc.dispose();
    super.dispose();
  }

  /// Остаток из поля: для кг вводим килограммы, храним граммы.
  int? _parseStock() {
    if (_unit == Unit.kg) {
      final v = parseNumber(_stock.text);
      return v == null ? null : (v * 1000).round();
    }
    return int.tryParse(_stock.text.trim());
  }

  /// Выбор фото в галерее и загрузка в хранилище по временной ссылке от сервера.
  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.toLowerCase();
      final type = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      final api = ref.read(apiProvider);
      final ticket = await api.requestUpload(type);
      await api.putFile(ticket, bytes);
      if (!mounted) return;
      setState(() {
        _imageUrl = ticket.imageUrl;
        _preview = bytes;
      });
    } catch (e) {
      reportError(e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete() async {
    final p = widget.product;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(
          '«${p.name}» пропадёт из каталога. Старые заказы с ним сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final done = await ref.read(catalogProvider.notifier).remove(p.id);
    if (!mounted) return;
    if (!done) {
      setState(() => _saving = false);
      return;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Товар удалён')));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final base = widget.product;
    final product = Product(
      id: base?.id ?? '',
      name: _name.text.trim(),
      category: _category,
      unit: _unit,
      priceKop: parseKop(_price.text)!,
      description: _desc.text.trim(),
      imageUrl: _imageUrl,
      weightSteps: base?.weightSteps ?? const [300, 500, 1000],
      stock: _parseStock()!,
      isActive: _active,
    );
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final ok = await ref
        .read(catalogProvider.notifier)
        .save(product, isNew: _isNew);
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      return;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(_isNew ? 'Товар добавлен' : 'Изменения сохранены')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новый товар' : 'Редактировать товар'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _uploading ? null : _pickPhoto,
              child: Ink(
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.mist,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_preview != null)
                        Image.memory(_preview!, fit: BoxFit.cover)
                      else if (_imageUrl != null)
                        Image.network(
                          _imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      Center(
                        child: _uploading
                            ? const CircularProgressIndicator()
                            : _imageUrl == null
                                ? const Text(
                                    'Добавить фото',
                                    style: TextStyle(color: AppColors.teal),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Заменить фото',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Название'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Введите название' : null,
            ),
            const SizedBox(height: 12),
            const Text(
              'Категория',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  AppChoiceChip(
                    label: c,
                    selected: c == _category,
                    onSelected: () => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<Unit>(
              showSelectedIcon: false,
              segments: [
                for (final u in Unit.values)
                  ButtonSegment<Unit>(value: u, label: Text(u.label)),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: _unit.priceLabel),
                    validator: (v) {
                      final k = parseKop(v ?? '');
                      return (k == null || k <= 0) ? 'Введите цену' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _stock,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: _unit == Unit.kg,
                    ),
                    decoration: InputDecoration(labelText: _unit.stockLabel),
                    validator: (v) =>
                        _parseStock() == null ? 'Введите остаток' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Показывать в приложении',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: (_saving || _uploading) ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить товар'),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              FilledButton(
                style: lightButtonStyle(),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (_saving || _uploading) ? null : _save,
                  child: Text(_isNew ? 'Добавить товар' : 'Сохранить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
