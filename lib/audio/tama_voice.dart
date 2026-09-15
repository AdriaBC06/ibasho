// Ibasho — la voz de un Tama, sintetizada al vuelo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';

import '../backend/tama.dart';

/// Que dice el Tama.
enum ChirpKind {
  /// Al tocarlo o saludar.
  hello,

  /// Con los mimos.
  happy,

  /// Comiendo.
  munch,

  /// Cuando esta melancolico.
  sigh,
}

/// Una silaba de un graznido.
class ChirpSyllable {
  const ChirpSyllable({
    required this.semitones,
    required this.glide,
    required this.seconds,
    required this.gap,
  });

  /// Altura respecto al tono base.
  final double semitones;

  /// Cuanto sube (positivo) o baja a lo largo de la silaba, en semitonos.
  final double glide;

  final double seconds;

  /// Silencio despues.
  final double gap;
}

/// Hash FNV-1a de 32 bits del nombre. Estable entre ejecuciones y plataformas,
/// que es justo lo que no garantiza `String.hashCode`.
int voiceSeed(String name) {
  var h = 0x811C9DC5;
  for (final unit in name.trim().toLowerCase().codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// El patron de silabas de un Tama. Sale del nombre, asi que dos Tamas con
/// nombres distintos no graznan igual aunque compartan voz.
List<ChirpSyllable> chirpPattern(String name, TamaVoice voice, ChirpKind kind) {
  final rng = math.Random(voiceSeed(name) ^ (kind.index * 0x9E3779B1));
  final base = math.Random(voiceSeed(name));
  // Escala pentatonica: suena a melodia y nunca desafina.
  const steps = <double>[0, 2, 4, 7, 9, 12, -3, -5];
  final pace = 1.45 - voice.tempo / 100 * .8;

  final count = switch (kind) {
    ChirpKind.hello => 2 + base.nextInt(3),
    ChirpKind.happy => 3 + base.nextInt(3),
    ChirpKind.munch => 3,
    ChirpKind.sigh => 2,
  };

  final syllables = <ChirpSyllable>[];
  for (var i = 0; i < count; i++) {
    // El contorno principal es el del nombre; la clase de frase lo colorea.
    final step = steps[base.nextInt(steps.length)];
    final glideSign = base.nextInt(3) - 1;
    final length = .075 + base.nextDouble() * .075;
    final gap = .022 + base.nextDouble() * .04;
    final jitter = rng.nextDouble() * .6 - .3;
    switch (kind) {
      case ChirpKind.hello:
        syllables.add(ChirpSyllable(
          semitones: step + jitter,
          glide: glideSign * 2.5,
          seconds: length * pace,
          gap: gap * pace,
        ));
      case ChirpKind.happy:
        syllables.add(ChirpSyllable(
          semitones: step + 3 + i * 1.2 + jitter,
          glide: 3.5,
          seconds: length * .8 * pace,
          gap: gap * .7 * pace,
        ));
      case ChirpKind.munch:
        syllables.add(ChirpSyllable(
          semitones: -5 + step * .3 + jitter,
          glide: -1.5,
          seconds: .06 * pace,
          gap: .07 * pace,
        ));
      case ChirpKind.sigh:
        syllables.add(ChirpSyllable(
          semitones: step * .5 - 2 - i * 2.5,
          glide: -4,
          seconds: length * 2 * pace,
          gap: gap * 2 * pace,
        ));
    }
  }
  return syllables;
}

/// Duracion total del graznido, en segundos.
double chirpSeconds(List<ChirpSyllable> pattern) =>
    pattern.fold(0.0, (sum, s) => sum + s.seconds + s.gap) + .02;

/// Sintetiza el graznido como un WAV mono de 16 bits.
///
/// Todo sale de aqui: no hay ni un archivo de audio que licenciar.
Uint8List synthesizeChirp({
  required String name,
  required TamaVoice voice,
  required ChirpKind kind,
  int sampleRate = 44100,
}) {
  final pattern = chirpPattern(name, voice, kind);
  final total = (chirpSeconds(pattern) * sampleRate).ceil();
  final samples = Float64List(total);
  // Cada timbre vive en su propio registro: el silbido arriba, el ronroneo
  // abajo.
  final register = switch (voice.timbre) {
    TamaTimbre.whistle => 1.6,
    TamaTimbre.purr => .45,
    TamaTimbre.bubble => .85,
    _ => 1.0,
  };
  final base = 320 * register * math.pow(2, voice.pitch / 100 * 1.6).toDouble();
  // Aire del silbido: ruido determinista, para que el mismo Tama suene igual.
  final breath = math.Random(voiceSeed(name) ^ 0x5EED);

  var cursor = 0;
  var phase = 0.0;
  for (final syllable in pattern) {
    final length = (syllable.seconds * sampleRate).round();
    for (var i = 0; i < length && cursor + i < total; i++) {
      final t = i / sampleRate;
      final u = i / length;
      // Un pellizco agudo al empezar: es lo que lo hace sonar a bicho y no a
      // silbato.
      final blip = 2.2 * math.exp(-t * 60);
      var semis = syllable.semitones + syllable.glide * u + blip;
      switch (voice.timbre) {
        case TamaTimbre.round:
          semis += math.sin(t * 2 * math.pi * 7) * .35;
        case TamaTimbre.whistle:
          // Sube rapido al empezar, como un pajarito.
          semis += 3 * (1 - math.exp(-t * 35));
        case TamaTimbre.bubble:
          // Cada silaba cae en picado: "blup".
          semis -= 11 * u * u;
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
        TamaTimbre.whistle => math.sin(phase) * .9 + (breath.nextDouble() * 2 - 1) * .08,
        // Temblor rapido de amplitud: un ronroneo.
        TamaTimbre.purr => (math.sin(phase) + .35 * math.sin(2 * phase)) *
            (.55 + .45 * math.sin(t * 2 * math.pi * 26)),
        TamaTimbre.bubble => math.sin(phase) + .2 * math.sin(2 * phase + .6),
      };

      const attack = .006;
      final decay = math.exp(-math.max(0.0, t - attack) * (2.4 / syllable.seconds));
      final rise = math.min(1.0, t / attack);
      final tail = math.min(1.0, (length - i) / (sampleRate * .012));
      samples[cursor + i] += wave * rise * decay * tail * .42;
    }
    cursor += length + (syllable.gap * sampleRate).round();
  }

  return _wav(samples, sampleRate);
}

Uint8List _wav(Float64List samples, int sampleRate) {
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
