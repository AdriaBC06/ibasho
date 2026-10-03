// Ibasho — Tama Kōen: los dúos, su racha y su casita.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'koen.dart' show koenHash;
import 'koen_bonds.dart';
import 'tama.dart';

/// Un **dúo** son dos amigos que se cuidan a medias un Tama cada uno: A cuida
/// uno de B y B uno de A. Lo que comparten vive en `/koen/{a_b}` (los dos ids
/// ordenados, como `/dm`), con `a` y `b` dentro para que las reglas lo
/// comprueben.
String koenDuoKey(String x, String y) => x.compareTo(y) < 0 ? '${x}_$y' : '${y}_$x';

const int _dayMs = 86400000;

/// Los premios de la racha conjunta, una sola vez por dúo y cuenta
/// *(propuesta)*. Los cobra cada uno por su lado.
@immutable
class KoenStreakPrize {
  const KoenStreakPrize(this.days, {this.coins = 0, this.ticket = false, this.furniture});

  final int days;
  final int coins;

  /// Un gachaken.
  final bool ticket;

  /// El mueble que se lleva la casita.
  final KoenFurniture? furniture;
}

const List<KoenStreakPrize> koenStreakPrizes = [
  KoenStreakPrize(3, coins: 10),
  KoenStreakPrize(7, coins: 20),
  KoenStreakPrize(14, ticket: true),
  KoenStreakPrize(30, furniture: KoenFurniture.maneki),
];

KoenStreakPrize? koenStreakPrize(int days) => koenStreakPrizes.where((p) => p.days == days).firstOrNull;

/// La racha conjunta: `{count, day, best}`. El día cuenta cuando los dos
/// Tamas del dúo han comido y les han hecho un mimo; lo apunta el primero que
/// lo vea, y las reglas comprueban los cuidados de los dos.
@immutable
class KoenStreak {
  const KoenStreak({this.count = 0, this.day = 0, this.best = 0});

  final int count;

  /// El último día contado.
  final int day;

  /// La más larga que han tenido: con ella sube la casita.
  final int best;

  static KoenStreak fromJson(Object? raw) {
    if (raw is! Map) return const KoenStreak();
    int at(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    return KoenStreak(count: at('count'), day: at('day'), best: at('best'));
  }

  Map<String, int> toJson() => {'count': count, 'day': day, 'best': best};

  /// La racha que llevan hoy: si ayer no contó, ya se ha roto.
  int current(int today) => day >= today - 1 ? count : 0;

  bool countedOn(int today) => day == today;

  /// La racha con [today] contado. Igual si ya contaba.
  KoenStreak advance(int today) {
    if (day == today) return this;
    final next = day == today - 1 ? count + 1 : 1;
    return KoenStreak(count: next, day: today, best: math.max(best, next));
  }
}

/// Si a [tama] ya le han dado de comer y le han hecho un mimo el día [day].
bool koenDuoCared(Tama tama, int day) {
  bool today(DateTime? at) => at != null && at.millisecondsSinceEpoch >= day * _dayMs;
  return today(tama.care.lastFed) && today(tama.care.lastPetted);
}

// --- La casita -----------------------------------------------------------------

/// Los muebles de la casita: un catálogo propio del parque, que no sale en el
/// gacha *(propuesta)*. Cada nivel trae uno (el primero, dos) y la racha de
/// 30 días, el gato de la suerte.
enum KoenFurniture {
  zabuton(level: 1),
  andon(level: 1),
  kotatsu(level: 2),
  bonsai(level: 3),
  tansu(level: 4),
  byobu(level: 5),
  maneki(streak: 30);

  const KoenFurniture({this.level = 0, this.streak = 0});

  /// El nivel de la casita que lo trae, o 0.
  final int level;

  /// La racha que lo trae, o 0.
  final int streak;

  static KoenFurniture? byName(Object? name) => values.where((f) => f.name == name).firstOrNull;
}

/// Lo que pide cada nivel de la casita (2–5): la mejor racha y la amistad
/// entre los dos jugadores *(propuesta)*.
const List<(int, KoenFriendLevel)> koenHouseSteps = [
  (3, KoenFriendLevel.none),
  (7, KoenFriendLevel.friends),
  (14, KoenFriendLevel.good),
  (30, KoenFriendLevel.inseparable),
];

const int koenHouseMaxLevel = 5;

/// El nivel de la casita (1–5).
int koenHouseLevel(int best, KoenFriendLevel friend) {
  var level = 1;
  for (final (streak, need) in koenHouseSteps) {
    if (best < streak || friend.index < need.index) break;
    level++;
  }
  return level;
}

/// Los huecos para muebles: uno más que el nivel.
int koenDecorSpots(int level) => level + 1;

/// Los muebles que tiene la casita con [level] y la mejor racha [best].
List<KoenFurniture> koenFurnitureFor(int level, int best) => [
  for (final f in KoenFurniture.values)
    if ((f.level > 0 && f.level <= level) || (f.streak > 0 && best >= f.streak)) f,
];

/// Lo que comparte un dúo, tal como está en `/koen/{a_b}`.
@immutable
class KoenDuoData {
  const KoenDuoData({
    this.exists = false,
    this.left,
    this.right,
    this.streak = const KoenStreak(),
    this.decor = const <int, KoenFurniture>{},
    this.charm,
  });

