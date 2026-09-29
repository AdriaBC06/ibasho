// Ibasho — Hatarakitama: el motor idle, sin interfaz.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import '../../backend/tama.dart' show TamaPersonality;
import 'hataraki_data.dart';

/// Nivel máximo de cada oficio y de cada maestría.
const int hMaxLevel = 99;

/// Lo más que se trabaja sin la app abierta.
const Duration hOfflineCap = Duration(hours: 12);

/// Lo que dura un té.
const Duration hTeaDuration = Duration(minutes: 30);

/// Nivel total que abre cada ranura de trabajo (la primera viene de serie).
const List<int> hSlotThresholds = [0, 40, 100, 200, 350, 550];

/// Tamas por expedición.
const int hMaxParty = 3;

/// Experiencia acumulada para llegar a cada nivel: se empieza en el 0, el 1
/// llega con la primera tanda de trabajo y del 2 al 99 es la curva de
/// RuneScape (el 92 es la mitad del 99). `_xpTable[n]` = experiencia del
/// nivel n.
final List<int> _xpTable = () {
  final table = <int>[0, hXpLevelOne];
  var points = 0.0;
  for (var level = 1; level < hMaxLevel; level++) {
    points += (level + 300 * pow(2, level / 7)).floorToDouble();
    table.add((points / 4).floor());
  }
  return table;
}();

/// Experiencia del nivel 1, a medio camino del 2 (83).
const int hXpLevelOne = 40;

/// Experiencia total que pide `level` (0–99).
int hXpForLevel(int level) => _xpTable[level.clamp(0, hMaxLevel)];

