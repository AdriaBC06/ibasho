// Ibasho — Hatarakitama: el pueblo (edificios, tienda del día y lonja).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'hataraki_data.dart';

/// Los edificios del pueblo. Cada uno va del nivel 0 (sin hacer) al 5.
enum HBuilding {
  // El tablón va primero: viene hecho y es lo que más se visita.
  board,
  workshop,
  kiln,
  dock,
  greenhouse,
  library,
  tower,
  inn,
  shop,
  market;

  static HBuilding? byName(Object? raw) {
    for (final b in values) {
      if (b.name == raw) return b;
    }
    return null;
  }
}

const int hTownMaxLevel = 5;

/// Lo que pide subir un edificio a un nivel: ginmon, piezas y nivel de
/// construcción.
class HBuildCost {
  const HBuildCost(this.money, this.items, this.construction);
  final int money;
  final Map<String, int> items;
  final int construction;
}

/// Las piezas y el nivel de construcción de cada nivel (del 1 al 5), igual
/// para todos los edificios; los ginmon van por edificio.
const List<(int, int, Map<String, int>)> _tiers = [
  (0, 800, {'build_beam': 6}),
  (20, 6000, {'build_beam': 10, 'build_frame': 4}),
  (40, 30000, {'build_wall': 10, 'build_roof': 6}),
  (60, 120000, {'build_roof': 10, 'build_shoji': 8}),
  (90, 400000, {'build_pillar': 10, 'build_ornament': 2}),
];

/// Lo que cada edificio pide además de las piezas, del nivel 2 en adelante,
/// y cuánto cuesta en ginmon respecto a los demás.
const Map<HBuilding, (String, double)> _flavour = {
  HBuilding.workshop: ('bar_bronze', 1.5),
  HBuilding.kiln: ('pot_brick', 1),
  HBuilding.dock: ('plank_sugi', 1),
  HBuilding.greenhouse: ('pot_planter', 1),
  HBuilding.library: ('book_notes', 1.2),
  HBuilding.tower: ('gem_quartz', 1.5),
  HBuilding.inn: ('cloth_cotton', 1.5),
  HBuilding.shop: ('cloth_cotton', .6),
  HBuilding.market: ('pot_bowl', 1.2),
  HBuilding.board: ('paper', .8),
};

const List<int> _flavourCount = [0, 4, 10, 20, 40];

/// Lo que cuesta subir [b] al nivel [level] (1–5).
HBuildCost hBuildCost(HBuilding b, int level) {
  final (construction, money, items) = _tiers[level - 1];
  final (extra, mult) = _flavour[b]!;
  final n = _flavourCount[level - 1];
  return HBuildCost((money * mult).round(), {
    ...items,
    if (n > 0) extra: n,
  }, construction);
}

// --- Lo que da cada edificio ---------------------------------------------------

/// Los oficios que transforman cosas (los acelera el taller).
const Set<HSkill> hCraftSkills = {
  HSkill.cooking,
  HSkill.carpentry,
  HSkill.smithing,
  HSkill.tailoring,
  HSkill.tea,
  HSkill.jewelry,
  HSkill.pottery,
  HSkill.dyeing,
  HSkill.construction,
  HSkill.writing,
  HSkill.brewing,
  HSkill.magic,
};

/// Velocidad de más por nivel: el taller en todo lo que transforma, y el
/// horno, el muelle, el invernadero y la torre en su oficio.
const double hWorkshopSpeed = .04;
const double hBuildingSpeed = .05;

/// El edificio que acelera un oficio en concreto.
const Map<HSkill, HBuilding> hSkillBuilding = {
  HSkill.pottery: HBuilding.kiln,
  HSkill.fishing: HBuilding.dock,
  HSkill.farming: HBuilding.greenhouse,
  HSkill.magic: HBuilding.tower,
};

