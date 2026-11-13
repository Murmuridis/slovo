import 'package:flutter/material.dart';

import '../daily.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit.dart';

/// Список цитат с поиском. Используется и для «Все», и для «Избранное»,
/// и внутри карточки источника.
class QuotesScreen extends StatefulWidget {
  final bool favoritesOnly;
  final int? sourceId;
  const QuotesScreen({super.key, this.favoritesOnly = false, this.sourceId});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  final _search = TextEditingController();
  List<Quote> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Store.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    Store.instance.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await Store.instance.search(
      text: _search.text,
      favoritesOnly: widget.favoritesOnly,
      sourceId: widget.sourceId,
    );
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          controller: _search,
          onChanged: (_) => _reload(),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Поиск по тексту и автору',
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      _reload();
                    },
                  ),
          ),
        ),
      ),
      if (!_loading)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(pluralQuotes(_items.length),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? EmptyHint(
                    icon: widget.favoritesOnly
                        ? Icons.favorite_border
                        : Icons.search_off,
                    text: widget.favoritesOnly && _search.text.isEmpty
                        ? 'Здесь будут цитаты, отмеченные сердечком.'
                        : 'Ничего не найдено.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _QuoteTile(quote: _items[i]),
                  ),
      ),
    ]);
  }
}

class _QuoteTile extends StatelessWidget {
  final Quote quote;
  const _QuoteTile({required this.quote});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showQuoteSheet(context, quote.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quote.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: quoteFont,
                        fontSize: 17 * textScale(),
                        height: 1.35),
                  ),
                  if (quote.author.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(quote.author,
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 13.5,
                            color: scheme.primary)),
                  ],
                ],
              ),
            ),
            if (quote.favorite)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Icon(Icons.favorite, size: 18, color: scheme.primary),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Нижняя шторка с цитатой целиком и действиями.
Future<void> showQuoteSheet(BuildContext context, int quoteId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _QuoteSheet(quoteId: quoteId),
  );
}

class _QuoteSheet extends StatefulWidget {
  final int quoteId;
  const _QuoteSheet({required this.quoteId});

  @override
  State<_QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends State<_QuoteSheet> {
  Quote? _q;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = await Store.instance.quote(widget.quoteId);
    if (mounted) setState(() => _q = q);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    if (q == null) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(children: [
            const Ornament(),
            const SizedBox(height: 18),
            QuoteText(quote: q, fontSize: 21),
            const SizedBox(height: 10),
            QuoteActions(
              quote: q,
              onChanged: _load,
              extra: [
                IconButton(
                  tooltip: 'Изменить',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    await editQuote(context, quote: q);
                    _load();
                  },
                ),
                IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirm(context,
                        'Удалить цитату?', 'Её можно будет добавить заново вручную.');
                    if (ok) {
                      await Store.instance.deleteQuote(q.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
