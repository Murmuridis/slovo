import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native.dart';
import 'store.dart';
import 'theme.dart';

/// Восьмиконечный крест, нарисованный линиями.
class CrossMark extends StatelessWidget {
  final double size;
  final Color? color;
  const CrossMark({super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 0.62, size),
      painter: _CrossPainter(color ?? Theme.of(context).colorScheme.secondary),
    );
  }
}

class _CrossPainter extends CustomPainter {
  final Color color;
  _CrossPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = s.width * 0.11
      ..strokeCap = StrokeCap.round;
    final cx = s.width / 2;
    final h = s.height;
    canvas.drawLine(Offset(cx, h * 0.04), Offset(cx, h * 0.96), p);
    // верхняя короткая перекладина (титло)
    canvas.drawLine(
        Offset(cx - s.width * 0.22, h * 0.17), Offset(cx + s.width * 0.22, h * 0.17), p);
    // основная перекладина
    canvas.drawLine(
        Offset(cx - s.width * 0.48, h * 0.33), Offset(cx + s.width * 0.48, h * 0.33), p);
    // нижняя косая перекладина: левый (для смотрящего) конец выше
    canvas.drawLine(
        Offset(cx - s.width * 0.3, h * 0.68), Offset(cx + s.width * 0.3, h * 0.80), p);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}

/// Тонкая золотая черта с крестиком посередине.
class Ornament extends StatelessWidget {
  final double width;
  const Ornament({super.key, this.width = 180});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.secondary;
    Widget line() => Expanded(
          child: Container(height: 1, color: c.withValues(alpha: 0.7)),
        );
    return SizedBox(
      width: width,
      child: Row(children: [
        line(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: CrossMark(size: 18, color: c),
        ),
        line(),
      ]),
    );
  }
}

double textScale() =>
    double.tryParse(Store.instance.setting('text_scale', '1.0')) ?? 1.0;

/// Красиво набранная цитата: буквица-кавычка, текст, автор.
class QuoteText extends StatelessWidget {
  final Quote quote;
  final double fontSize;
  final bool showSource;
  const QuoteText({
    super.key,
    required this.quote,
    this.fontSize = 23,
    this.showSource = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = fontSize * textScale();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          quote.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: quoteFont,
            fontSize: size,
            height: 1.45,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 18),
        if (quote.author.isNotEmpty)
          Text(
            quote.author,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: quoteFont,
              fontStyle: FontStyle.italic,
              fontSize: size * 0.72,
              color: scheme.primary,
            ),
          ),
        if (showSource && quote.sourceName.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            quote.sourceName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Действия с цитатой: избранное, поделиться, скопировать.
class QuoteActions extends StatelessWidget {
  final Quote quote;
  final VoidCallback? onChanged;
  final List<Widget> extra;
  const QuoteActions({
    super.key,
    required this.quote,
    this.onChanged,
    this.extra = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: quote.favorite ? 'Убрать из избранного' : 'В избранное',
          icon: Icon(quote.favorite ? Icons.favorite : Icons.favorite_border,
              color: scheme.primary),
          onPressed: () async {
            await Store.instance.setFavorite(quote.id, !quote.favorite);
            onChanged?.call();
          },
        ),
        IconButton(
          tooltip: 'Поделиться',
          icon: const Icon(Icons.share_outlined),
          onPressed: () => Native.share(quote.shareText),
        ),
        IconButton(
          tooltip: 'Скопировать',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: quote.shareText));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Цитата скопирована')));
            }
          },
        ),
        ...extra,
      ],
    );
  }
}

// ---------------- Радио ВЕРА ----------------

const defaultRadioUrl = 'https://radiovera.hostingradio.ru:8007/radiovera_128';
const radioSite = 'https://radiovera.ru/';

String radioUrl() {
  final u = Store.instance.setting('radio_url', '').trim();
  return u.isEmpty ? defaultRadioUrl : u;
}

/// Полоска радио над нижним меню: включить / выключить «Радио ВЕРА».
class RadioBar extends StatefulWidget {
  const RadioBar({super.key});

  @override
  State<RadioBar> createState() => _RadioBarState();
}

class _RadioBarState extends State<RadioBar> {
  String _state = 'stopped';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final s = await Native.radioState();
    if (mounted && s != _state) setState(() => _state = s);
  }

  Future<void> _toggle() async {
    if (_state == 'playing' || _state == 'buffering') {
      await Native.radioStop();
      setState(() => _state = 'stopped');
    } else {
      setState(() => _state = 'buffering');
      await Native.radioPlay(radioUrl(), 'Радио ВЕРА');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playing = _state == 'playing';
    final buffering = _state == 'buffering';
    final status = switch (_state) {
      'playing' => 'В эфире',
      'buffering' => 'Подключаюсь…',
      'error' => 'Нет связи — нажмите ещё раз',
      _ => 'Светлое радио',
    };
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: _toggle,
        onLongPress: () => Native.openUrl(radioSite),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Icon(Icons.radio, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Радио ВЕРА',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                          fontSize: 15)),
                  Text(status,
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (buffering)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4)),
              ),
            IconButton.filled(
              tooltip: playing || buffering ? 'Выключить радио' : 'Включить радио',
              onPressed: _toggle,
              icon: Icon(playing || buffering ? Icons.stop : Icons.play_arrow),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Пустой экран с подсказкой.
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyHint({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: c),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: c)),
        ]),
      ),
    );
  }
}
