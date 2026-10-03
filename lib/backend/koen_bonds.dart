// Ibasho — Tama Kōen: la amistad entre Tamas y entre jugadores.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'koen.dart';
import 'koen_rewards.dart';

/// Lo que lleva sumado una amistad: los puntos ([p]) y cuántos de ellos son
/// del día [d] ([n]). Así, al volver a contar los encuentros de hoy, solo se
/// suma lo nuevo. Se guarda como `{p, d, n}` y las reglas comprueban que
/// `p` solo crece lo mismo que `n`.
@immutable
class KoenTally {
  const KoenTally({this.p = 0, this.d = 0, this.n = 0});

  final int p;
  final int d;
  final int n;

  static KoenTally fromJson(Object? raw) {
    if (raw is! Map) return const KoenTally();
    int at(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    return KoenTally(p: at('p'), d: at('d'), n: at('n'));
  }

  Map<String, int> toJson() => {'p': p, 'd': d, 'n': n};

  /// Con [total] encuentros contados hoy ([day]). Igual si no hay nada nuevo.
  KoenTally count(int day, int total) {
    final before = d == day ? n : 0;
    if (total <= before) return this;
    return KoenTally(p: p + total - before, d: day, n: total);
  }

  @override
  bool operator ==(Object other) => other is KoenTally && other.p == p && other.d == d && other.n == n;

  @override
  int get hashCode => Object.hash(p, d, n);
}

// --- Entre Tamas -------------------------------------------------------------

/// Los puntos que hacen falta para cada nivel de amistad entre dos Tamas
/// (1–5) *(propuesta)*. Cada encuentro, natural o forzado, da 1.
const List<int> koenBondSteps = [0, 3, 8, 15, 25];

/// Como mucho, 1 encuentro natural y 3 forzados por pareja y día.
const int koenBondDailyCap = 1 + koenDragsPerPair;

int koenBondLevel(int points) {
  var level = 1;
  for (var i = 1; i < koenBondSteps.length; i++) {
    if (points >= koenBondSteps[i]) level = i + 1;
  }
  return level;
}

/// Desde este nivel, al encontrarse hacen su baile de pareja.
const int koenBondDanceLevel = 2;

/// Lo que da la amistad entre Tamas, la primera vez que una pareja propia
/// llega a cada nivel: un fondo para el menú y un gorro, que no salen en el
/// gacha.
const Map<int, String> koenBondPrizes = {3: 'bg_koen', 5: 'momiji_red'};

/// Lo bien que se conocen, de 0 a 1, para la conversación y los recuerdos.
/// Los de la misma cuenta ya se conocen de casa.
double koenBondCloseness(int points, {bool siblings = false}) {
  final c = (koenBondLevel(points) - 1) / (koenBondSteps.length - 1);
  return siblings && c < .6 ? .6 : c;
}

// --- Entre jugadores -----------------------------------------------------------

/// Los niveles de amistad entre dos jugadores, por los puntos de los dos
/// sumados *(propuesta)*. Cada encuentro de un Tama propio con uno del amigo
/// da 1 a quien lo cuenta; como lo cuentan los dos, sube el doble si entran
/// los dos.
enum KoenFriendLevel {
  none(0, 0),
  acquainted(1, 0),
  friends(20, 20),
  good(60, 40),
  inseparable(150, 60);

  const KoenFriendLevel(this.points, this.coins);

  /// Los puntos (de los dos) que hacen falta.
  final int points;

  /// Lo que cobra cada uno al llegar.
  final int coins;

  static KoenFriendLevel of(int points) =>
      values.lastWhere((l) => points >= l.points, orElse: () => none);
}

/// Como mucho, los 9 encuentros (3×3 Tamas) y sus forzados al día con un
/// amigo.
const int koenFriendDailyCap = koenSlots * koenSlots * koenBondDailyCap;

/// Cuántos puntos de amistad da hoy cada pareja de Tamas: el encuentro
/// natural (si ya ha pasado) más los forzados.
Map<String, int> koenTodayByPair({
  required List<KoenEncounter> all,
  required DateTime now,
  required int Function(String pairKey) drags,
  required Iterable<String> draggedPairs,
}) {
  final out = <String, int>{};
  for (final e in koenDone(all, now)) {
    out[e.pairKey] = (out[e.pairKey] ?? 0) + 1;
  }
  for (final key in draggedPairs) {
    final n = drags(key);
    if (n > 0) out[key] = (out[key] ?? 0) + n;
  }
  return out;
}
