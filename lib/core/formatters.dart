import 'dart:math' as math;

import 'package:flutter/material.dart';

String compactNumber(int value) {
  final int safe = math.max(0, value);
  if (safe < 1000) {
    return safe.toString();
  }
  final double thousands = safe / 1000;
  if (thousands < 100) {
    return '${_decimal(thousands)}k';
  }
  if (safe < 1000000) {
    return '${(safe / 1000).round()}k';
  }
  final double millions = safe / 1000000;
  return '${_decimal(millions)}M';
}

String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

const List<String> _monthsPt = <String>[
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

const List<String> _monthsEn = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String monthShort(int month, {required bool en}) {
  if (month < 1 || month > 12) {
    return '';
  }
  return en ? _monthsEn[month - 1] : _monthsPt[month - 1];
}

String formatMonthYear(DateTime? date, {required bool en}) {
  if (date == null) {
    return '—';
  }
  return '${monthShort(date.month, en: en)} ${date.year}';
}

String formatDate(DateTime? date, {required bool en}) {
  if (date == null) {
    return '—';
  }
  return '${date.day.toString().padLeft(2, '0')} ${monthShort(date.month, en: en)} ${date.year}';
}

String relativeDay(DateTime? date, {required bool en}) {
  if (date == null) {
    return '—';
  }
  final DateTime now = DateTime.now();
  final int days = now.difference(date).inDays;
  if (days <= 0) {
    return en ? 'today' : 'hoje';
  }
  if (days == 1) {
    return en ? 'yesterday' : 'ontem';
  }
  if (days < 30) {
    return en ? '$days days ago' : 'há $days dias';
  }
  return formatDate(date, en: en);
}

String initialsOf(String title) {
  const Set<String> skip = <String>{
    'the', 'a', 'an', 'of', 'de', 'do', 'da', 'dos', 'das', 'o', 'os', 'as', 'e', 'and', 'in', 'on',
  };
  final List<String> words = title
      .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((String word) => word.trim().isNotEmpty)
      .where((String word) => !skip.contains(word.toLowerCase()))
      .toList(growable: false);
  if (words.isEmpty) {
    return 'P';
  }
  final StringBuffer buffer = StringBuffer();
  for (final String word in words.take(2)) {
    buffer.write(word.substring(0, 1).toUpperCase());
  }
  return buffer.toString();
}

int stableHash(String input) {
  int hash = 0x811c9dc5;
  for (final int unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

double hueFor(String seed) => (stableHash(seed) % 360).toDouble();

String formatRating(double value) {
  if (value <= 0) {
    return '—';
  }
  return value.toStringAsFixed(1).replaceAll('.', ',');
}

String formatPercent(double value) => '${(value.clamp(0, 1) * 100).round()}%';

String truncate(String input, int maxChars) {
  if (input.length <= maxChars) {
    return input;
  }
  return '${input.substring(0, math.max(0, maxChars - 1)).trimRight()}…';
}

String greetingFor(DateTime time, {required bool en}) {
  final int hour = time.hour;
  if (hour < 12) {
    return en ? 'Good morning' : 'Bom dia';
  }
  if (hour < 18) {
    return en ? 'Good afternoon' : 'Boa tarde';
  }
  return en ? 'Good evening' : 'Boa noite';
}

// Paleta determinística para capas ausentes: cada jogo ganha um par de cores
// estável, escuro o bastante para manter contraste com texto claro.
List<Color> coverColorsFor(String seed) {
  final double hue = hueFor(seed);
  final Color top = HSLColor.fromAHSL(1, hue, 0.52, 0.24).toColor();
  final Color bottom = HSLColor.fromAHSL(1, (hue + 42) % 360, 0.62, 0.10).toColor();
  return <Color>[top, bottom];
}
