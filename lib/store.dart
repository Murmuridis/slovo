import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'native.dart';
import 'prayers_seed.dart';

/// Источник высказываний: книга, сайт или своя подборка.
class Source {
  final int id;
  final String name;
  final String url;
  final String note;
  final bool enabled;
  final bool builtin;
  final int count;

  const Source({
    required this.id,
    required this.name,
    required this.url,
    required this.note,
    required this.enabled,
    required this.builtin,
    this.count = 0,
  });

  factory Source.fromRow(Map<String, Object?> r) => Source(
        id: r['id'] as int,
        name: (r['name'] as String?) ?? '',
        url: (r['url'] as String?) ?? '',
        note: (r['note'] as String?) ?? '',
        enabled: (r['enabled'] as int? ?? 1) == 1,
        builtin: (r['builtin'] as int? ?? 0) == 1,
        count: (r['cnt'] as int?) ?? 0,
      );
}

/// Одно высказывание.
class Quote {
  final int id;
  final String text;
  final String author;
  final int sourceId;
  final String sourceName;
  final String sourceUrl;
  final bool favorite;
  final bool builtin;

  const Quote({
    required this.id,
    required this.text,
    required this.author,
    required this.sourceId,
    required this.sourceName,
    required this.sourceUrl,
    required this.favorite,
    required this.builtin,
  });

  factory Quote.fromRow(Map<String, Object?> r) => Quote(
        id: r['id'] as int,
        text: (r['text'] as String?) ?? '',
        author: (r['author'] as String?) ?? '',
        sourceId: (r['source_id'] as int?) ?? 0,
        sourceName: (r['source_name'] as String?) ?? '',
        sourceUrl: (r['source_url'] as String?) ?? '',
        favorite: (r['favorite'] as int? ?? 0) == 1,
        builtin: (r['builtin'] as int? ?? 0) == 1,
      );

  /// Текст для «Поделиться» и «Копировать».
  String get shareText {
    final b = StringBuffer('«$text»');
    if (author.isNotEmpty) b.write('\n— $author');
    return b.toString();
  }
}

/// Картинка или аудио, прикреплённые к молитве.
class Attachment {
  final int id;
  final String kind; // image | audio
  final String file; // имя файла в папке media
  final String name; // как показывать
  const Attachment(
      {this.id = 0, required this.kind, required this.file, required this.name});

  String get path => p.join(Store.instance.mediaDir, file);

  Attachment rename(String n) =>
      Attachment(id: id, kind: kind, file: file, name: n);
}

class Prayer {
  final int id;
  final String title;
  final String text;
  final bool favorite;
  final List<Attachment> images;
  final List<Attachment> audios;

  const Prayer({
    required this.id,
    required this.title,
    required this.text,
    required this.favorite,
    this.images = const [],
    this.audios = const [],
  });

  String get shareText => '$title\n\n$text';
}

/// Всё хранение приложения: SQLite-база с источниками, цитатами и настройками.
/// Любое изменение оповещает слушателей, чтобы экраны перерисовались.
class Store extends ChangeNotifier {
  Store._();
  static final Store instance = Store._();

  late Database _db;
  final Map<String, String> _settings = {};

  /// Полный путь к файлу базы (для резервной копии).
  String dbPath = '';

  /// Папка с картинками и аудио молитв.
  String mediaDir = '';

  /// Версия встроенной подборки. Если в новой версии приложения в
  /// assets/data/quotes.json добавятся цитаты — увеличить здесь и там.
  static const _seedVersion = 1;

