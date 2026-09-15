// Ibasho — lo que hace que un Tama parezca vivo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../backend/tama.dart';
import 'tama_painter.dart';

/// Ritmos propios de cada personalidad.
class TamaTraits {
  const TamaTraits({
    required this.blinkEvery,
    required this.blinkHold,
    required this.breathPeriod,
    required this.stiffness,
    required this.damping,
    required this.idleEvery,
    required this.hopScale,
    required this.glanceEvery,
    required this.glanceSpeed,
  });

  /// Segundos entre parpadeos (minimo, maximo).
  final (double, double) blinkEvery;

  /// Cuanto se quedan cerrados los ojos al parpadear.
  final double blinkHold;

  /// Segundos que dura una respiracion.
  final double breathPeriod;

  /// Muelle del aplastamiento: rigidez y amortiguacion. Poca amortiguacion es
  /// gelatina que rebota; mucha es un Tama que se mueve con cuidado.
  final double stiffness;
  final double damping;

  /// Segundos entre gestos de reposo (minimo, maximo).
  final (double, double) idleEvery;

  /// Cuanto salta, relativo a lo normal.
  final double hopScale;

  /// Segundos entre miradas cuando nadie le hace caso.
  final (double, double) glanceEvery;

  /// Rapidez con la que mueve los ojos.
  final double glanceSpeed;

  static TamaTraits of(TamaPersonality personality) => switch (personality) {
        TamaPersonality.calm => const TamaTraits(
            blinkEvery: (3.6, 6.2),
            blinkHold: .12,
            breathPeriod: 3.9,
            stiffness: 70,
            damping: 7,
            idleEvery: (5, 9),
            hopScale: .7,
            glanceEvery: (2.6, 5),
            glanceSpeed: 3,
          ),
        TamaPersonality.playful => const TamaTraits(
            blinkEvery: (2.2, 4),
            blinkHold: .08,
            breathPeriod: 2.5,
            stiffness: 130,
            damping: 5.5,
            idleEvery: (2.4, 4.8),
            hopScale: 1.4,
            glanceEvery: (.9, 2.2),
            glanceSpeed: 9,
          ),
        TamaPersonality.shy => const TamaTraits(
            blinkEvery: (1.6, 3.2),
            blinkHold: .1,
            breathPeriod: 3,
            stiffness: 95,
            damping: 11,
            idleEvery: (3.6, 7),
            hopScale: .5,
            glanceEvery: (1.4, 3),
            glanceSpeed: 6,
          ),
        TamaPersonality.cheeky => const TamaTraits(
            blinkEvery: (3, 5),
            blinkHold: .09,
            breathPeriod: 3.1,
            stiffness: 100,
            damping: 7,
            idleEvery: (3, 6),
            hopScale: 1,
            glanceEvery: (1.6, 3.4),
            glanceSpeed: 7,
          ),
        TamaPersonality.sleepy => const TamaTraits(
            blinkEvery: (4, 7),
            blinkHold: .34,
            breathPeriod: 4.8,
            stiffness: 50,
            damping: 8,
            idleEvery: (4.5, 8),
            hopScale: .4,
            glanceEvery: (3.5, 7),
            glanceSpeed: 2,
          ),
      };
}

/// Estado continuo de un Tama vivo.
///
/// No sabe de widgets: recibe el paso del tiempo y lo que pasa a su alrededor
/// (el puntero, un toque, mimos, comida) y devuelve una [TamaPose]. Asi se
/// puede probar sin pintar nada.
class TamaAnimator {
  TamaAnimator({required TamaPersonality personality, int seed = 0})
      : _rng = math.Random(seed),
        _personality = personality,
        _traits = TamaTraits.of(personality) {
    _breathPhase = _rng.nextDouble();
    _nextBlink = _between(_traits.blinkEvery) * _rng.nextDouble();
    _nextIdle = _between(_traits.idleEvery);
    _nextGlance = _between(_traits.glanceEvery) * .5;
  }

