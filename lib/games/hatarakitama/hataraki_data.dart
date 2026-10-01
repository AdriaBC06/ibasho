// Ibasho — Hatarakitama: los datos del juego (skills, objetos, acciones).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import '../../backend/tama.dart' show TamaPersonality;

/// Los oficios. Los seis primeros sacan cosas del mundo (agilidad solo da
/// experiencia y velocidad), los doce siguientes las transforman, estudio
/// solo da experiencia (leyendo libros) y las expediciones van aparte: se
/// sube mandando grupos de Tamas de viaje.
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
  pottery,
  dyeing,
  construction,
  writing,
  brewing,
  magic,
  study,
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

/// Qué clase de cosa es un objeto del almacén. `boost` son los cebos,
/// abonos y mechas que se le ponen a un Tama; `potion`, `rune` y `map` se
/// llevan de viaje, y `furniture` va a las casas.
enum HItemKind {
  material,
  seed,
  gem,
  food,
  tea,
  gear,
  boost,
  potion,
  rune,
  map,
  furniture,
}

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
    this.boostSkill,
    this.boost = 0,
    this.zones = const [],
    this.zonePower = 0,
    this.effect,
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

  /// Cebo, abono o mecha: oficio en el que sirve y cuánto ayuda (pesca: más
  /// probabilidad de doble; huerto: cosechas de más; minería: gemas por
  /// tanto).
  final HSkill? boostSkill;
  final double boost;

  /// Ropa teñida: sitios en los que suma [zonePower] de más.
  final List<String> zones;
  final int zonePower;

  /// Pociones, runas y mapas: qué hacen en el mapa del viaje (`heal`,
  /// `sight`, `luck`, `haste`, `reveal`).
  final String? effect;
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
const _fu = HItemKind.furniture;

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
  // Recolecta nueva, barro y lo que sale del horno.
  HItem('wild_yomogi', _m), HItem('water_spring', _m), HItem('clay', _m),
  HItem('soot', _m), HItem('seed_ai', HItemKind.seed), HItem('crop_ai', _m),
  // Cerámica.
  HItem('pot_bowl', _m), HItem('pot_brick', _m), HItem('pot_flask', _m),
  HItem('pot_tile', _m), HItem('pot_teapot', _m), HItem('pot_planter', _m),
  HItem('pot_vase', _m), HItem('pot_celadon', _m),
  // Tintes y telas teñidas.
  HItem('dye_yellow', _m), HItem('dye_black', _m), HItem('dye_brown', _m),
  HItem('dye_blue', _m), HItem('dye_red', _m), HItem('dye_pink', _m),
  HItem('dye_gold', _m),
  HItem('cloth_blue', _m), HItem('cloth_red', _m), HItem('cloth_gold', _m),
  // Piezas de construcción.
  HItem('build_beam', _m), HItem('build_frame', _m), HItem('build_wall', _m),
  HItem('build_roof', _m), HItem('build_shoji', _m), HItem('build_pillar', _m),
  HItem('build_ornament', _m),
  // Escritura.
  HItem('paper', _m), HItem('ink', _m), HItem('book_notes', _m),
  HItem('book_basic', _m), HItem('book_tome', _m), HItem('book_arcane', _m),
  HItem('map_trail', HItemKind.map, effect: 'reveal'),
  HItem('map_chart', HItemKind.map, effect: 'reveal'),
  HItem('map_star', HItemKind.map, effect: 'reveal'),
  // Brebajes.
  HItem('potion_heal', HItemKind.potion, effect: 'heal'),
  HItem('potion_sight', HItemKind.potion, effect: 'sight'),
  HItem('potion_luck', HItemKind.potion, effect: 'luck'),
  HItem('potion_haste', HItemKind.potion, effect: 'haste'),
  HItem('potion_elixir', HItemKind.potion, effect: 'heal'),
  // Magia: runas que encantan el equipo durante un viaje.
  HItem('rune_spark', HItemKind.rune, power: 6),
  HItem('rune_guard', HItemKind.rune, power: 14),
  HItem('rune_compass', HItemKind.rune, power: 10, effect: 'sight'),
  HItem('rune_fortune', HItemKind.rune, power: 18, effect: 'luck'),
  HItem('rune_titan', HItemKind.rune, power: 40),
  HItem('rune_star', HItemKind.rune, power: 60, effect: 'reveal'),
  // Cebos, abonos y mechas: se le ponen a un Tama y se gasta uno por vez.
  HItem('bait_worm', HItemKind.boost, boostSkill: HSkill.fishing, boost: .15),
  HItem('bait_lure', HItemKind.boost, boostSkill: HSkill.fishing, boost: .35),
  HItem('fert_compost', HItemKind.boost, boostSkill: HSkill.farming, boost: 1),
  HItem('fert_rich', HItemKind.boost, boostSkill: HSkill.farming, boost: 2),
  HItem('fuse_basic', HItemKind.boost, boostSkill: HSkill.mining, boost: 1),
  HItem('fuse_star', HItemKind.boost, boostSkill: HSkill.mining, boost: 3),
  // Tesoros de expedición.
  HItem('rare_feather', _m), HItem('rare_shell', _m), HItem('rare_amber', _m),
  HItem('rare_ember', _m), HItem('rare_cloud', _m), HItem('rare_moondust', _m),
  HItem('silk_thread', _m),
  // El paquete de las casillas de encargo del mapa (lo pide el tablón).
  HItem('parcel', _m),
  // Muebles para las casas (los estilos y tamaños, en hataraki_home.dart).
  HItem('fu_stool', _fu),
  HItem('fu_zabuton', _fu),
  HItem('fu_sign', _fu),
  HItem('fu_chabudai', _fu),
  HItem('fu_bonsai', _fu),
  HItem('fu_futon', _fu),
  HItem('fu_andon', _fu),
  HItem('fu_boat', _fu),
  HItem('fu_aquarium', _fu),
  HItem('fu_rug_wave', _fu),
  HItem('fu_hammock', _fu),
  HItem('fu_seachart', _fu),
  HItem('fu_shell_lamp', _fu),
  HItem('fu_scroll', _fu),
  HItem('fu_rug_red', _fu),
  HItem('fu_tansu', _fu),
  HItem('fu_celadon', _fu),
  HItem('fu_silk_futon', _fu),
  HItem('fu_maneki', _fu),
  HItem('fu_lantern', _fu),
  HItem('fu_crystal', _fu),
  HItem('fu_bookcase', _fu),
  HItem('fu_orrery', _fu),
  HItem('fu_candles', _fu),
  HItem('fu_flowerbowl', _fu),
  HItem('fu_noren', _fu),
  HItem('fu_blossom_lamp', _fu),
  HItem('fu_ikebana', _fu),
  HItem('fu_flowerstand', _fu),
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
  // Ropa teñida: más fuerza en los sitios de su color.
  HItem(
    'gear_ai_happi',
    HItemKind.gear,
    slot: HGearSlot.outfit,
    power: 12,
    zones: ['river', 'coast'],
    zonePower: 10,
  ),
  HItem(
    'gear_beni_cloak',
    HItemKind.gear,
    slot: HGearSlot.outfit,
    power: 22,
    zones: ['mountain', 'onsen'],
    zonePower: 14,
  ),
  HItem(
    'gear_kin_kimono',
    HItemKind.gear,
    slot: HGearSlot.outfit,
    power: 36,
    zones: ['sky', 'moon'],
    zonePower: 20,
  ),
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
const _po = HSkill.pottery;
const _dy = HSkill.dyeing;
const _bu = HSkill.construction;
const _wr = HSkill.writing;
const _br = HSkill.brewing;
const _ma = HSkill.magic;
const _st = HSkill.study;

