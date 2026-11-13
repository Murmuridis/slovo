import 'package:flutter/material.dart';

import '../daily.dart';
import '../native.dart';
import '../store.dart';
import '../widgets.dart';
import 'edit.dart';
import 'quotes.dart';

/// Вкладка «Источники»: книги и сайты, из которых берутся цитаты.
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  List<Source> _items = [];
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
    super.dispose();
  }

  Future<void> _reload() async {
    final s = await Store.instance.sources();
    if (mounted) {
      setState(() {
        _items = s;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final withQuotes = _items.where((s) => s.count > 0).toList();
    final links = _items.where((s) => s.count == 0).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'Выключенный источник не попадает в «слово дня». '
            'Нажмите на источник, чтобы добавить в него цитаты.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        for (final s in withQuotes) _SourceTile(source: s),
        if (links.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text('Ссылки без цитат',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: scheme.primary)),
          ),
          for (final s in links) _SourceTile(source: s),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  final Source source;
  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = source;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              pluralQuotes(s.count),
              if (s.url.isNotEmpty) Uri.tryParse(s.url)?.host ?? '',
            ].where((x) => x.isNotEmpty).join(' · '),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          trailing: s.count == 0
              ? (s.url.isNotEmpty
                  ? IconButton(
                      tooltip: 'Открыть ссылку',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => Native.openUrl(s.url),
                    )
                  : null)
              : Switch(
                  value: s.enabled,
                  onChanged: (v) => Store.instance.setSourceEnabled(s.id, v),
                ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SourceScreen(sourceId: s.id)),
          ),
        ),
      ),
    );
  }
}

/// Карточка одного источника: его цитаты и действия.
class SourceScreen extends StatefulWidget {
  final int sourceId;
  const SourceScreen({super.key, required this.sourceId});

  @override
  State<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends State<SourceScreen> {
  Source? _s;

  @override
  void initState() {
    super.initState();
    Store.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Store.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final s = await Store.instance.source(widget.sourceId);
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await editSource(context, source: s);
                case 'import':
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ImportScreen(source: s)));
                case 'delete':
                  final ok = await confirm(
                      context,
                      'Удалить источник?',
                      'Вместе с ним удалятся ${pluralQuotes(s.count)}. '
                          'Если нужно только убрать их из «слова дня» — '
                          'выключите источник переключателем.');
                  if (ok) {
                    await Store.instance.deleteSource(s.id);
                    if (context.mounted) Navigator.pop(context);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Изменить')),
              PopupMenuItem(value: 'import', child: Text('Добавить списком')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.note.isNotEmpty)
                    Text(s.note,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  if (s.url.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact),
                      onPressed: () async {
                        final ok = await Native.openUrl(s.url);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Не удалось открыть ссылку')));
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(Uri.tryParse(s.url)?.host ?? s.url,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            Column(children: [
              Switch(
                value: s.enabled,
                onChanged: (v) => Store.instance.setSourceEnabled(s.id, v),
              ),
              Text(s.enabled ? 'в «слове дня»' : 'выключен',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant)),
            ]),
          ]),
        ),
        Expanded(
          child: s.count == 0
              ? EmptyHint(
                  icon: Icons.note_add_outlined,
                  text: s.url.isNotEmpty
                      ? 'Откройте ссылку, скопируйте понравившиеся '
                          'высказывания и добавьте их кнопкой «+» '
                          'или списком через меню ⋮.'
                      : 'Добавьте цитаты кнопкой «+» или списком через меню ⋮.',
                )
              : QuotesScreen(sourceId: s.id),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить цитату',
        onPressed: () => editQuote(context, sourceId: s.id),
        child: const Icon(Icons.add),
      ),
    );
  }
}
