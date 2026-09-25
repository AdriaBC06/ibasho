// Ibasho — Odori: la partitura base que exporta tool/gen_odori_music.py.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Un evento de la partitura: un golpe o una nota de un instrumento.
@immutable
class ScoreEvent {
  const ScoreEvent(this.beat, this.role, this.pitch, this.length, this.accent);

  /// Pulso desde el principio de la cancion.
  final double beat;

  /// `k` bombo, `s` caja, `h` charles, `o` abierto, `x` crash, `b` bajo,
  /// `c` acorde, `a` arpegio, `l` melodia y `v` voz.
  final String role;

  /// Nota MIDI (en la percusion, la nota General MIDI).
  final int pitch;

  /// Duracion en pulsos (0 en la percusion).
  final double length;
  final bool accent;

  /// La voz y la melodia tocada son la misma linea: asi el chart sale igual
  /// en la instrumental y en las versiones cantadas.
  bool get melodic => role == 'l' || role == 'v';
}

/// Una seccion de la cancion: donde empieza, como se llama y su energia
/// (de 1, tranquila, a 4 o 5, el estribillo final).
@immutable
class ScoreSection {
  const ScoreSection(this.beat, this.name, this.energy);

  final double beat;
  final String name;
  final double energy;
}

/// La partitura base de una cancion.
@immutable
class OdoriScore {
  const OdoriScore({
    required this.id,
    required this.title,
    required this.bpm,
    required this.offset,
    required this.length,
    required this.sections,
    required this.events,
  });

  final String id;
  final String title;
  final double bpm;

  /// Segundos de silencio antes del pulso 0.
  final double offset;

  /// Duracion total en segundos.
  final double length;
  final List<ScoreSection> sections;
  final List<ScoreEvent> events;

  double get secondsPerBeat => 60 / bpm;

  /// El pulso [beat] en segundos desde el principio del audio.
  double timeOf(double beat) => offset + beat * secondsPerBeat;

  /// Energia de la seccion en la que cae [beat].
  double energyAt(double beat) {
    var e = sections.isEmpty ? 2.0 : sections.first.energy;
    for (final s in sections) {
      if (s.beat > beat + 1e-6) break;
      e = s.energy;
    }
    return e;
  }

  factory OdoriScore.fromJson(Map<String, Object?> json) {
    double n(Object? v) => v is num ? v.toDouble() : 0;
    final sections = <ScoreSection>[
      for (final s in (json['sections'] as List? ?? const []))
        if (s is List && s.length >= 3) ScoreSection(n(s[0]), '${s[1]}', n(s[2])),
    ]..sort((a, b) => a.beat.compareTo(b.beat));
    final events = <ScoreEvent>[
      for (final e in (json['events'] as List? ?? const []))
        if (e is List && e.length >= 5) ScoreEvent(n(e[0]), '${e[1]}', n(e[2]).round(), n(e[3]), n(e[4]) > 0),
    ]..sort((a, b) => a.beat.compareTo(b.beat));
    return OdoriScore(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      bpm: n(json['bpm']) > 0 ? n(json['bpm']) : 120,
      offset: n(json['offset']),
      length: n(json['length']),
      sections: sections,
      events: events,
    );
  }
}
