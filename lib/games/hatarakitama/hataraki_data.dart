// Ibasho — Hatarakitama: los datos del juego (skills, objetos, acciones).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import '../../backend/tama.dart' show TamaPersonality;

/// Los oficios. Los seis primeros sacan cosas del mundo (agilidad solo da
/// experiencia y velocidad), los seis siguientes las transforman, y las
/// expediciones van aparte: se sube mandando grupos de Tamas de viaje.
enum HSkill {
  woodcutting,
  fishing,
  mining,
  farming,
  foraging,
  agility,
  cooking,
  carpentry,
  smithing,
  tailoring,
  tea,
  jewelry,
  expedition;

  static HSkill? byName(Object? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  /// Los que se hacen desde una ranura de trabajo.
  static List<HSkill> get workable =>
      values.where((s) => s != HSkill.expedition).toList();
}

/// Qué clase de cosa es un objeto del almacén.
enum HItemKind { material, seed, gem, food, tea, gear }

/// Dónde se lleva una pieza de equipo en las expediciones.
enum HGearSlot { tool, outfit, bag, charm }

class HItem {
  const HItem(
    this.id,
    this.kind, {
    this.food = 0,
    this.slot,
    this.power = 0,
    this.teaSkill,
    this.teaBoost = 0,
  });

  final String id;
  final HItemKind kind;

  /// Lo que alimenta en una expedición (comida).
  final int food;

  /// Equipo: hueco y fuerza que suma al grupo.
  final HGearSlot? slot;
  final int power;

  /// Té: oficio que acelera (null = todos) y cuánto (0,10 = un 10 %).
  final HSkill? teaSkill;
  final double teaBoost;
}

/// Lo que puede caer además del producto: (objeto, probabilidad).
class HDrop {
  const HDrop(this.item, this.chance);
  final String item;
  final double chance;
}

class HAction {
  const HAction(
    this.id,
    this.skill,
    this.level,
    this.seconds,
    this.xp, {
    this.inputs = const {},
    this.outputs = const {},
    this.drops = const [],
  });

  final String id;
  final HSkill skill;

  /// Nivel del oficio que pide.
  final int level;

  /// Lo que tarda una vez, antes de bonos.
  final double seconds;
  final int xp;
  final Map<String, int> inputs;
  final Map<String, int> outputs;
  final List<HDrop> drops;
}

/// Un sitio al que ir de expedición.
class HZone {
  const HZone(
    this.id,
    this.level,
    this.minutes,
    this.difficulty,
    this.xp,
    this.loot, {
    this.prizeChance = 0,
  });

  final String id;

  /// Nivel de expediciones que pide.
  final int level;
  final int minutes;

  /// Fuerza con la que se vuelve seguro con todo el botín.
  final int difficulty;
  final int xp;

  /// Botín: cada entrada cae con su probabilidad, (min–max) unidades.
  final List<HLoot> loot;

