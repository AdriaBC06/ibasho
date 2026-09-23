// Ibasho — el catalogo de fondos del gacha.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/backdrops.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';

void main() {
  test('16 fondos, con el reparto de rareza de los premios', () {
    expect(backdrops.length, 16);
    final byRarity = <Rarity, int>{
      for (final r in Rarity.values) r: backdropsOf(r).length,
    };
    expect(byRarity, <Rarity, int>{
      Rarity.n: 4,
      Rarity.r: 4,
      Rarity.sr: 3,
      Rarity.ssr: 2,
      Rarity.ur: 2,
      Rarity.mu: 1,
    });
  });

  test(
    'cada clave cabe en la clave de premio del gacha (bg_<id>, 16 letras)',
    () {
      final pattern = RegExp(r'^[a-z0-9_]+$');
      final seen = <String>{};
      for (final b in backdrops) {
        expect(b.key, startsWith('bg_'));
        expect(b.key.length, lessThanOrEqualTo(16), reason: b.key);
        expect(pattern.hasMatch(b.key), isTrue, reason: b.key);
        expect(seen.add(b.key), isTrue, reason: 'clave repetida: ${b.key}');
      }
      expect(backdropByKey('bg_no-existe'), isNull);
    },
  );

  test('cada fondo tiene nombre en los dos idiomas', () {
    for (final locale in const [Locale('es'), Locale('en')]) {
      final l = lookupL(locale);
      final fallback = l.backdropName('?');
      for (final b in backdrops) {
        expect(
          l.backdropName(b.key),
          isNot(fallback),
          reason: '${locale.languageCode}: ${b.key}',
        );
      }
    }
  });

  test('backdropById y backdropByKey se corresponden', () {
    for (final b in backdrops) {
      expect(backdropById(b.id), b);
      expect(backdropByKey(b.key), b);
    }
    expect(backdropById(null), isNull);
    expect(backdropById(''), isNull);
    expect(backdropByKey(null), isNull);
  });
}
