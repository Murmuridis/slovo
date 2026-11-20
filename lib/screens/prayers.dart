import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../native.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit.dart';

/// Вкладка «Молитвы»: список, поиск, порядок перетаскиванием.
class PrayersScreen extends StatefulWidget {
  const PrayersScreen({super.key});

  @override
  State<PrayersScreen> createState() => _PrayersScreenState();
}

class _PrayersScreenState extends State<PrayersScreen> {
  final _search = TextEditingController();
  List<Prayer> _items = [];
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
    try {
      final items = await Store.instance.prayers(search: _search.text);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _reorder(int from, int to) async {
    if (to > from) to -= 1;
    final list = List<Prayer>.of(_items);
    final item = list.removeAt(from);
    list.insert(to, item);
    setState(() => _items = list);
    await Store.instance.reorderPrayers(list.map((x) => x.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final searching = _search.text.trim().isNotEmpty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          controller: _search,
          onChanged: (_) => _reload(),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Поиск молитвы',
            suffixIcon: !searching
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
      if (!_loading && !searching && _items.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
          child: Text('Порядок: удерживайте молитву и перетащите',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? EmptyHint(
                    icon: Icons.auto_stories_outlined,
                    text: searching
                        ? 'Ничего не найдено.'
                        : 'Добавьте свою молитву кнопкой «+».',
                  )
                : searching
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        children: [for (final x in _items) _PrayerTile(x)],
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        itemCount: _items.length,
                        onReorder: _reorder,
                        itemBuilder: (_, i) => _PrayerTile(_items[i],
                            key: ValueKey(_items[i].id)),
                      ),
      ),
    ]);
  }
}

class _PrayerTile extends StatelessWidget {
  final Prayer prayer;
  const _PrayerTile(this.prayer, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final x = prayer;
    var firstLine = x.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // «Отче наш» → «…Иже еси на небесех», а не повтор названия.
    final t = x.title.trim();
    if (t.isNotEmpty &&
        firstLine.toLowerCase().startsWith(t.toLowerCase()) &&
        firstLine.length > t.length + 3) {
      firstLine = firstLine
          .substring(t.length)
          .replaceFirst(RegExp(r'^[\s,.;:!—–-]+'), '');
      if (firstLine.isNotEmpty) firstLine = '…$firstLine';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PrayerScreen(prayerId: x.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: x.images.isNotEmpty
                      ? Image.file(File(x.images.first.path),
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          errorBuilder: (_, __, ___) => _thumbPlaceholder(scheme))
                      : _thumbPlaceholder(scheme),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(x.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: quoteFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 17.5)),
                    if (firstLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(firstLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (x.audios.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.headphones, size: 20, color: scheme.primary),
                ),
              if (x.favorite)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.favorite, size: 18, color: scheme.primary),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget _thumbPlaceholder(ColorScheme scheme) => Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: CrossMark(size: 26, color: scheme.secondary),
    );

// ---------------- Чтение молитвы ----------------

class PrayerScreen extends StatefulWidget {
  final int prayerId;
  const PrayerScreen({super.key, required this.prayerId});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  Prayer? _p;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    Store.instance.addListener(_load);
    Native.keepScreenOn(true);
    _load();
  }

  @override
  void dispose() {
    Store.instance.removeListener(_load);
    Native.keepScreenOn(false);
    Native.audioStop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final x = await Store.instance.prayer(widget.prayerId);
      if (!mounted) return;
      setState(() {
        _p = x;
        _gone = x == null;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final x = _p;
    if (x == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _gone
            ? const EmptyHint(icon: Icons.delete_outline, text: 'Молитва удалена.')
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final scale = textScale();
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: x.favorite ? 'Убрать из избранного' : 'В избранное',
            icon: Icon(x.favorite ? Icons.favorite : Icons.favorite_border,
                color: scheme.primary),
            onPressed: () => Store.instance.setPrayerFavorite(x.id, !x.favorite),
          ),
          IconButton(
            tooltip: 'Поделиться',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Native.share(x.shareText),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PrayerEditScreen(prayer: x)));
              } else if (v == 'delete') {
                final ok = await confirm(
                    context,
                    'Удалить молитву?',
                    'Вместе с ней удалятся прикреплённые картинки и аудио.');
                if (ok) {
                  await Native.audioStop();
                  await Store.instance.deletePrayer(x.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Изменить')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text(x.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: quoteFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 25 * scale,
                  height: 1.25,
                  color: scheme.primary)),
          const SizedBox(height: 12),
          const Ornament(),
          const SizedBox(height: 16),
          for (final img in x.images) ...[
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ImageViewer(images: x.images, start: img))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image.file(File(img.path),
                      fit: BoxFit.contain,
                      cacheWidth: 1200,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined, size: 48)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final a in x.audios) ...[
            AudioTile(audio: a),
            const SizedBox(height: 8),
          ],
          if (x.images.isNotEmpty || x.audios.isNotEmpty)
            const SizedBox(height: 8),
          SelectableText(
            x.text,
            style: TextStyle(
              fontFamily: quoteFont,
              fontSize: 21 * scale,
              height: 1.55,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          const Ornament(width: 120),
        ],
      ),
    );
  }
}

/// Аудио молитвы: кнопка, название, перемотка.
class AudioTile extends StatefulWidget {
  final Attachment audio;
  const AudioTile({super.key, required this.audio});

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  Timer? _timer;
  String _state = 'stopped';
  int _pos = 0, _dur = 0;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final m = await Native.audioState();
    if (!mounted) return;
    final mine = m['path'] == widget.audio.path;
    setState(() {
      _state = mine ? '${m['state']}' : 'stopped';
      _pos = mine ? (m['pos'] as int? ?? 0) : 0;
      _dur = mine ? (m['dur'] as int? ?? 0) : 0;
    });
  }