/// Velocidad de más en [skill] con el pueblo [town] (0,2 = un 20 %).
double hTownSpeed(HSkill skill, Map<HBuilding, int> town) {
  var bonus = 0.0;
  if (hCraftSkills.contains(skill)) {
    bonus += (town[HBuilding.workshop] ?? 0) * hWorkshopSpeed;
  }
  final own = hSkillBuilding[skill];
  if (own != null) bonus += (town[own] ?? 0) * hBuildingSpeed;
  return bonus;
}

/// Hollín de más por nivel de horno (sobre el 50 % de siempre).
const double hKilnSoot = .1;

/// Experiencia de estudio de más por nivel de biblioteca.
const double hLibraryStudy = .1;

/// Comida de viaje de menos por nivel de posada.
const double hInnFood = .08;

/// Nivel de posada con el que caben cuatro Tamas en un viaje.
const int hInnFourth = 3;

/// Las tareas que piden un edificio: los libros y mapas buenos, la
/// biblioteca; las runas fuertes, la torre.
const Map<String, (HBuilding, int)> hActionGates = {
  'wr_map_trail': (HBuilding.library, 1),
  'wr_tome': (HBuilding.library, 2),
  'wr_map_chart': (HBuilding.library, 2),
  'wr_arcane': (HBuilding.library, 3),
  'wr_map_star': (HBuilding.library, 4),
  'ma_compass': (HBuilding.tower, 1),
  'ma_fortune': (HBuilding.tower, 2),
  'ma_titan': (HBuilding.tower, 3),
  'ma_star': (HBuilding.tower, 4),
};

// --- Azar del día ---------------------------------------------------------------

/// Azar que sale igual en todos los aparatos (también en la web): un
/// generador de Lehmer con números que caben en un double.
class HDayRng {
  HDayRng(int day, int salt)
    : _x = ((day * 7919 + salt * 104729) % 2147483646).abs() + 1;
  int _x;

  int _next() => _x = _x * 48271 % 2147483647;

  /// Un número entre 0 (incluido) y [n] (sin incluir).
  int nextInt(int n) => _next() % n;

  /// Entre 0 y 1.
  double nextDouble() => (_next() - 1) / 2147483646;

  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }
}

// --- La tienda del día ----------------------------------------------------------

/// Se compra a cuatro veces lo que se vende: no sale a cuenta revender.
const int hShopMarkup = 4;

/// Lo que puede salir en la tienda: semillas, cebos, abonos, mechas, tés
/// sencillos y materiales de los primeros niveles.
final List<String> hShopPool = [
  for (final i in hItems)
    if (i.kind == HItemKind.seed || i.kind == HItemKind.boost) i.id,
  'tea_tanpopo',
  'tea_sencha',
  'tea_genmai',
  'tea_yuzu',
  'log_sugi',
  'log_matsu',
  'log_take',
  'fish_iwashi',
  'fish_aji',
  'ore_copper',
  'ore_tin',
  'ore_iron',
  'clay',
  'soot',
  'water_spring',
  'wild_tanpopo',
  'wild_yomogi',
  'crop_rice',
  'crop_cotton',
  'plank_sugi',
  'paper',
  'pot_flask',
  'gem_quartz',
  // Los muebles que no se fabrican: solo salen aquí.
  for (final i in hItems)
    if (i.kind == HItemKind.furniture &&
        !hActions.any((a) => a.outputs.containsKey(i.id)))
      i.id,
];

/// Una cosa a la venta: a cuánto y cuántas hay en el día. Con [plan], lo
/// que se vende es el plano del mueble [item], no el mueble.
class HOffer {
  const HOffer(this.item, this.price, this.stock, {this.plan = false});
  final String item;
  final int price;
  final int stock;
  final bool plan;
}

/// Cosas a la venta con la tienda a nivel [level]: 4 con el 1 y una más por
/// nivel.
int hShopSlots(int level) => level <= 0 ? 0 : 3 + level;