/// Nivel que da tanta experiencia (0–99).
int hLevelForXp(int xp) {
  var lo = 0, hi = _xpTable.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (_xpTable[mid] <= xp) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// Ranuras de trabajo con este nivel total.
int hSlotsFor(int totalLevel) =>
    hSlotThresholds.where((t) => totalLevel >= t).length;

/// Lo que el juego necesita saber de un Tama para ponerlo a trabajar.
class HTama {
  const HTama(this.id, this.personality, this.mood);
  final String id;
  final TamaPersonality personality;

  /// Ánimo de 0 a 1 (`TamaMoodReading.value`).
  final double mood;

  bool likes(HSkill skill) =>
      hAffinities[personality]?.contains(skill) ?? false;
}

/// Una ranura de trabajo: qué Tama hace qué y cuánto lleva.
class HWorker {
  HWorker(
    this.tamaId,
    this.actionId, {
    this.progress = 0,
    this.stalled = false,
  });

  String tamaId;
  String actionId;

  /// De 0 a 1: lo que lleva de la acción en curso.
  double progress;

  /// Se ha parado porque faltan materiales.
  bool stalled;

  Map<String, Object> toJson() => {
    'tama': tamaId,
    'action': actionId,
    'progress': progress,
    if (stalled) 'stalled': true,
  };

  static HWorker? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tama = raw['tama'], action = raw['action'];
    if (tama is! String || action is! String) return null;
    if (hAction(action) == null) return null;
    return HWorker(
      tama,
      action,
      progress: ((raw['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      stalled: raw['stalled'] == true,
    );
  }
}

/// Una expedición en curso. La fuerza se fija al salir.
class HExpedition {
  const HExpedition(
    this.zone,
    this.tamaIds,
    this.startedAt,
    this.endsAt,
    this.power,
  );

  final String zone;
  final List<String> tamaIds;
  final int startedAt;
  final int endsAt;
  final int power;

  Map<String, Object> toJson() => {
    'zone': zone,
    'tamas': tamaIds,
    'start': startedAt,
    'end': endsAt,
    'power': power,
  };

  static HExpedition? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final zone = raw['zone'];
    if (zone is! String || hZoneById[zone] == null) return null;
    return HExpedition(
      zone,
      _list(raw['tamas']).whereType<String>().toList(),
      (raw['start'] as num?)?.toInt() ?? 0,
      (raw['end'] as num?)?.toInt() ?? 0,
      (raw['power'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Lo que ha pasado en un tramo de tiempo: para el resumen de «mientras no
/// estabas» y para los avisos en vivo.
class HReport {
  final Map<String, int> gained = {};
  final Map<String, int> spent = {};
  final Map<HSkill, int> xp = {};

  /// Oficio → nivel nuevo, solo si ha subido.
  final Map<HSkill, int> levelUps = {};
  final Set<String> stalledTamas = {};

  /// Expedición que ha vuelto en este tramo (con su éxito, 0–1).
  String? expeditionZone;
  double expeditionSuccess = 0;
  int prizes = 0;

  /// Segundos simulados (con el tope aplicado).
  double seconds = 0;

  bool get isEmpty => gained.isEmpty && xp.isEmpty && expeditionZone == null;

  void _add(Map<String, int> into, String item, int n) =>
      into[item] = (into[item] ?? 0) + n;
}

/// La partida entera. Se guarda en `/users/{cuenta}/hataraki`.
class HState {
  HState({
    Map<HSkill, int>? xp,
    Map<String, int>? mastery,
    Map<String, int>? bank,
    List<HWorker>? workers,
    Map<HGearSlot, String>? kit,
    this.tea,
    this.teaUntil = 0,
    this.expedition,
    required this.lastTick,
    this.seed = 1,
    this.prizes = 0,
    this.claimAt = 0,
    this.day = 0,
    this.dayXp = 0,
    this.week = 0,
    this.weekXp = 0,
    this.money = 0,
    this.earned = 0,
    this.dayMoney = 0,
    this.weekMoney = 0,
  }) : xp = xp ?? {},
       mastery = mastery ?? {},
       bank = bank ?? {},
       workers = workers ?? [],
       kit = kit ?? {};

  final Map<HSkill, int> xp;
  final Map<String, int> mastery;
  final Map<String, int> bank;
  final List<HWorker> workers;

  /// Equipo que se lleva a las expediciones (tiene que estar en el almacén).
  final Map<HGearSlot, String> kit;
  String? tea;
  int teaUntil;
  HExpedition? expedition;

  /// Hasta dónde está simulada la partida (ms desde epoch).
  int lastTick;
  int seed;

  /// Premios del gacha traídos de expedición y aún sin entregar.
  int prizes;

  /// Cuándo se canjeó el último tesoro por un ticket (hora del servidor).
  int claimAt;

  /// Experiencia ganada en el día y la semana en curso (los números los pone
  /// quien llama): es lo que cuenta en la clasificación.
  int day;
  int dayXp;
  int week;
  int weekXp;

  /// Mon (la moneda del pueblo) que hay ahora y los ganados vendiendo desde
  /// siempre, en el día y en la semana: la clasificación va por riqueza.
  int money;
  int earned;
  int dayMoney;
  int weekMoney;

  /// Pasa al día [today] y a la semana [thisWeek], empezando de cero lo que
  /// cuenta en cada uno si han cambiado.
  void _roll(int today, int thisWeek) {
    if (day != today) {
      day = today;
      dayXp = 0;
      dayMoney = 0;
    }
    if (week != thisWeek) {
      week = thisWeek;
      weekXp = 0;
      weekMoney = 0;
    }
  }

  /// Suma [amount] de experiencia al día [today] y a la semana [thisWeek].
  void countXp(int amount, {required int today, required int thisWeek}) {
    _roll(today, thisWeek);
    dayXp += amount;
    weekXp += amount;
  }

  /// Vende [n] de [item] del almacén (lo que haya, si hay menos) y apunta
  /// los mon al día [today] y a la semana [thisWeek]. Devuelve lo ganado.
  int sell(String item, int n, {required int today, required int thisWeek}) {
    final units = min(n, count(item));
    final price = hSellValue(item);
    if (units <= 0 || price <= 0) return 0;
    _take(item, units);
    final got = units * price;
    _roll(today, thisWeek);
    money += got;
    earned += got;
    dayMoney += got;
    weekMoney += got;
    return got;
  }

  int levelOf(HSkill skill) => hLevelForXp(xp[skill] ?? 0);

  int get totalLevel => HSkill.values.fold(0, (sum, s) => sum + levelOf(s));

  int get slots => hSlotsFor(totalLevel);

  int masteryOf(String action) => hLevelForXp(mastery[action] ?? 0);

  int count(String item) => bank[item] ?? 0;

  bool isBusy(String tamaId) =>
      workers.any((w) => w.tamaId == tamaId) ||
      (expedition?.tamaIds.contains(tamaId) ?? false);

  bool _has(Map<String, int> items, [int times = 1]) =>
      items.entries.every((e) => count(e.key) >= e.value * times);

  // ------------------------------------------------------------------
  // Órdenes del jugador. Devuelven false si no se puede.

  /// Pone a un Tama a hacer una acción (o le cambia la que hace).
  bool assign(String tamaId, String actionId) {
    final action = hAction(actionId);
    if (action == null || levelOf(action.skill) < action.level) return false;
    if (expedition?.tamaIds.contains(tamaId) ?? false) return false;
    final current = workers.where((w) => w.tamaId == tamaId).firstOrNull;
    if (current != null) {
      if (current.actionId != actionId) current.progress = 0;
      current
        ..actionId = actionId
        ..stalled = false;
      return true;
    }
    if (workers.length >= slots) return false;
    workers.add(HWorker(tamaId, actionId));
    return true;
  }

  void release(String tamaId) => workers.removeWhere((w) => w.tamaId == tamaId);

  /// Se toma un té: acelera durante media hora.
  bool drinkTea(String item, int now) {
    if (hItem(item)?.kind != HItemKind.tea || count(item) < 1) return false;
    _take(item, 1);
    tea = item;
    teaUntil = now + hTeaDuration.inMilliseconds;
    return true;
  }

  /// Un Tama se come una unidad de [item] (tiene que ser comida).
  bool eat(String item) {
    if (hItem(item)?.kind != HItemKind.food || count(item) < 1) return false;
    _take(item, 1);
    return true;
  }

  /// Quita del equipo de viaje lo que hay en [slot].
  bool unequip(HGearSlot slot) => kit.remove(slot) != null;

  /// Vuelve antes de tiempo: sin botín ni experiencia, y la comida ya se
  /// gastó al salir.
  bool cancelExpedition() {
    if (expedition == null) return false;
    expedition = null;
    return true;
  }

  /// Éxito de una expedición (0,3–1) con [power] frente a [zone].
  static double successFor(HZone zone, int power) =>
      (power / zone.difficulty).clamp(0.3, 1.0);

  bool equip(String item) {
    final def = hItem(item);
    if (def?.slot == null || count(item) < 1) return false;
    kit[def!.slot!] = item;
    return true;
  }

  /// Fuerza de un grupo con el equipo actual.
  int partyPower(List<HTama> party) {
    final level = levelOf(HSkill.expedition);
    var power = 0.0;
    for (final t in party) {
      power +=
          (5 + level) * (t.likes(HSkill.expedition) ? 1 + hAffinityBonus : 1);
    }
    for (final item in kit.values) {
      if (count(item) > 0) power += hItem(item)?.power ?? 0;
    }
    return power.round();
  }

  /// Comida (puntos) que pide una expedición.
  static int foodNeeded(HZone zone, int party) =>
      (party * zone.minutes / 10).ceil();

  /// Sale de expedición: gasta comida del tipo elegido.
  bool startExpedition(String zoneId, List<HTama> party, String food, int now) {
    final zone = hZoneById[zoneId];
    final foodDef = hItem(food);
    if (zone == null || expedition != null) return false;
    if (party.isEmpty || party.length > hMaxParty) return false;
    if (levelOf(HSkill.expedition) < zone.level) return false;
    if (party.any((t) => isBusy(t.id))) return false;
    if (foodDef == null || foodDef.food <= 0) return false;
    final units = (foodNeeded(zone, party.length) / foodDef.food).ceil();
    if (count(food) < units) return false;
    _take(food, units);
    expedition = HExpedition(
      zoneId,
      [for (final t in party) t.id],
      now,
      now + zone.minutes * 60000,
      partyPower(party),
    );
    return true;
  }

  // ------------------------------------------------------------------
  // El paso del tiempo.

  /// Trabaja desde `lastTick` hasta `now` (con el tope de 12 h) y cierra la
  /// expedición si ya ha vuelto. `tamas` da personalidad y ánimo de cada uno;
  /// si un Tama ya no existe, su ranura se libera.
  HReport advance(int now, Map<String, HTama> tamas) {
    final report = HReport();
    workers.removeWhere((w) => !tamas.containsKey(w.tamaId));
    final rng = Random(seed);
    final levelsBefore = {for (final s in HSkill.values) s: levelOf(s)};

    final elapsed = (now - lastTick).clamp(0, hOfflineCap.inMilliseconds);
    final total = elapsed / 1000;
    report.seconds = total;
    final start = now - elapsed;

    final active = workers.where((w) => !w.stalled).toList();
    final durations = <HWorker, double>{};
    final nextAt = <HWorker, double>{};
    for (final w in active) {
      durations[w] = _duration(w, tamas[w.tamaId]!, start);
      nextAt[w] = (1 - w.progress) * durations[w]!;
    }

    // Cola de eventos: siempre acaba primero el que menos le queda, para que
    // dos Tamas que gastan lo mismo se lo repartan en orden.
    while (nextAt.isNotEmpty) {
      var w = nextAt.keys.first;
      for (final other in nextAt.keys) {
        if (nextAt[other]! < nextAt[w]!) w = other;
      }
      final t = nextAt[w]!;
      if (t > total) break;
      if (!_complete(w, rng, report)) {
        w
          ..stalled = true
          ..progress = 0;
        report.stalledTamas.add(w.tamaId);
        nextAt.remove(w);
        continue;
      }
      final d = _duration(w, tamas[w.tamaId]!, start + (t * 1000).round());
      durations[w] = d;
      nextAt[w] = t + d;
    }
    for (final w in nextAt.keys) {
      w.progress = (1 - (nextAt[w]! - total) / durations[w]!).clamp(0.0, 1.0);
    }

    final exp = expedition;
    if (exp != null && now >= exp.endsAt) _finishExpedition(exp, rng, report);

    for (final s in HSkill.values) {
      final after = levelOf(s);
      if (after > levelsBefore[s]!) report.levelUps[s] = after;
    }
    seed = rng.nextInt(1 << 31);
    lastTick = now;
    return report;
  }

  /// Segundos que tarda una vez la acción de este Tama en este momento.
  double _duration(HWorker w, HTama tama, int atMs) =>
      secondsFor(hAction(w.actionId)!, tama, atMs);

  /// Segundos que tarda [action] con [tama] en [atMs]: ánimo, maña,
  /// agilidad, té y maestría.
  double secondsFor(HAction action, HTama tama, int atMs) {
    var speed =
        (0.8 + 0.4 * tama.mood.clamp(0.0, 1.0)) *
        (tama.likes(action.skill) ? 1 + hAffinityBonus : 1) *
        (1 + levelOf(HSkill.agility) * 0.001);
    final teaDef = tea == null ? null : hItem(tea!);
    if (teaDef != null &&
        atMs < teaUntil &&
        (teaDef.teaSkill == null || teaDef.teaSkill == action.skill)) {
      speed *= 1 + teaDef.teaBoost;
    }
    final mastery = 1 - masteryOf(action.id) * 0.002;
    return action.seconds * mastery / speed;
  }

  /// Termina una vez la acción. False si no hay materiales.
  bool _complete(HWorker w, Random rng, HReport report) {
    final action = hAction(w.actionId)!;
    if (!_has(action.inputs)) return false;
    for (final e in action.inputs.entries) {
      _take(e.key, e.value);
      report._add(report.spent, e.key, e.value);
    }
    // Con maestría, a veces sale doble.
    final times = rng.nextDouble() < masteryOf(action.id) / 400 ? 2 : 1;
    for (final e in action.outputs.entries) {
      _give(e.key, e.value * times);
      report._add(report.gained, e.key, e.value * times);
    }
    for (final drop in action.drops) {
      if (rng.nextDouble() < drop.chance) {
        _give(drop.item, 1);
        report._add(report.gained, drop.item, 1);
      }
    }
    _gainXp(action.skill, action.xp, report);
    // La maestría va a otro ritmo: una cuarta parte de la experiencia.
    mastery[action.id] = (mastery[action.id] ?? 0) + max(1, action.xp ~/ 4);
    return true;
  }

  void _finishExpedition(HExpedition exp, Random rng, HReport report) {
    final zone = hZoneById[exp.zone]!;
    final success = successFor(zone, exp.power);
    for (final loot in zone.loot) {
      if (rng.nextDouble() >= loot.chance * success) continue;
      final n = loot.min + rng.nextInt(loot.max - loot.min + 1);
      final got = max(1, (n * success).round());
      _give(loot.item, got);
      report._add(report.gained, loot.item, got);
    }
    if (rng.nextDouble() < zone.prizeChance * success) {
      prizes++;
      report.prizes++;
    }
    _gainXp(HSkill.expedition, (zone.xp * success).round(), report);
    report
      ..expeditionZone = zone.id
      ..expeditionSuccess = success;
    expedition = null;
  }

  void _gainXp(HSkill skill, int amount, HReport report) {
    final cap = hXpForLevel(hMaxLevel) * 2;
    xp[skill] = min(cap, (xp[skill] ?? 0) + amount);
    report.xp[skill] = (report.xp[skill] ?? 0) + amount;
  }

  void _give(String item, int n) => bank[item] = count(item) + n;

  void _take(String item, int n) {
    final left = count(item) - n;
    if (left > 0) {
      bank[item] = left;
    } else {
      bank.remove(item);
      kit.removeWhere((_, id) => id == item);
    }
  }

  // ------------------------------------------------------------------
  // Guardado.

  Map<String, Object> toJson() => {
    'xp': {for (final e in xp.entries) e.key.name: e.value},
    'mastery': mastery,
    'bank': bank,
    'workers': {
      for (var i = 0; i < workers.length; i++) '$i': workers[i].toJson(),
    },
    'kit': {for (final e in kit.entries) e.key.name: e.value},
    if (tea != null) 'tea': {'item': tea!, 'until': teaUntil},
    if (expedition != null) 'expedition': expedition!.toJson(),
    'last': lastTick,
    'seed': seed,
    'prizes': prizes,
    if (claimAt > 0) 'claimAt': claimAt,
    'money': money,
    'earned': earned,
    'period': {
      'day': day,
      'dayXp': dayXp,
      'week': week,
      'weekXp': weekXp,
      'dayMoney': dayMoney,
      'weekMoney': weekMoney,
    },
  };

  /// Partida nueva: todo a nivel 0 y un puñado de semillas para el huerto.
  factory HState.fresh(int now) =>
      HState(lastTick: now, seed: now & 0x7fffffff, bank: {'seed_rice': 5});

  static HState fromJson(Object? raw, int now) {
    if (raw is! Map) return HState.fresh(now);
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    Map<String, int> counts(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is num && (e.value as num) > 0)
            '${e.key}': (e.value as num).toInt(),
    };
    final xp = <HSkill, int>{};
    for (final e in counts(raw['xp']).entries) {
      final skill = HSkill.byName(e.key);
      if (skill != null) xp[skill] = e.value;
    }
    final kit = <HGearSlot, String>{};
    final rawKit = raw['kit'];
    if (rawKit is Map) {
      for (final slot in HGearSlot.values) {
        final item = rawKit[slot.name];
        if (item is String && hItem(item)?.slot == slot) kit[slot] = item;
      }
    }
    final tea = raw['tea'];
    final period = raw['period'] is Map ? raw['period'] as Map : const {};
    return HState(
      day: n(period['day']),
      dayXp: n(period['dayXp']),
      week: n(period['week']),
      weekXp: n(period['weekXp']),
      dayMoney: n(period['dayMoney']),
      weekMoney: n(period['weekMoney']),
      money: n(raw['money']),
      earned: n(raw['earned']),
      xp: xp,
      mastery: counts(raw['mastery']),
      bank: counts(raw['bank']),
      workers: _list(
        raw['workers'],
      ).map(HWorker.fromJson).whereType<HWorker>().toList(),
      kit: kit,
      tea: tea is Map && tea['item'] is String ? tea['item'] as String : null,
      teaUntil: tea is Map ? n(tea['until']) : 0,
      expedition: HExpedition.fromJson(raw['expedition']),
      lastTick: raw['last'] is num ? n(raw['last']) : now,
      seed: n(raw['seed']),
      prizes: n(raw['prizes']),
      claimAt: n(raw['claimAt']),
    );
  }
}

/// Mon que se dan por cada experiencia que costó hacer algo.
const double hMonPerXp = .2;

final Map<String, int> _prices = {};

/// Lo que vale un objeto al venderlo, en mon. Sale de lo que cuesta hacerlo:
/// lo que valen sus materiales más la experiencia de la tarea (repartido
/// entre lo que saca). Lo que solo cae (gemas, semillas, tesoros de viaje)
/// vale más cuanto menos cae. Siempre al menos 1.
int hSellValue(String id) =>
    _prices[id] ??= hItem(id) == null ? 0 : max(1, _price(id, <String>{}).round());

double _price(String id, Set<String> seen) {
  // Un objeto que se usa para hacerse a sí mismo (las semillas) no cuenta
  // dos veces.
  if (!seen.add(id)) return 0;
  var best = double.infinity;
  for (final a in hActions) {
    final out = a.outputs[id];
    if (out == null) continue;
    var cost = a.xp * hMonPerXp;
    for (final e in a.inputs.entries) {
      cost += _price(e.key, {...seen}) * e.value;
    }
    best = min(best, cost / out);
  }
  if (best.isFinite) return best;
  // Lo que cae de una tarea: una décima parte de lo que vale hacerla, entre
  // lo poco que cae.
  for (final a in hActions) {
    for (final d in a.drops) {
      if (d.item == id) best = min(best, a.xp * hMonPerXp * .1 / d.chance);
    }
  }
  // El botín de una expedición: la experiencia del viaje repartida entre lo
  // que se trae.
  for (final z in hZones) {
    for (final l in z.loot) {
      if (l.item != id) continue;
      final units = l.chance * (l.min + l.max) / 2;
      best = min(best, z.xp * hMonPerXp / z.loot.length / units);
    }
  }
  return best.isFinite ? best : 1;
}

/// La base de datos devuelve las listas como mapas con claves numéricas.
List<Object?> _list(Object? raw) {
  if (raw is List) return raw;
  if (raw is Map) {
    final keys = raw.keys.map((k) => '$k').toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return [for (final k in keys) raw[k]];
  }
  return const [];
}