  Future<void> open() async {
    _settings.clear();
    dbPath = p.join(await getDatabasesPath(), 'slovo.db');
    _db = await openDatabase(
      dbPath,
      version: 2,
      onUpgrade: (db, from, to) async {
        if (from < 2) await _createPrayerTables(db);
      },
      onCreate: (db, v) async {
        await _createPrayerTables(db);
        await db.execute('''
          CREATE TABLE sources(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            skey TEXT,
            name TEXT NOT NULL,
            url TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            builtin INTEGER NOT NULL DEFAULT 0,
            created INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE quotes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            author TEXT NOT NULL DEFAULT '',
            source_id INTEGER NOT NULL,
            favorite INTEGER NOT NULL DEFAULT 0,
            builtin INTEGER NOT NULL DEFAULT 0,
            created INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE INDEX q_src ON quotes(source_id)');
      },
    );
    for (final r in await _db.query('settings')) {
      _settings[r['key'] as String] = r['value'] as String;
    }
    await _seedIfNeeded();
    await _seedPrayers();
    mediaDir = await Native.mediaDir();
    await _cleanMedia();
    notifyListeners();
  }

  /// Закрыть базу (перед сохранением или восстановлением копии).
  Future<void> close() => _db.close();

  static Future<void> _createPrayerTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prayers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        favorite INTEGER NOT NULL DEFAULT 0,
        builtin INTEGER NOT NULL DEFAULT 0,
        sort INTEGER NOT NULL DEFAULT 0,
        created INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prayer_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        file TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        sort INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS a_prayer ON attachments(prayer_id)');
  }

  Future<void> _seedPrayers() async {
    if (setting('prayers_seed') == '1') return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = _db.batch();
    var i = 0;
    for (final (title, text) in prayerSeed) {
      batch.insert('prayers', {
        'title': title,
        'text': text,
        'builtin': 1,
        'sort': i++,
        'created': now,
      });
    }
    await batch.commit(noResult: true);
    await setSetting('prayers_seed', '1');
  }

  /// Удалить из папки media файлы, которые ни к чему не прикреплены
  /// (например, выбранные, но не сохранённые).
  Future<void> _cleanMedia() async {
    if (mediaDir.isEmpty) return;
    try {
      final used = {
        for (final r in await _db.query('attachments', columns: ['file']))
          r['file'] as String,
      };
      for (final f in Directory(mediaDir).listSync().whereType<File>()) {
        if (!used.contains(p.basename(f.path))) f.deleteSync();
      }
    } catch (_) {}
  }

  // ---------- Молитвы ----------

  Future<List<Prayer>> prayers({String search = ''}) async {
    final rows = await _db.query('prayers', orderBy: 'sort, id');
    final att = await _db.query('attachments', orderBy: 'sort, id');
    final byPrayer = <int, List<Attachment>>{};
    for (final a in att) {
      byPrayer.putIfAbsent(a['prayer_id'] as int, () => []).add(Attachment(
            id: a['id'] as int,
            kind: a['kind'] as String,
            file: a['file'] as String,
            name: (a['name'] as String?) ?? '',
          ));
    }
    var list = [
      for (final r in rows)
        _prayerFrom(r, byPrayer[r['id'] as int] ?? const []),
    ];
    final needle = search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      list = list
          .where((x) =>
              x.title.toLowerCase().contains(needle) ||
              x.text.toLowerCase().contains(needle))
          .toList();
    }
    return list;
  }

  Prayer _prayerFrom(Map<String, Object?> r, List<Attachment> att) => Prayer(
        id: r['id'] as int,
        title: (r['title'] as String?) ?? '',
        text: (r['text'] as String?) ?? '',
        favorite: (r['favorite'] as int? ?? 0) == 1,
        images: att.where((a) => a.kind == 'image').toList(),
        audios: att.where((a) => a.kind == 'audio').toList(),
      );

  Future<Prayer?> prayer(int id) async {
    final rows =
        await _db.query('prayers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final att = await _db.query('attachments',
        where: 'prayer_id = ?', whereArgs: [id], orderBy: 'sort, id');
    return _prayerFrom(rows.first, [
      for (final a in att)
        Attachment(
          id: a['id'] as int,
          kind: a['kind'] as String,
          file: a['file'] as String,
          name: (a['name'] as String?) ?? '',
        ),
    ]);
  }

  /// Сохранить молитву со всеми вложениями. Файлы, которые были
  /// прикреплены раньше, а теперь убраны, удаляются с телефона.
  Future<int> savePrayer({
    int? id,
    required String title,
    required String text,
    required List<Attachment> attachments,
  }) async {
    final oldFiles = <String>{};
    late int pid;
    await _db.transaction((txn) async {
      if (id == null) {
        final mx = await txn.rawQuery('SELECT MAX(sort) AS m FROM prayers');
        final sort = ((mx.first['m'] as int?) ?? -1) + 1;
        pid = await txn.insert('prayers', {
          'title': title.trim(),
          'text': text.trim(),
          'sort': sort,
          'created': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        pid = id;
        await txn.update(
            'prayers', {'title': title.trim(), 'text': text.trim()},
            where: 'id = ?', whereArgs: [id]);
        for (final r in await txn.query('attachments',
            columns: ['file'], where: 'prayer_id = ?', whereArgs: [id])) {
          oldFiles.add(r['file'] as String);
        }
        await txn.delete('attachments', where: 'prayer_id = ?', whereArgs: [id]);
      }
      var i = 0;
      for (final a in attachments) {
        await txn.insert('attachments', {
          'prayer_id': pid,
          'kind': a.kind,
          'file': a.file,
          'name': a.name,
          'sort': i++,
        });
      }
    });
    oldFiles.removeAll(attachments.map((a) => a.file));
    deleteMediaFiles(oldFiles);
    notifyListeners();
    return pid;
  }

  Future<void> deletePrayer(int id) async {
    final files = [
      for (final r in await _db.query('attachments',
          columns: ['file'], where: 'prayer_id = ?', whereArgs: [id]))
        r['file'] as String,
    ];
    await _db.transaction((txn) async {
      await txn.delete('attachments', where: 'prayer_id = ?', whereArgs: [id]);
      await txn.delete('prayers', where: 'id = ?', whereArgs: [id]);
    });
    deleteMediaFiles(files);
    notifyListeners();
  }

  Future<void> setPrayerFavorite(int id, bool fav) async {
    await _db.update('prayers', {'favorite': fav ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  /// Новый порядок молитв (id сверху вниз).
  Future<void> reorderPrayers(List<int> ids) async {
    final batch = _db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update('prayers', {'sort': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
    notifyListeners();
  }

  Future<int> prayerCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM prayers');
    return (r.first['c'] as int?) ?? 0;
  }

  void deleteMediaFiles(Iterable<String> files) {
    for (final f in files) {
      try {
        final file = File(p.join(mediaDir, f));
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _seedIfNeeded() async {
    final have = int.tryParse(_settings['seed_version'] ?? '') ?? 0;
    if (have >= _seedVersion) return;
    final raw = await rootBundle.loadString('assets/data/quotes.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      final ids = <String, int>{};
      for (final s in (data['sources'] as List)) {
        final m = s as Map<String, dynamic>;
        final key = m['k'] as String;
        final found = await txn.query('sources',
            columns: ['id'], where: 'skey = ?', whereArgs: [key], limit: 1);
        if (found.isNotEmpty) {
          ids[key] = found.first['id'] as int;
        } else {
          ids[key] = await txn.insert('sources', {
            'skey': key,
            'name': m['n'] ?? '',
            'url': m['u'] ?? '',
            'note': m['d'] ?? '',
            'enabled': 1,
            'builtin': 1,
            'created': now,
          });
        }
      }
      // Уже имеющиеся встроенные цитаты не дублируем.
      final existing = <String>{};
      for (final r in await txn
          .query('quotes', columns: ['text'], where: 'builtin = 1')) {
        existing.add(r['text'] as String);
      }
      final batch = txn.batch();
      for (final q in (data['quotes'] as List)) {
        final m = q as Map<String, dynamic>;
        final text = m['t'] as String;
        if (existing.contains(text)) continue;
        batch.insert('quotes', {
          'text': text,
          'author': m['a'] ?? '',
          'source_id': ids[m['s']] ?? 0,
          'builtin': 1,
          'created': now,
        });
      }
      await batch.commit(noResult: true);
    });
    await setSetting('seed_version', '$_seedVersion');
  }

  // ---------- Настройки ----------

  String setting(String key, [String def = '']) => _settings[key] ?? def;

  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    await _db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  // ---------- Цитаты ----------

  static const _quoteSelect = '''
    SELECT q.id, q.text, q.author, q.source_id, q.favorite, q.builtin,
           s.name AS source_name, s.url AS source_url
    FROM quotes q LEFT JOIN sources s ON s.id = q.source_id''';

  /// Цитаты, участвующие в «слове дня»: из включённых источников.
  /// Порядок — по id, чтобы перемешивание было воспроизводимым.
  Future<List<Quote>> dailyPool() async {
    final rows = await _db.rawQuery(
        '$_quoteSelect WHERE s.enabled = 1 ORDER BY q.id');
    return rows.map(Quote.fromRow).toList();
  }

  Future<List<Quote>> search({
    String text = '',
    bool favoritesOnly = false,
    int? sourceId,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (favoritesOnly) where.add('q.favorite = 1');
    if (sourceId != null) {
      where.add('q.source_id = ?');
      args.add(sourceId);
    }
    final rows = await _db.rawQuery(
      '$_quoteSelect ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY q.author COLLATE NOCASE, q.id',
      args,
    );
    var list = rows.map(Quote.fromRow).toList();
    final needle = text.trim().toLowerCase();
    if (needle.isNotEmpty) {
      // SQLite LOWER() не умеет кириллицу, поэтому фильтруем в Dart.
      list = list
          .where((q) =>
              q.text.toLowerCase().contains(needle) ||
              q.author.toLowerCase().contains(needle))
          .toList();
    }
    return list;
  }

  Future<Quote?> quote(int id) async {
    final rows =
        await _db.rawQuery('$_quoteSelect WHERE q.id = ? LIMIT 1', [id]);
    return rows.isEmpty ? null : Quote.fromRow(rows.first);
  }

  Future<void> setFavorite(int id, bool fav) async {
    await _db.update('quotes', {'favorite': fav ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<int> addQuote(String text, String author, int sourceId) async {
    final id = await _db.insert('quotes', {
      'text': text.trim(),
      'author': author.trim(),
      'source_id': sourceId,
      'builtin': 0,
      'created': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
    return id;
  }

  Future<int> addQuotes(List<(String, String)> items, int sourceId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = _db.batch();
    for (final (text, author) in items) {
      batch.insert('quotes', {
        'text': text.trim(),
        'author': author.trim(),
        'source_id': sourceId,
        'builtin': 0,
        'created': now,
      });
    }
    await batch.commit(noResult: true);
    notifyListeners();
    return items.length;
  }

  Future<void> updateQuote(int id, String text, String author) async {
    await _db.update('quotes', {'text': text.trim(), 'author': author.trim()},
        where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> deleteQuote(int id) async {
    await _db.delete('quotes', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<List<String>> authors() async {
    final rows = await _db.rawQuery(
        "SELECT DISTINCT author FROM quotes WHERE author <> '' "
        'ORDER BY author COLLATE NOCASE');
    return rows.map((r) => r['author'] as String).toList();
  }

  Future<int> quoteCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM quotes');
    return (r.first['c'] as int?) ?? 0;
  }

  // ---------- Источники ----------

  Future<List<Source>> sources() async {
    final rows = await _db.rawQuery('''
      SELECT s.*, (SELECT COUNT(*) FROM quotes q WHERE q.source_id = s.id) AS cnt
      FROM sources s
      ORDER BY s.builtin ASC, cnt DESC, s.name COLLATE NOCASE''');
    return rows.map(Source.fromRow).toList();
  }

  Future<Source?> source(int id) async {
    final rows = await _db.rawQuery('''
      SELECT s.*, (SELECT COUNT(*) FROM quotes q WHERE q.source_id = s.id) AS cnt
      FROM sources s WHERE s.id = ? LIMIT 1''', [id]);
    return rows.isEmpty ? null : Source.fromRow(rows.first);
  }

  Future<int> addSource(String name, String url, String note) async {
    final id = await _db.insert('sources', {
      'name': name.trim(),
      'url': url.trim(),
      'note': note.trim(),
      'enabled': 1,
      'builtin': 0,
      'created': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
    return id;
  }

  Future<void> updateSource(int id, String name, String url, String note) async {
    await _db.update(
        'sources', {'name': name.trim(), 'url': url.trim(), 'note': note.trim()},
        where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> setSourceEnabled(int id, bool on) async {
    await _db.update('sources', {'enabled': on ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  /// Удаляет источник вместе с его цитатами.
  Future<void> deleteSource(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('quotes', where: 'source_id = ?', whereArgs: [id]);
      await txn.delete('sources', where: 'id = ?', whereArgs: [id]);
    });
    notifyListeners();
  }

  /// «Мои цитаты» — источник по умолчанию для добавленного вручную.
  Future<int> myQuotesSourceId() async {
    final rows = await _db.query('sources',
        columns: ['id'], where: 'skey = ?', whereArgs: ['mine'], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    final id = await _db.insert('sources', {
      'skey': 'mine',
      'name': 'Мои цитаты',
      'url': '',
      'note': 'Добавленные вручную',
      'enabled': 1,
      'builtin': 0,
      'created': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
    return id;
  }
}
