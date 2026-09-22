// Ibasho — los kana de Nihongo y la logica de una ronda, sin Flutter.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

enum KanaScript { hiragana, katakana }

enum KanaGroup { basic, dakuten, combo }

enum AnswerMode { choices, write }

/// Un kana con su lectura en Hepburn y las otras formas que se aceptan al
/// escribirla (si, ti, tu, hu…).
class Kana {
  const Kana(this.char, this.romaji, this.group, [this.also = const <String>[]]);

  final String char;
  final String romaji;
  final KanaGroup group;
  final List<String> also;

  bool accepts(String typed) {
    final t = normalizeRomaji(typed);
    return t == romaji || also.contains(t);
  }
}

String normalizeRomaji(String s) => s.trim().toLowerCase().replaceAll(RegExp(r"[\s'’-]"), '');

// La tabla en hiragana: `lectura:kana`, y las formas de mas tras una barra.
const String _basic = 'a:あ i:い u:う e:え o:お '
    'ka:か ki:き ku:く ke:け ko:こ '
    'sa:さ shi:し|si su:す se:せ so:そ '
    'ta:た chi:ち|ti tsu:つ|tu te:て to:と '
    'na:な ni:に nu:ぬ ne:ね no:の '
    'ha:は hi:ひ fu:ふ|hu he:へ ho:ほ '
    'ma:ま mi:み mu:む me:め mo:も '
    'ya:や yu:ゆ yo:よ '
    'ra:ら ri:り ru:る re:れ ro:ろ '
    'wa:わ wo:を|o n:ん|nn';

const String _dakuten = 'ga:が gi:ぎ gu:ぐ ge:げ go:ご '
    'za:ざ ji:じ|zi zu:ず ze:ぜ zo:ぞ '
    'da:だ ji:ぢ|di zu:づ|du de:で do:ど '
    'ba:ば bi:び bu:ぶ be:べ bo:ぼ '
    'pa:ぱ pi:ぴ pu:ぷ pe:ぺ po:ぽ';

const String _combo = 'kya:きゃ kyu:きゅ kyo:きょ '
    'sha:しゃ|sya shu:しゅ|syu sho:しょ|syo '
    'cha:ちゃ|tya|cya chu:ちゅ|tyu|cyu cho:ちょ|tyo|cyo '
    'nya:にゃ nyu:にゅ nyo:にょ '
    'hya:ひゃ hyu:ひゅ hyo:ひょ '
    'mya:みゃ myu:みゅ myo:みょ '
    'rya:りゃ ryu:りゅ ryo:りょ '
    'gya:ぎゃ gyu:ぎゅ gyo:ぎょ '
    'ja:じゃ|zya|jya ju:じゅ|zyu|jyu jo:じょ|zyo|jyo '
    'bya:びゃ byu:びゅ byo:びょ '
    'pya:ぴゃ pyu:ぴゅ pyo:ぴょ';

List<Kana> _parse(String table, KanaGroup group, KanaScript script) => [
      for (final entry in table.split(' '))
        () {
          final [reading, rest] = entry.split(':');
          final [char, ...also] = rest.split('|');
          return Kana(script == KanaScript.katakana ? toKatakana(char) : char, reading, group, also);
        }(),
    ];

/// El katakana esta 0x60 puntos por encima del hiragana, letra a letra.
String toKatakana(String hira) =>
    String.fromCharCodes(hira.runes.map((r) => r >= 0x3041 && r <= 0x3096 ? r + 0x60 : r));

final Map<KanaScript, List<Kana>> kanaTable = {
  for (final s in KanaScript.values)
    s: List<Kana>.unmodifiable([
      ..._parse(_basic, KanaGroup.basic, s),
      ..._parse(_dakuten, KanaGroup.dakuten, s),
      ..._parse(_combo, KanaGroup.combo, s),
    ]),
};

List<Kana> kanaOf(KanaScript script, Set<KanaGroup> groups) =>
    kanaTable[script]!.where((k) => groups.contains(k.group)).toList();

/// Lo que se sabe de un kana: cuantas veces ha salido, cuantas se ha
/// acertado y la racha de aciertos seguidos.
class KanaStat {
  const KanaStat({this.seen = 0, this.right = 0, this.streak = 0});

  final int seen;
  final int right;
  final int streak;

  /// Tres aciertos seguidos: dominado.
  bool get mastered => streak >= 3;

  KanaStat answered(bool ok) => KanaStat(seen: seen + 1, right: right + (ok ? 1 : 0), streak: ok ? streak + 1 : 0);
}

class KanaQuestion {
  KanaQuestion(this.kana, this.choices);

  final Kana kana;

  /// Cuatro lecturas, una de ellas la buena. Vacia en modo escribir.
  final List<String> choices;

  /// `null` hasta que se responde.
  String? answer;
  bool? correct;
}

