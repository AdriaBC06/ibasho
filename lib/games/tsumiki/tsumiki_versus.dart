// Ibasho — Tsumiki versus: filas grises, sabotajes y ayuda al que va perdiendo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'tsumiki.dart';

/// Las trabas que se le lanzan al otro con el medidor lleno.
enum TsumikiSabotage {
  /// Sus piezas caen mas rapido.
  rush,

  /// No ve las siguientes.
  blind,

  /// No puede usar la reserva.
  lock,

  /// Niebla en la parte de arriba del tablero.
  fog;

  /// Segundos que dura.
  double get duration => switch (this) {
        rush => 8,
        blind => 10,
        lock => 10,
        fog => 8,
      };
}

/// Filas grises que se mandan de una vez, con su hueco.
class TsumikiAttack {
  const TsumikiAttack(this.rows, this.hole);

  final int rows;
  final int hole;
}

/// Filas grises que manda un asentamiento, antes de compensar: la tabla
/// clasica (2 → 1, 3 → 2, tsumiki → 4), +1 por dos tsumikis seguidos y lo
/// que sumen los combos largos.
int tsumikiAttackFor(int lines, {int combo = 1, bool backToBack = false}) {
  if (lines <= 0) return 0;
  final base = const [0, 0, 1, 2, 4][math.min(lines, 4)];
  final bonus = _comboBonus[math.min(math.max(combo - 1, 0), _comboBonus.length - 1)];
  return base + (backToBack ? 1 : 0) + bonus;
}

// Lo que suma cada combo: el primero que borra es el 1.
const List<int> _comboBonus = [0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5];

/// Un jugador en el versus: su partida, lo que manda, lo que recibe y el
/// medidor de sabotajes. Sin Flutter y sin red: el canal le pasa lo que
/// llega del otro y manda lo que devuelve.
class TsumikiDuel {
  /// Los dos usan la misma [seed] (las mismas piezas); [side] (0 o 1)
  /// separa los huecos de las filas grises de cada uno.
  TsumikiDuel({required int seed, required int side})
      : game = TsumikiGame(seed: seed),
        _holes = math.Random(seed * 31 + side + 1);

  static const double meterFull = 100;

  /// Lo que carga cada fila borrada y cada fila gris recibida.
  static const double chargePerLine = 8;
  static const double chargePerGarbage = 4;

  /// Cuanto mas rapido caen las piezas con [TsumikiSabotage.rush].
  static const double rushFactor = 2.5;

  /// Filas de arriba tapadas con [TsumikiSabotage.fog].
  static const int fogRows = 9;

  final TsumikiGame game;
  final math.Random _holes;

  double meter = 0;
  int sent = 0;
  int received = 0;
  int sabotagesUsed = 0;

  /// Filas ocupadas del otro (0–20), de su ultimo tablero.
  int opponentHeight = 0;

  /// Sabotajes que estoy sufriendo y lo que les queda.
  final Map<TsumikiSabotage, double> active = {};

  /// Filas ocupadas de mi tablero (0–20), sin las que se estan borrando.
  int get height => math.max(
      0, TsumikiGame.visibleRows - game.stackTop.clamp(0, TsumikiGame.visibleRows) - game.clearing.length);

  /// Ayuda al que va perdiendo: el medidor carga hasta el doble si mi
  /// tablero (contando lo que espera por subir) esta mas lleno que el suyo.
  double get catchUp {
    final behind = height + game.pendingGarbage - opponentHeight;
    return 1 + (behind / 8).clamp(0.0, 1.0);
  }

  bool get hasCharge => meter >= meterFull;
  bool get previewHidden => active.containsKey(TsumikiSabotage.blind);
  bool get foggy => active.containsKey(TsumikiSabotage.fog);

  /// Lo que hacer tras cada asentamiento: carga el medidor, compensa lo que
  /// espera y devuelve lo que hay que mandar al otro, si algo.
  TsumikiAttack? onLock(LockEvent e) {
    received += e.garbageIn;
    if (e.garbageIn > 0) _charge(e.garbageIn * chargePerGarbage);
    if (e.rows.isEmpty) return null;
    _charge(e.rows.length * chargePerLine);
    final attack = tsumikiAttackFor(e.rows.length, combo: e.combo, backToBack: e.backToBack);
    final left = game.cancelGarbage(attack);
    if (left <= 0) return null;
    sent += left;
    return TsumikiAttack(left, _holes.nextInt(TsumikiGame.width));
  }

  /// Llegan filas grises del otro.
  void receive(TsumikiAttack a) => game.queueGarbage(a.rows, a.hole);

  /// Gasta el medidor lleno para lanzar [s]. Devuelve si se ha podido.
  bool use(TsumikiSabotage s) {
    if (!hasCharge || game.isOver) return false;
    meter = 0;
    sabotagesUsed++;
    return true;
  }

  /// El otro me lanza [s]: si ya lo tenia, vuelve a empezar.
  void suffer(TsumikiSabotage s) {
    active[s] = s.duration;
    _apply();
  }

  /// Avanza el reloj de los sabotajes (la partida va aparte, con su tick).
  void tick(double dt) {
    if (active.isEmpty) return;
    for (final s in active.keys.toList()) {
      final left = active[s]! - dt;
      if (left <= 0) {
        active.remove(s);
      } else {
        active[s] = left;
      }
    }
    _apply();
  }

  void _charge(double amount) => meter = math.min(meterFull, meter + amount * catchUp);

  void _apply() {
    game.speedFactor = active.containsKey(TsumikiSabotage.rush) ? rushFactor : 1;
    game.holdLocked = active.containsKey(TsumikiSabotage.lock);
  }
}
