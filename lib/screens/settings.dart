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

  @override
  void initState() {
    super.initState();
    store.addListener(_rebuild);
    store.quoteCount().then((c) {
      if (mounted) setState(() => _count = c);
    });
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
        header('О приложении'),
        ListTile(
          leading: const CrossMark(size: 24),
          title: const Text('Слово старца'),
          subtitle: Text('В базе ${pluralQuotes(_count)}. Источники и ссылки '
              'на них — на вкладке «Источники».'),
        ),
      ]),
    );
  }
}