/// La tienda del día [day] (el mismo para todos), con [sellValue] como
/// precio de venta de cada cosa.
List<HOffer> hShop(int day, int level, int Function(String) sellValue) {
  final pool = [...hShopPool];
  HDayRng(day, 1).shuffle(pool);
  return [
    for (final id in pool.take(hShopSlots(level)))
      HOffer(
        id,
        sellValue(id) * hShopMarkup,
        // Lo barato viene a montones; lo caro, en pocas unidades.
        (400 / (sellValue(id) * hShopMarkup)).round().clamp(3, 50),
      ),
  ];
}

// --- La lonja -------------------------------------------------------------------

/// Un cambio de precio del día: en todo lo de un oficio o en una cosa.
class HMarketMove {
  const HMarketMove({this.skill, this.item, required this.pct});
  final HSkill? skill;
  final String? item;

  /// +0,5 = se paga un 50 % más; −0,3 = un 30 % menos.
  final double pct;

  bool covers(String id) =>
      item == id || (skill != null && hItemSkill(id) == skill);
}

/// Nivel de lonja con el que se ve la de mañana.
const int hMarketTomorrow = 3;

/// Cuántas cosas suben cada día.
const int hMarketUps = 6;

/// Los oficios de los que sale algo que se vende.
final List<HSkill> _marketSkills = [
  for (final s in HSkill.values)
    if (s != HSkill.agility && s != HSkill.study) s,
];

/// Lo que se mueve en la lonja el día [day], igual para todos y haya lonja o
/// no: primero lo que sube y luego lo que baja.
List<HMarketMove> hMarket(int day) {
  final rng = HDayRng(day, 2);
  final skills = [..._marketSkills];
  rng.shuffle(skills);
  final items = [
    for (final i in hItems)
      if (i.id != 'parcel') i.id,
  ];
  rng.shuffle(items);
  // Lo que sube: oficio, cosa, cosa, oficio, cosa, cosa.
  final ups = <HMarketMove>[];
  var si = 0, ii = 0;
  for (var k = 0; k < hMarketUps; k++) {
    if (k % 3 == 0) {
      ups.add(
        HMarketMove(skill: skills[si++], pct: .25 + rng.nextInt(8) * .05),
      );
    } else {
      ups.add(HMarketMove(item: items[ii++], pct: .5 + rng.nextInt(11) * .05));
    }
  }
  // Lo que baja: dos oficios que no suben.
  final downs = [
    for (var k = 0; k < 2; k++)
      HMarketMove(skill: skills[si++], pct: -(.2 + rng.nextInt(7) * .05)),
  ];
  return [...ups, ...downs];
}

/// Cuántas de las cosas que suben enseña la lonja a nivel [level].
int hMarketUpsSeen(int level) => level <= 0 ? 0 : min(level + 1, hMarketUps);

/// Lo que la lonja a nivel [level] enseña de [moves]: lo que baja y las
/// primeras [hMarketUpsSeen] cosas que suben. Sin lonja, nada.
List<HMarketMove> hMarketSeen(List<HMarketMove> moves, int level) {
  if (level <= 0) return const [];
  final ups = moves.where((m) => m.pct > 0).take(hMarketUpsSeen(level));
  return [...ups, ...moves.where((m) => m.pct < 0)];
}

/// Por cuánto se multiplica hoy lo que vale [id] en la lonja.
double hMarketFactor(String id, List<HMarketMove> moves) {
  var f = 1.0;
  for (final m in moves) {
    if (m.covers(id)) f *= 1 + m.pct;
  }
  return f;
}

final Map<String, HSkill> _itemSkill = {};

/// El oficio del que sale [id]: el de la tarea que lo hace, o el de la que
/// lo suelta; lo que solo se trae de viaje, expediciones.
HSkill hItemSkill(String id) => _itemSkill[id] ??= () {
  for (final a in hActions) {
    if (a.outputs.containsKey(id)) return a.skill;
  }
  for (final a in hActions) {
    if (a.drops.any((d) => d.item == id)) return a.skill;
  }
  return HSkill.expedition;
}();

/// El precio al que sale [base] tras la lonja: siempre al menos 1.
int hMarketPrice(int base, double factor) => max(1, (base * factor).round());