/// Lo que sale del horno además de la pieza.
const _soot = [HDrop('soot', .5)];

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
  HAction('mi_clay', _mi, 0, 3, 8, outputs: {'clay': 2}),
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
  HAction(
    'fa_compost',
    _fa,
    5,
    8,
    20,
    inputs: {'wild_tanpopo': 3},
    outputs: {'fert_compost': 2},
  ),
  HAction(
    'fa_ai',
    _fa,
    15,
    15,
    65,
    inputs: {'seed_ai': 1},
    outputs: {'crop_ai': 3},
    drops: [HDrop('seed_ai', .4)],
  ),
  HAction(
    'fa_rich',
    _fa,
    50,
    12,
    120,
    inputs: {'crop_soy': 2, 'rare_shell': 1},
    outputs: {'fert_rich': 3},
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
  HAction(
    'fo_yomogi',
    _fo,
    5,
    3.5,
    15,
    outputs: {'wild_yomogi': 1},
    drops: [HDrop('seed_ai', .2)],
  ),
  HAction('fo_worm', _fo, 8, 4, 18, outputs: {'bait_worm': 2}),
  HAction('fo_spring', _fo, 12, 4, 20, outputs: {'water_spring': 2}),
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
  HAction(
    'sm_fuse',
    _sm,
    10,
    4,
    30,
    inputs: {'ore_copper': 1, 'soot': 1},
    outputs: {'fuse_basic': 3},
  ),
  HAction(
    'sm_lure',
    _sm,
    30,
    5,
    70,
    inputs: {'bar_silver': 1, 'rare_feather': 1},
    outputs: {'bait_lure': 4},
  ),
  HAction(
    'sm_fuse_star',
    _sm,
    60,
    6,
    160,
    inputs: {'bar_gold': 1, 'rare_ember': 1},
    outputs: {'fuse_star': 4},
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
  // Cerámica: barro y leña al horno.
  HAction(
    'po_bowl',
    _po,
    0,
    4,
    12,
    inputs: {'clay': 2, 'log_sugi': 1},
    outputs: {'pot_bowl': 1},
    drops: _soot,
  ),
  HAction(
    'po_brick',
    _po,
    5,
    4,
    18,
    inputs: {'clay': 3, 'log_sugi': 1},
    outputs: {'pot_brick': 2},
    drops: _soot,
  ),
  HAction(
    'po_flask',
    _po,
    12,
    4.5,
    30,
    inputs: {'clay': 2, 'log_matsu': 1},
    outputs: {'pot_flask': 2},
    drops: _soot,
  ),
  HAction(
    'po_tile',
    _po,
    20,
    5,
    45,
    inputs: {'clay': 3, 'log_take': 1},
    outputs: {'pot_tile': 2},
    drops: _soot,
  ),
  HAction(
    'po_teapot',
    _po,
    30,
    6,
    80,
    inputs: {'clay': 4, 'log_kaede': 1, 'dye_brown': 1},
    outputs: {'pot_teapot': 1},
    drops: _soot,
  ),
  HAction(
    'po_planter',
    _po,
    40,
    6,
    100,
    inputs: {'clay': 4, 'log_kaede': 1},
    outputs: {'pot_planter': 1},
    drops: _soot,
  ),
  HAction(
    'po_vase',
    _po,
    55,
    7,
    170,
    inputs: {'clay': 5, 'log_sakura': 1, 'gem_quartz': 1},
    outputs: {'pot_vase': 1},
    drops: _soot,
  ),
  HAction(
    'po_celadon',
    _po,
    75,
    9,
    300,
    inputs: {'clay': 6, 'log_kusu': 1, 'ore_jade': 1},
    outputs: {'pot_celadon': 1},
    drops: _soot,
  ),
  // Tintes: flores y cosechas a tinte, y tinte a tela y ropa.
  HAction(
    'dy_yellow',
    _dy,
    0,
    3.5,
    12,
    inputs: {'wild_tanpopo': 3},
    outputs: {'dye_yellow': 1},
  ),
  HAction(
    'dy_black',
    _dy,
    5,
    4,
    18,
    inputs: {'soot': 3},
    outputs: {'dye_black': 1},
  ),
  HAction(
    'dy_brown',
    _dy,
    10,
    4,
    28,
    inputs: {'wild_kuri': 2},
    outputs: {'dye_brown': 1},
  ),
  HAction(
    'dy_blue',
    _dy,
    20,
    4.5,
    42,
    inputs: {'crop_ai': 2},
    outputs: {'dye_blue': 1},
  ),
  HAction(
    'dy_cloth_blue',
    _dy,
    25,
    5,
    55,
    inputs: {'cloth_cotton': 1, 'dye_blue': 1},
    outputs: {'cloth_blue': 1},
  ),
  HAction(
    'dy_red',
    _dy,
    35,
    5,
    70,
    inputs: {'crop_ichigo': 2},
    outputs: {'dye_red': 1},
  ),
  HAction(
    'dy_cloth_red',
    _dy,
    40,
    5.5,
    85,
    inputs: {'cloth_cotton': 1, 'dye_red': 1},
    outputs: {'cloth_red': 1},
  ),
  HAction(
    'dy_ai_happi',
    _dy,
    45,
    7,
    200,
    inputs: {'gear_happi': 1, 'dye_blue': 3},
    outputs: {'gear_ai_happi': 1},
  ),
  HAction(
    'dy_pink',
    _dy,
    55,
    6,
    120,
    inputs: {'wild_hasu': 2},
    outputs: {'dye_pink': 1},
  ),
  HAction(
    'dy_beni_cloak',
    _dy,
    65,
    8,
    380,
    inputs: {'gear_cloak': 1, 'dye_red': 4},
    outputs: {'gear_beni_cloak': 1},
  ),
  HAction(
    'dy_gold',
    _dy,
    75,
    7,
    200,
    inputs: {'wild_kinmokusei': 2, 'ore_gold': 1},
    outputs: {'dye_gold': 1},
  ),
  HAction(
    'dy_cloth_gold',
    _dy,
    80,
    8,
    260,
    inputs: {'cloth_silk': 1, 'dye_gold': 1},
    outputs: {'cloth_gold': 1},
  ),
  HAction(
    'dy_kin_kimono',
    _dy,
    90,
    10,
    700,
    inputs: {'gear_kimono': 1, 'dye_gold': 4},
    outputs: {'gear_kin_kimono': 1},
  ),
  // Construcción: las piezas con las que se levanta el pueblo.
  HAction(
    'bu_beam',
    _bu,
    0,
    5,
    20,
    inputs: {'plank_sugi': 2},
    outputs: {'build_beam': 1},
  ),
  HAction(
    'bu_frame',
    _bu,
    15,
    6,
    60,
    inputs: {'plank_kaede': 2, 'bar_iron': 1},
    outputs: {'build_frame': 1},
  ),
  HAction(
    'bu_wall',
    _bu,
    25,
    6,
    80,
    inputs: {'pot_brick': 4, 'clay': 2},
    outputs: {'build_wall': 1},
  ),
  HAction(
    'bu_roof',
    _bu,
    35,
    7,
    120,
    inputs: {'pot_tile': 4, 'plank_kaede': 1},
    outputs: {'build_roof': 1},
  ),
  HAction(
    'bu_shoji',
    _bu,
    50,
    7,
    170,
    inputs: {'paper': 3, 'plank_sakura': 1},
    outputs: {'build_shoji': 1},
  ),
  HAction(
    'bu_pillar',
    _bu,
    70,
    9,
    300,
    inputs: {'log_kusu': 2, 'bar_gold': 1},
    outputs: {'build_pillar': 1},
  ),
  HAction(
    'bu_ornament',
    _bu,
    90,
    12,
    750,
    inputs: {'bar_star': 1, 'pot_celadon': 1, 'dye_gold': 1},
    outputs: {'build_ornament': 1},
  ),
  // Escritura.
  HAction(
    'wr_paper',
    _wr,
    0,
    3.5,
    10,
    inputs: {'log_sugi': 1},
    outputs: {'paper': 2},
  ),
  HAction(
    'wr_notes',
    _wr,
    5,
    4,
    20,
    inputs: {'paper': 3},
    outputs: {'book_notes': 1},
  ),
  HAction('wr_ink', _wr, 10, 4, 25, inputs: {'soot': 2}, outputs: {'ink': 1}),
  HAction(
    'wr_basic',
    _wr,
    20,
    6,
    70,
    inputs: {'paper': 4, 'ink': 2},
    outputs: {'book_basic': 1},
  ),
  HAction(
    'wr_map_trail',
    _wr,
    30,
    6,
    100,
    inputs: {'paper': 3, 'ink': 2, 'rare_feather': 1},
    outputs: {'map_trail': 1},
  ),
  HAction(
    'wr_tome',
    _wr,
    45,
    8,
    180,
    inputs: {'paper': 6, 'ink': 3, 'cloth_blue': 1},
    outputs: {'book_tome': 1},
  ),
  HAction(
    'wr_map_chart',
    _wr,
    60,
    8,
    240,
    inputs: {'paper': 4, 'ink': 3, 'rare_shell': 2},
    outputs: {'map_chart': 1},
  ),
  HAction(
    'wr_arcane',
    _wr,
    75,
    10,
    400,
    inputs: {'paper': 8, 'ink': 4, 'rare_moondust': 1},
    outputs: {'book_arcane': 1},
  ),
  HAction(
    'wr_map_star',
    _wr,
    90,
    11,
    600,
    inputs: {'paper': 5, 'ink': 4, 'rare_cloud': 2},
    outputs: {'map_star': 1},
  ),
  // Brebajes: hierbas, agua de manantial y un frasco.
  HAction(
    'br_heal',
    _br,
    0,
    5,
    16,
    inputs: {'wild_yomogi': 2, 'water_spring': 1, 'pot_flask': 1},
    outputs: {'potion_heal': 1},
  ),
  HAction(
    'br_sight',
    _br,
    20,
    6,
    60,
    inputs: {
      'wild_yomogi': 1,
      'wild_shiitake': 2,
      'water_spring': 1,
      'pot_flask': 1,
    },
    outputs: {'potion_sight': 1},
  ),
  HAction(
    'br_luck',
    _br,
    40,
    7,
    130,
    inputs: {
      'rare_feather': 1,
      'wild_kuri': 1,
      'water_spring': 1,
      'pot_flask': 1,
    },
    outputs: {'potion_luck': 1},
  ),
  HAction(
    'br_haste',
    _br,
    60,
    8,
    220,
    inputs: {
      'tea_matcha': 1,
      'rare_amber': 1,
      'water_spring': 1,
      'pot_flask': 1,
    },
    outputs: {'potion_haste': 1},
  ),
  HAction(
    'br_elixir',
    _br,
    85,
    10,
    520,
    inputs: {
      'rare_cloud': 1,
      'crop_momo': 2,
      'water_spring': 2,
      'pot_flask': 1,
    },
    outputs: {'potion_elixir': 1},
  ),
  // Magia: gemas, polvo de luna y nubes, a runas para el equipo de viaje.
  HAction(
    'ma_spark',
    _ma,
    0,
    6,
    25,
    inputs: {'gem_quartz': 1, 'ink': 1},
    outputs: {'rune_spark': 1},
  ),
  HAction(
    'ma_guard',
    _ma,
    15,
    7,
    70,
    inputs: {'gem_amethyst': 1, 'ink': 1},
    outputs: {'rune_guard': 1},
  ),
  HAction(
    'ma_compass',
    _ma,
    30,
    8,
    130,
    inputs: {'gem_sapphire': 1, 'rare_feather': 1},
    outputs: {'rune_compass': 1},
  ),
  HAction(
    'ma_fortune',
    _ma,
    50,
    9,
    250,
    inputs: {'gem_ruby': 1, 'rare_moondust': 1},
    outputs: {'rune_fortune': 1},
  ),
  HAction(
    'ma_titan',
    _ma,
    70,
    10,
    420,
    inputs: {'gem_pearl': 1, 'rare_cloud': 1, 'rare_moondust': 1},
    outputs: {'rune_titan': 1},
  ),
  HAction(
    'ma_star',
    _ma,
    90,
    12,
    800,
    inputs: {'bar_star': 1, 'rare_moondust': 2, 'rare_cloud': 2},
    outputs: {'rune_star': 1},
  ),
  // Muebles: los de carpintería…
  HAction(
    'fu_stool',
    _ca,
    3,
    5,
    25,
    inputs: {'plank_sugi': 2},
    outputs: {'fu_stool': 1},
  ),
  HAction(
    'fu_chabudai',
    _ca,
    15,
    7,
    70,
    inputs: {'plank_sugi': 5},
    outputs: {'fu_chabudai': 1},
  ),
  HAction(
    'fu_boat',
    _ca,
    25,
    7,
    90,
    inputs: {'plank_sugi': 3, 'rare_shell': 1},
    outputs: {'fu_boat': 1},
  ),
  HAction(
    'fu_bookcase',
    _ca,
    45,
    9,
    220,
    inputs: {'plank_kaede': 4, 'book_basic': 2},
    outputs: {'fu_bookcase': 1},
  ),
  HAction(
    'fu_tansu',
    _ca,
    55,
    9,
    260,
    inputs: {'plank_sakura': 4, 'bar_silver': 1},
    outputs: {'fu_tansu': 1},
  ),
  // … de cerámica…
  HAction(
    'fu_flowerbowl',
    _po,
    3,
    5,
    22,
    inputs: {'pot_bowl': 1, 'wild_tanpopo': 3},
    outputs: {'fu_flowerbowl': 1},
  ),
  HAction(
    'fu_aquarium',
    _po,
    22,
    6,
    80,
    inputs: {'pot_bowl': 2, 'water_spring': 2, 'fish_iwashi': 2},
    outputs: {'fu_aquarium': 1},
  ),
  HAction(
    'fu_bonsai',
    _po,
    42,
    7,
    150,
    inputs: {'pot_planter': 1, 'log_matsu': 2},
    outputs: {'fu_bonsai': 1},
  ),
  HAction(
    'fu_ikebana',
    _po,
    58,
    8,
    230,
    inputs: {'pot_vase': 1, 'wild_hasu': 2},
    outputs: {'fu_ikebana': 1},
  ),
  HAction(
    'fu_celadon',
    _po,
    78,
    10,
    380,
    inputs: {'pot_celadon': 1, 'plank_sakura': 1},
    outputs: {'fu_celadon': 1},
  ),
  // … de tintes…
  HAction(
    'fu_rug_wave',
    _dy,
    28,
    7,
    110,
    inputs: {'cloth_blue': 3},
    outputs: {'fu_rug_wave': 1},
  ),
  HAction(
    'fu_rug_red',
    _dy,
    42,
    8,
    180,
    inputs: {'cloth_red': 4},
    outputs: {'fu_rug_red': 1},
  ),
  HAction(
    'fu_noren',
    _dy,
    57,
    8,
    200,
    inputs: {'cloth_cotton': 2, 'dye_pink': 2},
    outputs: {'fu_noren': 1},
  ),
  // … de costura…
  HAction(
    'fu_zabuton',
    _ta,
    3,
    5,
    25,
    inputs: {'cloth_cotton': 2},
    outputs: {'fu_zabuton': 1},
  ),
  HAction(
    'fu_futon',
    _ta,
    20,
    7,
    90,
    inputs: {'cloth_cotton': 6},
    outputs: {'fu_futon': 1},
  ),
  HAction(
    'fu_hammock',
    _ta,
    48,
    8,
    200,
    inputs: {'cloth_blue': 3, 'plank_kaede': 2},
    outputs: {'fu_hammock': 1},
  ),
  HAction(
    'fu_silk_futon',
    _ta,
    70,
    10,
    420,
    inputs: {'cloth_silk': 4, 'cloth_gold': 1},
    outputs: {'fu_silk_futon': 1},
  ),
  // … de escritura…
  HAction(
    'fu_sign',
    _wr,
    12,
    5,
    40,
    inputs: {'paper': 2, 'ink': 1, 'plank_sugi': 1},
    outputs: {'fu_sign': 1},
  ),
  HAction(
    'fu_scroll',
    _wr,
    35,
    7,
    130,
    inputs: {'paper': 4, 'ink': 2, 'cloth_blue': 1},
    outputs: {'fu_scroll': 1},
  ),
  HAction(
    'fu_seachart',
    _wr,
    62,
    8,
    260,
    inputs: {'map_chart': 1, 'plank_kaede': 1},
    outputs: {'fu_seachart': 1},
  ),
  // … y de magia.
  HAction(
    'fu_lantern',
    _ma,
    5,
    6,
    40,
    inputs: {'rune_spark': 1, 'paper': 2},
    outputs: {'fu_lantern': 1},
  ),
  HAction(
    'fu_crystal',
    _ma,
    35,
    8,
    160,
    inputs: {'gem_amethyst': 1, 'gem_quartz': 2, 'bar_silver': 1},
    outputs: {'fu_crystal': 1},
  ),
  HAction(
    'fu_blossom_lamp',
    _ma,
    52,
    9,
    240,
    inputs: {'rune_guard': 1, 'log_sakura': 2},
    outputs: {'fu_blossom_lamp': 1},
  ),
  HAction(
    'fu_orrery',
    _ma,
    85,
    12,
    700,
    inputs: {'bar_star': 1, 'rare_moondust': 2, 'gem_sapphire': 1},
    outputs: {'fu_orrery': 1},
  ),
  // Estudio: leer solo da experiencia.
  HAction('st_notes', _st, 0, 20, 60, inputs: {'book_notes': 1}),
  HAction('st_basic', _st, 20, 30, 260, inputs: {'book_basic': 1}),
  HAction('st_tome', _st, 45, 40, 700, inputs: {'book_tome': 1}),
  HAction('st_arcane', _st, 75, 60, 1800, inputs: {'book_arcane': 1}),
];

final Map<String, HAction> hActionById = {for (final a in hActions) a.id: a};

HAction? hAction(String id) => hActionById[id];

/// Las tareas de [skill], de menos a más nivel (los muebles van al final de
/// `hActions`, pero se ven entre las demás).
List<HAction> hActionsOf(HSkill skill) =>
    hActions.where((a) => a.skill == skill).toList()..sort(
      (a, b) => a.level != b.level
          ? a.level - b.level
          : hActions.indexOf(a) - hActions.indexOf(b),
    );

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
    HLoot('clay', .6, 3, 6),
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
  TamaPersonality.calm: {
    HSkill.fishing,
    HSkill.farming,
    HSkill.tea,
    HSkill.brewing,
  },
  TamaPersonality.playful: {
    HSkill.agility,
    HSkill.foraging,
    HSkill.dyeing,
    HSkill.expedition,
  },
  TamaPersonality.shy: {
    HSkill.tailoring,
    HSkill.jewelry,
    HSkill.writing,
    HSkill.study,
  },
  TamaPersonality.cheeky: {
    HSkill.mining,
    HSkill.smithing,
    HSkill.woodcutting,
    HSkill.construction,
  },
  TamaPersonality.sleepy: {
    HSkill.cooking,
    HSkill.carpentry,
    HSkill.pottery,
    HSkill.magic,
  },
};

const double hAffinityBonus = .15;
