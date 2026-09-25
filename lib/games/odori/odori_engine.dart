// Ibasho — Odori: el juicio de cada toque, el combo y la puntuacion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'odori_chart.dart';

/// Lo que vale un toque. «¡brillo!», «bien», «vale» y «uy».
enum Judgment {
  brillo(1),
  bien(.7),
  vale(.4),
  miss(0);

  const Judgment(this.weight);

  /// Parte de los puntos de precision que da.
  final double weight;
}

/// Ventanas del juicio, en segundos a cada lado.
const double windowBrillo = .045;
const double windowBien = .090;
const double windowVale = .135;

/// Un toque antes de tiempo, hasta aqui, se come la nota como fallo.
const double windowEarlyMiss = .180;

/// Lo que se puede soltar una larga antes de su final sin perderla.
const double holdRelease = .135;

/// Puntos: 900 000 por precision y 100 000 por combo.
const int odoriMaxScore = 1000000;
const int _accuracyPoints = 900000;
const int _comboPoints = 100000;

enum OdoriRank {
  d('D'),
  c('C'),
  b('B'),
  a('A'),
  s('S'),
  sPlus('S+'),
  sPlusPlus('S++');

  const OdoriRank(this.label);
  final String label;
}

/// Un juicio que acaba de pasar, para pintarlo.
@immutable
class JudgeEvent {
  const JudgeEvent(this.judgment, this.lane, this.at, {this.delta, this.tail = false, this.helped = false});

  final Judgment judgment;
  final int lane;

  /// Tiempo de la partida en que se juzgo.
  final double at;

  /// Adelanto (negativo) o retraso del toque, si lo hubo.
  final double? delta;

  /// El final de una larga.
  final bool tail;

  /// La ayuda del Tama ha cambiado este juicio (o salvado el combo).
  final bool helped;
}

/// La ayuda pequeña del Tama que acompaña, segun su personalidad. Las
/// partidas con ayuda van a sus propios récords.
enum OdoriAssist {
  /// Tranquilo: todas las ventanas 15 ms mas anchas.
  wide,

  /// Juguetón: los 3 primeros fallos no rompen el combo.
  shield,

  /// Tímido: los toques antes de tiempo no cuentan como «uy».
  noEarly,

  /// Pícaro: salva 5 fallos, que se quedan en «vale».
  rescue,

  /// Dormilón: 30 ms mas de margen para los toques tardíos.
  lateWide;

  /// Veces que ayuda en una partida, si tiene tope.
  int? get uses => switch (this) {
        shield => 3,
        rescue => 5,
        _ => null,
      };
}

/// Estado de una nota durante la partida.
enum NoteState { pending, holding, done, missed }

/// Una partida de Taki: recibe toques y el paso del tiempo y juzga.
class OdoriEngine {
  OdoriEngine(this.chart, {this.assist})
      : state = List<NoteState>.filled(chart.notes.length, NoteState.pending),
        _total = math.max(1, chart.judgments);

  final OdoriChart chart;
  final OdoriAssist? assist;
  final List<NoteState> state;
  final int _total;

  /// Primera nota que aun puede estar pendiente, para no recorrer todas.
  int _cursor = 0;

  /// Larga que se esta manteniendo en cada carril.
  late final List<int?> _holding = List<int?>.filled(chart.keys, null);

  final Map<Judgment, int> counts = {for (final j in Judgment.values) j: 0};
  int combo = 0;
  int maxCombo = 0;
  int early = 0;
  int late = 0;
  double _weight = 0;

  /// Veces que ya ha ayudado el Tama.
  int helps = 0;

  double get _extra => assist == OdoriAssist.wide ? .015 : 0;
  double get _lateExtra => assist == OdoriAssist.lateWide ? .030 : 0;

  bool _canHelp(OdoriAssist a) => assist == a && helps < (a.uses ?? 1 << 30);

  /// Ventana de [base] para un toque con retraso [delta].
  double _window(double base, double delta) => base + _extra + (delta > 0 ? _lateExtra : 0);

  /// Juicios de la ultima llamada; los recoge la pantalla.
  final List<JudgeEvent> events = <JudgeEvent>[];

  int get judged => counts.values.fold(0, (a, b) => a + b);
  bool get finished => judged >= chart.judgments;
  int get misses => counts[Judgment.miss]!;

  /// Precision de 0 a 1 sobre lo ya juzgado.
  double get accuracy => judged == 0 ? 1 : _weight / judged;

  int get score => (_accuracyPoints * _weight / _total + _comboPoints * maxCombo / _total).round();

  OdoriRank get rank {
    if (finished && misses == 0) {
      return counts[Judgment.brillo] == chart.judgments ? OdoriRank.sPlusPlus : OdoriRank.sPlus;
    }
    final s = score;
    if (s >= 950000) return OdoriRank.s;
    if (s >= 900000) return OdoriRank.a;
    if (s >= 800000) return OdoriRank.b;
    if (s >= 700000) return OdoriRank.c;
    return OdoriRank.d;
  }

