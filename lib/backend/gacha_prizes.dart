// Ibasho — todo lo que puede dar una bola del pinball, de las cuatro
// categorias: gorros, accesorios, fondos y musicas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Cada categoria tiene su catalogo (`prizes.dart`, `backdrops.dart`,
// `gacha_music.dart`), pero el pinball, el Catalogo y las reglas necesitan
// verlos juntos: una clave de `/users/{cuenta}/prizes` puede ser `cap_red`,
// `bg_sky` o `mu_nana`. En la 0.6.0 el sorteo solo conocia gorros y
// accesorios, y una bola que entraba en el agujero de fondos o de musica se
// quedaba sin premio; por eso todo el sorteo pasa ahora por aqui.

import 'dart:math' as math;

import 'backdrops.dart';
import 'gacha.dart';
import 'gacha_music.dart';
import 'prizes.dart';

/// Las claves de [category] con [rarity] exacta, en el orden del catalogo.
List<String> gachaPrizeKeysOf(GachaCategory category, Rarity rarity) =>
    switch (category) {
      GachaCategory.hats || GachaCategory.accessories => [
        for (final item in prizeItemsOf(category, rarity)) item.key,
      ],
      GachaCategory.backdrops => [for (final b in backdropsOf(rarity)) b.key],
      GachaCategory.music => [for (final m in gachaMusicOf(rarity)) m.key],
    };

/// Todas las claves de [category], de menos a mas raras.
List<String> gachaPrizeKeys(GachaCategory category) => [
  for (final rarity in Rarity.values) ...gachaPrizeKeysOf(category, rarity),
];

/// De donde sale el premio de una bola de [rarity] que entra en [category]:
/// los de su rareza. Si la categoria no tiene ninguno de esa rareza (la
/// musica no tiene SSR), los de la rareza mas cercana por debajo y, si no
/// hay, por encima. Asi ninguna bola que entra se queda sin premio. Las
/// reglas aceptan exactamente esto (lo comprueba `test/prize_rules_test.dart`).
List<String> gachaPrizePool(GachaCategory category, Rarity rarity) {
  final exact = gachaPrizeKeysOf(category, rarity);
  if (exact.isNotEmpty) return exact;
  for (var i = rarity.index - 1; i >= 0; i--) {
    final lower = gachaPrizeKeysOf(category, Rarity.values[i]);
    if (lower.isNotEmpty) return lower;
  }
  for (var i = rarity.index + 1; i < Rarity.values.length; i++) {
    final upper = gachaPrizeKeysOf(category, Rarity.values[i]);
    if (upper.isNotEmpty) return upper;
  }
  return const <String>[];
}

/// El premio de una bola de [rarity] que entra en [category]. Todos pesan lo
/// mismo. Si [fresh] (la bola dirigida del Catalogo), sale uno que no este en
/// [owned] mientras quede alguno; si ya estan todos, cualquiera. `null` solo
/// si la categoria no tiene ningun premio.
String? rollGachaPrize(
  GachaCategory category,
  Rarity rarity,
  math.Random random, {
  Set<String> owned = const <String>{},
  bool fresh = false,
}) {
  final all = gachaPrizePool(category, rarity);
  if (all.isEmpty) return null;
  final missing = fresh
      ? all.where((k) => !owned.contains(k)).toList()
      : const <String>[];
  final pool = missing.isNotEmpty ? missing : all;
  return pool[random.nextInt(pool.length)];
}

/// La categoria de la clave [key], o `null` si esta version no la conoce.
GachaCategory? gachaPrizeCategory(String? key) {
  if (key == null) return null;
  if (backdropByKey(key) != null) return GachaCategory.backdrops;
  if (gachaMusicByKey(key) != null) return GachaCategory.music;
  return prizeItem(key)?.prize.category;
}

/// La rareza propia de [key] (no la de la bola que lo dio), o `null`.
Rarity? gachaPrizeRarity(String? key) =>
    backdropByKey(key)?.rarity ??
    gachaMusicByKey(key)?.rarity ??
    prizeItem(key)?.prize.rarity;

/// Todas las claves que se pueden ganar, de las cuatro categorias.
List<String> get allGachaPrizeKeys => [
  for (final category in GachaCategory.values) ...gachaPrizeKeys(category),
];