/// Una ronda de [length] tarjetas.
class KanaRound {
  KanaRound({
    required this.script,
    required this.mode,
    required List<Kana> pool,
    required Map<String, KanaStat> stats,
    this.length = 10,
    this.review = false,
    int? seed,
  }) : _random = math.Random(seed) {
    final picks = _pick(pool, stats, math.min(length, pool.length));
    questions = [for (final k in picks) KanaQuestion(k, mode == AnswerMode.choices ? _choicesFor(k, pool) : const [])];
  }

  final KanaScript script;
  final AnswerMode mode;
  final int length;

  /// Solo con los fallos de la ronda anterior: no da monedas.
  final bool review;
  final math.Random _random;
  late final List<KanaQuestion> questions;
  int index = 0;
  int streak = 0;
  int bestStreak = 0;

  KanaQuestion get current => questions[index];
  bool get isLast => index == questions.length - 1;
  bool get done => questions.every((q) => q.correct != null);
  int get right => questions.where((q) => q.correct == true).length;
  bool get perfect => questions.length == length && right == length;
  List<Kana> get missed => [for (final q in questions) if (q.correct == false) q.kana];

  /// Responde la tarjeta actual. Devuelve si es correcta.
  bool answer(String text) {
    final q = current;
    if (q.correct != null) return q.correct!;
    final ok = q.kana.accepts(text);
    q
      ..answer = text
      ..correct = ok;
    streak = ok ? streak + 1 : 0;
    bestStreak = math.max(bestStreak, streak);
    return ok;
  }

  bool next() {
    if (isLast) return false;
    index++;
    return true;
  }

  /// Sin repetir, y con mas papeletas para lo que aun no se domina o se ha
  /// fallado, y para lo que casi no ha salido.
  List<Kana> _pick(List<Kana> pool, Map<String, KanaStat> stats, int n) {
    final left = List<Kana>.of(pool);
    final out = <Kana>[];
    while (out.length < n && left.isNotEmpty) {
      final weights = [
        for (final k in left)
          () {
            final s = stats[k.char] ?? const KanaStat();
            if (s.seen == 0) return 3.0;
            if (s.mastered) return 1.0;
            return 2.0 + (s.seen - s.right).clamp(0, 4);
          }(),
      ];
      final total = weights.fold<double>(0, (a, b) => a + b);
      var r = _random.nextDouble() * total;
      var i = 0;
      while (i < weights.length - 1 && r >= weights[i]) {
        r -= weights[i];
        i++;
      }
      out.add(left.removeAt(i));
    }
    return out;
  }

  /// La buena y tres que se le parecen: de la misma vocal o la misma fila si
  /// se puede, para que haya que fijarse. Nunca dos lecturas iguales (じ y ぢ
  /// se leen las dos «ji»).
  List<String> _choicesFor(Kana k, List<Kana> pool) {
    final all = kanaTable[script]!;
    String vowel(String r) => r.substring(r.length - 1);
    String row(String r) => r.length > 1 ? r.substring(0, r.length - 1) : '';
    final candidates = {
      for (final o in [...pool, ...all])
        if (o.romaji != k.romaji && !k.also.contains(o.romaji) && o.group == k.group) o.romaji,
    }.toList()
      ..shuffle(_random);
    final similar = candidates.where((r) => vowel(r) == vowel(k.romaji) || row(r) == row(k.romaji)).toList();
    final picks = <String>[];
    for (final r in [...similar.take(2), ...candidates]) {
      if (picks.length == 3) break;
      if (!picks.contains(r)) picks.add(r);
    }
    return [...picks, k.romaji]..shuffle(_random);
  }
}

/// Monedas de una ronda: solo un pleno, y nunca un repaso.
int nihongoRewardFor(KanaRound round) =>
    round.review || !round.perfect ? 0 : (round.mode == AnswerMode.write ? 5 : 3);

/// La tabla de un grupo como se ve en los libros: una fila por consonante y
/// una columna por vocal (a i u e o), con huecos donde no hay kana (yi, ye,
/// wu…). Los combinados van en tres columnas: ya, yu, yo.
List<List<Kana?>> kanaChart(KanaScript script, KanaGroup group) {
  final kana = kanaOf(script, {group});
  final width = group == KanaGroup.combo ? 3 : 5;
  // Donde van los kana de las filas que no estan completas.
  const gaps = <String, List<int>>{'ya': [0, 2, 4], 'wa': [0, 4], 'n': [0]};
  final rows = <List<Kana?>>[];
  var i = 0;
  while (i < kana.length) {
    final slots = group == KanaGroup.basic ? gaps[kana[i].romaji] : null;
    final row = List<Kana?>.filled(width, null);
    for (final s in slots ?? List<int>.generate(width, (s) => s)) {
      row[s] = kana[i++];
    }
    rows.add(row);
  }
  return rows;
}
