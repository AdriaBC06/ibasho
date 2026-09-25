// Ibasho — pruebas del charter y del juicio de Odori.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/odori/odori_catalog.dart';
import 'package:ibasho/games/odori/odori_chart.dart';
import 'package:ibasho/games/odori/odori_engine.dart';
import 'package:ibasho/games/odori/odori_hits.dart';
import 'package:ibasho/games/odori/odori_keys.dart';
import 'package:flutter/services.dart';
import 'package:ibasho/games/odori/odori_board.dart';
import 'package:ibasho/games/odori/odori_butai.dart';
import 'package:ibasho/games/odori/odori_lyrics.dart';
import 'package:ibasho/games/odori/odori_song.dart';
import 'package:ibasho/games/odori/odori_store.dart';

OdoriScore _load(String path) =>
    OdoriScore.fromJson((jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>());

void main() {
  final scores = [
    _load('assets/odori/tamagoyaki/tamagoyaki.json'),
    _load('assets/odori/yako/yako_ja_teto.json'),
    _load('assets/odori/kasa/kasa.json'),
  ];

  test('el chart sale igual cada vez y respeta separacion y carriles', () {
    for (final score in scores) {
      for (final d in OdoriDifficulty.values) {
        for (var keys = 1; keys <= 7; keys++) {
          final a = buildChart(score, keys: keys, difficulty: d);
          final b = buildChart(score, keys: keys, difficulty: d);
          expect(a.notes.length, b.notes.length);
          for (var i = 0; i < a.notes.length; i++) {
            expect(a.notes[i].lane, b.notes[i].lane);
          }
          final lastEnd = List<double>.filled(keys, -99);
          double? prev;
          for (final n in a.notes) {
            expect(n.lane, inInclusiveRange(0, keys - 1));
            // Nada empieza en un carril con una larga sin acabar.
            expect(n.time, greaterThan(lastEnd[n.lane]), reason: '${score.id} $d $keys');
            lastEnd[n.lane] = n.end;
            if (prev != null && n.time != prev) {
              expect(n.time - prev, greaterThanOrEqualTo(d.minGap - 1e-3));
            }
            prev = n.time;
          }
        }
      }
    }
  });

  test('la densidad crece con la dificultad', () {
    for (final score in scores) {
      var last = 0;
      for (final d in OdoriDifficulty.values) {
        final c = buildChart(score, keys: 4, difficulty: d);
        final nps = c.notes.map((n) => n.time).toSet().length / score.length;
        // ignore: avoid_print
        print('${score.id} ${d.name}: ${c.notes.length} notas, '
            '${c.notes.where((n) => n.hold).length} largas, ${nps.toStringAsFixed(2)} por segundo');
        expect(c.notes.length, greaterThan(last));
        last = c.notes.length;
      }
    }
  });

  test('tocarlo todo a tiempo da S++ y un millon', () {
    final chart = buildChart(scores.first, keys: 4, difficulty: OdoriDifficulty.hard);
    final e = OdoriEngine(chart);
    final times = <(double, int, bool)>[
      for (final n in chart.notes) ...[(n.time, n.lane, true), if (n.hold) (n.end, n.lane, false)],
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (t, lane, down) in times) {
      e.advance(t);
      if (down) {
        e.press(lane, t);
      } else {
        e.advance(t);
      }
      if (down && !chart.notes.any((n) => n.hold && n.time == t && n.lane == lane)) {
        e.release(lane, t);
      }
    }
    e.advance(scores.first.length + 1);
    expect(e.finished, isTrue);
    expect(e.score, odoriMaxScore);
    expect(e.rank, OdoriRank.sPlusPlus);
  });

  test('no tocar nada es D y todo fallos', () {
    final chart = buildChart(scores.first, keys: 4, difficulty: OdoriDifficulty.normal);
    final e = OdoriEngine(chart)..advance(999);
    expect(e.finished, isTrue);
    expect(e.misses, chart.judgments);
    expect(e.score, 0);
    expect(e.rank, OdoriRank.d);
  });

  test('ventanas del juicio', () {
    const chart = OdoriChart(keys: 1, difficulty: OdoriDifficulty.easy, notes: [
      ChartNote(1, 0),
      ChartNote(2, 0),
      ChartNote(3, 0),
      ChartNote(4, 0),
      ChartNote(5, 0, 6),
    ]);
    final e = OdoriEngine(chart)
      ..press(0, 1.04)
      ..press(0, 1.93)
      ..press(0, 3.12)
      ..press(0, 3.84) // demasiado pronto: fallo
      ..press(0, 5)
      ..release(0, 5.5); // soltada antes de tiempo
    expect(e.counts[Judgment.brillo], 2);
    expect(e.counts[Judgment.bien], 1);
    expect(e.counts[Judgment.vale], 1);
    expect(e.counts[Judgment.miss], 2);
    expect(e.early, 1);
    expect(e.late, 1);
    e.advance(10);
    expect(e.finished, isTrue);
    expect(e.rank, OdoriRank.d);
  });

  test('el catalogo encuentra todas las canciones y sus versiones', () {
    final files = Directory('assets/odori').listSync(recursive: true).map((f) => f.path.replaceAll('\\', '/'));
    final songs = songsFromAssets(files);
    expect(songs.first.id, 'tamagoyaki');
    expect(songs.map((s) => s.id), containsAll(['yako', 'kasa', 'ibasho']));
    expect(songs.map((s) => s.id), isNot(contains('hoshikuzu')));
    for (final song in songs) {
      expect(song.versions.first.instrumental, isTrue, reason: song.id);
      for (final v in song.versions) {
        expect(File(v.scoreAsset).existsSync(), isTrue, reason: v.id);
      }
    }
    final yako = songs.firstWhere((s) => s.id == 'yako');
    expect(yako.versions.where((v) => v.lang == 'en').single.singer, 'teto');
    expect(yako.authorOf(yako.versions.last), startsWith('Ibasho feat. '));
  });

  group('ayuda del Tama', () {
    const five = OdoriChart(keys: 1, difficulty: OdoriDifficulty.easy, notes: [
      ChartNote(1, 0),
      ChartNote(2, 0),
      ChartNote(3, 0),
      ChartNote(4, 0),
      ChartNote(5, 0),
      ChartNote(6, 0),
      ChartNote(7, 0),
    ]);

    test('tranquilo: ventanas 15 ms mas anchas', () {
      final plain = OdoriEngine(five)..press(0, 1.055);
      final calm = OdoriEngine(five, assist: OdoriAssist.wide)..press(0, 1.055);
      expect(plain.counts[Judgment.bien], 1);
      expect(calm.counts[Judgment.brillo], 1);
    });

    test('dormilon: solo el lado tardio', () {
      final e = OdoriEngine(five, assist: OdoriAssist.lateWide)
        ..press(0, 1.07)
        ..press(0, 1.93);
      expect(e.counts[Judgment.brillo], 1);
      expect(e.counts[Judgment.bien], 1);
    });

    test('timido: un toque pronto no se come la nota', () {
      final e = OdoriEngine(five, assist: OdoriAssist.noEarly)
        ..press(0, .84)
        ..press(0, 1);
      expect(e.misses, 0);
      expect(e.counts[Judgment.brillo], 1);
    });

    test('jugueton: 3 fallos sin romper el combo', () {
      final e = OdoriEngine(five, assist: OdoriAssist.shield)..press(0, 1);
      for (final t in [2.5, 3.5, 4.5]) {
        e.advance(t);
      }
      expect(e.misses, 3);
      expect(e.combo, 1);
      expect(e.helps, 3);
      e
        ..press(0, 5)
        ..advance(6.5);
      expect(e.combo, 0);
    });

    test('picaro: 5 fallos se quedan en vale', () {
      final e = OdoriEngine(five, assist: OdoriAssist.rescue)..advance(99);
      expect(e.counts[Judgment.vale], 5);
      expect(e.misses, 2);
      expect(e.events.where((ev) => ev.helped).length, 5);
    });
  });

  test('récords y opciones se guardan y se leen', () {
    final data = OdoriData();
    const r1 = OdoriResult(
      score: 800000, rank: OdoriRank.b, accuracy: .9, brillo: 1, bien: 0, vale: 0,
      misses: 1, maxCombo: 1, early: 0, late: 0, total: 2);
    const r2 = OdoriResult(
      score: 950000, rank: OdoriRank.s, accuracy: .97, brillo: 2, bien: 0, vale: 0,
      misses: 0, maxCombo: 2, early: 0, late: 0, total: 2);
    final key = odoriRecordKey('yako', OdoriDifficulty.hard, 4);
    expect(data.record(key, r1).$1, isFalse, reason: 'la primera no es récord');
    final (fresh, old) = data.record(key, r2);
    expect(fresh, isTrue);
    expect(old!.score, 800000);
    expect(data.record(key, r1).$1, isFalse);
    expect(odoriRecordKey('yako', OdoriDifficulty.hard, 4, assisted: true), isNot(key));

    data.prefs = const OdoriPrefs().copyWith(
      songId: 'yako',
      keys: 6,
      flow: TakiFlow.left,
      themeId: () => 'dusk',
      keyMaps: {2: [PhysicalKeyboardKey.keyA, PhysicalKeyboardKey.keyL]},
    );
    final back = OdoriData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, Object?>);
    expect(back.records[key]!.score, 950000);
    expect(back.records[key]!.plays, 3);
    expect(back.prefs.keys, 6);
    expect(back.prefs.flow, TakiFlow.left);
    expect(back.prefs.themeId, 'dusk');
    expect(back.prefs.keysFor(2), [PhysicalKeyboardKey.keyA, PhysicalKeyboardKey.keyL]);
    expect(back.prefs.keysFor(4).length, 4);

    expect(odoriRecordKey('yako', OdoriDifficulty.hard, 4, mode: OdoriMode.butai), 'yako|hard|butai');
    data.prefs = data.prefs.copyWith(
      mode: OdoriMode.butai,
      butaiMark: ButaiMark.shapes,
      butaiTouch: ButaiTouch.pad,
      hitVolume: 0,
      butaiDouble: true,
      butaiAlt: const [
        PhysicalKeyboardKey.keyW,
        PhysicalKeyboardKey.keyA,
        PhysicalKeyboardKey.keyS,
        PhysicalKeyboardKey.keyE,
      ],
    );
    final butaiPrefs = OdoriData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, Object?>).prefs;
    expect(butaiPrefs.mode, OdoriMode.butai);
    expect(butaiPrefs.butaiMark, ButaiMark.shapes);
    expect(butaiPrefs.butaiTouch, ButaiTouch.pad);
    expect(butaiPrefs.butaiDouble, isTrue);
    expect(butaiPrefs.butaiAlt, [
      PhysicalKeyboardKey.keyW,
      PhysicalKeyboardKey.keyA,
      PhysicalKeyboardKey.keyS,
      PhysicalKeyboardKey.keyE,
    ]);
    expect(const OdoriPrefs().butaiDouble, isFalse);
    expect(const OdoriPrefs().butaiAlt, butaiAltDefault);
    expect(butaiPrefs.hitVolume, 0);
    expect(const OdoriPrefs().butaiTouch, ButaiTouch.targets);
    expect(const OdoriPrefs().hitVolume, greaterThan(0));
    expect(const OdoriPrefs().butaiMark, ButaiMark.arrows);
  });

  test('Butai: las dianas caben en el escenario, salen igual y no se pisan', () {
    for (final score in scores) {
      for (final d in OdoriDifficulty.values) {
        final chart = buildChart(score, keys: butaiKeys, difficulty: d, butai: true);
        // Butai es bastante mas suave que Taki con las mismas teclas.
        final taki = buildChart(score, keys: butaiKeys, difficulty: d);
        expect(chart.notes.length, lessThan(taki.notes.length * .7), reason: '${score.id} $d');
        final a = butaiLayout(chart, seed: score.id);
        final b = butaiLayout(chart, seed: score.id);
        expect(a.length, chart.notes.length);
        var close = 0;
        for (var i = 0; i < a.length; i++) {
          expect(a[i].at, b[i].at);
          expect(a[i].at.dx, inInclusiveRange(.06, .94));
          expect(a[i].at.dy, inInclusiveRange(.08, .92));
          // Dos notas seguidas en momentos distintos nunca en el mismo sitio.
          if (i > 0 && chart.notes[i].time - chart.notes[i - 1].time > .01 &&
              (a[i].at - a[i - 1].at).distance < .1) {
            close++;
          }
          expect(a[i].fly(1), a[i].at);
        }
        expect(close, lessThan(chart.notes.length * .02 + 1), reason: '${score.id} $d');
      }
    }
  });

  test('los récords van por canción: los de cada versión se juntan', () {
    final data = OdoriData.fromJson({
      'records': {
        'yako_ja_teto|hard|4': {'score': 800000, 'rank': 'a', 'accuracy': .9, 'misses': 3, 'maxCombo': 200, 'plays': 2},
        'yako|hard|4': {'score': 900000, 'rank': 's', 'accuracy': .95, 'misses': 1, 'maxCombo': 300, 'plays': 1},
        'yako_es_merrow|hard|butai|tama': {'score': 500000, 'rank': 'c', 'accuracy': .7, 'misses': 9, 'maxCombo': 50},
      },
    });
    expect(data.records.keys, unorderedEquals(['yako|hard|4', 'yako|hard|butai|tama']));
    final best = data.bestOf('yako', OdoriDifficulty.hard, 4)!;
    expect(best.score, 900000);
    expect(best.plays, 3);
    expect(data.bestOf('yako', OdoriDifficulty.hard, 4, assisted: true, mode: OdoriMode.butai)!.score, 500000);
  });

  test('los toques suenan: un WAV corto por cada uno', () {
    for (final h in OdoriHit.values) {
      final wav = synthesizeHit(h);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, lessThan(44100 * 2 * .4));
      expect(synthesizeHit(h), wav);
    }
    expect(OdoriHit.of(Judgment.brillo), OdoriHit.perfect);
    expect(OdoriHit.of(Judgment.miss), OdoriHit.miss);
  });

  test('la letra pasa a segundos, une con guion y se ilumina nota a nota', () {
    final score = scores[1];
    final raw = jsonDecode(File('assets/odori/yako/yako_letra_ja.json').readAsStringSync()) as Map<String, Object?>;
    final lyrics = OdoriLyrics.fromJson(raw, score);
    expect(lyrics.lines, isNotEmpty);
    final first = lyrics.lines.first;
    expect(first.start, closeTo(score.timeOf(32.5), 1e-9));
    expect(lyrics.at(0), (null, null), reason: 'en la intro no hay letra');
    expect(lyrics.at(first.start - 1).$1, 0);
    expect(lyrics.at(first.start + .1).$2, 1);
    final bar = first.bars.first;
    expect(OdoriLyrics.sung(bar, bar.notes.first.$1 - 1), 0);
    expect(OdoriLyrics.sung(bar, bar.notes.last.$2 + .1), 1);
    final mid = OdoriLyrics.sung(bar, bar.notes[2].$1);
    expect(mid, closeTo(2 / bar.notes.length, 1e-9));

    const joined = LyricLine(start: 0, end: 1, bars: [
      LyricBar('cami-', []),
      LyricBar('no largo', []),
    ]);
    expect(joined.text, 'camino largo');
    const spaced = LyricLine(start: 0, end: 1, bars: [LyricBar('窓に映る', []), LyricBar('夜の街', [])]);
    expect(spaced.text, '窓に映る 夜の街');
  });

  test('la clasificacion solo cuenta 4 teclas sin ayuda, ponderado por dificultad', () {
    int? board(OdoriDifficulty d, {int keys = 4, bool assisted = false}) =>
        odoriBoardScore(1000000, d, keys: keys, assisted: assisted);
    expect(board(OdoriDifficulty.easy), 500000);
    expect(board(OdoriDifficulty.normal), 750000);
    expect(board(OdoriDifficulty.hard), 1000000);
    expect(board(OdoriDifficulty.extreme), 1250000);
    expect(board(OdoriDifficulty.impossible), 1500000);
    expect(board(OdoriDifficulty.hard, keys: 5), isNull);
    expect(board(OdoriDifficulty.hard, assisted: true), isNull);
  });
}
