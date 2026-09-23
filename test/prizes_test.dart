// Ibasho — el catalogo de premios que se ponen y lo que lleva puesto un Tama.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/backend/prizes.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';

void main() {
  test('el catalogo cuadra con el manifiesto y con los SVG', () {
    final manifest = (jsonDecode(File('tool/prizes/prizes.json').readAsStringSync()) as List)
        .cast<Map<String, Object?>>();
    final fromJson = {
      for (final p in manifest)
        for (final v in (p['variants']! as Map).keys) '${p['id']}_$v',
    };
    final fromDart = {
      for (final p in wearablePrizes) ...p.items.map((i) => i.key),
    };
    expect(fromDart, fromJson);
    for (final key in fromDart) {
      expect(File(prizeItem(key)!.asset).existsSync(), isTrue, reason: key);
      expect(TamaOutfit.keyPattern.hasMatch(key), isTrue, reason: key);
    }
    final files = Directory('assets/prizes')
        .listSync()
        .map((f) => f.uri.pathSegments.last.replaceAll('.svg', ''))
        .toSet();
    final fronts = {
      for (final p in wearablePrizes.where((p) => p.front)) ...p.items.map((i) => '${i.key}_front'),
    };
    for (final key in fronts) {
      expect(File('assets/prizes/$key.svg').existsSync(), isTrue, reason: key);
    }
    expect(files, {...fromDart, ...fronts}, reason: 'hay SVG sin premio o premios sin SVG');
  });

  test('cada premio tiene nombre en los dos idiomas', () {
    for (final locale in const [Locale('es'), Locale('en')]) {
      final l = lookupL(locale);
      final fallback = l.prizeName('?');
      for (final p in wearablePrizes) {
        for (final item in p.items) {
          expect(l.prizeName(item.key), isNot(fallback), reason: '${locale.languageCode}: ${item.key}');
        }
      }
    }
  });

  test('los gorros van a la cabeza y el resto son accesorios', () {
    for (final p in wearablePrizes) {
      expect(p.category == GachaCategory.hats, p.slot == PrizeSlot.head, reason: p.id);
    }
  });

  group('TamaOutfit', () {
    PrizeItem item(String key) => prizeItem(key)!;

    test('un gorro sustituye al gorro y tocarlo otra vez lo quita', () {
      var o = TamaOutfit.none.toggle(item('cap_red'))!;
      expect(o.hat, 'cap_red');
      o = o.toggle(item('crown_gold'))!;
      expect(o.hat, 'crown_gold');
      expect(o.toggle(item('crown_gold'))!.hat, isNull);
    });

    test('un accesorio sustituye al de su sitio y no pasa de tres', () {
      var o = TamaOutfit.none.toggle(item('glasses_red'))!;
      o = o.toggle(item('shutter_shades_lime'))!;
      expect(o.accessories, ['shutter_shades_lime']);
      o = o.toggle(item('bowtie_black'))!.toggle(item('angel_wings_white'))!;
      expect(o.accessories, hasLength(3));
      expect(o.toggle(item('bottle_cola')), isNull);
      // Uno del mismo sitio si entra: sustituye.
      expect(o.toggle(item('bowtie_red'))!.accessories, contains('bowtie_red'));
      expect(o.toggle(item('bowtie_black'))!.accessories, hasLength(2));
    });

    test('se guarda solo si lleva algo, y vuelve igual', () {
      const bare = TamaLook();
      expect(bare.toJson().containsKey('hat'), isFalse);
      expect(bare.toJson().containsKey('acc'), isFalse);

      final dressed = bare.withOutfit(
          const TamaOutfit(hat: 'cap_red', accessories: ['glasses_red', 'bowtie_black']));
      final json = dressed.toJson();
      expect(json['hat'], 'cap_red');
      expect(json['acc'], {'a': 'glasses_red', 'b': 'bowtie_black'});
      expect(TamaLook.fromJson(json), dressed);
    });

    test('lee con cuidado lo que venga de fuera', () {
      final o = TamaOutfit.fromJson('Cap Red', 'a,b,c,d,e');
      expect(o.hat, isNull);
      expect(o.accessories, ['a', 'b', 'c']);
      // Los huecos van en orden, y el formato viejo se sigue leyendo.
      expect(TamaOutfit.fromJson(null, {'b': 'bowtie_red', 'a': 'glasses_red', 'z': 'x'}).accessories,
          ['glasses_red', 'bowtie_red']);
      // Una clave que esta version no conoce se conserva.
      expect(TamaOutfit.fromJson('future_hat', null).hat, 'future_hat');
    });
  });
}