  /// Probabilidad de traer un premio del gacha (gorro, accesorio…).
  final double prizeChance;
}

class HLoot {
  const HLoot(this.item, this.chance, this.min, this.max);
  final String item;
  final double chance;
  final int min;
  final int max;
}

const _m = HItemKind.material;

/// Todo lo que puede haber en el almacén.
const List<HItem> hItems = [
  // Madera.
  HItem('log_sugi', _m), HItem('log_matsu', _m), HItem('log_take', _m),
  HItem('log_kaede', _m), HItem('log_sakura', _m), HItem('log_ichou', _m),
  HItem('log_kusu', _m), HItem('log_shinboku', _m),
  // Pescado.
  HItem('fish_iwashi', _m), HItem('fish_aji', _m), HItem('fish_saba', _m),
  HItem('fish_tai', _m), HItem('fish_sake', _m), HItem('fish_unagi', _m),
  HItem('fish_maguro', _m), HItem('fish_kinkoi', _m),
  // Minerales y lingotes.
  HItem('ore_copper', _m), HItem('ore_tin', _m), HItem('ore_iron', _m),
  HItem('ore_silver', _m), HItem('ore_gold', _m), HItem('ore_jade', _m),
  HItem('ore_moon', _m), HItem('ore_star', _m),
  HItem('bar_bronze', _m), HItem('bar_iron', _m), HItem('bar_silver', _m),
  HItem('bar_gold', _m), HItem('bar_star', _m),
  // Gemas (caen minando).
  HItem('gem_quartz', HItemKind.gem), HItem('gem_amethyst', HItemKind.gem),
  HItem('gem_sapphire', HItemKind.gem), HItem('gem_ruby', HItemKind.gem),
  HItem('gem_pearl', HItemKind.gem),
  // Semillas (caen recolectando) y cosechas.
  HItem('seed_rice', HItemKind.seed), HItem('seed_daikon', HItemKind.seed),
  HItem('seed_cotton', HItemKind.seed), HItem('seed_soy', HItemKind.seed),
  HItem('seed_tea', HItemKind.seed), HItem('seed_ichigo', HItemKind.seed),
  HItem('seed_imo', HItemKind.seed), HItem('seed_momo', HItemKind.seed),
  HItem('crop_rice', _m), HItem('crop_daikon', _m), HItem('crop_cotton', _m),
  HItem('crop_soy', _m), HItem('crop_tea', _m), HItem('crop_ichigo', _m),
  HItem('crop_imo', _m), HItem('crop_momo', _m),
  // Recolecta.
  HItem('wild_tanpopo', _m), HItem('wild_shiitake', _m),
  HItem('wild_takenoko', _m), HItem('wild_kuri', _m), HItem('wild_yuzu', _m),
  HItem('wild_matsutake', _m), HItem('wild_hasu', _m),
  HItem('wild_kinmokusei', _m),
  // Intermedios.
  HItem('plank_sugi', _m), HItem('plank_kaede', _m), HItem('plank_sakura', _m),
  HItem('cloth_cotton', _m), HItem('cloth_silk', _m),
  // Tesoros de expedición.
  HItem('rare_feather', _m), HItem('rare_shell', _m), HItem('rare_amber', _m),
  HItem('rare_ember', _m), HItem('rare_cloud', _m), HItem('rare_moondust', _m),
  HItem('silk_thread', _m),
  // Comida.
  HItem('food_onigiri', HItemKind.food, food: 2),
  HItem('food_iwashi', HItemKind.food, food: 2),
  HItem('food_miso', HItemKind.food, food: 4),
  HItem('food_aji', HItemKind.food, food: 5),
  HItem('food_saba', HItemKind.food, food: 7),
  HItem('food_taimeshi', HItemKind.food, food: 10),
  HItem('food_yakiimo', HItemKind.food, food: 12),
  HItem('food_unadon', HItemKind.food, food: 16),
  HItem('food_sushi', HItemKind.food, food: 22),
  HItem('food_feast', HItemKind.food, food: 32),
  // Tés: aceleran un oficio (o todos) durante un rato.
  HItem('tea_tanpopo', HItemKind.tea, teaSkill: HSkill.foraging, teaBoost: .1),
  HItem('tea_sencha', HItemKind.tea, teaBoost: .05),
  HItem('tea_genmai', HItemKind.tea, teaSkill: HSkill.farming, teaBoost: .15),
  HItem('tea_yuzu', HItemKind.tea, teaSkill: HSkill.fishing, teaBoost: .15),
  HItem('tea_hoji', HItemKind.tea, teaSkill: HSkill.woodcutting, teaBoost: .15),
  HItem('tea_matcha', HItemKind.tea, teaBoost: .1),
  HItem('tea_hasu', HItemKind.tea, teaSkill: HSkill.mining, teaBoost: .2),
  HItem('tea_kinmoku', HItemKind.tea, teaBoost: .15),
  // Equipo de expedición.
  HItem('gear_bronze_pick', HItemKind.gear, slot: HGearSlot.tool, power: 4),
  HItem('gear_iron_pick', HItemKind.gear, slot: HGearSlot.tool, power: 10),
  HItem('gear_silver_pick', HItemKind.gear, slot: HGearSlot.tool, power: 18),
  HItem('gear_gold_pick', HItemKind.gear, slot: HGearSlot.tool, power: 28),
  HItem('gear_star_pick', HItemKind.gear, slot: HGearSlot.tool, power: 42),
  HItem('gear_scarf', HItemKind.gear, slot: HGearSlot.outfit, power: 3),
  HItem('gear_happi', HItemKind.gear, slot: HGearSlot.outfit, power: 9),
  HItem('gear_cloak', HItemKind.gear, slot: HGearSlot.outfit, power: 17),
  HItem('gear_kimono', HItemKind.gear, slot: HGearSlot.outfit, power: 30),
  HItem('gear_cloudrobe', HItemKind.gear, slot: HGearSlot.outfit, power: 44),
  HItem('gear_basket', HItemKind.gear, slot: HGearSlot.bag, power: 3),
  HItem('gear_backpack', HItemKind.gear, slot: HGearSlot.bag, power: 9),
  HItem('gear_chest', HItemKind.gear, slot: HGearSlot.bag, power: 18),
  HItem('gear_sakurabox', HItemKind.gear, slot: HGearSlot.bag, power: 30),
  HItem('gear_shrine', HItemKind.gear, slot: HGearSlot.bag, power: 44),
  HItem('gear_quartz_charm', HItemKind.gear, slot: HGearSlot.charm, power: 4),
  HItem('gear_amethyst_ring', HItemKind.gear, slot: HGearSlot.charm, power: 10),
  HItem(
    'gear_sapphire_charm',
    HItemKind.gear,
    slot: HGearSlot.charm,
    power: 18,
  ),
  HItem('gear_ruby_ring', HItemKind.gear, slot: HGearSlot.charm, power: 28),
  HItem('gear_pearl_crown', HItemKind.gear, slot: HGearSlot.charm, power: 42),
];

final Map<String, HItem> hItemById = {for (final i in hItems) i.id: i};

HItem? hItem(String id) => hItemById[id];

const _wc = HSkill.woodcutting;
const _fi = HSkill.fishing;
const _mi = HSkill.mining;
const _fa = HSkill.farming;
const _fo = HSkill.foraging;
const _ag = HSkill.agility;
const _co = HSkill.cooking;
const _ca = HSkill.carpentry;
const _sm = HSkill.smithing;
const _ta = HSkill.tailoring;
const _te = HSkill.tea;
const _je = HSkill.jewelry;

const _gems = [
  HDrop('gem_quartz', .02),
  HDrop('gem_amethyst', .008),
  HDrop('gem_sapphire', .004),
  HDrop('gem_ruby', .002),
];

/// Todas las acciones, por oficio y nivel.
const List<HAction> hActions = [
  // Tala.
  HAction('wc_sugi', _wc, 0, 3, 10, outputs: {'log_sugi': 1}),
  HAction('wc_matsu', _wc, 10, 4, 25, outputs: {'log_matsu': 1}),
  HAction('wc_take', _wc, 20, 4.5, 38, outputs: {'log_take': 1}),
  HAction('wc_kaede', _wc, 35, 5, 60, outputs: {'log_kaede': 1}),
  HAction('wc_sakura', _wc, 50, 6, 95, outputs: {'log_sakura': 1}),
  HAction('wc_ichou', _wc, 65, 7, 140, outputs: {'log_ichou': 1}),
  HAction('wc_kusu', _wc, 80, 8, 200, outputs: {'log_kusu': 1}),
  HAction('wc_shinboku', _wc, 95, 10, 300, outputs: {'log_shinboku': 1}),
  // Pesca.
  HAction('fi_iwashi', _fi, 0, 3.5, 10, outputs: {'fish_iwashi': 1}),
  HAction('fi_aji', _fi, 10, 4, 24, outputs: {'fish_aji': 1}),
  HAction('fi_saba', _fi, 20, 5, 40, outputs: {'fish_saba': 1}),
  HAction('fi_tai', _fi, 35, 6, 65, outputs: {'fish_tai': 1}),
  HAction('fi_sake', _fi, 50, 6.5, 95, outputs: {'fish_sake': 1}),
  HAction(
    'fi_unagi',
    _fi,
    65,
    7.5,
    140,
    outputs: {'fish_unagi': 1},
    drops: [HDrop('gem_pearl', .002)],
  ),
  HAction(
    'fi_maguro',
    _fi,
    80,
    9,
    210,
    outputs: {'fish_maguro': 1},
    drops: [HDrop('gem_pearl', .004)],
  ),
  HAction(
    'fi_kinkoi',
    _fi,
    95,
    11,
    320,
    outputs: {'fish_kinkoi': 1},
    drops: [HDrop('gem_pearl', .008)],
  ),
  // Minería.
  HAction('mi_copper', _mi, 0, 3, 9, outputs: {'ore_copper': 1}, drops: _gems),
  HAction('mi_tin', _mi, 5, 3, 12, outputs: {'ore_tin': 1}, drops: _gems),
  HAction('mi_iron', _mi, 15, 4, 28, outputs: {'ore_iron': 1}, drops: _gems),
  HAction(
    'mi_silver',
    _mi,
    30,
    5,
    50,
    outputs: {'ore_silver': 1},
    drops: _gems,
  ),
  HAction('mi_gold', _mi, 45, 6, 80, outputs: {'ore_gold': 1}, drops: _gems),
  HAction('mi_jade', _mi, 60, 7, 120, outputs: {'ore_jade': 1}, drops: _gems),
  HAction('mi_moon', _mi, 75, 8, 175, outputs: {'ore_moon': 1}, drops: _gems),
  HAction('mi_star', _mi, 90, 10, 260, outputs: {'ore_star': 1}, drops: _gems),
  // Huerto: una semilla da varias cosechas y a veces se recupera.
  HAction(
    'fa_rice',
    _fa,
    0,
    12,
    30,
    inputs: {'seed_rice': 1},
    outputs: {'crop_rice': 4},
    drops: [HDrop('seed_rice', .5)],
  ),
  HAction(
    'fa_daikon',
    _fa,
    10,
    14,
    55,
    inputs: {'seed_daikon': 1},
    outputs: {'crop_daikon': 3},
    drops: [HDrop('seed_daikon', .4)],
  ),
  HAction(
    'fa_cotton',
    _fa,
    20,
    16,
    80,
    inputs: {'seed_cotton': 1},
    outputs: {'crop_cotton': 4},
    drops: [HDrop('seed_cotton', .4)],
  ),
  HAction(
    'fa_soy',
    _fa,
    28,
    16,
    100,
    inputs: {'seed_soy': 1},
    outputs: {'crop_soy': 4},
    drops: [HDrop('seed_soy', .4)],
  ),
  HAction(
    'fa_tea',
    _fa,
    35,
    18,
    130,
    inputs: {'seed_tea': 1},
    outputs: {'crop_tea': 4},
    drops: [HDrop('seed_tea', .35)],
  ),
  HAction(
    'fa_ichigo',
    _fa,
    45,
    20,
    170,
    inputs: {'seed_ichigo': 1},
    outputs: {'crop_ichigo': 3},
    drops: [HDrop('seed_ichigo', .35)],
  ),
  HAction(
    'fa_imo',
    _fa,
    60,
    22,
    230,
    inputs: {'seed_imo': 1},
    outputs: {'crop_imo': 3},
    drops: [HDrop('seed_imo', .3)],
  ),
  HAction(
    'fa_momo',
    _fa,
    80,
    26,
    330,
    inputs: {'seed_momo': 1},
    outputs: {'crop_momo': 3},
    drops: [HDrop('seed_momo', .3)],
  ),
  // Recolecta: de aquí salen las semillas.
  HAction(
    'fo_tanpopo',
    _fo,
    0,
    3,
    9,
    outputs: {'wild_tanpopo': 1},
    drops: [HDrop('seed_rice', .5), HDrop('seed_daikon', .15)],
  ),
  HAction(
    'fo_shiitake',
    _fo,
    10,
    4,
    22,
    outputs: {'wild_shiitake': 1},
    drops: [HDrop('seed_cotton', .3), HDrop('seed_soy', .2)],
  ),
  HAction(
    'fo_takenoko',
    _fo,
    20,
    4.5,
    36,
    outputs: {'wild_takenoko': 1},
    drops: [HDrop('seed_soy', .2), HDrop('seed_tea', .25)],
  ),
  HAction(
    'fo_kuri',
    _fo,
    35,
    5,
    58,
    outputs: {'wild_kuri': 1},
    drops: [HDrop('seed_tea', .2), HDrop('seed_ichigo', .2)],
  ),
  HAction(
    'fo_yuzu',
    _fo,
    50,
    6,
    90,
    outputs: {'wild_yuzu': 1},
    drops: [HDrop('seed_ichigo', .2), HDrop('seed_imo', .2)],
  ),
  HAction(
    'fo_matsutake',
    _fo,
    65,
    7,
    135,
    outputs: {'wild_matsutake': 1},
    drops: [HDrop('seed_imo', .2), HDrop('seed_momo', .1)],
  ),
  HAction(
    'fo_hasu',
    _fo,
    80,
    8,
    195,
    outputs: {'wild_hasu': 1},
    drops: [HDrop('seed_momo', .15)],
  ),
  HAction(
    'fo_kinmokusei',
    _fo,
    95,
    10,
    290,
    outputs: {'wild_kinmokusei': 1},
    drops: [HDrop('seed_momo', .25)],
  ),
  // Agilidad: solo experiencia; cada nivel acelera un poco todo.
  HAction('ag_path', _ag, 0, 6, 16),
  HAction('ag_stones', _ag, 10, 7, 32),
  HAction('ag_bridge', _ag, 25, 8, 60),
  HAction('ag_roofs', _ag, 40, 9, 95),
  HAction('ag_falls', _ag, 55, 10, 140),
  HAction('ag_bamboo', _ag, 70, 11, 195),
  HAction('ag_clouds', _ag, 85, 12, 270),
  // Cocina.
  HAction(
    'co_onigiri',
    _co,
    0,
    3,
    8,
    inputs: {'crop_rice': 1},
    outputs: {'food_onigiri': 1},
  ),
  HAction(
    'co_iwashi',
    _co,
    5,
    3,
    12,
    inputs: {'fish_iwashi': 1},
    outputs: {'food_iwashi': 1},
  ),
  HAction(
    'co_miso',
    _co,
    15,
    4,
    26,
    inputs: {'crop_soy': 1, 'crop_daikon': 1},
    outputs: {'food_miso': 1},
  ),
  HAction(
    'co_aji',
    _co,
    20,
    4,
    32,
    inputs: {'fish_aji': 1},
    outputs: {'food_aji': 1},
  ),
  HAction(
    'co_saba',
    _co,
    30,
    4.5,
    50,
    inputs: {'fish_saba': 1},
    outputs: {'food_saba': 1},
  ),
  HAction(
    'co_taimeshi',
    _co,
    40,
    5,
    75,
    inputs: {'fish_tai': 1, 'crop_rice': 1},
    outputs: {'food_taimeshi': 1},
  ),
  HAction(
    'co_yakiimo',
    _co,
    55,
    5,
    100,
    inputs: {'crop_imo': 1, 'log_sugi': 1},
    outputs: {'food_yakiimo': 1},
  ),
  HAction(
    'co_unadon',
    _co,
    65,
    6,
    140,
    inputs: {'fish_unagi': 1, 'crop_rice': 1},
    outputs: {'food_unadon': 1},
  ),
  HAction(
    'co_sushi',
    _co,
    80,
    6.5,
    200,
    inputs: {'fish_maguro': 1, 'crop_rice': 2},
    outputs: {'food_sushi': 1},
  ),
  HAction(
    'co_feast',
    _co,
    95,
    8,
    320,
    inputs: {'fish_kinkoi': 1, 'crop_momo': 1, 'food_sushi': 1},
    outputs: {'food_feast': 1},
  ),
  // Carpintería.
  HAction(
    'ca_plank_sugi',
    _ca,
    0,
    3,
    10,
    inputs: {'log_sugi': 2},
    outputs: {'plank_sugi': 1},
  ),
  HAction(
    'ca_basket',
    _ca,
    8,
    5,
    30,
    inputs: {'log_take': 2},
    outputs: {'gear_basket': 1},
  ),
  HAction(
    'ca_plank_kaede',
    _ca,
    30,
    4,
    55,
    inputs: {'log_kaede': 2},
    outputs: {'plank_kaede': 1},
  ),
  HAction(
    'ca_backpack',
    _ca,
    35,
    6,
    110,
    inputs: {'plank_sugi': 4, 'cloth_cotton': 2},
    outputs: {'gear_backpack': 1},
  ),
  HAction(
    'ca_plank_sakura',
    _ca,
    50,
    5,
    100,
    inputs: {'log_sakura': 2},
    outputs: {'plank_sakura': 1},
  ),
  HAction(
    'ca_chest',
    _ca,
    60,
    8,
    260,
    inputs: {'plank_kaede': 6, 'bar_iron': 2},
    outputs: {'gear_chest': 1},
  ),
  HAction(
    'ca_sakurabox',
    _ca,
    80,
    10,
    520,
    inputs: {'plank_sakura': 6, 'log_ichou': 4, 'bar_gold': 2},
    outputs: {'gear_sakurabox': 1},
  ),
  HAction(
    'ca_shrine',
    _ca,
    95,
    12,
    700,
    inputs: {'log_shinboku': 3, 'log_kusu': 3, 'plank_sakura': 2},
    outputs: {'gear_shrine': 1},
  ),
  // Forja.
  HAction(
    'sm_bronze',
    _sm,
    0,
    3,
    10,
    inputs: {'ore_copper': 1, 'ore_tin': 1},
    outputs: {'bar_bronze': 1},
  ),
  HAction(
    'sm_bronze_pick',
    _sm,
    5,
    5,
    40,
    inputs: {'bar_bronze': 3},
    outputs: {'gear_bronze_pick': 1},
  ),
  HAction(
    'sm_iron',
    _sm,
    15,
    4,
    26,
    inputs: {'ore_iron': 2},
    outputs: {'bar_iron': 1},
  ),
  HAction(
    'sm_iron_pick',
    _sm,
    25,
    6,
    120,
    inputs: {'bar_iron': 3, 'plank_sugi': 1},
    outputs: {'gear_iron_pick': 1},
  ),
  HAction(
    'sm_silver',
    _sm,
    35,
    5,
    60,
    inputs: {'ore_silver': 2},
    outputs: {'bar_silver': 1},
  ),
  HAction(
    'sm_silver_pick',
    _sm,
    45,
    7,
    230,
    inputs: {'bar_silver': 3, 'plank_kaede': 1},
    outputs: {'gear_silver_pick': 1},
  ),
  HAction(
    'sm_gold',
    _sm,
    55,
    6,
    100,
    inputs: {'ore_gold': 2},
    outputs: {'bar_gold': 1},
  ),
  HAction(
    'sm_gold_pick',
    _sm,
    65,
    8,
    380,
    inputs: {'bar_gold': 3, 'plank_sakura': 1},
    outputs: {'gear_gold_pick': 1},
  ),
  HAction(
    'sm_star',
    _sm,
    85,
    8,
    220,
    inputs: {'ore_star': 2, 'ore_moon': 1},
    outputs: {'bar_star': 1},
  ),
  HAction(
    'sm_star_pick',
    _sm,
    92,
    10,
    700,
    inputs: {'bar_star': 3, 'rare_ember': 1},
    outputs: {'gear_star_pick': 1},
  ),
  // Costura.
  HAction(
    'ta_cloth',
    _ta,
    0,
    3,
    10,
    inputs: {'crop_cotton': 2},
    outputs: {'cloth_cotton': 1},
  ),
  HAction(
    'ta_scarf',
    _ta,
    5,
    5,
    35,
    inputs: {'cloth_cotton': 2},
    outputs: {'gear_scarf': 1},
  ),
  HAction(
    'ta_happi',
    _ta,
    25,
    6,
    110,
    inputs: {'cloth_cotton': 5},
    outputs: {'gear_happi': 1},
  ),
  HAction(
    'ta_silk',
    _ta,
    40,
    5,
    80,
    inputs: {'silk_thread': 2},
    outputs: {'cloth_silk': 1},
  ),
  HAction(
    'ta_cloak',
    _ta,
    45,
    7,
    240,
    inputs: {'cloth_cotton': 6, 'rare_feather': 2},
    outputs: {'gear_cloak': 1},
  ),
  HAction(
    'ta_kimono',
    _ta,
    65,
    9,
    420,
    inputs: {'cloth_silk': 5, 'crop_ichigo': 3},
    outputs: {'gear_kimono': 1},
  ),
  HAction(
    'ta_cloudrobe',
    _ta,
    90,
    11,
    760,
    inputs: {'cloth_silk': 6, 'rare_cloud': 3},
    outputs: {'gear_cloudrobe': 1},
  ),
  // Té.
  HAction(
    'te_tanpopo',
    _te,
    0,
    4,
    12,
    inputs: {'wild_tanpopo': 2},
    outputs: {'tea_tanpopo': 1},
  ),
  HAction(
    'te_sencha',
    _te,
    12,
    5,
    30,
    inputs: {'crop_tea': 2},
    outputs: {'tea_sencha': 1},
  ),
  HAction(
    'te_genmai',
    _te,
    22,
    5,
    45,
    inputs: {'crop_tea': 1, 'crop_rice': 1},
    outputs: {'tea_genmai': 1},
  ),
  HAction(
    'te_yuzu',
    _te,
    35,
    6,
    70,
    inputs: {'crop_tea': 1, 'wild_yuzu': 1},
    outputs: {'tea_yuzu': 1},
  ),
  HAction(
    'te_hoji',
    _te,
    45,
    6,
    95,
    inputs: {'crop_tea': 2, 'wild_kuri': 1},
    outputs: {'tea_hoji': 1},
  ),
  HAction(
    'te_matcha',
    _te,
    60,
    7,
    140,
    inputs: {'crop_tea': 3, 'wild_takenoko': 1},
    outputs: {'tea_matcha': 1},
  ),
  HAction(
    'te_hasu',
    _te,
    75,
    8,
    200,
    inputs: {'crop_tea': 2, 'wild_hasu': 1},
    outputs: {'tea_hasu': 1},
  ),
  HAction(
    'te_kinmoku',
    _te,
    90,
    9,
    290,
    inputs: {'crop_tea': 2, 'wild_kinmokusei': 1},
    outputs: {'tea_kinmoku': 1},
  ),
  // Joyería.
  HAction(
    'je_quartz',
    _je,
    0,
    5,
    25,
    inputs: {'bar_bronze': 1, 'gem_quartz': 1},
    outputs: {'gear_quartz_charm': 1},
  ),
  HAction(
    'je_amethyst',
    _je,
    20,
    6,
    80,
    inputs: {'bar_silver': 1, 'gem_amethyst': 1},
    outputs: {'gear_amethyst_ring': 1},
  ),
  HAction(
    'je_sapphire',
    _je,
    40,
    7,
    180,
    inputs: {'bar_silver': 2, 'gem_sapphire': 1},
    outputs: {'gear_sapphire_charm': 1},
  ),
  HAction(
    'je_ruby',
    _je,
    60,
    8,
    320,
    inputs: {'bar_gold': 2, 'gem_ruby': 1},
    outputs: {'gear_ruby_ring': 1},
  ),
  HAction(
    'je_pearl',
    _je,
    85,
    10,
    650,
    inputs: {'bar_star': 1, 'gem_pearl': 3, 'ore_jade': 2},
    outputs: {'gear_pearl_crown': 1},
  ),
];

final Map<String, HAction> hActionById = {for (final a in hActions) a.id: a};

HAction? hAction(String id) => hActionById[id];

List<HAction> hActionsOf(HSkill skill) =>
    hActions.where((a) => a.skill == skill).toList();

/// Los sitios de expedición.
const List<HZone> hZones = [
  HZone('meadow', 0, 10, 8, 60, [
    HLoot('wild_tanpopo', .8, 2, 5),
    HLoot('seed_rice', .5, 1, 3),
    HLoot('rare_feather', .15, 1, 1),
  ], prizeChance: .002),
  HZone('forest', 10, 20, 20, 160, [
    HLoot('log_matsu', .7, 3, 6),
    HLoot('wild_shiitake', .6, 2, 4),
    HLoot('rare_feather', .3, 1, 2),
    HLoot('silk_thread', .15, 1, 2),
  ], prizeChance: .004),
  HZone('river', 20, 30, 34, 300, [
    HLoot('fish_saba', .7, 2, 5),
    HLoot('rare_shell', .35, 1, 2),
    HLoot('silk_thread', .25, 1, 3),
  ], prizeChance: .006),
  HZone('mountain', 35, 45, 55, 560, [
    HLoot('ore_silver', .6, 2, 5),
    HLoot('rare_amber', .3, 1, 2),
    HLoot('gem_sapphire', .08, 1, 1),
    HLoot('silk_thread', .3, 2, 4),
  ], prizeChance: .01),
  HZone('coast', 50, 60, 80, 900, [
    HLoot('fish_sake', .6, 3, 6),
    HLoot('rare_shell', .5, 2, 4),
    HLoot('gem_pearl', .1, 1, 1),
  ], prizeChance: .014),
  HZone('onsen', 65, 90, 110, 1500, [
    HLoot('rare_ember', .45, 1, 2),
    HLoot('ore_moon', .4, 1, 3),
    HLoot('gem_ruby', .08, 1, 1),
  ], prizeChance: .02),
  HZone('sky', 80, 120, 150, 2400, [
    HLoot('rare_cloud', .5, 1, 3),
    HLoot('rare_feather', .6, 3, 6),
    HLoot('gem_pearl', .12, 1, 2),
  ], prizeChance: .03),
  HZone('moon', 95, 180, 200, 4000, [
    HLoot('rare_moondust', .6, 1, 3),
    HLoot('ore_star', .5, 2, 4),
    HLoot('rare_cloud', .4, 2, 3),
  ], prizeChance: .05),
];

final Map<String, HZone> hZoneById = {for (final z in hZones) z.id: z};

/// Los oficios que se le dan bien a cada personalidad: van un 15 % más rápido.
const Map<TamaPersonality, Set<HSkill>> hAffinities = {
  TamaPersonality.calm: {HSkill.fishing, HSkill.farming, HSkill.tea},
  TamaPersonality.playful: {HSkill.agility, HSkill.foraging, HSkill.expedition},
  TamaPersonality.shy: {HSkill.tailoring, HSkill.jewelry},
  TamaPersonality.cheeky: {HSkill.mining, HSkill.smithing, HSkill.woodcutting},
  TamaPersonality.sleepy: {HSkill.cooking, HSkill.carpentry},
};

const double hAffinityBonus = .15;