  Future<void> _toggle() async {
    if (_state == 'playing' || _state == 'preparing') {
      await Native.audioPause();
    } else {
      await Native.audioPlay(widget.audio.path);
    }
    _poll();
  }

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playing = _state == 'playing';
    final active = _dur > 0;
    final value = (_drag ?? _pos.toDouble()).clamp(0, _dur.toDouble()).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
        child: Row(children: [
          IconButton.filled(
            tooltip: playing ? 'Пауза' : 'Слушать',
            onPressed: _toggle,
            icon: _state == 'preparing'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2))
                : Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.audio.name.isEmpty ? 'Аудио' : widget.audio.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_state == 'error')
                  Text('Не удалось воспроизвести файл',
                      style: TextStyle(fontSize: 12.5, color: scheme.error))
                else if (active)
                  Row(children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 7),
                        ),
                        child: Slider(
                          value: value,
                          max: _dur.toDouble(),
                          onChanged: (v) => setState(() => _drag = v),
                          onChangeEnd: (v) async {
                            await Native.audioSeek(v.round());
                            setState(() => _drag = null);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${_fmt(value.round())} / ${_fmt(_dur)}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ])
                else
                  Text('Нажмите, чтобы слушать',
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Картинка во весь экран, с увеличением пальцами; листается.
class ImageViewer extends StatelessWidget {
  final List<Attachment> images;
  final Attachment start;
  const ImageViewer({super.key, required this.images, required this.start});

  @override
  Widget build(BuildContext context) {
    final i = images.indexWhere((a) => a.file == start.file);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView(
        controller: PageController(initialPage: i < 0 ? 0 : i),
        children: [
          for (final a in images)
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.file(File(a.path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- Новая молитва / изменить ----------------

class PrayerEditScreen extends StatefulWidget {
  final Prayer? prayer;
  const PrayerEditScreen({super.key, this.prayer});

  @override
  State<PrayerEditScreen> createState() => _PrayerEditScreenState();
}

class _PrayerEditScreenState extends State<PrayerEditScreen> {
  late final _title = TextEditingController(text: widget.prayer?.title ?? '');
  late final _text = TextEditingController(text: widget.prayer?.text ?? '');
  List<Attachment> _images = [];
  List<Attachment> _audios = [];

  /// Файлы, которые были у молитвы до правки (их удаляет Store при сохранении).
  final Set<String> _original = {};
  bool _dirty = false;
  bool _saved = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _images = List.of(widget.prayer?.images ?? const <Attachment>[]);
    _audios = List.of(widget.prayer?.audios ?? const <Attachment>[]);
    _original.addAll([..._images, ..._audios].map((a) => a.file));
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Файлы, добавленные в этой правке и не сохранённые, — удалить.
  void _discardNew() {
    Store.instance.deleteMediaFiles([
      ..._images.map((a) => a.file),
      ..._audios.map((a) => a.file),
    ].where((f) => !_original.contains(f)));
  }

  void _remove(Attachment a) {
    setState(() {
      _images.removeWhere((x) => x.file == a.file);
      _audios.removeWhere((x) => x.file == a.file);
      _dirty = true;
    });
    if (!_original.contains(a.file)) Store.instance.deleteMediaFiles([a.file]);
  }

  Future<void> _pick(String kind) async {
    setState(() => _busy = true);
    final files = await Native.pickFiles(kind);
    if (!mounted) {
      Store.instance.deleteMediaFiles(files.map((f) => f.file));
      return;
    }
    setState(() {
      _busy = false;
      final list = [
        for (final f in files) Attachment(kind: kind, file: f.file, name: f.name),
      ];
      if (kind == 'image') {
        _images = [..._images, ...list];
      } else {
        _audios = [..._audios, ...list];
      }
      if (list.isNotEmpty) _dirty = true;
    });
  }

  Future<void> _renameAudio(int i) async {
    final c = TextEditingController(text: _audios[i].name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название записи'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() {
        _audios[i] = _audios[i].rename(name);
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Напишите название молитвы')));
      return;
    }
    final id = await Store.instance.savePrayer(
      id: widget.prayer?.id,
      title: title,
      text: _text.text,
      attachments: [..._images, ..._audios],
    );
    _saved = true;
    if (!mounted) return;
    if (widget.prayer == null) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => PrayerScreen(prayerId: id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
          child: Text(t,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: scheme.primary)),
        );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          if (!_saved) _discardNew();
          return;
        }
        final ok = await confirm(context, 'Не сохранять изменения?',
            'Добавленные картинки и аудио тоже не сохранятся.');
        if (ok && context.mounted) {
          _discardNew();
          _saved = true; // файлы уже убраны
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.prayer == null ? 'Новая молитва' : 'Изменить',
              style: const TextStyle(fontSize: 20)),
          actions: [
            IconButton(
                tooltip: 'Сохранить',
                onPressed: _save,
                icon: const Icon(Icons.check)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            TextField(
              controller: _title,
              onChanged: (_) => _changed(),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              onChanged: (_) => _changed(),
              minLines: 8,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontFamily: quoteFont, fontSize: 18),
              decoration: const InputDecoration(
                  labelText: 'Текст молитвы', alignLabelWithHint: true),
            ),
            header('Изображения'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in _images)
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(a.path),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        cacheWidth: 240,
                        errorBuilder: (_, __, ___) => Container(
                            width: 96,
                            height: 96,
                            color: scheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined))),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: InkWell(
                      onTap: () => _remove(a),
                      child: Container(
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(3),
                        child: const Icon(Icons.close,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _busy ? null : () => _pick('image'),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: scheme.primary),
                        const SizedBox(height: 4),
                        const Text('Добавить', style: TextStyle(fontSize: 12.5)),
                      ]),
                ),
              ),
            ]),
            header('Аудио'),
            for (var i = 0; i < _audios.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.audiotrack, color: scheme.primary),
                    title: Text(_audios[i].name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Нажмите, чтобы переименовать'),
                    onTap: () => _renameAudio(i),
                    trailing: IconButton(
                      tooltip: 'Убрать',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(_audios[i]),
                    ),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick('audio'),
              icon: const Icon(Icons.audio_file_outlined),
              label: const Text('Прикрепить аудиофайл'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