  final math.Random _rng;
  TamaPersonality _personality;
  TamaTraits _traits;

  set personality(TamaPersonality value) {
    if (value == _personality) return;
    _personality = value;
    _traits = TamaTraits.of(value);
  }

  /// Humor de -1 a 1. Lo fija quien lo muestra, a partir de los cuidados.
  double joy = .4;

  // --- Entradas ------------------------------------------------------------

  Offset? _pointer;
  double _pointerAge = double.infinity;
  bool _pointerIsMouse = false;
  bool _hovered = false;

  /// Hacia donde esta el puntero, en unidades del propio Tama (cada eje de -1
  /// a 1 dentro de su caja; fuera de ella, mas). `mouse` distingue un raton,
  /// que se sigue siempre, de un toque, que se mira solo un rato.
  void pointAt(Offset? target, {required bool mouse}) {
    if (target == null) {
      _pointer = null;
      return;
    }
    _pointer = target;
    _pointerIsMouse = mouse;
    _pointerAge = 0;
  }

  set hovered(bool value) {
    if (value == _hovered) return;
    _hovered = value;
    if (value) _onHover();
  }

  // --- Estado --------------------------------------------------------------

  double _time = 0;
  double _breathPhase = 0;

  double _squash = 0;
  double _squashV = 0;

  double _tilt = 0;
  double _tiltTarget = 0;
  double _tiltV = 0;

  double _sway = 0;
  double _swayV = 0;

  Offset _gaze = Offset.zero;
  Offset _gazeTarget = Offset.zero;

  double _blink = 0;
  double _blinkTimer = -1;
  double _nextBlink = 2;

  double _nextIdle = 4;
  double _nextGlance = 1;

  // Saltos: progreso, duracion y altura.
  double _hopT = -1;
  double _hopDur = .42;
  double _hopHeight = 0;
  int _hopsQueued = 0;

  double _happy = 0;
  double _happyHold = 0;
  double _tongue = 0;
  double _tongueHold = 0;
  double _doze = 0;
  double _dozeHold = 0;
  double _blush = 0;
  double _blushHold = 0;
  double _wave = 0;
  double _waveHold = 0;
  double _hearts = 0;
  double _heartsHold = 0;
  double _heartPhase = 0;
  double _wiggle = 0;

  double _mouth = 0;
  double _speakHold = 0;
  double _yawnHold = 0;

  double _treat = -1;
  TamaFood _food = TamaFood.cookie;
  double _chewHold = 0;

  bool _petting = false;
  double _petRub = 0;

  // --- Acontecimientos ------------------------------------------------------

  /// Le han tocado.
  void poke() {
    _doze = 0;
    _dozeHold = 0;
    switch (_personality) {
      case TamaPersonality.playful:
        _queueHops(2, 12);
        _wave = 1;
        _waveHold = .6;
      case TamaPersonality.shy:
        _squashV += 5;
        _blushHold = 1.8;
        _gazeTarget = Offset(_rng.nextBool() ? -1 : 1, .7);
      case TamaPersonality.cheeky:
        _queueHops(1, 9);
        _tongueHold = 1.1;
        _tiltTarget = (_rng.nextBool() ? 1 : -1) * .14;
      case TamaPersonality.sleepy:
        _squashV -= 4;
        _blinkTimer = -1;
        _queueHops(1, 5);
      case TamaPersonality.calm:
        _queueHops(1, 8);
        _happyHold = .7;
    }
  }

  /// Abre la boca mientras suena su voz.
  void speak(double seconds) => _speakHold = math.max(_speakHold, seconds);

  /// Empiezan o terminan los mimos. `rub` es el desplazamiento horizontal del
  /// gesto, para que se deje llevar.
  void pet({required bool active, double rub = 0}) {
    if (active && !_petting) {
      _squashV += 3;
      _doze = 0;
      _dozeHold = 0;
    }
    _petting = active;
    _petRub = (_petRub + rub * .02).clamp(-1.0, 1.0);
    if (active) {
      _heartsHold = math.max(_heartsHold, 1.2);
    }
  }

