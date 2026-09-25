// Ibasho — Odori: el charter, que convierte la partitura base en notas para
// k teclas y cinco dificultades.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'odori_song.dart';

enum OdoriDifficulty {
  easy(nps: 1.4, minGap: .30, holdFrom: 2),
  normal(nps: 2.4, minGap: .18, holdFrom: 1.5),
  hard(nps: 3.8, minGap: .12, holdFrom: 1),
  extreme(nps: 5.4, minGap: .085, holdFrom: 1),
  impossible(nps: 7.5, minGap: .06, holdFrom: .75);

  const OdoriDifficulty({required this.nps, required this.minGap, required this.holdFrom});

  /// Notas por segundo que se buscan con 5 teclas.
  final double nps;

  /// Separacion minima entre dos notas, en segundos.
  final double minGap;

  /// Pulsos que tiene que durar una nota de la melodia para ser larga.
  final double holdFrom;

  /// Por cuanto se multiplican los puntos en la clasificacion: una S en
  /// Hard vale el doble que en Easy.
  double get boardWeight => switch (this) {
    OdoriDifficulty.easy => .5,
    OdoriDifficulty.normal => .75,
    OdoriDifficulty.hard => 1,
    OdoriDifficulty.extreme => 1.25,
    OdoriDifficulty.impossible => 1.5,
  };
}

/// La puntuacion de una partida en la clasificacion de Odori, o `null` si no
/// cuenta: solo entran las de 4 teclas y sin ayuda del Tama, para que todo
/// el mundo compita en lo mismo. Taki y Butai van en tablas separadas
/// (`LeaderboardGame.odori` y `odoriButai`).
int? odoriBoardScore(
  int score,
  OdoriDifficulty difficulty, {
  required int keys,
  required bool assisted,
}) {
  if (keys != 4 || assisted) return null;
  return (score * difficulty.boardWeight).round();
}

/// Teclas con las que se puede jugar.
const int odoriMinKeys = 1;
const int odoriMaxKeys = 7;

/// Con pocas teclas se buscan menos notas; con muchas, algunas mas.
double keysDensity(int keys) => const [.55, .7, .8, .9, 1.0, 1.08, 1.15][keys.clamp(1, 7) - 1];

/// Una nota del chart. Si [end] es mayor que [time], es larga: se mantiene.
@immutable
class ChartNote {
  const ChartNote(this.time, this.lane, [double? end]) : end = end ?? time;

  final double time;
  final double end;
  final int lane;

  bool get hold => end > time;

  ChartNote withEnd(double end) => ChartNote(time, lane, end);
}

@immutable
class OdoriChart {
  const OdoriChart({required this.keys, required this.difficulty, required this.notes});

  final int keys;
  final OdoriDifficulty difficulty;

  /// Ordenadas por tiempo y, a igual tiempo, por carril.
  final List<ChartNote> notes;

  /// Juicios de una partida entera: uno por nota y otro por el final de
  /// cada larga.
  int get judgments => notes.length + notes.where((n) => n.hold).length;
}

class _Onset {
  _Onset(this.q);

  /// Posicion en doceavos de pulso.
  final int q;
  final Set<String> roles = <String>{};
  bool accent = false;
  int? pitch;
  double melodyLength = 0;
  double time = 0;
  double priority = 0;
  bool get drumsOnly => pitch == null;
}

const Map<String, double> _roleWeight = {
  'l': 3.0,
  'v': 3.0,
  'x': 2.6,
  'k': 2.2,
  's': 2.0,
  'c': 1.5,
  'b': 1.3,
  'a': .9,
  'o': .7,
  'h': .35,
};