  /// Si ya se ha escrito algo (con `a` y `b`).
  final bool exists;

  /// Los Tamas de cada lado de la casita.
  final String? left;
  final String? right;

  final KoenStreak streak;

  /// Los muebles, por hueco.
  final Map<int, KoenFurniture> decor;

  /// El accesorio de pareja que han elegido, si ya hay uno.
  final KoenCharmChoice? charm;

  static KoenDuoData fromJson(Object? raw) {
    if (raw is! Map) return const KoenDuoData();
    final slots = raw['slots'] is Map ? raw['slots'] as Map : const <Object?, Object?>{};
    final decor = <int, KoenFurniture>{};
    final rawDecor = (raw['house'] is Map ? raw['house'] as Map : const <Object?, Object?>{})['decor'];
    void put(Object? key, Object? value) {
      final spot = int.tryParse('$key');
      final f = KoenFurniture.byName(value);
      if (spot != null && f != null) decor[spot] = f;
    }

    if (rawDecor is Map) {
      rawDecor.forEach(put);
    } else if (rawDecor is List) {
      for (var i = 0; i < rawDecor.length; i++) {
        put(i, rawDecor[i]);
      }
    }
    return KoenDuoData(
      exists: raw['a'] is String,
      left: slots['left'] is String ? slots['left'] as String : null,
      right: slots['right'] is String ? slots['right'] as String : null,
      streak: KoenStreak.fromJson(raw['streak']),
      decor: decor,
      charm: KoenCharmChoice.fromJson(raw['charm']),
    );
  }

  KoenDuoData copyWith({
    bool? exists,
    String? left,
    String? right,
    KoenStreak? streak,
    Map<int, KoenFurniture>? decor,
    KoenCharmChoice? charm,
  }) => KoenDuoData(
    exists: exists ?? this.exists,
    left: left ?? this.left,
    right: right ?? this.right,
    streak: streak ?? this.streak,
    decor: decor ?? this.decor,
    charm: charm ?? this.charm,
  );
}

/// Un dúo visto desde la cuenta [me]: con quién, los Tamas que se cuidan a
/// medias el uno al otro y lo que comparten.
@immutable
class KoenDuo {
  const KoenDuo({
    required this.me,
    required this.friend,
    required this.mine,
    required this.theirs,
    this.data = const KoenDuoData(),
    this.demo = false,
  });

  final String me;
  final String friend;

  /// Los Tamas propios que cuida [friend], y los suyos que cuida la cuenta.
  final List<Tama> mine;
  final List<Tama> theirs;

  final KoenDuoData data;

  /// El dúo de prueba del parque: no escribe nada.
  final bool demo;

  String get key => koenDuoKey(me, friend);

  /// `a`, la cuenta con el id menor.
  String get a => me.compareTo(friend) < 0 ? me : friend;

  Tama? _byId(String? id) => [...mine, ...theirs].where((t) => t.id == id).firstOrNull;

  /// Los Tamas de la casita. Lo guardado si aún vale (uno de cada uno y los
  /// dos todavía a medias); si no, el primero de cada uno, el de `a` a la
  /// izquierda.
  (Tama, Tama) get pair {
    final l = _byId(data.left);
    final r = _byId(data.right);
    if (l != null && r != null && l.creator != r.creator) return (l, r);
    final ofA = a == me ? mine.first : theirs.first;
    final ofB = a == me ? theirs.first : mine.first;
    return (ofA, ofB);
  }

  Tama get left => pair.$1;
  Tama get right => pair.$2;

  /// Los ids de los dos Tamas de la casita.
  Set<String> get tamaIds => {left.id, right.id};

  /// El otro Tama de la casita, si [tamaId] es uno de ellos.
  String? mateOf(String tamaId) => tamaId == left.id
      ? right.id
      : tamaId == right.id
      ? left.id
      : null;

  bool caredOn(int day) => koenDuoCared(left, day) && koenDuoCared(right, day);