  /// Un mimo corto, desde un boton.
  void cuddle() {
    _happyHold = 1.8;
    _heartsHold = 2;
    _blushHold = 1.6;
    _squashV += 4;
    _wiggle = 1;
    _doze = 0;
    _dozeHold = 0;
  }

  /// Cae una chuche y se la come.
  void feed([TamaFood food = TamaFood.cookie]) {
    _food = food;
    _treat = 0;
    _doze = 0;
    _dozeHold = 0;
    _gazeTarget = const Offset(.4, -1);
  }

  // --- Paso del tiempo -----------------------------------------------------

  double _between((double, double) range) =>
      range.$1 + _rng.nextDouble() * (range.$2 - range.$1);

  static double _approach(double value, double target, double rate, double dt) =>
      value + (target - value) * (1 - math.exp(-rate * dt));

  void _queueHops(int count, double height) {
    _hopsQueued = count;
    _hopHeight = height * _traits.hopScale * (.55 + .45 * (joy + 1) / 2);
    if (_hopT < 0) _startHop();
  }

  void _startHop() {
    if (_hopsQueued <= 0) return;
    _hopsQueued--;
    _hopT = 0;
    _hopDur = .28 + _hopHeight * .014;
    // Coge impulso: se aplasta antes de despegar.
    _squashV += 5;
  }

  void _onHover() {
    switch (_personality) {
      case TamaPersonality.shy:
        _blushHold = 1.4;
        _squashV += 2.5;
      case TamaPersonality.playful:
        _squashV -= 5;
        _waveHold = .5;
      case TamaPersonality.cheeky:
        _tiltTarget = (_rng.nextBool() ? 1 : -1) * .1;
      case TamaPersonality.sleepy:
        _dozeHold = 0;
      case TamaPersonality.calm:
        _squashV -= 3;
    }
  }

  void _idleGesture() {
    final lively = .35 + .65 * (joy + 1) / 2;
    // Con el animo bajo casi no hace gestos: mira al suelo y respira.
    if (_rng.nextDouble() > lively) {
      _gazeTarget = Offset((_rng.nextDouble() - .5) * .6, .8);
      return;
    }
    switch (_personality) {
      case TamaPersonality.calm:
        if (_rng.nextBool()) {
          _happyHold = 1.3;
        } else {
          _tiltTarget = (_rng.nextDouble() - .5) * .16;
        }
      case TamaPersonality.playful:
        switch (_rng.nextInt(3)) {
          case 0:
            _queueHops(1 + _rng.nextInt(2), 10);
          case 1:
            _wiggle = 1;
          default:
            _waveHold = .9;
        }
      case TamaPersonality.shy:
        _gazeTarget = Offset(_rng.nextBool() ? -1 : 1, .6);
        _blushHold = 1.2;
        _squashV += 2;
      case TamaPersonality.cheeky:
        if (_rng.nextBool()) {
          _tongueHold = 1.2;
          _tiltTarget = (_rng.nextBool() ? 1 : -1) * .12;
        } else {
          _gazeTarget = Offset(_rng.nextBool() ? -1 : 1, 0);
          _queueHops(1, 6);
        }
      case TamaPersonality.sleepy:
        if (_rng.nextDouble() < .6) {
          _dozeHold = 3.5 + _rng.nextDouble() * 3;
        } else {
          _yawnHold = 1.3;
        }
    }
  }

