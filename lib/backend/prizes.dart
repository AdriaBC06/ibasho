// Ibasho — los premios del gacha que se pone un Tama: gorros y accesorios.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'gacha.dart';

/// Donde va puesto un premio. Un Tama lleva un gorro y hasta tres accesorios,
/// uno por sitio: asi dos gafas no se pisan y la botella no tapa al mando.
enum PrizeSlot {
  /// El gorro. Solo hay uno.
  head,

  /// Detras del cuerpo: alas, capas, mochilas.
  back,

  /// Alrededor de la cintura: el flotador.
  waist,

  /// Revoloteando alrededor: las hadas.
  aura,

  /// Sobre los ojos: gafas, antifaces.
  eyes,

  /// En la nariz: narices de payaso, tiritas.
  nose,

  /// Al cuello: pajaritas, collares.
  neck,

  /// En lugar de los pies: zapatillas.
  feet,

  /// A su derecha: bebidas, lo que empuna (espada, pico, microfono) y el
  /// cursor.
  right,

  /// A su izquierda: el mando, el globo, el farolillo y lo que se come.
  left,
}

/// Un premio: un dibujo con una o varias variantes de color. Cada variante es
/// un premio distinto del gacha; su clave es `id_variante` y su SVG sale de
/// `tool/gen_prizes.py`.
///
/// Si [front], el dibujo va en dos partes: la principal detras del cuerpo y
/// `<clave>_front.svg` delante (las correas de la mochila, la mitad de
/// delante del flotador, las hadas que pasan por delante).
@immutable
class Prize {
  const Prize(this.id, this.rarity, this.slot, this.variants, {this.front = false});

  final String id;
  final Rarity rarity;
  final PrizeSlot slot;
  final List<String> variants;
  final bool front;

  GachaCategory get category => slot == PrizeSlot.head ? GachaCategory.hats : GachaCategory.accessories;

  Iterable<PrizeItem> get items => variants.map((v) => PrizeItem(this, v));
}

/// Una variante concreta: lo que se gana, se guarda y se pone.
@immutable
class PrizeItem {
  const PrizeItem(this.prize, this.variant);

  final Prize prize;
  final String variant;

  String get key => '${prize.id}_$variant';
  String get asset => 'assets/prizes/$key.svg';

  /// La parte de delante, si el premio va en dos partes.
  String? get frontAsset => prize.front ? 'assets/prizes/${key}_front.svg' : null;

