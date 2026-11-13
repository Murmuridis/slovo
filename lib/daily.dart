import 'store.dart';

/// Выбор «слова дня».
///
/// Все цитаты из включённых источников раскладываются в постоянном
/// перемешанном порядке, и каждый день берётся следующая. Так подряд
/// не повторяется ни одна цитата, пока не будут показаны все, а в один
/// и тот же день у приложения и у напоминания — одна и та же цитата.
class Daily {
  /// Номер дня: сколько календарных дней прошло с 1 января 2000 года.
  static int dayNumber(DateTime d) {
    final utc = DateTime.utc(d.year, d.month, d.day);
    return utc.difference(DateTime.utc(2000, 1, 1)).inDays;
  }

  /// Перемешивание по id: не зависит от того, как цитаты лежат в базе.
  static List<Quote> order(List<Quote> pool) {
    final list = List<Quote>.of(pool);
    list.sort((a, b) {
      final c = _mix(a.id).compareTo(_mix(b.id));
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return list;
  }

  static int _mix(int x) {
    // Простой целочисленный хеш (вариант splitmix), ограниченный 31 битом.
    var z = (x * 0x9E3779B1) & 0x7fffffff;
    z = ((z ^ (z >> 15)) * 0x85EBCA6B) & 0x7fffffff;
    z = ((z ^ (z >> 13)) * 0xC2B2AE35) & 0x7fffffff;
    return z ^ (z >> 16);
  }

  static Quote? forDay(List<Quote> ordered, DateTime day) {
    if (ordered.isEmpty) return null;
    return ordered[dayNumber(day) % ordered.length];
  }
}

const _months = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];
const _weekdays = [
  'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота',
  'воскресенье',
];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatWeekday(DateTime d) => _weekdays[d.weekday - 1];

/// Дата по старому (юлианскому) стилю — для XX–XXI веков разница 13 дней.
String formatOldStyle(DateTime d) {
  final o = d.subtract(const Duration(days: 13));
  return '${o.day} ${_months[o.month - 1]} ст. ст.';
}

String pluralQuotes(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n цитата';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n цитаты';
  return '$n цитат';
}
