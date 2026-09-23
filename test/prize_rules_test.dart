// Ibasho — las reglas saben que premio es de que rareza y categoria.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// `gacha/turn` solo acepta un premio de la rareza de la bola (y de la
// categoria de la bola dirigida). Las reglas no pueden leer el catalogo de
// Dart, asi que llevan la lista de claves escrita a mano; este test comprueba
// que cuadra. Si falla, imprime el trozo que hay que pegar en
// `database.rules.json`.
//
// En la 0.6.0 las listas solo tenian gorros y accesorios: una bola que caia
// en el agujero de fondos o de musica no podia guardar premio. Desde la 0.6.1
// salen de `gachaPrizePool`, el mismo monton del que sortea el pinball.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/backend/gacha_prizes.dart';

/// Lo que puede dar una bola de [rarity], caiga en el agujero que caiga.
List<String> rarityKeys(Rarity rarity) => [
  for (final category in GachaCategory.values)
    ...gachaPrizePool(category, rarity),
];

/// Lo que tiene que aparecer en las reglas para cada rareza.
String rarityRule(Rarity rarity) =>
    "newData.child('rarity').val() === '${rarity.name}' && newData.child('prize').val().matches(/^(${rarityKeys(rarity).join('|')})\$/)";

/// Y para cada categoria (la de la bola dirigida).
String categoryRule(GachaCategory category) =>
    "newData.child('category').val() === '${category.name}' && newData.child('prize').val().matches(/^(${gachaPrizeKeys(category).join('|')})\$/)";

void main() {
  final rules = File('database.rules.json').readAsStringSync();

  test('las reglas conocen la rareza de cada premio', () {
    for (final rarity in Rarity.values) {
      final want = rarityRule(rarity);
      expect(
        rules.contains(want),
        isTrue,
        reason: 'falta en las reglas:\n($want)',
      );
    }
  });

  test('las reglas conocen la categoria de cada premio', () {
    for (final category in GachaCategory.values) {
      final want = categoryRule(category);
      expect(
        rules.contains(want),
        isTrue,
        reason: 'falta en las reglas:\n($want)',
      );
    }
  });

  test('ninguna clave pasa del tope de las reglas de la coleccion', () {
    for (final key in allGachaPrizeKeys) {
      expect(RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(key), isTrue, reason: key);
    }
  });
}
