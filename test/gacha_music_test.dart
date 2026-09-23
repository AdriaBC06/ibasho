// Ibasho — el catalogo de musica del gacha.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/audio/audio_service.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/backend/gacha_music.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/ui/track_text.dart';

void main() {
  test('6 pistas, con un reparto de rareza razonable para 6 huecos', () {
    expect(gachaMusicTracks.length, 6);
    final byRarity = <Rarity, int>{
      for (final r in Rarity.values) r: gachaMusicOf(r).length,
    };
    expect(byRarity, <Rarity, int>{
      Rarity.n: 2,
      Rarity.r: 1,
      Rarity.sr: 1,
      Rarity.ssr: 0,
      Rarity.ur: 1,
      Rarity.mu: 1,
    });
  });

  test(
    'cada clave cabe en la clave de premio del gacha (mu_<id>)',
    () {
      final pattern = RegExp(r'^[a-z0-9_]+$');
      final seen = <String>{};
      for (final m in gachaMusicTracks) {
        expect(m.key, startsWith('mu_'));
        expect(pattern.hasMatch(m.key), isTrue, reason: m.key);
        expect(seen.add(m.key), isTrue, reason: 'clave repetida: ${m.key}');
      }
      expect(gachaMusicByKey('mu_no-existe'), isNull);
    },
  );

  test('gachaMusicById y gachaMusicByKey se corresponden', () {
    for (final m in gachaMusicTracks) {
      expect(gachaMusicById(m.id), m);
      expect(gachaMusicByKey(m.key), m);
    }
    expect(gachaMusicById(null), isNull);
    expect(gachaMusicById(''), isNull);
    expect(gachaMusicByKey(null), isNull);
  });

  test('cada pista del gacha tiene una entrada en MusicTrack, sin unlockedByDefault', () {
    for (final m in gachaMusicTracks) {
      final track = MusicTrack.byId(m.id);
      expect(track.id, m.id, reason: 'MusicTrack.byId no conoce ${m.id}');
      expect(track.unlockedByDefault, isFalse, reason: '${m.id} no deberia ir de serie');
    }
  });

  test('cada pista del gacha tiene descripcion en los dos idiomas', () {
    for (final locale in const [Locale('es'), Locale('en')]) {
      final l = lookupL(locale);
      for (final m in gachaMusicTracks) {
        final track = MusicTrack.byId(m.id);
        expect(
          describeTrack(l, track).isNotEmpty,
          isTrue,
          reason: '${locale.languageCode}: ${m.id}',
        );
      }
    }
  });
}
