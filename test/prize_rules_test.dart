// Ibasho — las reglas saben que premio es de que rareza y categoria.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// `gacha/turn` solo acepta un premio de la rareza de la bola (y de la
// categoria de la bola dirigida). Las reglas no pueden leer el catalogo de
// Dart, asi que llevan la lista de claves escrita a mano; este test comprueba
// que cuadra. Si falla, imprime el trozo que hay que pegar en
// `database.rules.json`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/backend/prizes.dart';

String _keys(Iterable<PrizeItem> items) => items.map((i) => i.key).join('|');

/// Lo que tiene que aparecer en las reglas para cada rareza.
String rarityRule(Rarity rarity) {
  final items = [
    for (final p in wearablePrizes)
      if (p.rarity == rarity) ...p.items,
  ];
  return "newData.child('rarity').val() === '${rarity.name}' && newData.child('prize').val().matches(/^(${_keys(items)})\$/)";
}

/// Y para cada categoria (la de la bola dirigida).
String categoryRule(GachaCategory category) =>
    "newData.child('category').val() === '${category.name}' && newData.child('prize').val().matches(/^(${_keys(prizeItems(category))})\$/)";

void main() {
  final rules = File('database.rules.json').readAsStringSync();

  test('las reglas conocen la rareza de cada premio', () {
    for (final rarity in Rarity.values) {
      final want = rarityRule(rarity);
      expect(rules.contains(want), isTrue, reason: 'falta en las reglas:\n($want)');
    }
  });

  test('las reglas conocen la categoria de cada premio', () {
    for (final category in [GachaCategory.hats, GachaCategory.accessories]) {
      final want = categoryRule(category);
      expect(rules.contains(want), isTrue, reason: 'falta en las reglas:\n($want)');
    }
  });
}