  @override
  bool operator ==(Object other) => other is PrizeItem && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Todos los premios que se ponen, de menos a mas raros. Tiene que cuadrar
/// con `tool/prizes/prizes.json` (lo comprueba `test/prizes_test.dart`).
const List<Prize> wearablePrizes = <Prize>[
  // Gorros.
  Prize('cap', Rarity.n, PrizeSlot.head, ['red', 'blue', 'green', 'yellow']),
  Prize('afro', Rarity.n, PrizeSlot.head, ['brown']),
  Prize('beanie', Rarity.n, PrizeSlot.head, ['red', 'blue', 'cream']),
  Prize('hachimaki', Rarity.n, PrizeSlot.head, ['white', 'red']),
  Prize('leaf', Rarity.n, PrizeSlot.head, ['green', 'orange']),
  Prize('bow', Rarity.n, PrizeSlot.head, ['pink', 'blue', 'yellow']),
  Prize('headphones', Rarity.r, PrizeSlot.head, ['white', 'skyblue']),
  Prize('beret', Rarity.r, PrizeSlot.head, ['red', 'black', 'green']),
  Prize('top_hat', Rarity.r, PrizeSlot.head, ['black', 'white']),
  Prize('hard_hat', Rarity.r, PrizeSlot.head, ['yellow', 'orange']),
  Prize('frog_hat', Rarity.r, PrizeSlot.head, ['green', 'pink']),
  Prize('chef_hat', Rarity.r, PrizeSlot.head, ['white']),
  Prize('hood', Rarity.sr, PrizeSlot.head, ['black', 'red', 'green']),
  Prize('witch_hat', Rarity.sr, PrizeSlot.head, ['purple', 'black']),
  Prize('nightcap', Rarity.sr, PrizeSlot.head, ['navy', 'pink']),
  Prize('flower_crown', Rarity.sr, PrizeSlot.head, ['sakura', 'sunflower', 'lavender']),
  Prize('kitsune', Rarity.sr, PrizeSlot.head, ['white', 'red']),
  Prize('viking', Rarity.sr, PrizeSlot.head, ['iron']),
  Prize('sombrero', Rarity.sr, PrizeSlot.head, ['straw', 'charro']),
  Prize('gamer_headset', Rarity.ssr, PrizeSlot.head, ['black', 'blue', 'pink']),
  Prize('crown', Rarity.ssr, PrizeSlot.head, ['gold', 'silver']),
  Prize('kabuto', Rarity.ssr, PrizeSlot.head, ['red', 'black']),
  Prize('wizard_hat', Rarity.ssr, PrizeSlot.head, ['blue', 'purple']),
  Prize('cat_headset', Rarity.ur, PrizeSlot.head, ['black', 'blue', 'pink', 'white']),
  Prize('halo', Rarity.ur, PrizeSlot.head, ['gold']),
  Prize('devil_horns', Rarity.ur, PrizeSlot.head, ['red', 'black']),
  Prize('rainbow_cloud', Rarity.ur, PrizeSlot.head, ['sky']),
  Prize('cat_headset_rgb', Rarity.mu, PrizeSlot.head, ['black', 'blue', 'pink', 'white']),
  Prize('halo_rgb', Rarity.mu, PrizeSlot.head, ['rainbow']),
  Prize('crown_rgb', Rarity.mu, PrizeSlot.head, ['rainbow']),
  // Accesorios.
  Prize('glasses', Rarity.n, PrizeSlot.eyes, ['black', 'white', 'red', 'navy']),
  Prize('bowtie', Rarity.n, PrizeSlot.neck, ['black', 'red']),
  Prize('sneakers', Rarity.n, PrizeSlot.feet, ['red', 'blue', 'green']),
  Prize('scarf', Rarity.n, PrizeSlot.neck, ['red', 'blue', 'cream']),
  Prize('randoseru', Rarity.n, PrizeSlot.back, ['red', 'black'], front: true),
  Prize('groucho', Rarity.r, PrizeSlot.eyes, ['black']),
  Prize('clown_nose', Rarity.r, PrizeSlot.nose, ['red', 'black', 'green']),
  Prize('bottle', Rarity.r, PrizeSlot.right, ['water', 'cola', 'bluecola']),
  Prize('energy', Rarity.r, PrizeSlot.right, ['green', 'white', 'red']),
  Prize('boba', Rarity.r, PrizeSlot.right, ['pink', 'green', 'brown']),
  Prize('taco', Rarity.r, PrizeSlot.left, ['classic']),
  Prize('balloon', Rarity.r, PrizeSlot.left, ['red', 'blue', 'yellow', 'pink']),
  Prize('uchiwa', Rarity.r, PrizeSlot.left, ['sun', 'fish']),
  Prize('mask', Rarity.sr, PrizeSlot.eyes, ['a', 'b', 'c', 'd']),
  Prize('bandage', Rarity.sr, PrizeSlot.nose, ['stars']),
  Prize('pickaxe', Rarity.sr, PrizeSlot.right, ['diamond']),
  Prize('sword', Rarity.sr, PrizeSlot.right, ['iron', 'diamond']),
  Prize('swim_ring', Rarity.sr, PrizeSlot.waist, ['stripes'], front: true),
  Prize('lantern', Rarity.sr, PrizeSlot.left, ['red']),
  Prize('fish_bag', Rarity.sr, PrizeSlot.left, ['gold']),
  Prize('cape', Rarity.sr, PrizeSlot.back, ['red', 'blue']),
  Prize('shutter_shades', Rarity.ssr, PrizeSlot.eyes, ['orange', 'blue', 'yellow', 'red', 'lime']),
  Prize('dollar_chain', Rarity.ssr, PrizeSlot.neck, ['gold', 'silver']),
  Prize('microphone', Rarity.ssr, PrizeSlot.right, ['silver']),
  Prize('kendama', Rarity.ssr, PrizeSlot.left, ['red', 'blue']),
  Prize('cursor', Rarity.ur, PrizeSlot.right, ['white', 'black', 'inverted']),
  Prize('controller', Rarity.ur, PrizeSlot.left, ['blue']),
  Prize('fairies', Rarity.ur, PrizeSlot.aura, ['light'], front: true),
  Prize('angel_wings', Rarity.ur, PrizeSlot.back, ['white', 'black']),
  Prize('rgb_shades', Rarity.mu, PrizeSlot.eyes, ['rainbow']),
  Prize('rgb_wings', Rarity.mu, PrizeSlot.back, ['rainbow']),
];

final Map<String, PrizeItem> _byKey = <String, PrizeItem>{
  for (final p in wearablePrizes)
    for (final item in p.items) item.key: item,
};

/// La variante con clave [key], o `null` si esta version de la app no la
/// conoce (un premio nuevo puesto desde una version mas moderna).
PrizeItem? prizeItem(String? key) => key == null ? null : _byKey[key];

/// Todas las variantes de una categoria, en el orden del catalogo.
List<PrizeItem> prizeItems(GachaCategory category) => [
      for (final p in wearablePrizes)
        if (p.category == category) ...p.items,
    ];

/// Las variantes de [category] con [rarity], en el orden del catalogo.
List<PrizeItem> prizeItemsOf(GachaCategory category, Rarity rarity) => [
      for (final p in wearablePrizes)
        if (p.category == category && p.rarity == rarity) ...p.items,
    ];