  bool isHolding(int lane) => _holding[lane] != null;

  void _judge(Judgment j, int lane, double at, {double? delta, bool tail = false}) {
    var helped = false;
    if (j == Judgment.miss && _canHelp(OdoriAssist.rescue)) {
      helps++;
      helped = true;
      j = Judgment.vale;
    }
    counts[j] = counts[j]! + 1;
    _weight += j.weight;
    if (j == Judgment.miss) {
      if (_canHelp(OdoriAssist.shield) && combo > 0) {
        helps++;
        helped = true;
      } else {
        combo = 0;
      }
    } else {
      combo++;
      maxCombo = math.max(maxCombo, combo);
    }
    events.add(JudgeEvent(j, lane, at, delta: delta, tail: tail, helped: helped));
  }

  /// Toque en [lane] en el tiempo [t] de la cancion.
  void press(int lane, double t) {
    if (lane < 0 || lane >= chart.keys) return;
    final notes = chart.notes;
    for (var i = _cursor; i < notes.length; i++) {
      final n = notes[i];
      if (n.time - t > windowEarlyMiss) break;
      if (n.lane != lane || state[i] != NoteState.pending) continue;
      final delta = t - n.time;
      if (delta > _window(windowVale, delta)) continue;
      final ad = delta.abs();
      final Judgment j;
      if (ad <= _window(windowBrillo, delta)) {
        j = Judgment.brillo;
      } else if (ad <= _window(windowBien, delta)) {
        j = Judgment.bien;
      } else if (ad <= _window(windowVale, delta)) {
        j = Judgment.vale;
      } else if (assist == OdoriAssist.noEarly) {
        // El Tama timido no deja que un toque pronto se coma la nota.
        return;
      } else {
        j = Judgment.miss;
      }
      if (j != Judgment.brillo && j != Judgment.miss) {
        if (delta < 0) {
          early++;
        } else {
          late++;
        }
      }
      _judge(j, lane, t, delta: delta);
      if (j == Judgment.miss) {
        // Una larga fallada de entrada pierde tambien su final.
        state[i] = NoteState.missed;
        if (n.hold) _judge(Judgment.miss, lane, t, tail: true);
      } else if (n.hold) {
        state[i] = NoteState.holding;
        _holding[lane] = i;
      } else {
        state[i] = NoteState.done;
      }
      return;
    }
  }

  /// Se suelta [lane] en el tiempo [t].
  void release(int lane, double t) {
    if (lane < 0 || lane >= chart.keys) return;
    final i = _holding[lane];
    if (i == null) return;
    _holding[lane] = null;
    final n = chart.notes[i];
    if (t >= n.end - holdRelease) {
      state[i] = NoteState.done;
      _judge(Judgment.brillo, lane, t, tail: true);
    } else {
      state[i] = NoteState.missed;
      _judge(Judgment.miss, lane, t, tail: true);
    }
  }

  /// Avanza el tiempo: lo que se paso sin tocar es fallo y las largas que
  /// llegan a su final se cierran solas.
  void advance(double t) {
    final notes = chart.notes;
    for (var i = _cursor; i < notes.length; i++) {
      final n = notes[i];
      if (n.time - t > windowVale) break;
      if (state[i] == NoteState.pending && t - n.time > windowVale + _extra + _lateExtra) {
        state[i] = NoteState.missed;
        _judge(Judgment.miss, n.lane, t);
        if (n.hold) _judge(Judgment.miss, n.lane, t, tail: true);
      }
    }
    for (var lane = 0; lane < chart.keys; lane++) {
      final i = _holding[lane];
      if (i != null && t >= notes[i].end) {
        _holding[lane] = null;
        state[i] = NoteState.done;
        _judge(Judgment.brillo, lane, t, tail: true);
      }
    }
    while (_cursor < notes.length && state[_cursor] != NoteState.pending && state[_cursor] != NoteState.holding) {
      _cursor++;
    }
  }

  OdoriResult result() => OdoriResult(
        score: score,
        rank: rank,
        accuracy: accuracy,
        brillo: counts[Judgment.brillo]!,
        bien: counts[Judgment.bien]!,
        vale: counts[Judgment.vale]!,
        misses: misses,
        maxCombo: maxCombo,
        early: early,
        late: late,
        total: chart.judgments,
      );
}

/// El resumen de una partida acabada.
@immutable
class OdoriResult {
  const OdoriResult({
    required this.score,
    required this.rank,
    required this.accuracy,
    required this.brillo,
    required this.bien,
    required this.vale,
    required this.misses,
    required this.maxCombo,
    required this.early,
    required this.late,
    required this.total,
  });

  final int score;
  final OdoriRank rank;
  final double accuracy;
  final int brillo;
  final int bien;
  final int vale;
  final int misses;
  final int maxCombo;
  final int early;
  final int late;
  final int total;

  bool get fullCombo => misses == 0;
}