/// Semilla estable (FNV-1a): `String.hashCode` no promete ser igual entre
/// ejecuciones.
int odoriSeed(String text) {
  var h = 0x811c9dc5;
  for (final c in text.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// En Butai hay que mirar a donde cae cada nota antes de tocarla: se buscan
/// bastantes menos notas, mas separadas y con acordes mas pequeños.
const double butaiDensity = .55;
const double butaiGap = 1.7;

/// Hace el chart de [score] para [keys] teclas en [difficulty]. Sale siempre
/// igual para la misma partitura.
OdoriChart buildChart(OdoriScore score, {required int keys, required OdoriDifficulty difficulty, bool butai = false}) {
  keys = keys.clamp(odoriMinKeys, odoriMaxKeys);
  final spb = score.secondsPerBeat;

  // 1. Onsets: los eventos agrupados a 1/12 de pulso.
  final byQ = <int, _Onset>{};
  for (final e in score.events) {
    final q = (e.beat * 12).round();
    final o = byQ.putIfAbsent(q, () => _Onset(q));
    o.roles.add(e.role);
    if (e.accent) o.accent = true;
    if (e.melodic) {
      // Con dos voces, manda la de arriba.
      if (o.pitch == null || e.pitch > o.pitch!) o.pitch = e.pitch;
      o.melodyLength = math.max(o.melodyLength, e.length);
    }
  }
  final onsets = byQ.values.toList()..sort((a, b) => a.q.compareTo(b.q));
  if (onsets.isEmpty) return OdoriChart(keys: keys, difficulty: difficulty, notes: const []);

  // 2. Prioridad: rol × posicion en el compas × energia de la seccion.
  for (final o in onsets) {
    final beat = o.q / 12;
    o.time = score.timeOf(beat);
    var best = 0.0;
    var sum = 0.0;
    for (final r in o.roles) {
      final w = _roleWeight[r] ?? .5;
      best = math.max(best, w);
      sum += w;
    }
    final roleW = best + .25 * (sum - best);
    final double pos;
    if (o.q % 48 == 0) {
      pos = 1.5;
    } else if (o.q % 12 == 0) {
      pos = 1.25;
    } else if (o.q % 6 == 0) {
      pos = 1.0;
    } else if (o.q % 3 == 0) {
      pos = .8;
    } else {
      pos = .65;
    }
    final energy = .55 + .15 * score.energyAt(beat);
    o.priority = roleW * pos * energy * (o.accent ? 1.25 : 1);
  }

  // 3. Seleccion: las de mas prioridad, respetando la separacion minima,
  // hasta la densidad buscada.
  final span = math.max(1.0, onsets.last.time - onsets.first.time);
  final target = (difficulty.nps * keysDensity(keys) * (butai ? butaiDensity : 1) * span).round();
  final ranked = [...onsets]
    ..sort((a, b) {
      final c = b.priority.compareTo(a.priority);
      return c != 0 ? c : a.q.compareTo(b.q);
    });
  final picked = SplayTreeMap<double, _Onset>();
  final minGap = difficulty.minGap * (butai ? butaiGap : 1);
  final gap = minGap - 1e-6;
  for (final o in ranked) {
    if (picked.length >= target) break;
    final before = picked.lastKeyBefore(o.time);
    final after = picked.firstKeyAfter(o.time);
    if (picked.containsKey(o.time)) continue;
    if (before != null && o.time - before < gap) continue;
    if (after != null && after - o.time < gap) continue;
    picked[o.time] = o;
  }

  // Si la cancion no da para tantos golpes, lo que falta sale en acordes,
  // en los golpes que mas pesan.
  final extra = <_Onset, int>{};
  final maxChord = _maxChord(keys, difficulty, butai: butai);
  var missing = target - picked.length;
  if (missing > 0 && maxChord > 1) {
    final strong = picked.values.toList()..sort((a, b) => b.priority.compareTo(a.priority));
    for (var size = 2; size <= maxChord && missing > 0; size++) {
      for (final o in strong) {
        if (missing <= 0) break;
        if (_chordSize(o, keys, difficulty) + (extra[o] ?? 0) >= size) continue;
        extra[o] = (extra[o] ?? 0) + 1;
        missing--;
      }
    }
  }

  // 4. Carriles, acordes y largas.
  final rnd = math.Random(odoriSeed('${score.id}/$keys/${difficulty.index}'));
  final lastAt = List<double>.filled(keys, -99);
  final freeAt = List<double>.filled(keys, -99);
  final holdIndex = List<int?>.filled(keys, null);
  final usage = List<int>.filled(keys, 0);
  final notes = <ChartNote>[];
  var prevLane = keys ~/ 2;
  int? prevPitch;

  for (final o in picked.values) {
    final t = o.time;
    // Si una larga ocupa todos los carriles, se corta la que acaba antes.
    var free = [
      for (var j = 0; j < keys; j++)
        if (freeAt[j] <= t) j,
    ];
    if (free.isEmpty) {
      var j = 0;
      for (var i = 1; i < keys; i++) {
        if (freeAt[i] < freeAt[j]) j = i;
      }
      final idx = holdIndex[j]!;
      final held = notes[idx];
      final cut = t - math.max(minGap, .12);
      notes[idx] = cut - held.time >= .2 ? held.withEnd(cut) : ChartNote(held.time, held.lane);
      lastAt[j] = notes[idx].end;
      freeAt[j] = t;
      holdIndex[j] = null;
      free = [j];
    }

    final size = math.min(
      free.length,
      math.min(maxChord, _chordSize(o, keys, difficulty, butai: butai) + (extra[o] ?? 0)),
    );
    final chosen = <int>[];
    final mean = usage.fold<int>(0, (a, b) => a + b) / keys;
    for (var n = 0; n < size; n++) {
      int? bestLane;
      var bestCost = double.infinity;
      for (final j in free) {
        if (chosen.contains(j)) continue;
        var c = 0.0;
        // Sin martilleo: la misma tecla muy seguida cansa.
        final since = t - lastAt[j];
        if (since < .22) {
          c += 4;
        } else if (since < .36) {
          c += 1.5;
        }
        if (n == 0) {
          final p = o.pitch;
          final pp = prevPitch;
          if (p != null && pp != null) {
            // La mano sigue el contorno de la melodia.
            final dp = p - pp;
            final step = dp == 0 ? 0 : (dp / 2.5).round().clamp(-2, 2);
            final desired = (prevLane + (dp != 0 && step == 0 ? dp.sign : step)).clamp(0, keys - 1);
            c += .7 * (j - desired).abs();
            if (dp > 0 && j < prevLane) c += 1.2;
            if (dp < 0 && j > prevLane) c += 1.2;
          } else if (o.drumsOnly && keys > 1) {
            // Bombo a la izquierda, caja a la derecha.
            final x = j / (keys - 1);
            if (o.roles.contains('k') && !o.roles.contains('s')) c += 1.2 * x;
            if (o.roles.contains('s')) c += 1.2 * (1 - x);
          }
        } else {
          // Las otras notas del acorde, lejos de la primera.
          c -= .5 * (j - chosen.first).abs();
        }
        c += .5 * (usage[j] - mean) / math.max(1, mean);
        c += rnd.nextDouble() * .35;
        if (c < bestCost) {
          bestCost = c;
          bestLane = j;
        }
      }
      if (bestLane == null) break;
      chosen.add(bestLane);
    }

    for (var n = 0; n < chosen.length; n++) {
      final j = chosen[n];
      final long = n == 0 && keys > 0 && o.melodyLength >= difficulty.holdFrom;
      final end = long ? t + o.melodyLength * spb * .9 : t;
      final isHold = long && end - t >= .35;
      notes.add(ChartNote(t, j, isHold ? end : null));
      usage[j]++;
      lastAt[j] = isHold ? end : t;
      freeAt[j] = isHold ? end + math.max(minGap, .1) : t + 1e-6;
      holdIndex[j] = isHold ? notes.length - 1 : null;
    }
    if (chosen.isNotEmpty) prevLane = chosen.first;
    if (o.pitch != null) prevPitch = o.pitch;
  }

  notes.sort((a, b) {
    final c = a.time.compareTo(b.time);
    return c != 0 ? c : a.lane.compareTo(b.lane);
  });
  return OdoriChart(keys: keys, difficulty: difficulty, notes: List.unmodifiable(notes));
}

/// Acorde mas grande que se permite: nunca todas las teclas a la vez (salvo
/// con dos). En Butai, como mucho dos.
int _maxChord(int keys, OdoriDifficulty d, {bool butai = false}) {
  if (keys < 2) return 1;
  final cap = butai ? 2 : (keys == 2 ? 2 : keys - 1);
  return math.min(cap, switch (d) {
    OdoriDifficulty.easy => 1,
    OdoriDifficulty.normal => 2,
    OdoriDifficulty.hard => 2,
    OdoriDifficulty.extreme => 3,
    OdoriDifficulty.impossible => 4,
  });
}

/// Cuantas notas a la vez: acordes desde Normal y solo en los acentos. En
/// Butai, desde Difícil.
int _chordSize(_Onset o, int keys, OdoriDifficulty d, {bool butai = false}) {
  if (keys < 2 || !o.accent) return 1;
  if (butai && d.index < OdoriDifficulty.hard.index) return 1;
  final downbeat = o.q % 48 == 0;
  final crash = o.roles.contains('x');
  return switch (d) {
    OdoriDifficulty.easy => 1,
    OdoriDifficulty.normal => downbeat ? 2 : 1,
    OdoriDifficulty.hard => 2,
    OdoriDifficulty.extreme || OdoriDifficulty.impossible => crash && keys >= 4 ? 3 : 2,
  };
}

/// Monedas por acabar una canción con rango C o mejor. Las reglas solo
/// aceptan subidas de 3, 5 u 8, con un tope de 30 al día en Odori.
int odoriRewardFor(OdoriDifficulty d) => switch (d) {
      OdoriDifficulty.easy || OdoriDifficulty.normal => 3,
      OdoriDifficulty.hard => 5,
      OdoriDifficulty.extreme || OdoriDifficulty.impossible => 8,
    };
