// Ibasho — Hatarakitama: los encargos del tablón.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'hataraki_data.dart';
import 'hataraki_town.dart' show HDayRng;

/// Lo que traen las casillas de encargo del mapa y a veces pide el gran
/// encargo.
const String hParcel = 'parcel';

/// Encargos normales al día con el tablón a nivel [level]: tres, cuatro con
/// el nivel 2 y cinco con el 4. El gran encargo va aparte. El tablón viene
/// hecho (nivel 1) desde el principio.
int hBoardSlots(int level) => 3 + level ~/ 2;

/// Ginmon de más por cada nivel de tablón por encima del 1.
const double hBoardPay = .06;

/// Un encargo: lo que pide y lo que paga. El gran encargo paga además un
/// ticket gachaken (uno al día).
class HOrder {
  HOrder({
    required this.wants,
    required this.money,
    this.skill,
    this.xp = 0,
    this.gift,
    this.giftN = 0,
    this.plan,
    this.big = false,
    this.done = false,
  });

  final Map<String, int> wants;
  final int money;

  /// Experiencia en [skill] (el oficio de lo que se pide).
  final HSkill? skill;
  final int xp;

  /// Algo raro de regalo.
  final String? gift;
  final int giftN;

  /// El plano de un mueble, de regalo.
  final String? plan;
  final bool big;
  bool done;

  /// Lo que cuesta cambiarlo por otro (una vez al día).
  int get swapPrice => max(20, money ~/ 4);

  Map<String, Object> toJson() => {
    'wants': wants,
    'money': money,
    if (skill != null && xp > 0) ...{'skill': skill!.name, 'xp': xp},
    if (gift != null && giftN > 0) ...{'gift': gift!, 'giftN': giftN},
    'plan': ?plan,
    if (big) 'big': true,
    if (done) 'done': true,
  };

  static HOrder? fromJson(Object? raw) {
    if (raw is! Map || raw['wants'] is! Map) return null;
    final wants = <String, int>{
      for (final e in (raw['wants'] as Map).entries)
        if (hItem('${e.key}') != null && e.value is num && (e.value as num) > 0)
          '${e.key}': (e.value as num).toInt(),
    };
    if (wants.isEmpty) return null;
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final gift = raw['gift'];
    final plan = raw['plan'];
    return HOrder(
      wants: wants,
      money: n(raw['money']),
      skill: HSkill.byName(raw['skill']),
      xp: n(raw['xp']),
      gift: gift is String && hItem(gift) != null ? gift : null,
      giftN: n(raw['giftN']),
      plan: plan is String && hItem(plan)?.kind == HItemKind.furniture
          ? plan
          : null,
      big: raw['big'] == true,
      done: raw['done'] == true,
    );
  }
}

final Map<String, double> _efforts = {};

/// Segundos de trabajo que cuesta hacer una unidad de [id] desde cero (con
/// sus materiales), sin bonos. Lo que cae de una tarea cuenta lo que se
/// tarda en que caiga; lo que solo se trae de viaje, infinito.
double hEffort(String id) => _efforts[id] ??= _effort(id, <String>{});

double _effort(String id, Set<String> seen) {
  if (!seen.add(id)) return double.infinity;
  var best = double.infinity;
  for (final a in hActions) {
    final out = a.outputs[id];
    if (out == null) continue;
    var cost = a.seconds;
    for (final e in a.inputs.entries) {
      // Las semillas se sacan de la cosecha: no cuentan dos veces.
      final input = _effort(e.key, {...seen});
      if (!input.isFinite) {
        // Lo que se usa para hacerse a sí mismo (semillas) no cuenta; lo
        // que solo se trae de viaje, tampoco se puede pedir hecho.
        if (hItem(e.key)?.kind == HItemKind.seed) continue;
        cost = double.infinity;
        break;
      }
      cost += input * e.value;
    }
    best = min(best, cost / out);
  }
  for (final a in hActions) {
    for (final d in a.drops) {
      if (d.item == id) best = min(best, a.seconds / d.chance);
    }
  }
  return best;
}