  /// Avanza `dt` segundos y devuelve la postura resultante.
  TamaPose tick(double dt) {
    dt = dt.clamp(0.0, .1);
    _time += dt;
    final lively = (joy + 1) / 2;

    // Respiracion: con el animo bajo, mas lenta.
    _breathPhase += dt / (_traits.breathPeriod * (1.25 - lively * .25));
    final breathe = math.sin(_breathPhase * 2 * math.pi);

    // Parpadeo.
    _nextBlink -= dt;
    if (_nextBlink <= 0 && _blinkTimer < 0) {
      _blinkTimer = 0;
      _nextBlink = _between(_traits.blinkEvery);
      // A veces dos seguidos, como hacen los bichos de verdad.
      if (_rng.nextDouble() < .18) _nextBlink = .32;
    }
    if (_blinkTimer >= 0) {
      _blinkTimer += dt;
      const close = .07;
      final hold = _traits.blinkHold;
      const open = .1;
      if (_blinkTimer < close) {
        _blink = _blinkTimer / close;
      } else if (_blinkTimer < close + hold) {
        _blink = 1;
      } else if (_blinkTimer < close + hold + open) {
        _blink = 1 - (_blinkTimer - close - hold) / open;
      } else {
        _blink = 0;
        _blinkTimer = -1;
      }
    }

    // Gestos de reposo, solo si no esta pasando nada.
    final busy = _petting || _treat >= 0 || _chewHold > 0 || _hopT >= 0;
    _nextIdle -= dt;
    if (_nextIdle <= 0) {
      _nextIdle = _between(_traits.idleEvery) / (.6 + .4 * lively);
      if (!busy && !_hovered) _idleGesture();
    }

    // Mirada: raton, luego toque reciente, luego a su aire.
    _pointerAge += dt;
    final pointer = _pointer;
    if (pointer != null && (_pointerIsMouse || _pointerAge < 3)) {
      final d = pointer;
      final len = d.distance;
      final scaled = len < 1e-3 ? Offset.zero : d / math.max(1.0, len * .8);
      _gazeTarget = Offset(scaled.dx.clamp(-1.0, 1.0), scaled.dy.clamp(-1.0, 1.0));
      _nextGlance = _between(_traits.glanceEvery);
    } else {
      _nextGlance -= dt;
      if (_nextGlance <= 0) {
        _nextGlance = _between(_traits.glanceEvery);
        final down = joy < -.2 ? .5 : 0.0;
        _gazeTarget = switch (_personality) {
          TamaPersonality.shy => Offset((_rng.nextDouble() - .5) * 1.6, .3 + down + _rng.nextDouble() * .4),
          TamaPersonality.sleepy => Offset(math.sin(_time * .3) * .5, .2 + down),
          TamaPersonality.calm => Offset(math.sin(_time * .5) * .8, (_rng.nextDouble() - .5) * .4 + down),
          _ => Offset((_rng.nextDouble() - .5) * 2, (_rng.nextDouble() - .6) * 1.2 + down),
        };
      }
    }
    _gaze = Offset(
      _approach(_gaze.dx, _gazeTarget.dx, _traits.glanceSpeed, dt),
      _approach(_gaze.dy, _gazeTarget.dy, _traits.glanceSpeed, dt),
    );

    // Salto.
    var hop = 0.0;
    var hopVelocity = 0.0;
    if (_hopT >= 0) {
      _hopT += dt / _hopDur;
      if (_hopT >= 1) {
        _hopT = -1;
        _squashV += 6 * _traits.hopScale; // aterriza y se aplasta
        if (_hopsQueued > 0) _startHop();
      } else {
        hop = _hopHeight * math.sin(_hopT * math.pi);
        hopVelocity = math.cos(_hopT * math.pi);
      }
    }

    // Mimos: se deja llevar hacia donde le frotan.
    if (_petting) {
      _happyHold = math.max(_happyHold, .3);
      _blushHold = math.max(_blushHold, .3);
      _tiltTarget = _petRub * .16;
      _squashV += math.sin(_time * 18) * 1.2;
    } else {
      _petRub = _approach(_petRub, 0, 4, dt);
    }

    // Comer: la chuche cae, abre la boca y mastica.
    var treat = -1.0;
    if (_treat >= 0) {
      _treat += dt / .75;
      treat = _treat;
      if (_treat >= 1) {
        _treat = -1;
        treat = -1;
        _chewHold = 1.3;
        _squashV += 4;
        _gazeTarget = Offset.zero;
      }
    }
    var mouthTarget = 0.0;
    if (treat > .45) mouthTarget = (treat - .45) / .55 * .9;
    if (_chewHold > 0) {
      _chewHold -= dt;
      mouthTarget = (math.sin(_chewHold * 16) * .5 + .5) * .55;
      if (_chewHold <= 0) {
        _happyHold = 1.4;
        _heartsHold = 1.6;
      }
    }
    if (_speakHold > 0) {
      _speakHold -= dt;
      mouthTarget = math.max(mouthTarget, .35 + .35 * (math.sin(_time * 30) * .5 + .5));
    }
    if (_yawnHold > 0) {
      _yawnHold -= dt;
      mouthTarget = math.max(mouthTarget, math.sin((_yawnHold / 1.3).clamp(0.0, 1.0) * math.pi));
      _happyHold = math.max(_happyHold, .1);
    }
    _mouth = _approach(_mouth, mouthTarget, 18, dt);

    // Temporizadores con entrada y salida suaves.
    double hold(double v, double timer, double rate) =>
        _approach(v, timer > 0 ? 1 : 0, rate, dt);
    _happyHold -= dt;
    _happy = hold(_happy, _happyHold, 10);
    _tongueHold -= dt;
    _tongue = hold(_tongue, _tongueHold, 9);
    _dozeHold -= dt;
    _doze = hold(_doze, _dozeHold, 1.6);
    _blushHold -= dt;
    _blush = hold(_blush, _blushHold, 4);
    _waveHold -= dt;
    _wave = _waveHold > 0 ? (math.sin(_time * 14) * .5 + .5) : _approach(_wave, 0, 8, dt);
    _heartsHold -= dt;
    _hearts = hold(_hearts, _heartsHold, 5);
    if (_hearts > .01) _heartPhase = (_heartPhase + dt * .55) % 1.0;

    if (_wiggle > 0) {
      _wiggle = math.max(0, _wiggle - dt * .9);
      _tiltTarget = math.sin(_time * 16) * .1 * _wiggle;
    } else if (!_petting && _rng.nextDouble() < dt * .2) {
      _tiltTarget *= .5;
    }

    // Muelles: aplastamiento e inclinacion.
    final k = _traits.stiffness;
    final c = _traits.damping;
    _squashV += (-k * _squash - c * _squashV) * dt;
    _squash += _squashV * dt;
    _squash = _squash.clamp(-1.2, 1.2);
    _tiltV += (-k * .6 * (_tilt - _tiltTarget) - c * _tiltV) * dt;
    _tilt += _tiltV * dt;

    // Orejas y antenas van con retraso: es lo que da sensacion de blandura.
    final drive = -_tiltV * .08 - hopVelocity * (_hopT >= 0 ? .18 : 0) + _squashV * .01;
    _swayV += (-60 * _sway - 4 * _swayV + drive * 40) * dt;
    _sway += _swayV * dt;
    _sway = _sway.clamp(-.6, .6);

    // Estirado mientras sube.
    final stretch = _hopT >= 0 ? -hopVelocity.abs() * .35 : 0.0;

    return TamaPose(
      breathe: breathe,
      squash: (_squash + stretch).clamp(-1.0, 1.0),
      hop: hop,
      tilt: _tilt,
      blink: _happy > .5 ? 0 : _blink,
      gaze: _gaze,
      joy: math.max(joy, joy + _happy * .6).clamp(-1.0, 1.0),
      happyEyes: _happy,
      mouthOpen: _mouth,
      tongue: _tongue,
      blush: _blush * (_personality == TamaPersonality.shy ? 1 : .6),
      sway: _sway,
      armWave: _wave,
      doze: _doze,
      hearts: _hearts,
      heartPhase: _heartPhase,
      treat: treat,
      food: _food,
    );
  }
}
