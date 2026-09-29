// Ibasho — pruebas del motor de Hatarakitama.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/hatarakitama/hataraki_data.dart';
import 'package:ibasho/games/hatarakitama/hataraki_engine.dart';

const _t0 = 1790000000000;
const _hour = 3600000;

Map<String, HTama> _tamas(
  List<String> ids, {
  TamaPersonality p = TamaPersonality.shy,
  double mood = .5,
}) => {for (final id in ids) id: HTama(id, p, mood)};

void main() {
  group('datos', () {
    test(
      'todo lo que se usa existe y todo lo que se gasta se puede conseguir',
      () {
        final obtainable = <String>{
          for (final a in hActions) ...a.outputs.keys,
          for (final a in hActions) ...a.drops.map((d) => d.item),
          for (final z in hZones) ...z.loot.map((l) => l.item),
        };
        for (final a in hActions) {
          for (final id in [...a.inputs.keys, ...a.outputs.keys]) {
            expect(hItem(id), isNotNull, reason: '${a.id} usa $id');
          }
          for (final id in a.inputs.keys) {
            expect(obtainable, contains(id), reason: '${a.id} gasta $id');
          }
          expect(a.level, inInclusiveRange(0, hMaxLevel));
        }
        for (final z in hZones) {
          for (final l in z.loot) {
            expect(hItem(l.item), isNotNull, reason: '${z.id} da ${l.item}');
          }
        }
        expect(hActionById.length, hActions.length, reason: 'ids repetidos');
      },
    );

    test('cada oficio empieza en el nivel 0', () {
      for (final s in HSkill.workable) {
        expect(hActionsOf(s).map((a) => a.level), contains(0), reason: s.name);
      }
      expect(hZones.first.level, 0);
    });
  });

  group('curva', () {
    test('es la de RuneScape', () {
      expect(hXpForLevel(0), 0);
      expect(hXpForLevel(1), 40);
      expect(hXpForLevel(2), 83);
      expect(hXpForLevel(92), 6517253);
      expect(hXpForLevel(99), 13034431);
      expect(hLevelForXp(0), 0);
      expect(hLevelForXp(39), 0);
      expect(hLevelForXp(40), 1);
      expect(hLevelForXp(82), 1);
      expect(hLevelForXp(83), 2);
      expect(hLevelForXp(13034431), 99);
      expect(hLevelForXp(1 << 30), 99);
    });

    test('las ranuras se abren con el nivel total', () {
      expect(HState.fresh(_t0).slots, 1);
      expect(hSlotsFor(40), 2);
      expect(hSlotsFor(1200), 6);
    });
  });

  group('trabajo', () {
    test('una hora talando da unos 1200 troncos con ánimo medio', () {
      final s = HState.fresh(_t0)..assign('a', 'wc_sugi');
      final r = s.advance(_t0 + _hour, _tamas(['a']));
      // 3 s por tronco a velocidad 1 (ánimo .5) y algo de maestría.
      expect(s.count('log_sugi'), inInclusiveRange(1200, 1350));
      expect(r.levelUps[HSkill.woodcutting], inInclusiveRange(27, 31));
      expect(s.workers.single.progress, inInclusiveRange(0.0, 1.0));
    });

    test('el offline se corta a las 12 horas', () {
      final a = HState.fresh(_t0)..assign('a', 'ag_path');
      final r = a.advance(_t0 + 48 * _hour, _tamas(['a']));
      expect(r.seconds, hOfflineCap.inSeconds);
      expect(a.lastTick, _t0 + 48 * _hour);
    });

    test('trocear el tiempo da lo mismo que de golpe (sin azar)', () {
      final a = HState.fresh(_t0)..assign('a', 'ag_path');
      final b = HState.fresh(_t0)..assign('a', 'ag_path');
      a.advance(_t0 + _hour, _tamas(['a']));
      for (var i = 1; i <= 60; i++) {
        b.advance(_t0 + i * 60000, _tamas(['a']));
      }
      expect(b.xp[HSkill.agility], closeTo(a.xp[HSkill.agility]!, 16));
    });

    test('sin materiales se para y lo avisa', () {
      final s = HState.fresh(_t0)..assign('a', 'fa_rice');
      final r = s.advance(_t0 + 10 * _hour, _tamas(['a']));
      expect(s.count('crop_rice'), greaterThanOrEqualTo(20));
      expect(s.count('seed_rice'), 0);
      expect(s.workers.single.stalled, isTrue);
      expect(r.stalledTamas, {'a'});
    });

    test('la afinidad y el ánimo aceleran', () {
      final calm = HState.fresh(_t0)..assign('a', 'fi_iwashi');
      final shy = HState.fresh(_t0)..assign('a', 'fi_iwashi');
      calm.advance(
        _t0 + _hour,
        _tamas(['a'], p: TamaPersonality.calm, mood: 1),
      );
      shy.advance(_t0 + _hour, _tamas(['a'], mood: 0));
      expect(
        calm.count('fish_iwashi'),
        greaterThan(shy.count('fish_iwashi') * 1.6),
      );
    });

    test('un Tama que ya no existe deja la ranura', () {
      final s = HState.fresh(_t0)..assign('a', 'wc_sugi');
      s.advance(_t0 + 1000, {});
      expect(s.workers, isEmpty);
    });

    test('no se asigna por encima del nivel ni de las ranuras', () {
      final s = HState.fresh(_t0);
      expect(s.assign('a', 'wc_matsu'), isFalse);
      expect(s.assign('a', 'wc_sugi'), isTrue);
      expect(s.assign('b', 'fi_iwashi'), isFalse);
      expect(s.assign('a', 'fi_iwashi'), isTrue);
      expect(s.workers.single.actionId, 'fi_iwashi');
    });

    test('dos Tamas que gastan lo mismo se lo reparten', () {
      final s =
          HState(
              lastTick: _t0,
              xp: {HSkill.woodcutting: hXpForLevel(40)},
              bank: {'log_sugi': 10},
            )
            ..assign('a', 'ca_plank_sugi')
            ..assign('b', 'ca_plank_sugi');
      s.advance(_t0 + _hour, _tamas(['a', 'b']));
      expect(s.count('plank_sugi'), inInclusiveRange(5, 6));
      expect(s.count('log_sugi'), 0);
    });
  });

  group('té', () {
    test('acelera solo mientras dura', () {
      final s = HState.fresh(_t0)..bank['tea_sencha'] = 1;
      expect(s.drinkTea('tea_sencha', _t0), isTrue);
      expect(s.count('tea_sencha'), 0);
      expect(s.teaUntil, _t0 + hTeaDuration.inMilliseconds);
      expect(s.drinkTea('tea_sencha', _t0), isFalse);
    });
  });

  group('expediciones', () {
    test('sale, gasta comida y vuelve con botín', () {
      final s = HState.fresh(_t0)
        ..bank['food_onigiri'] = 10
        ..bank['gear_basket'] = 1;
      expect(s.equip('gear_basket'), isTrue);
      final party = [
        const HTama('a', TamaPersonality.playful, .5),
        const HTama('b', TamaPersonality.calm, .5),
      ];
      expect(s.startExpedition('meadow', party, 'food_onigiri', _t0), isTrue);
      // 2 Tamas × 10 min / 10 = 2 puntos = 1 onigiri.
      expect(s.count('food_onigiri'), 9);
      expect(s.isBusy('a'), isTrue);
      expect(s.assign('a', 'wc_sugi'), isFalse);

      s.advance(_t0 + 5 * 60000, _tamas(['a', 'b']));
      expect(s.expedition, isNotNull);
      final r = s.advance(_t0 + 11 * 60000, _tamas(['a', 'b']));
      expect(s.expedition, isNull);
      expect(r.expeditionZone, 'meadow');
      expect(r.expeditionSuccess, 1.0);
      expect(s.xp[HSkill.expedition], 60);
    });

    test('no sale sin nivel, sin comida o con un Tama ocupado', () {
      final s = HState.fresh(_t0)..assign('a', 'wc_sugi');
      const a = HTama('a', TamaPersonality.calm, .5);
      const b = HTama('b', TamaPersonality.calm, .5);
      expect(s.startExpedition('meadow', [b], 'food_onigiri', _t0), isFalse);
      s.bank['food_onigiri'] = 5;
      expect(s.startExpedition('forest', [b], 'food_onigiri', _t0), isFalse);
      expect(s.startExpedition('meadow', [a], 'food_onigiri', _t0), isFalse);
      expect(s.startExpedition('meadow', [b], 'food_onigiri', _t0), isTrue);
    });

    test('volver antes: sin botín, sin experiencia y los Tamas libres', () {
      final s = HState.fresh(_t0)..bank['food_onigiri'] = 5;
      const a = HTama('a', TamaPersonality.calm, .5);
      expect(s.startExpedition('meadow', [a], 'food_onigiri', _t0), isTrue);
      expect(s.cancelExpedition(), isTrue);
      expect(s.expedition, isNull);
      expect(s.isBusy('a'), isFalse);
      final r = s.advance(_t0 + 20 * 60000, _tamas(['a']));
      expect(r.expeditionZone, isNull);
      expect(s.xp[HSkill.expedition], isNull);
      expect(s.cancelExpedition(), isFalse);
    });

    test('quitar equipo resta su fuerza', () {
      final s = HState.fresh(_t0)..bank['gear_basket'] = 1;
      const a = HTama('a', TamaPersonality.calm, .5);
      final bare = s.partyPower([a]);
      expect(s.equip('gear_basket'), isTrue);
      expect(s.partyPower([a]), bare + 3);
      expect(s.unequip(HGearSlot.bag), isTrue);
      expect(s.partyPower([a]), bare);
      expect(s.unequip(HGearSlot.bag), isFalse);
    });
  });

  test('el ritmo que se enseña es el que se simula', () {
    final s = HState.fresh(_t0);
    const a = HTama('a', TamaPersonality.cheeky, .5);
    final secs = s.secondsFor(hAction('wc_sugi')!, a, _t0);
    expect(s.assign('a', 'wc_sugi'), isTrue);
    s.advance(_t0 + (secs * 10 * 1000).ceil(), {'a': a});
    expect(s.count('log_sugi'), inInclusiveRange(10, 12));
  });

  test('se guarda y se recupera igual (también como mapa de la base)', () {
    final s = HState.fresh(_t0)
      ..assign('a', 'wc_sugi')
      ..bank['tea_sencha'] = 2;
    s.drinkTea('tea_sencha', _t0);
    s.advance(_t0 + _hour, _tamas(['a']));
    final json = jsonDecode(jsonEncode(s.toJson()));
    final back = HState.fromJson(json, _t0);
    expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
    expect(back.workers.single.tamaId, 'a');
    expect(HState.fromJson(null, _t0).count('seed_rice'), 5);
  });

  group('vender', () {
    test('todo tiene precio, y lo hecho vale más que sus materiales', () {
      for (final i in hItems) {
        expect(hSellValue(i.id), greaterThanOrEqualTo(1), reason: i.id);
      }
      for (final a in hActions) {
        if (a.inputs.isEmpty || a.outputs.isEmpty) continue;
        final cost = a.inputs.entries.fold(0, (sum, e) => sum + hSellValue(e.key) * e.value);
        final value = a.outputs.entries.fold(0, (sum, e) => sum + hSellValue(e.key) * e.value);
        expect(value, greaterThanOrEqualTo(cost), reason: a.id);
      }
      expect(hSellValue('log_shinboku'), greaterThan(hSellValue('log_sugi')));
      expect(hSellValue('nada'), 0);
    });

    test('vender quita del almacén y suma mon al día, la semana y siempre', () {
      final s = HState(lastTick: _t0, bank: {'log_sugi': 10});
      final price = hSellValue('log_sugi');
      expect(s.sell('log_sugi', 3, today: 5, thisWeek: 1), 3 * price);
      expect(s.count('log_sugi'), 7);
      // Pide más de lo que hay: vende lo que queda.
      expect(s.sell('log_sugi', 99, today: 5, thisWeek: 1), 7 * price);
      expect(s.count('log_sugi'), 0);
      expect(s.sell('log_sugi', 1, today: 5, thisWeek: 1), 0);
      expect((s.money, s.earned, s.dayMoney, s.weekMoney), (10 * price, 10 * price, 10 * price, 10 * price));
    });

    test('un día nuevo empieza de cero, lo de siempre no', () {
      final s = HState(lastTick: _t0, bank: {'ore_copper': 4});
      final price = hSellValue('ore_copper');
      s.sell('ore_copper', 2, today: 5, thisWeek: 1);
      s.sell('ore_copper', 1, today: 6, thisWeek: 1);
      expect(s.dayMoney, price);
      expect(s.weekMoney, 3 * price);
      s.sell('ore_copper', 1, today: 9, thisWeek: 2);
      expect((s.dayMoney, s.weekMoney, s.earned), (price, price, 4 * price));
    });

    test('vender el equipo puesto lo quita del equipo', () {
      final s = HState(lastTick: _t0, bank: {'gear_basket': 1})..equip('gear_basket');
      s.sell('gear_basket', 1, today: 1, thisWeek: 1);
      expect(s.kit, isEmpty);
    });

    test('los mon se guardan', () {
      final s = HState(lastTick: _t0, bank: {'log_sugi': 5})..sell('log_sugi', 5, today: 3, thisWeek: 2);
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect((back.money, back.earned, back.dayMoney, back.weekMoney), (s.money, s.earned, s.dayMoney, s.weekMoney));
    });
  });
}
