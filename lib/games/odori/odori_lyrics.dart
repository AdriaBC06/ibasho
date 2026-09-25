// Ibasho — Odori: la letra en pantalla, como un karaoke. La linea que suena
// se ilumina nota a nota y debajo, mas tenue, espera la siguiente.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/type.dart';
import 'odori_catalog.dart';
import 'odori_song.dart';

/// Un compas de letra: lo que se lee y sus notas, en segundos.
@immutable
class LyricBar {
  const LyricBar(this.text, this.notes);

  final String text;

  /// Inicio y final de cada nota.
  final List<(double, double)> notes;
}

/// Una linea: dos compases.
@immutable
class LyricLine {
  const LyricLine({required this.start, required this.end, required this.bars});

  final double start;
  final double end;
  final List<LyricBar> bars;

  /// Los compases seguidos. Un guion final une la palabra con el compas
  /// siguiente; si no, van separados por un espacio.
  List<String> get pieces {
    final out = <String>[];
    for (var i = 0; i < bars.length; i++) {
      final t = bars[i].text;
      final joined = t.endsWith('-');
      final body = joined ? t.substring(0, t.length - 1) : t;
      out.add(i < bars.length - 1 && !joined ? '$body ' : body);
    }
    return out;
  }

  String get text => pieces.join();
}

/// La letra de una version, con los tiempos ya en segundos de la cancion.
@immutable
class OdoriLyrics {
  const OdoriLyrics(this.lines);

  final List<LyricLine> lines;

  /// Pasa la letra de pulsos a segundos con la partitura de la version.
  factory OdoriLyrics.fromJson(Map<String, Object?> j, OdoriScore score) {
    double n(Object? v) => v is num ? v.toDouble() : 0;
    final lines = <LyricLine>[];
    for (final raw in (j['lines'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final bars = <LyricBar>[];
      for (final b in (raw['bars'] as List?) ?? const []) {
        if (b is! Map) continue;
        final notes = <(double, double)>[
          for (final note in (b['notes'] as List?) ?? const [])
            if (note is List && note.length >= 2)
              (score.timeOf(n(note[0])), score.timeOf(n(note[0]) + n(note[1]))),
        ];
        final text = '${b['text'] ?? ''}';
        if (text.isNotEmpty) bars.add(LyricBar(text, notes));
      }
      if (bars.isEmpty) continue;
      lines.add(LyricLine(start: score.timeOf(n(raw['start'])), end: score.timeOf(n(raw['end'])), bars: bars));
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    return OdoriLyrics(lines);
  }

  /// Segundos antes de su primera nota en que ya se enseña una linea.
  static const double lead = 3;

  /// La linea que toca en [t] y la siguiente. Entre estrofas no sale nada
  /// hasta [lead] segundos antes de la que viene.
  (int?, int?) at(double t) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (t > line.end + .4) continue;
      if (line.start - t > lead) return (null, null);
      return (i, i + 1 < lines.length ? i + 1 : null);
    }
    return (null, null);
  }

  /// Cuanto se ha cantado de un compas en [t], de 0 a 1: las notas pasadas
  /// enteras y la que suena a medias.
  static double sung(LyricBar bar, double t) {
    if (bar.notes.isEmpty) return 0;
    var done = 0.0;
    for (final (from, to) in bar.notes) {
      if (t >= to) {
        done += 1;
      } else if (t > from) {
        done += (t - from) / math.max(.001, to - from);
        break;
      } else {
        break;
      }
    }
    return done / bar.notes.length;
  }
}

/// Lee la letra de una version, o `null` si es instrumental o no la tiene.
Future<OdoriLyrics?> loadOdoriLyrics(OdoriVersion version, OdoriScore score) async {
  final asset = version.lyricsAsset;
  if (asset == null) return null;
  try {
    final raw = await rootBundle.loadString(asset, cache: false);
    final lyrics = OdoriLyrics.fromJson((jsonDecode(raw) as Map).cast<String, Object?>(), score);
    return lyrics.lines.isEmpty ? null : lyrics;
  } catch (_) {
    // Hoshikuzu y alguna voz no traen letra en su idioma: se juega sin ella.
    return null;
  }
}

/// La franja del karaoke. Va debajo del tablero, nunca encima de las notas.
class KaraokeStrip extends StatelessWidget {
  const KaraokeStrip({
    super.key,
    required this.lyrics,
    required this.time,
    required this.lit,
    this.compact = false,
    this.onDark = false,
  });

  final OdoriLyrics lyrics;
  final ValueListenable<double> time;

  /// Color de lo ya cantado.
  final Color lit;
  final bool compact;

  /// Sobre el escenario de Butai: tinta clara.
  final bool onDark;

  /// Alto que ocupa, para reservarlo.
  static double heightFor({required bool compact}) => compact ? 52 : 70;

  @override
  Widget build(BuildContext context) {
    final big = compact ? 18.0 : 24.0;
    final small = compact ? 12.0 : 15.0;
    final ink = onDark ? const Color(0xFFFFFFFF) : Ty.ink;
    return SizedBox(
      height: heightFor(compact: compact),
      child: ValueListenableBuilder<double>(
        valueListenable: time,
        builder: (context, t, _) {
          final (cur, next) = lyrics.at(t);
          if (cur == null) return const SizedBox.shrink();
          final line = lyrics.lines[cur];
          final style = Ty.lead.copyWith(fontSize: big, fontWeight: FontWeight.w700, height: 1.2);
          final spans = <InlineSpan>[];
          final pieces = line.pieces;
          for (var i = 0; i < line.bars.length; i++) {
            spans.addAll(_wipe(pieces[i], OdoriLyrics.sung(line.bars[i], t), lit, ink.withValues(alpha: .5)));
          }
          return Column(
            key: const ValueKey<String>('odori.lyrics'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(style: style, children: spans),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (next != null)
                Text(
                  lyrics.lines[next].text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Ty.body.copyWith(fontSize: small, color: ink.withValues(alpha: .45)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// El texto partido en lo cantado, la letra que suena (a medio color) y
  /// lo que falta.
  static List<InlineSpan> _wipe(String text, double sung, Color lit, Color dim) {
    final chars = text.characters.toList();
    if (chars.isEmpty) return const [];
    final at = sung * chars.length;
    final full = at.floor().clamp(0, chars.length);
    final spans = <InlineSpan>[];
    if (full > 0) spans.add(TextSpan(text: chars.take(full).join(), style: TextStyle(color: lit)));
    if (full < chars.length) {
      spans.add(TextSpan(text: chars[full], style: TextStyle(color: Color.lerp(dim, lit, at - full))));
      if (full + 1 < chars.length) spans.add(TextSpan(text: chars.skip(full + 1).join(), style: TextStyle(color: dim)));
    }
    return spans;
  }
}

