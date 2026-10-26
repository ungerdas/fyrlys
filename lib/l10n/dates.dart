// Dager og måneder på språket appen vises på.

import 'tr.dart';

const _weekdaysNo = ['mandag', 'tirsdag', 'onsdag', 'torsdag', 'fredag', 'lørdag', 'søndag'];
const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthsNo = ['januar', 'februar', 'mars', 'april', 'mai', 'juni', 'juli', 'august', 'september', 'oktober',
    'november', 'desember'];
const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
    'November', 'December'];

bool get _en => appLanguage == 'en';

/// «lørdag» / «Saturday» (1 = mandag, som DateTime.weekday)
String weekdayName(int weekday) => (_en ? _weekdaysEn : _weekdaysNo)[weekday - 1];

/// «oktober» / «October» (1 = januar)
String monthName(int month) => (_en ? _monthsEn : _monthsNo)[month - 1];

/// «Lørdag 24. oktober» / «Saturday 24 October»
String longDate(DateTime t) {
  final day = weekdayName(t.weekday);
  if (_en) return '$day ${t.day} ${monthName(t.month)}';
  return '${day[0].toUpperCase()}${day.substring(1)} ${t.day}. ${monthName(t.month)}';
}

/// «24.10.2026» / «24/10/2026»
String shortDate(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return _en ? '${two(t.day)}/${two(t.month)}/${t.year}' : '${two(t.day)}.${two(t.month)}.${t.year}';
}
