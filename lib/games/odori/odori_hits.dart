// Ibasho — Odori: los soniditos de cada toque, sintetizados al vuelo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';

import '../../audio/tama_voice.dart';
import 'odori_engine.dart';

/// Lo que suena al tocar: un toque sin nota, un acierto, un brillo o un
/// fallo. Van por debajo de la cancion, flojitos. En orden: si pasan varios
/// a la vez, suena el ultimo.
enum OdoriHit {
  tap,
  miss,
  good,
  perfect;

  static OdoriHit of(Judgment j) => switch (j) {
        Judgment.brillo => perfect,
        Judgment.bien || Judgment.vale => good,
        Judgment.miss => miss,
      };

  /// Volumen de cada uno respecto al elegido: el toque vacio casi no se oye.
  double get level => switch (this) {
        tap => .35,
        miss => .5,
        good => .7,
        perfect => .8,
      };
}

/// Volumen de serie y el maximo del deslizador: tienen que quedar muy por
/// debajo de la cancion, que no molesten.
const double odoriHitDefault = .12;
const double odoriHitMax = .4;

const int _rate = 44100;

/// El WAV de [hit]. Sale siempre igual.
Uint8List synthesizeHit(OdoriHit hit) {
  final (length, voice) = switch (hit) {
    // Un roce muy corto.
    OdoriHit.tap => (.025, (double t) => _tone(t, 1400, .005) * .4),
    // Un «tic» blando.
    OdoriHit.good => (.06, (double t) => _tone(t, 1100, .012) * .5 + _tone(t, 2200, .006) * .12),
    // El brillo: el mismo «tic» un poco mas alto y con un destello corto.
    OdoriHit.perfect => (.09, (double t) => _tone(t, 1760, .016) * .45 + _tone(t, 3520, .008) * .12),
    // Un golpecito grave.
    OdoriHit.miss => (.07, (double t) => _sweep(t, 240, 160, .07, .02) * .5),
  };
  final n = (length * _rate).round();
  final samples = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    // Rampa de 2 ms al empezar y al acabar: sin chasquidos.
    final edge = math.min(1.0, math.min(i, n - 1 - i) / (_rate * .002));
    samples[i] = voice(t) * edge;
  }
  return encodeWav(samples, _rate);
}

/// Un seno de [freq] que se apaga con constante [decay].
double _tone(double t, double freq, double decay) {
  if (t < 0) return 0;
  return math.sin(2 * math.pi * freq * t) * math.exp(-t / decay);
}

/// Un seno que baja de [from] a [to] en [length] segundos.
double _sweep(double t, double from, double to, double length, double decay) {
  final k = (t / length).clamp(0.0, 1.0);
  // Fase de una frecuencia que cambia linealmente.
  final phase = 2 * math.pi * (from * t + (to - from) * t * k / 2);
  return math.sin(phase) * math.exp(-t / decay);
}