  int level(KoenFriendLevel friend) => koenHouseLevel(data.streak.best, friend);

  /// El Tama propio de la casita y si está a la izquierda.
  (Tama, bool) get myHalf {
    final (l, r) = pair;
    return l.creator == me ? (l, true) : (r, false);
  }

  /// El código de color del accesorio de la pareja.
  String get charmCode => koenCharmCode(key);

  KoenDuo copyWith({List<Tama>? mine, List<Tama>? theirs, KoenDuoData? data}) => KoenDuo(
    me: me,
    friend: friend,
    mine: mine ?? this.mine,
    theirs: theirs ?? this.theirs,
    data: data ?? this.data,
    demo: demo,
  );
}

/// Los dúos de [me]: los amigos con los que se cuida a medias un Tama de cada
/// uno. [own] son los Tamas propios y [cared] los de amigos que cuida.
Map<String, (List<Tama>, List<Tama>)> koenDuoTamas(String me, List<Tama> own, List<Tama> cared) {
  final out = <String, (List<Tama>, List<Tama>)>{};
  for (final t in own) {
    final friend = t.carer;
    if (friend == null || friend == me) continue;
    final theirs = [for (final c in cared) if (c.creator == friend && c.carer == me) c];
    if (theirs.isEmpty) continue;
    final mine = [for (final o in own) if (o.carer == friend) o];
    out[friend] = (mine, theirs);
  }
  return out;
}

// --- El accesorio de pareja ----------------------------------------------------

/// Las formas del accesorio de pareja. Cada Tama de la casita lleva una
/// mitad: la de la izquierda, el que está a la izquierda.
enum KoenCharm {
  /// Un corazón partido al cuello.
  pendant,

  /// Dos gorritos iguales, cada uno con la borla hacia el otro.
  twins,

  /// El hilo rojo, atado del lado del otro.
  thread;

  static KoenCharm? byName(Object? name) => values.where((c) => c.name == name).firstOrNull;
}

/// Lo que pide el accesorio: el dúo y ser «buenos amigos» *(propuesta)*.
const KoenFriendLevel koenCharmLevel = KoenFriendLevel.good;

/// El código de color de un dúo: sale de los dos ids ordenados, así que es
/// el mismo en los dos móviles. Va en la clave del premio, que así es propia
/// de cada pareja.
String koenCharmCode(String pairKey) => (koenHash('charm:$pairKey') & 0xffffff).toRadixString(16).padLeft(6, '0');

/// El tono (0–359) del accesorio con el código [code].
int koenCharmHue(String code) => (int.tryParse(code, radix: 16) ?? 0) % 360;

/// La clave de premio de una mitad: `charm_{forma}_{l|r}_{código}`.
String koenCharmKey(KoenCharm shape, {required bool left, required String code}) =>
    'charm_${shape.name}_${left ? 'l' : 'r'}_$code';

final RegExp _charmKey = RegExp(r'^charm_(pendant|twins|thread)_([lr])_([0-9a-f]{6})$');

/// Una mitad del accesorio leída de su clave.
typedef KoenCharmHalf = ({KoenCharm shape, bool left, String code});

KoenCharmHalf? koenCharmOf(String? key) {
  final m = key == null ? null : _charmKey.firstMatch(key);
  if (m == null) return null;
  return (shape: KoenCharm.byName(m[1])!, left: m[2] == 'l', code: m[3]!);
}

/// Lo que ha elegido la pareja, en `/koen/{a_b}/charm`.
@immutable
class KoenCharmChoice {
  const KoenCharmChoice(this.shape, this.code);

  final KoenCharm shape;
  final String code;

  static KoenCharmChoice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final shape = KoenCharm.byName(raw['shape']);
    final code = raw['code'];
    if (shape == null || code is! String || !RegExp(r'^[0-9a-f]{6}$').hasMatch(code)) return null;
    return KoenCharmChoice(shape, code);
  }

  Map<String, String> toJson() => {'shape': shape.name, 'code': code};

  String keyFor({required bool left}) => koenCharmKey(shape, left: left, code: code);
}

/// La forma y el color que comparten dos Tamas que llevan cada uno una mitad
/// del mismo accesorio (de la misma pareja y lados distintos), o `null`.
KoenCharmChoice? koenCharmMatch(Iterable<String> a, Iterable<String> b) {
  for (final x in a.map(koenCharmOf)) {
    if (x == null) continue;
    for (final y in b.map(koenCharmOf)) {
      if (y != null && y.shape == x.shape && y.code == x.code && y.left != x.left) {
        return KoenCharmChoice(x.shape, x.code);
      }
    }
  }
  return null;
}