/// Hace el encargo [slot] del tablón del día [day] para la partida de
/// semilla [seed]: con lo que ya se sabe hacer ([canDo]), mejor de oficios
/// que ya se trabajan ([practised]) y que no estén ya en el tablón
/// ([avoid]). El 0 es el gran encargo. [variant] sube al cambiarlo por otro.
/// Uno de cada cuatro normales regala uno de los [plans] de muebles.
HOrder hMakeOrder({
  required int day,
  required int seed,
  required int slot,
  required bool Function(HAction a) canDo,
  required bool Function(HSkill s) practised,
  required int Function(String id) sellValue,
  required int expeditionLevel,
  required int board,
  Set<HSkill> avoid = const {},
  List<String> plans = const [],
  int variant = 0,
}) {
  final rng = HDayRng(day, 40 + slot * 7 + variant * 101 + seed % 9973);
  final big = slot == 0;
  // Lo que se sabe hacer, por oficio (lo último que se ha abierto, antes).
  final bySkill = <HSkill, List<HAction>>{};
  for (final a in hActions) {
    if (a.outputs.isEmpty || !canDo(a)) continue;
    if (a.skill == HSkill.agility || a.skill == HSkill.study) continue;
    final item = a.outputs.keys.first;
    if (hItem(item)?.kind == HItemKind.seed || !hEffort(item).isFinite) {
      continue;
    }
    bySkill.putIfAbsent(a.skill, () => []).add(a);
  }
  for (final list in bySkill.values) {
    list.sort((a, b) => b.level.compareTo(a.level));
  }
  final skills = bySkill.keys.toList()..sort((a, b) => a.index - b.index);
  rng.shuffle(skills);
  // Primero lo que ya se trabaja y no está en el tablón; luego lo que no
  // está; al final, lo demás.
  int rank(HSkill s) => (avoid.contains(s) ? 2 : 0) + (practised(s) ? 0 : 1);
  final pool = [
    for (var r = 0; r <= 3; r++) ...skills.where((s) => rank(s) == r),
  ];

  /// Una cosa de un oficio: de las tres últimas que se han abierto, más a
  /// menudo la más nueva.
  HAction pick(HSkill skill) {
    final list = bySkill[skill]!;
    final roll = rng.nextInt(6);
    final i = roll < 3 ? 0 : (roll < 5 ? 1 : 2);
    return list[min(i, list.length - 1)];
  }

  // Lo que da un segundo del trabajo mejor pagado que ya se sabe hacer.
  var rate = 0.0;
  for (final list in bySkill.values) {
    for (final a in list) {
      final item = a.outputs.keys.first;
      rate = max(rate, sellValue(item) / hEffort(item));
    }
  }
  final wants = <String, int>{};
  var seconds = 0.0;
  var xp = 0;
  HSkill? xpSkill;
  for (final skill in pool.take(big ? 2 + rng.nextInt(2) : 1)) {
    final a = pick(skill);
    final item = a.outputs.keys.first;
    // Normales, de 20 a 40 minutos de trabajo; los grandes, de 40 a 80 por
    // cosa.
    final minutes = big ? 40 + rng.nextInt(9) * 5 : 20 + rng.nextInt(5) * 5;
    final n = (minutes * 60 / hEffort(item)).round().clamp(1, 500);
    wants[item] = n;
    seconds += n * hEffort(item);
    xpSkill ??= skill;
    if (skill == xpSkill) xp += (a.xp / a.outputs[item]! * n * .5).round();
  }
  // Sin nada que hacer todavía (no pasa: la tala empieza en el nivel 0).
  if (wants.isEmpty) wants['log_sugi'] = 100;
  if (big && rng.nextInt(2) == 0) wants[hParcel] = 1;
  final value = wants.entries.fold(
    0,
    (sum, e) => sum + (e.key == hParcel ? 0 : sellValue(e.key) * e.value),
  );
  // Siempre más que vender lo pedido, y al menos lo que daría ese rato en
  // el mejor trabajo.
  final money = max(
    10,
    (max(value, seconds * rate) *
            ((big ? 2.2 : 1.6) + rng.nextInt(5) * .1) *
            (1 + max(0, board - 1) * hBoardPay))
        .round(),
  );
  // De regalo, algo raro de los sitios a los que ya se llega.
  final rares = {
    for (final z in hZones)
      if (z.level <= expeditionLevel)
        for (final l in z.loot)
          if (l.chance < .5) l.item,
  }.toList();
  final bonus = big ? 3 : rng.nextInt(3);
  final gift = (bonus & 2) != 0 && rares.isNotEmpty
      ? rares[rng.nextInt(rares.length)]
      : null;
  // Se echa a suertes lo último, para no cambiar lo de antes.
  final plan = !big && plans.isNotEmpty && rng.nextInt(4) == 0
      ? plans[rng.nextInt(plans.length)]
      : null;
  return HOrder(
    wants: wants,
    money: money,
    plan: plan,
    skill: (bonus & 1) != 0 ? xpSkill : null,
    xp: (bonus & 1) != 0 ? max(1, xp) : 0,
    gift: gift,
    giftN: gift == null ? 0 : 1 + rng.nextInt(big ? 3 : 2),
    big: big,
  );
}
