// Ibasho — el coro de Tamakoro, sintetizado: cada Tama canta con su voz.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';

import '../../audio/tama_voice.dart';
import '../../backend/tama.dart';
import 'koro_song.dart';

/// Frecuencia de muestreo de las canciones enteras. Con la mitad de la de los
/// efectos basta para voces de bicho y el archivo del menu pesa la mitad.
const int koroSampleRate = 22050;

/// Voz de quien no esta: un asiento con tinta cuyo Tama ya no es de la
/// cuenta sigue cantando, con la voz de serie.
const TamaVoice koroFallbackVoice = TamaVoice();

/// Octava en la que canta una voz. El tono del Tama no desafina la
/// cancion: solo la sube o la baja una octava entera en los extremos.
int koroOctaveShift(TamaVoice voice) => voice.pitch < 25
    ? -12
    : voice.pitch > 75
        ? 12
        : 0;

/// Canta una nota en [out] desde [from] (en muestras), durante [seconds].
/// [gain] es el volumen de esta voz dentro de la mezcla.
void _sing(
  Float64List out, {
  required int from,
  required double seconds,
  required double midi,
  required TamaVoice voice,
  required int sampleRate,
  double gain = .3,
}) {
  final base = koroHz(midi + koroOctaveShift(voice));
  // Voces rapidas cantan mas picado; las pausadas, mas ligado.
  final decayRate = .6 + voice.tempo / 100 * 2.4;
  const release = .035;
  final length = ((seconds + release) * sampleRate).round();
  var phase = 0.0;
  for (var i = 0; i < length && from + i < out.length; i++) {
    final t = i / sampleRate;
    final u = math.min(1.0, t / seconds);
    // El mismo pellizco agudo de los graznidos, mas suave: asi canta un Tama
    // y no un sintetizador.
    var semis = 1.2 * math.exp(-t * 55);
    switch (voice.timbre) {
      case TamaTimbre.round:
        semis += math.sin(t * 2 * math.pi * 6) * .25 * math.min(1.0, t * 4);
      case TamaTimbre.whistle:
        semis -= 1.5 * math.exp(-t * 30);
      case TamaTimbre.bubble:
        // "Blup" al final de cada nota.
        if (u > .7) semis -= 5 * (u - .7) * (u - .7) / .09;
      case TamaTimbre.purr:
      case TamaTimbre.soft:
      case TamaTimbre.bright:
        break;
    }
    final freq = base * math.pow(2, semis / 12).toDouble();
    phase += 2 * math.pi * freq / sampleRate;

    final wave = switch (voice.timbre) {
      TamaTimbre.soft => math.sin(phase) + .18 * math.sin(2 * phase),
      TamaTimbre.bright => (math.sin(phase) +
              .45 * math.sin(2 * phase) +
              .28 * math.sin(3 * phase) +
              .14 * math.sin(4 * phase)) /
          1.5,
      TamaTimbre.round => math.sin(phase) + .12 * math.sin(3 * phase),
      TamaTimbre.whistle => math.sin(phase) * .95,
      TamaTimbre.purr => (math.sin(phase) + .35 * math.sin(2 * phase)) *
          (.6 + .4 * math.sin(t * 2 * math.pi * 26)),
      TamaTimbre.bubble => math.sin(phase) + .2 * math.sin(2 * phase + .6),
    };

    const attack = .008;
    final rise = math.min(1.0, t / attack);
    final body = .55 + .45 * math.exp(-t * decayRate);
    final tail = t <= seconds ? 1.0 : math.max(0.0, 1 - (t - seconds) / release);
    out[from + i] += wave * rise * body * tail * gain;
  }
}

/// Mezcla suave: con seis Tamas en acorde la suma pasa de 1 y un recorte
/// seco sonaria a radio rota.
Float64List _soften(Float64List samples) {
  for (var i = 0; i < samples.length; i++) {
    final x = samples[i];
    samples[i] = x.abs() < .6 ? x : (x.sign * (.6 + .4 * _tanh((x.abs() - .6) / .4)));
  }
  return samples;
}

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Una vuelta entera de [song] como WAV, lista para repetirse sin corte.
/// [voices] es la voz de cada asiento del coro (`null`: la de serie).
Uint8List renderKoroSong(
  KoroSong song,
  List<TamaVoice?> voices, {
  int sampleRate = koroSampleRate,
}) {
  final total = (song.loopSeconds * sampleRate).round();
  final samples = Float64List(total);
  final step = song.stepSeconds;
  // Una vuelta empieza donde acaba la anterior: la cola de las notas del
  // final se suma al principio para que el bucle no pegue un salto.
  final spill = Float64List(total + sampleRate);
  for (final note in song.notes) {
    _sing(
      spill,
      from: (note.start * step * sampleRate).round(),
      // Un pelo mas corta que el hueco: dos notas seguidas no se funden.
      seconds: note.length * step - .02,
      midi: song.scale.midiOf(note.row).toDouble(),
      voice: voices.elementAtOrNull(note.seat) ?? koroFallbackVoice,
      sampleRate: sampleRate,
    );
  }
  for (var i = 0; i < spill.length; i++) {
    samples[i % total] += spill[i];
  }
  return encodeWav(_soften(samples), sampleRate);
}

/// Una sola nota del Tamapiano: [midi] cantada por [voice].
Uint8List renderKoroNote({
  required TamaVoice voice,
  required int midi,
  double seconds = .55,
  int sampleRate = 44100,
}) {
  final samples = Float64List(((seconds + .05) * sampleRate).round());
  _sing(
    samples,
    from: 0,
    seconds: seconds,
    midi: midi.toDouble(),
    voice: voice,
    sampleRate: sampleRate,
    gain: .5,
  );
  return encodeWav(_soften(samples), sampleRate);
}
