import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'native.dart';
import 'screens/edit.dart';
import 'screens/prayers.dart';
import 'screens/quotes.dart';
import 'screens/settings.dart';
import 'screens/sources.dart';
import 'screens/today.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.open();
  Store.instance.addListener(Reminder.syncSoon);
  Reminder.sync();
  runApp(const SlovoApp());
}

class SlovoApp extends StatelessWidget {
  const SlovoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.instance,
      builder: (context, _) {
        final mode = switch (Store.instance.setting('theme', 'system')) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        return MaterialApp(
          title: 'Слово старца',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  static const _titles = [
    'Слово старца',
    'Все цитаты',
    'Молитвы',
    'Избранное',
    'Источники',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Наступил новый день или приложение долго не открывали —
      // обновить «слово дня» и расписание напоминаний.
      setState(() {});
      Reminder.sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => const TodayScreen(),
      1 => const QuotesScreen(key: ValueKey('all')),
      2 => const PrayersScreen(),
      3 => const QuotesScreen(key: ValueKey('fav'), favoritesOnly: true),
      _ => const SourcesScreen(),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        leadingWidth: 48,
        leading: const Center(child: CrossMark(size: 24)),
        actions: [
          const RadioVeraButton(),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: body,
      floatingActionButton: switch (_tab) {
        1 => FloatingActionButton(
            tooltip: 'Добавить цитату',
            onPressed: () => editQuote(context),
            child: const Icon(Icons.add),
          ),
        2 => FloatingActionButton(
            tooltip: 'Новая молитва',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PrayerEditScreen())),
            child: const Icon(Icons.add),
          ),
        4 => FloatingActionButton.extended(
            onPressed: () async {
              final id = await editSource(context);
              if (id != null && context.mounted) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SourceScreen(sourceId: id)));
              }
            },
            icon: const Icon(Icons.add_link),
            label: const Text('Источник'),
          ),
        _ => null,
      },
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Подписи меню не увеличиваем вместе с системным шрифтом,
          // иначе «Избранное» и «Источники» переносятся по буквам.
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.0),
            ),
            child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  selectedIcon: Icon(Icons.wb_sunny),
                  label: 'Сегодня'),
              NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: 'Цитаты'),
              NavigationDestination(
                  icon: Icon(Icons.auto_stories_outlined),
                  selectedIcon: Icon(Icons.auto_stories),
                  label: 'Молитвы'),
              NavigationDestination(
                  icon: Icon(Icons.favorite_border),
                  selectedIcon: Icon(Icons.favorite),
                  label: 'Избранное'),
              NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books),
                  label: 'Источники'),
            ],
          ),
          ),
        ],
      ),
    );
  }
}
