import 'package:flutter/material.dart';

import '../store.dart';

Future<bool> confirm(BuildContext context, String title, String text) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: const Text('Да')),
      ],
    ),
  );
  return r ?? false;
}

/// Добавить или изменить одну цитату.
Future<void> editQuote(BuildContext context,
    {Quote? quote, int? sourceId}) async {
  final sources = await Store.instance.sources();
  int? src = quote?.sourceId ?? sourceId;
  if (src == null || !sources.any((s) => s.id == src)) {
    src = await Store.instance.myQuotesSourceId();
  }
  final all = await Store.instance.sources();
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (_) =>
        _QuoteEditor(quote: quote, sourceId: src!, sources: all),
  );
}

class _QuoteEditor extends StatefulWidget {
  final Quote? quote;
  final int sourceId;
  final List<Source> sources;
  const _QuoteEditor(
      {required this.quote, required this.sourceId, required this.sources});

  @override
  State<_QuoteEditor> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends State<_QuoteEditor> {
  late final _text = TextEditingController(text: widget.quote?.text ?? '');
  late final _author = TextEditingController(text: widget.quote?.author ?? '');
  late int _source = widget.sourceId;

  @override
  void dispose() {
    _text.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.quote != null;
    return AlertDialog(
      title: Text(editing ? 'Изменить цитату' : 'Новая цитата'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            autofocus: !editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Текст'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _author,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Автор', hintText: 'Прп. Амвросий Оптинский'),
          ),
          if (!editing) ...[
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Источник'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _source,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    for (final s in widget.sources)
                      DropdownMenuItem(
                          value: s.id,
                          child:
                              Text(s.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _source = v ?? _source),
                ),
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            final t = _text.text.trim();
            if (t.isEmpty) return;
            final q = widget.quote;
            if (q != null) {
              await Store.instance.updateQuote(q.id, t, _author.text);
            } else {
              await Store.instance.addQuote(t, _author.text, _source);
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Добавить или изменить источник. Возвращает id источника.
Future<int?> editSource(BuildContext context, {Source? source}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _SourceEditor(source: source),
  );
}

class _SourceEditor extends StatefulWidget {
  final Source? source;
  const _SourceEditor({this.source});

  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late final _name = TextEditingController(text: widget.source?.name ?? '');
  late final _url = TextEditingController(text: widget.source?.url ?? '');
  late final _note = TextEditingController(text: widget.source?.note ?? '');

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    return AlertDialog(
      title: Text(s == null ? 'Новый источник' : 'Источник'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            autofocus: s == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Книга, сайт или подборка'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Ссылка (необязательно)', hintText: 'https://…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                const InputDecoration(labelText: 'Заметка (необязательно)'),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            var url = _url.text.trim();
            if (url.isNotEmpty && !url.contains('://')) url = 'https://$url';
            int id;
            if (s == null) {
              id = await Store.instance.addSource(name, url, _note.text);
            } else {
              id = s.id;
              await Store.instance.updateSource(id, name, url, _note.text);
            }
            if (context.mounted) Navigator.pop(context, id);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Разбор вставленного текста на цитаты.
///
/// Цитаты разделяются пустой строкой. Если последняя строка начинается
/// с тире — это автор. Ещё можно писать в одну строку: «текст || автор».
List<(String, String)> parseQuotes(String raw, String defaultAuthor) {
  final out = <(String, String)>[];
  final norm = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = norm.split(RegExp(r'\n\s*\n'));
  final dash = RegExp(r'^\s*[—–-]\s*');
  for (final block in blocks) {
    final lines = block
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) continue;
    // Формат «текст || автор», по одной цитате в строке
    if (lines.every((l) => l.contains('||'))) {
      for (final l in lines) {
        final i = l.indexOf('||');
        final t = _clean(l.substring(0, i));
        final a = l.substring(i + 2).trim();
        if (t.isNotEmpty) out.add((t, a.isEmpty ? defaultAuthor : a));
      }
      continue;
    }
    var author = defaultAuthor;
    if (lines.length > 1 && dash.hasMatch(lines.last)) {
      author = lines.removeLast().replaceFirst(dash, '').trim();
    }
    final text = _clean(lines.join(' '));
    if (text.isNotEmpty) out.add((text, author));
  }
  return out;
}

String _clean(String s) {
  var t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length > 1 &&
      (t.startsWith('«') && t.endsWith('»') ||
          t.startsWith('"') && t.endsWith('"'))) {
    t = t.substring(1, t.length - 1).trim();
  }
  return t;
}

/// Экран массового добавления: вставить текст из книги или сайта.
class ImportScreen extends StatefulWidget {
  final Source source;
  const ImportScreen({super.key, required this.source});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  final _author = TextEditingController();
  List<(String, String)> _parsed = [];

  @override
  void dispose() {
    _text.dispose();
    _author.dispose();
    super.dispose();
  }

  void _update() =>
      setState(() => _parsed = parseQuotes(_text.text, _author.text.trim()));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить списком')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('В «${widget.source.name}»',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Text(
          'Вставьте текст. Цитаты отделяйте пустой строкой; если последняя '
          'строка начинается с тире — это автор:\n\n'
          'Смиряйся, и все дела твои пойдут.\n— Прп. Амвросий Оптинский\n\n'
          'Можно и в одну строку: текст || автор',
          style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _author,
          onChanged: (_) => _update(),
          decoration: const InputDecoration(
              labelText: 'Автор по умолчанию (если не указан)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          onChanged: (_) => _update(),
          minLines: 10,
          maxLines: 24,
          decoration: const InputDecoration(
              labelText: 'Текст с цитатами', alignLabelWithHint: true),
        ),
        const SizedBox(height: 12),
        if (_parsed.isNotEmpty) ...[
          Text('Найдено цитат: ${_parsed.length}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final (t, a) in _parsed.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $t${a.isEmpty ? '' : ' — $a'}',
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          if (_parsed.length > 5) Text('… и ещё ${_parsed.length - 5}'),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _parsed.isEmpty
                ? null
                : () async {
                    final n = await Store.instance
                        .addQuotes(_parsed, widget.source.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Добавлено цитат: $n')));
                    Navigator.pop(context);
                  },
            icon: const Icon(Icons.playlist_add),
            label: Text(_parsed.isEmpty
                ? 'Добавить'
                : 'Добавить ${_parsed.length}'),
          ),
        ),
      ),
    );
  }
}
