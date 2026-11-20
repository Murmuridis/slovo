import 'package:flutter/material.dart';

import '../daily.dart';
import '../native.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final store = Store.instance;
  late final _radio = TextEditingController(text: store.setting('radio_url'));
  int _count = 0;
  int _prayers = 0;

  @override
  void initState() {
    super.initState();
    store.addListener(_rebuild);
    _counts();
  }

  Future<void> _counts() async {
    try {
      final c = await store.quoteCount();
      final pr = await store.prayerCount();
      if (mounted) {
        setState(() {
          _count = c;
          _prayers = pr;
        });
      }
    } catch (_) {}
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// Затемнить экран на время долгой операции.
  Future<T> _withProgress<T>(String text, Future<T> Function() work) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(text)),
          ]),
        ),
      ),
    );
    try {
      return await work();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _backup() async {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'slovo-backup-${d.year}-${two(d.month)}-${two(d.day)}.zip';
    final uri = await Native.createDocument(name, 'application/zip');
    if (uri == null || !mounted) return;
    final err = await _withProgress('Сохраняю копию…', () async {
      await Native.audioStop();
      await store.close();
      try {
        return await Native.writeBackup(uri, store.dbPath);
      } finally {
        await store.open();
      }
    });
    _toast(err ?? 'Резервная копия сохранена: $name');
  }

  Future<void> _restore() async {
    final uri = await Native.openDocument();
    if (uri == null || !mounted) return;
    final info = await Native.checkBackup(uri);
    if (!mounted) return;
    if (info['ok'] != true) {
      _toast('${info['error'] ?? 'Это не резервная копия'}');
      return;
    }
    final created = info['created'] as int? ?? 0;
    final when = created > 0
        ? ' от ${formatDate(DateTime.fromMillisecondsSinceEpoch(created))}'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Восстановить копию$when?'),
        content: Text(
            'Все текущие цитаты, избранное, источники, молитвы и настройки '
            'будут заменены данными из копии. Файлов картинок и аудио в копии: '
            '${info['media'] ?? 0}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Восстановить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await _withProgress('Восстанавливаю…', () async {
      await Native.audioStop();
      await store.close();
      try {
        return await Native.restoreBackup(uri, store.dbPath);
      } finally {
        await store.open();
      }
    });
    await Reminder.sync();
    _radio.text = store.setting('radio_url');
    _counts();
    _toast(err ?? 'Данные восстановлены');
  }

  @override
  void dispose() {
    store.removeListener(_rebuild);
    _radio.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _setReminder(bool on) async {
    if (on) {
      final allowed = await Native.requestNotificationPermission();
      if (!allowed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Разрешите уведомления для «Слова старца» '
                'в настройках телефона, иначе напоминание не появится.')));
      }
    }
    await store.setSetting('reminder_on', on ? '1' : '0');
    await Reminder.sync();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: Reminder.hour, minute: Reminder.minute),
      helpText: 'Время напоминания',
    );
    if (t == null) return;
    await store.setSetting('reminder_hour', '${t.hour}');
    await store.setSetting('reminder_minute', '${t.minute}');
    await Reminder.sync();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = textScale();
    final mode = store.setting('theme', 'system');
    final time =
        '${Reminder.hour.toString().padLeft(2, '0')}:${Reminder.minute.toString().padLeft(2, '0')}';
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(t,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  letterSpacing: 0.5)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        header('Напоминание'),
        SwitchListTile(
          title: const Text('Присылать слово дня'),
          subtitle: const Text('Уведомление с сегодняшней цитатой'),
          value: Reminder.enabled,
          onChanged: _setReminder,
        ),
        ListTile(
          enabled: Reminder.enabled,
          leading: const Icon(Icons.schedule),
          title: const Text('Время'),
          trailing: Text(time,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          onTap: Reminder.enabled ? _pickTime : null,
        ),
        header('Текст'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Смиряйся, и все дела твои пойдут.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: quoteFont, fontSize: 21 * scale),
          ),
        ),
        Slider(
          value: scale.clamp(0.8, 1.6).toDouble(),
          min: 0.8,
          max: 1.6,
          divisions: 8,
          label: '${(scale * 100).round()}%',
          onChanged: (v) => store.setSetting('text_scale', v.toStringAsFixed(2)),
        ),
        header('Оформление'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('Как в системе')),
              ButtonSegment(value: 'light', label: Text('Светлое')),
              ButtonSegment(value: 'dark', label: Text('Тёмное')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => store.setSetting('theme', v.first),
          ),
        ),
        header('Радио ВЕРА'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _radio,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Адрес потока',
              hintText: defaultRadioUrl,
              helperText: 'Оставьте пустым — будет основной эфир',
              suffixIcon: IconButton(
                tooltip: 'Сбросить',
                icon: const Icon(Icons.restart_alt),
                onPressed: () {
                  _radio.clear();
                  store.setSetting('radio_url', '');
                },
              ),
            ),
            onChanged: (v) => store.setSetting('radio_url', v.trim()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Сайт радио'),
          subtitle: const Text('radiovera.ru — программы и архив'),
          onTap: () => Native.openUrl(radioSite),
        ),
        header('Резервная копия'),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: const Text('Сохранить копию'),
          subtitle: const Text('Цитаты, избранное, источники, молитвы с '
              'картинками и аудио, настройки — в один файл .zip. Сохраните его '
              'на Google Диск или в «Загрузки».'),
          isThreeLine: true,
          onTap: _backup,
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: const Text('Восстановить из копии'),
          subtitle: const Text('Например, на новом телефоне'),
          onTap: _restore,
        ),
        header('О приложении'),
        ListTile(
          leading: const CrossMark(size: 24),
          title: const Text('Слово старца'),
          subtitle: Text('В базе ${pluralQuotes(_count)}, молитв: $_prayers. '
              'Источники и ссылки на них — на вкладке «Источники».'),
        ),
      ]),
    );
  }
}
