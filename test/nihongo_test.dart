// Ibasho — los kana de Nihongo y sus rondas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/nihongo/kana.dart';
import 'package:ibasho/games/nihongo/nihongo_store.dart';

void main() {
  test('tablas completas en las dos escrituras', () {
    for (final s in KanaScript.values) {
      expect(kanaOf(s, {KanaGroup.basic}).length, 46);
      expect(kanaOf(s, {KanaGroup.dakuten}).length, 25);
      expect(kanaOf(s, {KanaGroup.combo}).length, 33);
    }
    expect(kanaTable[KanaScript.katakana]!.first.char, 'ア');
    expect(kanaTable[KanaScript.katakana]!.firstWhere((k) => k.romaji == 'kya').char, 'キャ');
  });

  test('la tabla va por filas y columnas, con los huecos en su sitio', () {
    String line(List<Kana?> row) => row.map((k) => k?.char ?? '·').join();
    final basic = kanaChart(KanaScript.hiragana, KanaGroup.basic);
    expect(basic.length, 11);
    expect(line(basic[0]), 'あいうえお');
    expect(line(basic[7]), 'や·ゆ·よ');
    expect(line(basic[9]), 'わ···を');
    expect(line(basic[10]), 'ん····');
    final dakuten = kanaChart(KanaScript.katakana, KanaGroup.dakuten);
    expect(dakuten.map(line), ['ガギグゲゴ', 'ザジズゼゾ', 'ダヂヅデド', 'バビブベボ', 'パピプペポ']);
    final combo = kanaChart(KanaScript.hiragana, KanaGroup.combo);
    expect(combo.length, 11);
    expect(combo.first.map((k) => k!.romaji), ['kya', 'kyu', 'kyo']);
  });

  test('se aceptan las otras formas de escribir', () {
    final shi = kanaTable[KanaScript.hiragana]!.firstWhere((k) => k.char == 'し');
    expect(shi.accepts('shi'), isTrue);
    expect(shi.accepts(' SI '), isTrue);
    expect(shi.accepts('chi'), isFalse);
    final n = kanaTable[KanaScript.hiragana]!.firstWhere((k) => k.char == 'ん');
    expect(n.accepts('nn'), isTrue);
  });

  test('cuatro opciones distintas con la buena dentro', () {
    for (var seed = 0; seed < 30; seed++) {
      final pool = kanaOf(KanaScript.hiragana, KanaGroup.values.toSet());
      final r = KanaRound(script: KanaScript.hiragana, mode: AnswerMode.choices, pool: pool, stats: const {}, seed: seed);
      expect(r.questions.length, 10);
      expect(r.questions.map((q) => q.kana.char).toSet().length, 10);
      for (final q in r.questions) {
        expect(q.choices.toSet().length, 4, reason: q.kana.char);
        expect(q.choices.where((c) => q.kana.accepts(c)).length, 1, reason: q.kana.char);
      }
    }
  });

  test('monedas solo con pleno, y nunca en un repaso', () {
    final pool = kanaOf(KanaScript.katakana, {KanaGroup.basic});
    final r = KanaRound(script: KanaScript.katakana, mode: AnswerMode.write, pool: pool, stats: const {}, seed: 1);
    for (final q in r.questions) {
      r.answer(q.kana.romaji);
      r.next();
    }
    expect(r.perfect, isTrue);
    expect(nihongoRewardFor(r), 5);
    final c = KanaRound(script: KanaScript.katakana, mode: AnswerMode.choices, pool: pool, stats: const {}, seed: 2);
    c.answer('zzz');
    expect(nihongoRewardFor(c), 0);
    final review = KanaRound(script: KanaScript.katakana, mode: AnswerMode.choices, pool: pool.take(3).toList(), stats: const {}, length: 3, review: true);
    expect(nihongoRewardFor(review), 0);
  });

  test('dominar un kana son tres aciertos seguidos y se guarda', () {
    final a = kanaTable[KanaScript.hiragana]!.first;
    var rec = const NihongoRecords();
    rec = rec.answered(a, true).answered(a, true);
    expect(rec.mastered(KanaScript.hiragana), 0);
    rec = rec.answered(a, true);
    expect(rec.mastered(KanaScript.hiragana), 1);
    final back = NihongoRecords.fromJson(rec.copyWith(groups: {KanaGroup.combo}, mode: AnswerMode.write).toJson());
    expect(back.mastered(KanaScript.hiragana), 1);
    expect(back.groups, {KanaGroup.combo});
    expect(back.mode, AnswerMode.write);
  });
}
