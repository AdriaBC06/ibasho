// Ibasho — cumpleaños y hora local de otra persona.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import '../backend/models.dart';
import 'timezones.dart';

/// Si hoy es el cumpleaños de alguien, contado en **su** zona horaria: el dia
/// de fiesta es el suyo, no el de quien mira.
///
/// Quien nacio un 29 de febrero lo celebra el 28 los años que no son
/// bisiestos.
bool isBirthdayToday(UserProfile profile, DateTime now) {
  final parts = profile.birthdayParts;
  if (parts == null) return false;
  final local = wallClockIn(profile.timezone, now);
  var (_, month, day) = parts;
  if (month == 2 && day == 29 && !_isLeap(local.year)) day = 28;
  return local.month == month && local.day == day;
}

/// El año de su muro que toca hoy: el año en curso en su zona.
int wallYearFor(UserProfile profile, DateTime now) =>
    wallClockIn(profile.timezone, now).year;

/// Cuantos cumple hoy, o `null` si no se sabe o no es su dia.
int? ageToday(UserProfile profile, DateTime now) {
  final parts = profile.birthdayParts;
  if (parts == null || !isBirthdayToday(profile, now)) return null;
  final age = wallClockIn(profile.timezone, now).year - parts.$1;
  return age > 0 ? age : null;
}

/// Diferencia entre su hora y la mia en este instante. Positiva si va por
/// delante.
Duration zoneDifference(String theirs, String mine, DateTime now) {
  final them = offsetOfZone(theirs, now) ?? now.timeZoneOffset;
  final me = offsetOfZone(mine, now) ?? now.timeZoneOffset;
  return them - me;
}

/// El dia de su cumpleaños en un año dado. Quien nacio un 29 de febrero lo
/// celebra el 28 los años que no son bisiestos.
DateTime birthdayInYear(int month, int day, int year) =>
    DateTime(year, month, month == 2 && day == 29 && !_isLeap(year) ? 28 : day);

/// Un cumpleaños del calendario: el de un amigo o el propio
/// ([accountId] `null`).
@immutable
class BirthdayEntry {
  const BirthdayEntry({
    required this.accountId,
    required this.name,
    required this.year,
    required this.month,
    required this.day,
  });

  /// Del perfil, o `null` si no ha puesto cumpleaños.
  static BirthdayEntry? of(String? accountId, String name, UserProfile? profile) {
    final parts = profile?.birthdayParts;
    if (parts == null) return null;
    final (year, month, day) = parts;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return BirthdayEntry(accountId: accountId, name: name, year: year, month: month, day: day);
  }

  final String? accountId;
  final String name;
  final int year;
  final int month;
  final int day;

  bool get mine => accountId == null;

  /// El proximo cumpleaños desde [today] (solo cuenta la fecha); si es hoy,
  /// es hoy.
  DateTime nextFrom(DateTime today) {
    final start = DateTime(today.year, today.month, today.day);
    final thisYear = birthdayInYear(month, day, start.year);
    return thisYear.isBefore(start) ? birthdayInYear(month, day, start.year + 1) : thisYear;
  }

  /// Dias que faltan: 0 si es hoy.
  int daysFrom(DateTime today) {
    final start = DateTime.utc(today.year, today.month, today.day);
    final next = nextFrom(today);
    return DateTime.utc(next.year, next.month, next.day).difference(start).inDays;
  }

  /// Los que cumple en su proximo cumpleaños, o `null` si el año no cuadra.
  int? turnsFrom(DateTime today) {
    final age = nextFrom(today).year - year;
    return year > 1900 && age > 0 && age < 130 ? age : null;
  }

  /// El dia del mes en que cae ese año.
  int dayIn(int year) => birthdayInYear(month, day, year).day;
}

/// Los cumpleaños por orden de cercania: hoy primero; a igualdad, el propio
/// delante y luego por nombre.
List<BirthdayEntry> upcomingBirthdays(Iterable<BirthdayEntry> entries, DateTime today) {
  final list = entries.toList();
  list.sort((a, b) {
    final byDays = a.daysFrom(today).compareTo(b.daysFrom(today));
    if (byDays != 0) return byDays;
    if (a.mine != b.mine) return a.mine ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}

/// Los cumpleaños de un mes, por dia.
Map<int, List<BirthdayEntry>> birthdaysByDay(Iterable<BirthdayEntry> entries, int year, int month) {
  final days = <int, List<BirthdayEntry>>{};
  for (final e in upcomingBirthdays(entries, DateTime(year, month))) {
    if (e.month == month) (days[e.dayIn(year)] ??= []).add(e);
  }
  return days;
}

bool _isLeap(int year) => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
