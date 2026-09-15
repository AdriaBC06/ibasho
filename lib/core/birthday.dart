// Ibasho — cumpleaños y hora local de otra persona.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

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

bool _isLeap(int year) => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
