// Ibasho — pruebas del motor de Hatarakitama.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/hatarakitama/hataraki_data.dart';
import 'package:ibasho/games/hatarakitama/hataraki_engine.dart';
import 'package:ibasho/games/hatarakitama/hataraki_home.dart';
import 'package:ibasho/games/hatarakitama/hataraki_map.dart';
import 'package:ibasho/games/hatarakitama/hataraki_orders.dart';
import 'package:ibasho/games/hatarakitama/hataraki_town.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/hataraki.dart';

import 'support/fakes.dart';

const _t0 = 1790000000000;
const _hour = 3600000;
const _day = 20000;

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
          hParcel,
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

    test('cada objeto se consigue o se usa, y tiene nombre', () {
      final used = <String>{
        for (final a in hActions) ...a.inputs.keys,
        for (final a in hActions) ...a.outputs.keys,
        for (final a in hActions) ...a.drops.map((d) => d.item),
        for (final z in hZones) ...z.loot.map((l) => l.item),
        hParcel,
        // Los muebles que solo se venden en la tienda.
        ...hShopFurniture,
      };
      for (final lang in ['es', 'en']) {
        final l = lookupL(Locale(lang));
        for (final i in hItems) {
          expect(used, contains(i.id), reason: '${i.id} no sale de nada');
          expect(i.id, matches(RegExp(r'^[a-z0-9_]{1,24}$')));
          expect(l.hatarakiItemName(i.id), isNot('?'), reason: i.id);
        }
        for (final s in HSkill.values) {
          expect(l.hatarakiSkillName(s.name), isNot('?'), reason: s.name);
          expect(l.hatarakiSkillAbout(s.name), isNot('?'), reason: s.name);
        }
      }
    });

    test('la maña reparte los 20 oficios, 4 por personalidad', () {
      expect(HSkill.values, hasLength(20));
      final all = [for (final set in hAffinities.values) ...set];
      expect(all.toSet(), HSkill.values.toSet());
      expect(all, hasLength(HSkill.values.length));
      for (final set in hAffinities.values) {
        expect(set, hasLength(4));
      }
    });

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
      expect(hSlotsFor(700), 6);
      expect(hSlotsFor(1980), 8);
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

    HState chain() =>
        HState(
            lastTick: _t0,
            xp: {
              HSkill.woodcutting: hXpForLevel(20),
              HSkill.carpentry: hXpForLevel(8),
              HSkill.agility: hXpForLevel(20),
            },
          )
          ..assign('tala', 'wc_take')
          ..assign('cesta', 'ca_basket');

    test('en cadena, el que se queda sin material sigue cuando llega', () {
      final s = chain();
      final r = s.advance(_t0 + 12 * _hour, _tamas(['tala', 'cesta']));
      // Las cestas van al ritmo de la caña: unos 9000 troncos, dos por cesta.
      expect(s.count('gear_basket'), greaterThan(3500));
      expect(s.count('log_take'), lessThan(4));
      expect(r.stalledTamas.length, lessThanOrEqualTo(1));
    });

    test('la cadena da lo mismo segundo a segundo que de golpe', () {
      final a = chain(), b = chain();
      final tamas = _tamas(['tala', 'cesta']);
      a.advance(_t0 + 600000, tamas);
      for (var i = 1; i <= 600; i++) {
        b.advance(_t0 + i * 1000, tamas);
      }
      expect(b.count('gear_basket'), greaterThan(40));
      expect(b.count('gear_basket'), closeTo(a.count('gear_basket'), 3));
    });

    test('un parado vuelve en cuanto hay material en el almacén', () {
      final s = HState.fresh(_t0)..assign('a', 'fa_rice');
      s.advance(_t0 + 10 * _hour, _tamas(['a']));
      expect(s.workers.single.stalled, isTrue);
      s.bank['seed_rice'] = 3;
      final r = s.advance(_t0 + 10 * _hour + 60000, _tamas(['a']));
      expect(r.spent['seed_rice'], greaterThanOrEqualTo(3));
      expect(s.count('crop_rice'), greaterThan(0));
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

  group('oficios nuevos', () {
    HState at(Map<HSkill, int> levels, Map<String, int> bank) => HState(
      lastTick: _t0,
      seed: 7,
      xp: {for (final e in levels.entries) e.key: hXpForLevel(e.value)},
      bank: bank,
    );

    test('con 1100 de nivel total hay 8 ranuras', () {
      expect(hSlotsFor(1099), 7);
      expect(hSlotsFor(1100), 8);
      expect(hSlotThresholds, hasLength(8));
    });

    test('el cebo se gasta y, al acabarse, se sigue pescando', () {
      final s = at({}, {'bait_worm': 5})..assign('a', 'fi_iwashi');
      expect(s.setBoost('a', 'bait_worm'), isTrue);
      s.advance(_t0 + 60000, _tamas(['a']));
      expect(s.count('bait_worm'), 0);
      expect(s.count('fish_iwashi'), greaterThan(10));
      expect(s.workers.single.stalled, isFalse);
      expect(s.workers.single.boost, 'bait_worm');
    });

    test('el cebo solo vale para su oficio', () {
      final s = at({}, {'bait_worm': 5, 'fert_compost': 5})
        ..assign('a', 'fi_iwashi');
      expect(s.setBoost('a', 'fert_compost'), isFalse);
      expect(s.setBoost('a', 'nada'), isFalse);
      s.setBoost('a', 'bait_worm');
      // Cambiar a otro oficio lo quita.
      s.assign('a', 'wc_sugi');
      expect(s.workers.single.boost, isNull);
    });

    test('el abono da una cosecha más cada vez', () {
      final plain = at({}, {'seed_rice': 3})..assign('a', 'fa_rice');
      final fed = at({}, {'seed_rice': 3, 'fert_compost': 3})
        ..assign('a', 'fa_rice')
        ..setBoost('a', 'fert_compost');
      plain.advance(_t0 + 40000, _tamas(['a']));
      fed.advance(_t0 + 40000, _tamas(['a']));
      expect(fed.count('crop_rice') - plain.count('crop_rice'), 3);
    });

    test('la mecha saca más gemas', () {
      int gems(HState s) => [
        'gem_quartz',
        'gem_amethyst',
        'gem_sapphire',
        'gem_ruby',
      ].fold(0, (n, g) => n + s.count(g));
      final plain = at({}, {})..assign('a', 'mi_copper');
      final lit = at({}, {'fuse_star': 99999})
        ..assign('a', 'mi_copper')
        ..setBoost('a', 'fuse_star');
      plain.advance(_t0 + 10 * _hour, _tamas(['a']));
      lit.advance(_t0 + 10 * _hour, _tamas(['a']));
      expect(gems(lit), greaterThan(gems(plain) * 3));
    });

    test('estudiar gasta libros, no da nada y sube la experiencia de todo', () {
      final s = at({}, {'book_notes': 2})..assign('a', 'st_notes');
      final r = s.advance(_t0 + _hour, _tamas(['a']));
      expect(s.count('book_notes'), 0);
      expect(r.gained, isEmpty);
      expect(s.xp[HSkill.study], 120);
      expect(s.workers.single.stalled, isTrue);

      final wise = at({HSkill.study: 50}, {})..assign('a', 'ag_path');
      final plain = at({}, {})..assign('a', 'ag_path');
      wise.advance(_t0 + _hour, _tamas(['a']));
      plain.advance(_t0 + _hour, _tamas(['a']));
      expect(
        wise.xp[HSkill.agility]! / plain.xp[HSkill.agility]!,
        inInclusiveRange(1.04, 1.08),
      );
    });

    test('la cadena de cerámica a brebajes funciona', () {
      final s =
          at(
              {HSkill.pottery: 12, HSkill.foraging: 12},
              {'clay': 200, 'log_matsu': 100},
            )
            ..assign('a', 'po_flask')
            ..assign('b', 'fo_yomogi')
            ..assign('c', 'fo_spring')
            ..assign('d', 'br_heal');
      // Sin ranuras de sobra con nivel bajo: se dan a mano.
      s.workers
        ..clear()
        ..addAll([
          HWorker('a', 'po_flask'),
          HWorker('b', 'fo_yomogi'),
          HWorker('c', 'fo_spring'),
          HWorker('d', 'br_heal'),
        ]);
      s.advance(_t0 + _hour, _tamas(['a', 'b', 'c', 'd']));
      expect(s.count('potion_heal'), greaterThan(100));
      expect(s.count('soot'), greaterThan(0));
    });

    test('la tetera alarga el té', () {
      final s = at({}, {'tea_sencha': 2});
      s.drinkTea('tea_sencha', _t0);
      expect(s.teaUntil, _t0 + 30 * 60000);
      s.bank['pot_teapot'] = 1;
      s.drinkTea('tea_sencha', _t0);
      expect(s.teaUntil, _t0 + 45 * 60000);
    });

    test('la ropa teñida suma en los sitios de su color', () {
      final s = at({}, {'gear_ai_happi': 1})..equip('gear_ai_happi');
      final party = [HTama('a', TamaPersonality.shy, .5)];
      expect(s.partyPower(party, 'river') - s.partyPower(party, 'forest'), 10);
    });

    test('el cebo se guarda con la ranura', () {
      final s = at({}, {'bait_lure': 2})
        ..assign('a', 'fi_iwashi')
        ..setBoost('a', 'bait_lure');
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect(back.workers.single.boost, 'bait_lure');
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
    HTripPlan plan(
      String zone, {
      String food = 'food_onigiri',
      int day = _day,
    }) => HTripPlan(
      zone: zone,
      route: hZoneMap(zone, day).defaultRoute,
      food: food,
    );

    test('sale, gasta comida y pasa casilla a casilla', () {
      final s = HState.fresh(_t0)
        ..bank['food_onigiri'] = 10
        ..bank['gear_basket'] = 1;
      expect(s.equip('gear_basket'), isTrue);
      final party = [
        const HTama('a', TamaPersonality.playful, .5),
        const HTama('b', TamaPersonality.calm, .5),
      ];
      final p = plan('meadow');
      final units = s.foodUnits(p, 2, _day);
      expect(units, greaterThan(0));
      expect(s.startExpedition(p, party, _t0, _day), isTrue);
      expect(s.count('food_onigiri'), 10 - units);
      expect(s.isBusy('a'), isTrue);
      expect(s.assign('a', 'wc_sugi'), isFalse);
      final trip = s.expeditions.single;
      expect(trip.route.length, 4);
      expect(trip.at.length, 4);

      final r1 = s.advance(trip.at[0], _tamas(['a', 'b']));
      expect(trip.done, 1);
      expect(r1.nodes, hasLength(1));
      expect(s.expeditions, isNotEmpty);
      final r = s.advance(trip.endsAt + 1000, _tamas(['a', 'b']));
      expect(s.expeditions, isEmpty);
      expect(r.expeditionZone, 'meadow');
      expect(r.expeditionSuccess, 1.0);
      expect(s.xp[HSkill.expedition], 60);
    });

    test('no sale sin nivel, sin comida, sin ruta o con un Tama ocupado', () {
      final s = HState.fresh(_t0)..assign('a', 'wc_sugi');
      const a = HTama('a', TamaPersonality.calm, .5);
      const b = HTama('b', TamaPersonality.calm, .5);
      expect(s.tripProblem(plan('meadow'), [b], _day), 'food');
      s.bank['food_onigiri'] = 50;
      expect(s.tripProblem(plan('forest'), [b], _day), 'level');
      expect(s.tripProblem(plan('meadow'), [a], _day), 'busy');
      expect(s.tripProblem(plan('meadow'), [], _day), 'party');
      final bad = HTripPlan(
        zone: 'meadow',
        route: const [0],
        food: 'food_onigiri',
      );
      expect(s.tripProblem(bad, [b], _day), 'route');
      final pricey = HTripPlan(
        zone: 'meadow',
        route: plan('meadow').route,
        food: 'food_onigiri',
        cart: true,
      );
      expect(s.tripProblem(pricey, [b], _day), 'money');
      expect(s.startExpedition(plan('meadow'), [b], _t0, _day), isTrue);
      // Uno a la vez hasta la posada a nivel 5.
      expect(s.tripProblem(plan('meadow'), [b], _day), 'trips');
    });

    test('volver antes: se queda lo de las casillas pasadas', () {
      final s = HState.fresh(_t0)..bank['food_onigiri'] = 5;
      const a = HTama('a', TamaPersonality.calm, .5);
      expect(s.startExpedition(plan('meadow'), [a], _t0, _day), isTrue);
      final trip = s.expeditions.single;
      final before = Map.of(s.bank);
      s.advance(trip.at[0] + 1, _tamas(['a']));
      final gained = trip.log.single;
      expect(s.cancelExpedition('meadow'), isTrue);
      expect(s.expeditions, isEmpty);
      expect(s.isBusy('a'), isFalse);
      for (final e in gained.entries) {
        if (e.key == 'prize') continue;
        expect(s.count(e.key), (before[e.key] ?? 0) + e.value);
      }
      final xp = s.xp[HSkill.expedition];
      expect(xp, greaterThan(0));
      final r = s.advance(trip.endsAt + 1000, _tamas(['a']));
      expect(r.expeditionZone, isNull);
      expect(s.xp[HSkill.expedition], xp);
      expect(s.cancelExpedition('meadow'), isFalse);
    });

    test('el mapa: el mismo cada día, de 4 a 6 columnas, todo unido', () {
      for (final z in hZones) {
        final m = hZoneMap(z.id, _day);
        expect(m.columns.length, hMapColumns(z));
        expect(
          [for (final n in m.columns.expand((c) => c)) n.kind],
          [
            for (final n in hZoneMap(z.id, _day).columns.expand((c) => c))
              n.kind,
          ],
        );
        for (var c = 0; c < m.columns.length; c++) {
          expect(m.columns[c].length, inInclusiveRange(2, 3));
          for (final n in m.columns[c]) {
            if (c > 0) {
              expect(m.columns[c - 1].any((p) => p.leadsTo(n)), isTrue);
            }
            if (c < m.columns.length - 1) {
              expect(m.columns[c + 1].any(n.leadsTo), isTrue);
            }
          }
        }
        expect(m.isValid(m.defaultRoute), isTrue);
        // Tocar cualquier casilla deja una ruta buena que pasa por ella.
        for (final n in m.columns.expand((c) => c)) {
          final r = m.routeThrough(m.defaultRoute, n.col, n.row);
          expect(m.isValid(r), isTrue);
          expect(r[n.col], n.row);
        }
      }
      expect(hMapColumns(hZones.first), 4);
      expect(hMapColumns(hZones.last), 6);
      final days = {
        for (var d = 0; d < 10; d++)
          [
            for (final n in hZoneMap('moon', _day + d).columns.expand((c) => c))
              n.kind,
          ].join(),
      };
      expect(days.length, greaterThan(1));
    });

    test('peligros: sin fuerza se tarda más; con poción de cura se pasan', () {
      // Un día en que el mapa de la luna tiene un peligro en la ruta.
      late HZoneMap m;
      late List<int> route;
      for (var d = _day; ; d++) {
        m = hZoneMap('moon', d);
        final danger = m.columns
            .expand((c) => c)
            .where((n) => n.kind == HNodeKind.danger)
            .firstOrNull;
        if (danger == null) continue;
        route = m.routeThrough(m.defaultRoute, danger.col, danger.row);
        break;
      }
      HState fresh() => HState.fresh(_t0)
        ..xp[HSkill.expedition] = hXpForLevel(99)
        ..bank['food_feast'] = 50
        ..bank['potion_heal'] = 1;
      const a = HTama('a', TamaPersonality.calm, .5);
      final weak = fresh();
      final p = HTripPlan(zone: 'moon', route: route, food: 'food_feast');
      expect(weak.startExpedition(p, [a], _t0, m.day), isTrue);
      final slow = weak.expeditions.single;
      expect(slow.fails, isNotEmpty);
      final healed = fresh();
      final withHeal = HTripPlan(
        zone: 'moon',
        route: route,
        food: 'food_feast',
        supply: 'potion_heal',
      );
      expect(healed.startExpedition(withHeal, [a], _t0, m.day), isTrue);
      final fast = healed.expeditions.single;
      expect(healed.count('potion_heal'), 0);
      expect(fast.fails.length, slow.fails.length - 1);
      expect(fast.endsAt, lessThan(slow.endsAt));
    });

    test('servicios: carro, porteador y guía cuestan ginmon', () {
      final s = HState.fresh(_t0)
        ..bank['food_onigiri'] = 20
        ..xp[HSkill.expedition] = hXpForLevel(30)
        ..money = 1000;
      const a = HTama('a', TamaPersonality.calm, .5);
      final zone = hZoneById['meadow']!;
      final base = plan('meadow');
      expect(s.guided('meadow', _day), isFalse);
      expect(s.hireGuide('meadow', _day), isTrue);
      expect(s.guided('meadow', _day), isTrue);
      expect(s.guided('meadow', _day + 1), isFalse);
      expect(s.hireGuide('meadow', _day), isFalse);
      expect(s.money, 1000 - hGuidePrice(zone));
      final served = HTripPlan(
        zone: 'meadow',
        route: base.route,
        food: 'food_onigiri',
        porter: true,
        cart: true,
      );
      final money = s.money;
      expect(s.startExpedition(served, [a], _t0, _day), isTrue);
      expect(s.money, money - hPorterPrice(zone) - hCartPrice(zone));
      final trip = s.expeditions.single;
      final minutes = hZoneMap('meadow', _day).minutesOf(base.route);
      expect(
        trip.endsAt - _t0,
        closeTo(minutes * 60000 * (1 - hCartTime), 1000),
      );
      expect(trip.porter, isTrue);
    });

    test('la posada a nivel 5: dos viajes a la vez', () {
      final s = HState.fresh(_t0)
        ..bank['food_onigiri'] = 50
        ..xp[HSkill.expedition] = hXpForLevel(20)
        ..town[HBuilding.inn] = 5;
      const a = HTama('a', TamaPersonality.calm, .5);
      const b = HTama('b', TamaPersonality.calm, .5);
      expect(s.maxTrips, 2);
      expect(s.startExpedition(plan('meadow'), [a], _t0, _day), isTrue);
      expect(s.tripProblem(plan('meadow'), [b], _day), 'trips');
      expect(s.startExpedition(plan('forest'), [b], _t0, _day), isTrue);
      expect(s.expeditions, hasLength(2));
      // Fuera 12 h: vuelven los dos, con cada casilla en su hora.
      final r = s.advance(_t0 + 12 * _hour, _tamas(['a', 'b']));
      expect(s.expeditions, isEmpty);
      expect(r.nodes.length, 4 + hMapColumns(hZoneById['forest']!));
    });

    test('se guarda la ruta y se lee el viaje de antes del mapa', () {
      final s = HState.fresh(_t0)..bank['food_onigiri'] = 5;
      const a = HTama('a', TamaPersonality.calm, .5);
      expect(s.startExpedition(plan('meadow'), [a], _t0, _day), isTrue);
      final trip = s.expeditions.single;
      s.advance(trip.at[1] + 1, _tamas(['a']));
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      final again = back.expeditions.single;
      expect(again.route, trip.route);
      expect(again.at, trip.at);
      expect(again.done, 2);
      expect(again.log, trip.log);
      // 0.7.0: un solo viaje en `expedition`, sin ruta: vuelve de golpe.
      final old = HState.fromJson({
        'last': _t0,
        'seed': 1,
        'expedition': {
          'zone': 'meadow',
          'tamas': ['a'],
          'start': _t0,
          'end': _t0 + 600000,
          'power': 10,
        },
      }, _t0);
      expect(old.expeditions.single.route, isEmpty);
      final r = old.advance(_t0 + 700000, _tamas(['a']));
      expect(r.expeditionZone, 'meadow');
      expect(old.expeditions, isEmpty);
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

  group('encargos', () {
    HState game() => HState.fresh(_t0)
      ..seed = 7
      ..xp[HSkill.woodcutting] = hXpForLevel(30)
      ..xp[HSkill.cooking] = hXpForLevel(20)
      ..xp[HSkill.fishing] = hXpForLevel(15);

    test(
      'cada día un gran encargo y tres normales, de lo que se sabe hacer',
      () {
        final s = game();
        expect(s.refreshOrders(_day), isTrue);
        expect(s.refreshOrders(_day), isFalse);
        expect(s.orders, hasLength(4));
        expect(s.orders.first.big, isTrue);
        expect(s.orders.skip(1).every((o) => !o.big), isTrue);
        expect(s.orders.first.wants.length, greaterThanOrEqualTo(2));
        for (final o in s.orders) {
          expect(o.money, greaterThan(0));
          for (final id in o.wants.keys) {
            if (id == hParcel) continue;
            final makers = hActions.where((a) => a.outputs.containsKey(id));
            expect(makers.any(s.canDo), isTrue, reason: id);
          }
        }
        // Los normales, de oficios distintos.
        final skills = {
          for (final o in s.orders.skip(1)) hItemSkill(o.wants.keys.first),
        };
        expect(skills, hasLength(3));
        // El mismo día y la misma partida, lo mismo; otro día, otros.
        final again = game()..refreshOrders(_day);
        expect(
          jsonEncode([for (final o in again.orders) o.toJson()]),
          jsonEncode([for (final o in s.orders) o.toJson()]),
        );
        final before = jsonEncode([for (final o in s.orders) o.toJson()]);
        expect(s.refreshOrders(_day + 1), isTrue);
        expect(
          jsonEncode([for (final o in s.orders) o.toJson()]),
          isNot(before),
        );
      },
    );

    test('con el tablón mejorado hay más encargos y pagan más', () {
      final s = game()..refreshOrders(_day);
      s.town[HBuilding.board] = 4;
      expect(s.refreshOrders(_day), isTrue);
      expect(s.orders, hasLength(1 + 5));
      expect(hBoardSlots(1), 3);
      expect(hBoardSlots(5), 5);
      expect(s.townLevel(HBuilding.board), 4);
      expect(HState.fresh(_t0).townLevel(HBuilding.board), 1);
    });

    test('entregar gasta lo pedido, paga y cuenta para la riqueza', () {
      final s = game()..refreshOrders(_day);
      final o = s.orders[1];
      expect(s.canDeliver(1), isFalse);
      expect(s.deliver(1, today: _day, thisWeek: 3), isFalse);
      for (final e in o.wants.entries) {
        s.bank[e.key] = e.value + 2;
      }
      final xp = s.xp[o.skill] ?? 0;
      expect(s.deliver(1, today: _day, thisWeek: 3), isTrue);
      expect(o.done, isTrue);
      for (final id in o.wants.keys) {
        expect(s.count(id), 2);
      }
      expect(s.money, o.money);
      expect(s.earned, o.money);
      expect(s.dayMoney, o.money);
      if (o.skill != null) expect(s.xp[o.skill]!, greaterThan(xp));
      if (o.gift != null) expect(s.count(o.gift!), greaterThan(0));
      expect(s.orderTicket, isFalse);
      expect(s.deliver(1, today: _day, thisWeek: 3), isFalse);
    });

    test('el gran encargo deja un ticket por cobrar', () {
      final s = game()..refreshOrders(_day);
      for (final e in s.orders.first.wants.entries) {
        s.bank[e.key] = e.value;
      }
      expect(s.deliver(0, today: _day, thisWeek: 3), isTrue);
      expect(s.orderTicket, isTrue);
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect(back.orderTicket, isTrue);
      expect(back.orders.first.done, isTrue);
    });

    test('se cambia un encargo al día, pagando, y el grande no', () {
      final s = game()..refreshOrders(_day);
      final old = jsonEncode(s.orders[2].toJson());
      final price = s.orders[2].swapPrice;
      expect(s.swapOrder(2, _day), isFalse, reason: 'sin ginmon');
      s.money = price * 3;
      expect(s.canSwap(0, _day), isFalse);
      expect(s.swapOrder(2, _day), isTrue);
      expect(s.money, price * 2);
      expect(jsonEncode(s.orders[2].toJson()), isNot(old));
      expect(s.swapOrder(3, _day), isFalse, reason: 'uno al día');
      s.refreshOrders(_day + 1);
      expect(s.canSwap(3, _day + 1), isTrue);
    });

    test('se guarda y se recupera', () {
      final s = game()..refreshOrders(_day);
      s
        ..swapDay = _day
        ..orderDay = _day - 1;
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect(back.ordersDay, _day);
      expect(back.swapDay, _day);
      expect(back.orderDay, _day - 1);
      expect(
        jsonEncode([for (final o in back.orders) o.toJson()]),
        jsonEncode([for (final o in s.orders) o.toJson()]),
      );
      // Sin encargos guardados, el tablón se llena al entrar.
      final fresh = HState.fromJson({'last': _t0, 'seed': 3}, _t0);
      expect(fresh.orders, isEmpty);
      expect(fresh.refreshOrders(_day), isTrue);
    });

    test('cada mapa tiene una casilla de encargo y da un paquete', () {
      for (final z in hZones) {
        for (final day in [_day, _day + 1, _day + 2]) {
          final m = hZoneMap(z.id, day);
          final nodes = m.columns
              .expand((c) => c)
              .where((n) => n.kind == HNodeKind.order)
              .toList();
          expect(nodes, hasLength(1), reason: '${z.id} $day');
          expect(nodes.single.col, inInclusiveRange(1, m.columns.length - 2));
        }
      }
      final m = hZoneMap('meadow', _day);
      final node = m.columns
          .expand((c) => c)
          .firstWhere((n) => n.kind == HNodeKind.order);
      final s = HState.fresh(_t0)..bank['food_onigiri'] = 10;
      final p = HTripPlan(
        zone: 'meadow',
        route: m.routeThrough(m.defaultRoute, node.col, node.row),
        food: 'food_onigiri',
        porter: true,
      );
      s.money = p.price;
      const a = HTama('a', TamaPersonality.calm, .5);
      expect(s.startExpedition(p, [a], _t0, _day), isTrue);
      s.advance(s.expeditions.single.endsAt + 1000, _tamas(['a']));
      expect(s.count(hParcel), 1);
    });
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
        final cost = a.inputs.entries.fold(
          0,
          (sum, e) => sum + hSellValue(e.key) * e.value,
        );
        final value = a.outputs.entries.fold(
          0,
          (sum, e) => sum + hSellValue(e.key) * e.value,
        );
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
      expect(
        (s.money, s.earned, s.dayMoney, s.weekMoney),
        (10 * price, 10 * price, 10 * price, 10 * price),
      );
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
      final s = HState(lastTick: _t0, bank: {'gear_basket': 1})
        ..equip('gear_basket');
      s.sell('gear_basket', 1, today: 1, thisWeek: 1);
      expect(s.kit, isEmpty);
    });

    test('los mon se guardan', () {
      final s = HState(lastTick: _t0, bank: {'log_sugi': 5})
        ..sell('log_sugi', 5, today: 3, thisWeek: 2);
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect(
        (back.money, back.earned, back.dayMoney, back.weekMoney),
        (s.money, s.earned, s.dayMoney, s.weekMoney),
      );
    });
  });

  group('pueblo', () {
    HState rich() => HState(
      lastTick: _t0,
      bank: {'build_beam': 20, 'build_frame': 10, 'bar_bronze': 10},
      xp: {HSkill.construction: hXpForLevel(20)},
    )..money = 100000;

    test('construir gasta ginmon y piezas, pero no resta riqueza', () {
      final s = rich()..earned = 500;
      final cost = hBuildCost(HBuilding.workshop, 1);
      expect(s.build(HBuilding.workshop), isTrue);
      expect(s.townLevel(HBuilding.workshop), 1);
      expect(s.money, 100000 - cost.money);
      expect(s.count('build_beam'), 20 - cost.items['build_beam']!);
      expect(s.earned, 500);
    });

    test('sin piezas, ginmon o nivel de construcción no se construye', () {
      expect(
        HState(lastTick: _t0, bank: {'build_beam': 20}).build(HBuilding.kiln),
        isFalse,
      );
      expect(
        (HState(lastTick: _t0)..money = 99999).build(HBuilding.kiln),
        isFalse,
      );
      final s = rich()..town[HBuilding.kiln] = 2;
      // El nivel 3 pide construcción 40.
      s.bank.addAll({'build_wall': 20, 'build_roof': 20, 'pot_brick': 20});
      expect(s.build(HBuilding.kiln), isFalse);
      s.xp[HSkill.construction] = hXpForLevel(40);
      expect(s.build(HBuilding.kiln), isTrue);
      expect(s.nextBuildCost(HBuilding.kiln)!.construction, 60);
    });

    test('no pasa del nivel 5 y se guarda', () {
      final s = HState(lastTick: _t0, town: {HBuilding.dock: 5});
      expect(s.nextBuildCost(HBuilding.dock), isNull);
      expect(s.canBuild(HBuilding.dock), isFalse);
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect(back.townLevel(HBuilding.dock), 5);
    });

    test('el taller acelera lo que transforma y el muelle la pesca', () {
      final tama = HTama('a', TamaPersonality.shy, .5);
      final s = HState(lastTick: _t0);
      final cook = hAction('co_onigiri')!;
      final fish = hAction('fi_iwashi')!;
      final before = (
        s.secondsFor(cook, tama, _t0),
        s.secondsFor(fish, tama, _t0),
      );
      s.town
        ..[HBuilding.workshop] = 5
        ..[HBuilding.dock] = 2;
      expect(s.secondsFor(cook, tama, _t0), closeTo(before.$1 / 1.2, 1e-9));
      expect(s.secondsFor(fish, tama, _t0), closeTo(before.$2 / 1.1, 1e-9));
    });

    test('la biblioteca y la torre abren tareas', () {
      final s = HState(
        lastTick: _t0,
        xp: {HSkill.writing: hXpForLevel(99), HSkill.magic: hXpForLevel(99)},
      );
      expect(s.assign('a', 'wr_tome'), isFalse);
      expect(s.assign('a', 'wr_basic'), isTrue);
      s.town[HBuilding.library] = 2;
      expect(s.assign('a', 'wr_tome'), isTrue);
      expect(s.canDo(hAction('ma_star')!), isFalse);
      s.town[HBuilding.tower] = 4;
      expect(s.canDo(hAction('ma_star')!), isTrue);
      for (final id in hActionGates.keys) {
        expect(hAction(id), isNotNull, reason: id);
      }
    });

    test('la posada: menos comida y, a nivel 3, cuatro Tamas', () {
      final zone = hZones.last;
      final s = HState(lastTick: _t0);
      expect(s.maxParty, 3);
      final full = s.foodFor(zone.minutes, 3);
      s.town[HBuilding.inn] = 3;
      expect(s.maxParty, 4);
      expect(s.foodFor(zone.minutes, 3), lessThan(full));
    });

    test('la tienda: la misma cada día, a 4 veces, con existencias', () {
      expect(hShop(100, 0, hSellValue), isEmpty);
      final a = hShop(100, 5, hSellValue);
      expect(a.length, 8);
      expect(
        [for (final o in a) o.item],
        [for (final o in hShop(100, 5, hSellValue)) o.item],
      );
      expect([
        for (final o in hShop(101, 5, hSellValue)) o.item,
      ], isNot([for (final o in a) o.item]));
      for (final o in a) {
        expect(o.price, hSellValue(o.item) * hShopMarkup);
        expect(hItem(o.item), isNotNull);
      }
      final s = HState(lastTick: _t0, town: {HBuilding.shop: 1})
        ..money = 100000;
      final offer = s.shop(100).first;
      expect(s.buy(offer.item, 999, 100), offer.stock);
      expect(s.count(offer.item), offer.stock);
      expect(s.money, 100000 - offer.stock * offer.price);
      expect(s.buy(offer.item, 1, 100), 0, reason: 'agotado');
      // Al día siguiente la tienda es otra y se vuelve a poder comprar.
      final next = s.shop(101).first;
      expect(s.buy(next.item, 1, 101), 1);
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect(back.shopDay, 101);
      expect(back.shopBought, {next.item: 1});
    });

    test('sin ginmon no se compra', () {
      final s = HState(lastTick: _t0, town: {HBuilding.shop: 1});
      expect(s.buy(s.shop(7).first.item, 1, 7), 0);
    });

    test('la lonja: igual para todos, sube y baja según el día', () {
      final m = hMarket(50);
      expect(m.where((x) => x.pct > 0).length, hMarketUps);
      expect(m.where((x) => x.pct < 0).length, 2);
      for (final x in m) {
        expect(
          x.pct,
          x.pct > 0 ? inInclusiveRange(.25, 1) : inInclusiveRange(-.5, -.2),
        );
      }
      // Lo que sube y lo que baja nunca es el mismo oficio.
      final upSkills = {
        for (final x in m)
          if (x.pct > 0) x.skill,
      };
      for (final x in m.where((x) => x.pct < 0)) {
        expect(upSkills, isNot(contains(x.skill)));
      }
      expect([for (final x in hMarket(50)) x.pct], [for (final x in m) x.pct]);
      // La lonja solo lo enseña: más cuanto más nivel.
      expect(hMarketSeen(m, 0), isEmpty);
      for (var level = 1; level <= 5; level++) {
        final seen = hMarketSeen(m, level);
        expect(seen.where((x) => x.pct > 0).length, level + 1);
        expect(seen.where((x) => x.pct < 0).length, 2);
        expect(seen.every(m.contains), isTrue);
      }
    });

    test('los precios del día valen sin lonja', () {
      const day = 77;
      final up = hMarket(day).firstWhere((m) => m.item != null);
      final none = HState(lastTick: _t0);
      final built = HState(lastTick: _t0, town: {HBuilding.market: 1});
      expect(none.marketSeen(day), isEmpty);
      expect(none.priceOf(up.item!, day), greaterThan(hSellValue(up.item!)));
      expect(none.priceOf(up.item!, day), built.priceOf(up.item!, day));
    });

    test('vender con la lonja paga lo del día', () {
      const day = 77;
      final up = hMarket(day).firstWhere((m) => m.item != null);
      final s = HState(
        lastTick: _t0,
        bank: {up.item!: 10},
        town: {HBuilding.market: 5},
      );
      final price = s.priceOf(up.item!, day);
      expect(price, greaterThan(hSellValue(up.item!)));
      expect(s.sell(up.item!, 10, today: day, thisWeek: 1), 10 * price);
      // Comprar para revender nunca sale a cuenta.
      for (final o in hShop(day, 5, hSellValue)) {
        expect(s.priceOf(o.item, day), lessThan(o.price));
      }
    });

    test('cada edificio y cada oficio de la lonja tiene nombre', () {
      for (final lang in ['es', 'en']) {
        final l = lookupL(Locale(lang));
        for (final b in HBuilding.values) {
          expect(l.hatarakiBuildingName(b.name), isNot('?'));
          expect(l.hatarakiBuildingAbout(b.name), isNot('?'));
        }
      }
    });
  });

  group('casas', () {
    HState game() => HState.fresh(_t0)
      ..money = 1000000
      ..xp[HSkill.construction] = hXpForLevel(35)
      ..bank.addAll({
        'build_beam': 50,
        'build_frame': 50,
        'build_wall': 50,
        'fu_stool': 3,
        'fu_chabudai': 2,
        'fu_futon': 1,
        'fu_rug_red': 1,
        'fu_flowerbowl': 2,
      });

    test('cada mueble es un objeto, se fabrica o se compra y cabe', () {
      final crafts = {
        HSkill.carpentry,
        HSkill.pottery,
        HSkill.dyeing,
        HSkill.tailoring,
        HSkill.writing,
        HSkill.magic,
      };
      for (final f in hFurnitureList) {
        expect(hItem(f.id)?.kind, HItemKind.furniture, reason: f.id);
        final makers = hActions.where((a) => a.outputs.containsKey(f.id));
        if (f.value > 0) {
          expect(makers, isEmpty, reason: f.id);
          expect(hShopPool, contains(f.id));
          expect(hSellValue(f.id), f.value);
        } else {
          expect(makers, hasLength(1), reason: f.id);
          expect(crafts, contains(makers.first.skill), reason: f.id);
        }
        expect(f.w * f.h, lessThanOrEqualTo(4));
        expect(f.comfort, inInclusiveRange(1, 4));
      }
      expect([
        for (final i in hItems)
          if (i.kind == HItemKind.furniture) i.id,
      ], unorderedEquals(hFurniture.keys));
      for (final style in HStyle.values) {
        expect(
          hFurnitureList.where((f) => f.style == style).length,
          greaterThanOrEqualTo(5),
          reason: style.name,
        );
      }
      // De cada oficio de muebles hay alguno sin plano o para empezar.
      expect(hFavouriteStyle.keys.toSet(), TamaPersonality.values.toSet());
    });

    test('la primera casa es barata y las siguientes cuestan más', () {
      final s = game();
      final first = s.houseCost;
      expect(first.money, 300);
      expect(first.construction, 0);
      expect(s.buildHouse('a'), isTrue);
      expect(s.money, 1000000 - 300);
      expect(s.count('build_beam'), 48);
      expect(s.buildHouse('a'), isFalse, reason: 'ya tiene');
      expect(s.houseCost.money, greaterThan(first.money));
      expect(s.buildHouse('b'), isTrue);
      expect(s.buildHouse('c'), isTrue);
      expect(s.buildHouse('d'), isTrue);
      expect(s.houseCost.construction, greaterThan(35));
      expect(s.canBuildHouse('e'), isFalse, reason: 'falta construcción');
      final poor = HState.fresh(_t0)..bank['build_beam'] = 2;
      expect(poor.canBuildHouse('a'), isFalse, reason: 'sin ginmon');
    });

    test('poner, mover, girar y guardar muebles', () {
      final s = game()..buildHouse('a');
      final house = s.houses['a']!;
      expect(s.placeFurniture('a', 'fu_chabudai', 4, 0), isTrue);
      expect(s.count('fu_chabudai'), 1);
      expect(
        s.placeFurniture('a', 'fu_chabudai', 5, 2),
        isFalse,
        reason: 'se sale',
      );
      expect(
        s.placeFurniture('a', 'fu_stool', 5, 0),
        isFalse,
        reason: 'ocupado',
      );
      expect(
        s.placeFurniture('a', 'fu_celadon', 0, 0),
        isFalse,
        reason: 'no hay',
      );
      expect(s.placeFurniture('a', 'fu_stool', 0, 0), isTrue);
      expect(house.at(5, 0), 0);
      expect(house.at(0, 0), 1);
      expect(house.at(3, 3), isNull);
      // Girada, la mesa de 2×1 pasa a 1×2.
      expect(s.rotateFurniture('a', 0), isTrue);
      expect(house.items[0].size, (1, 2));
      expect(house.at(4, 1), 0);
      expect(house.at(5, 0), isNull);
      // En el borde de la derecha, al girar se arrima a la izquierda.
      expect(s.moveFurniture('a', 0, 5, 3), isTrue);
      expect(s.rotateFurniture('a', 0), isTrue);
      expect((house.items[0].x, house.items[0].y), (4, 3));
      expect(s.moveFurniture('a', 1, 4, 3), isFalse, reason: 'ocupado');
      expect(s.moveFurniture('a', 1, 2, 2), isTrue);
      expect(s.storeFurniture('a', 0), isTrue);
      expect(s.count('fu_chabudai'), 2);
      expect(house.items.single.id, 'fu_stool');
      expect(
        s.placeFurniture('b', 'fu_stool', 0, 0),
        isFalse,
        reason: 'sin casa',
      );
      // Lo puesto ya no se vende: no está en el almacén.
      final stools = s.count('fu_stool');
      expect(s.sell('fu_stool', 99, today: _day, thisWeek: 1), greaterThan(0));
      expect(s.count('fu_stool'), 0);
      expect(house.items.single.id, 'fu_stool');
      expect(stools, 2);
    });

    test('la comodidad: cuántos, si combinan y si le gusta', () {
      final s = game()
        ..buildHouse('a')
        ..xp.clear();
      const cheeky = HTama('a', TamaPersonality.cheeky, .1);
      const calm = HTama('a', TamaPersonality.calm, .1);
      expect(s.comfortOf(cheeky)!.value, 0);
      expect(s.comfortOf(const HTama('b', TamaPersonality.calm, .1)), isNull);
      s.placeFurniture('a', 'fu_stool', 0, 0);
      final one = s.comfortOf(cheeky)!;
      s
        ..placeFurniture('a', 'fu_stool', 1, 0)
        ..placeFurniture('a', 'fu_futon', 2, 0)
        ..placeFurniture('a', 'fu_chabudai', 3, 0);
      final rustic = s.comfortOf(cheeky)!;
      expect(rustic.value, greaterThan(one.value));
      expect(rustic.points, 1 + 1 + 3 + 2);
      // Todo rústico: combina del todo y al descarado le encanta.
      expect(rustic.match, 1);
      expect(rustic.liked, 1);
      // Al tranquilo le gusta lo floral: la misma casa le dice menos.
      expect(s.comfortOf(calm)!.value, lessThan(rustic.value));
      // Un mueble de otro estilo combina peor.
      s.placeFurniture('a', 'fu_rug_red', 0, 3);
      expect(s.comfortOf(cheeky)!.match, lessThan(1));
      // Suelo y pared también cuentan para el estilo.
      s.decorate('a', floor: HStyle.floral, wall: HStyle.floral);
      expect(s.comfortOf(calm)!.liked, greaterThan(0));
      for (final c in [one, rustic]) {
        expect(c.percent, inInclusiveRange(0, 100));
      }
      expect(hRestMood(0), .25);
      expect(hRestMood(1), closeTo(.8, 1e-9));
    });

    test('con casa trabaja más contento, solo aquí y sin bajar nunca', () {
      final s = game();
      final chop = hAction('wc_sugi')!;
      const sad = HTama('a', TamaPersonality.cheeky, 0);
      const happy = HTama('a', TamaPersonality.cheeky, 1);
      final before = s.secondsFor(chop, sad, _t0);
      expect(s.moodFor(sad), 0);
      s
        ..buildHouse('a')
        ..placeFurniture('a', 'fu_stool', 0, 0)
        ..placeFurniture('a', 'fu_futon', 1, 0)
        ..placeFurniture('a', 'fu_chabudai', 2, 0);
      expect(s.moodFor(sad), greaterThan(.25));
      expect(s.secondsFor(chop, sad, _t0), lessThan(before));
      // Al contento no le baja, y el ánimo de verdad no cambia.
      expect(s.moodFor(happy), 1);
      expect(sad.mood, 0);
      // Offline también: una hora con casa da más troncos.
      Map<String, int> hour(HState g) {
        g
          ..lastTick = _t0
          ..assign('a', 'wc_sugi')
          ..advance(_t0 + _hour, {'a': sad});
        return g.bank;
      }

      final without = hour(HState.fresh(_t0))['log_sugi']!;
      final withHouse = hour(s)['log_sugi']!;
      expect(withHouse, greaterThan(without));
    });

    test('los muebles con plano no se fabrican sin él', () {
      final s = HState.fresh(_t0)
        ..xp[HSkill.carpentry] = hXpForLevel(20)
        ..money = 100000
        ..town[HBuilding.shop] = 3;
      expect(s.canDo(hAction('fu_stool')!), isTrue, reason: 'sin plano');
      expect(s.canDo(hAction('fu_chabudai')!), isFalse);
      expect(s.missingPlan(hAction('fu_chabudai')!), 'fu_chabudai');
      expect(s.assign('a', 'fu_chabudai'), isFalse);
      // La tienda vende planos, los mismos para todos, dos con nivel 3.
      final plans = [
        for (final o in s.shop(_day))
          if (o.plan) o,
      ];
      expect(plans, hasLength(2));
      expect([for (final o in plans) o.item], hShopPlans(_day, 3));
      final plan = plans.first;
      expect(hFurniture[plan.item]!.plan, isTrue);
      expect(s.stockLeft(plan, _day), 1);
      expect(s.buy(plan.item, 5, _day), 1);
      expect(s.plans, contains(plan.item));
      expect(s.money, 100000 - plan.price);
      expect(s.count(plan.item), 0, reason: 'se compra el plano, no el mueble');
      expect(s.stockLeft(plan, _day), 0);
      expect(s.buy(plan.item, 1, _day), 0, reason: 'ya se sabe');
      expect(s.missingPlan(hAction(plan.item)!), isNull);
      expect(hShopPlans(_day, 0), isEmpty);
      expect(hShopPlans(_day, 1), hasLength(1));
    });

    test('los encargos regalan planos que aún no se saben', () {
      final s = HState.fresh(_t0)
        ..seed = 3
        ..xp[HSkill.woodcutting] = hXpForLevel(30)
        ..xp[HSkill.cooking] = hXpForLevel(20);
      final seen = <String>{};
      for (var d = 0; d < 40; d++) {
        s.refreshOrders(_day + d);
        expect(s.orders.first.plan, isNull, reason: 'el grande, no');
        final plans = [
          for (final o in s.orders)
            if (o.plan != null) o.plan!,
        ];
        expect(plans.toSet(), hasLength(plans.length), reason: 'repetido');
        seen.addAll(plans);
      }
      expect(seen, isNotEmpty);
      expect(seen.every(hPlanIds.contains), isTrue);
      // Al entregarlo se aprende, y ya no sale en otros encargos.
      var d = 40;
      while (!s.orders.any((o) => o.plan != null)) {
        s.refreshOrders(_day + d++);
      }
      final i = s.orders.indexWhere((o) => o.plan != null);
      final o = s.orders[i];
      for (final e in o.wants.entries) {
        s.bank[e.key] = e.value;
      }
      expect(s.deliver(i, today: _day + d, thisWeek: 1), isTrue);
      expect(s.plans, contains(o.plan));
      s.refreshOrders(_day + d + 1);
      expect(s.orders.where((x) => x.plan == o.plan), isEmpty);
      final back = HState.fromJson(jsonDecode(jsonEncode(s.toJson())), _t0);
      expect(
        jsonEncode([for (final o in back.orders) o.toJson()]),
        jsonEncode([for (final o in s.orders) o.toJson()]),
      );
    });

    test('se guardan las casas y los planos', () {
      final s = game()
        ..buildHouse('a')
        ..buildHouse('b')
        ..placeFurniture('a', 'fu_futon', 5, 4)
        ..placeFurniture('a', 'fu_chabudai', 0, 0, 1)
        ..decorate('a', floor: HStyle.marine, wall: HStyle.magic)
        ..plans.addAll({'fu_orrery', 'fu_boat'});
      final json = jsonDecode(jsonEncode(s.toJson()));
      final back = HState.fromJson(json, _t0);
      expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
      expect(back.houses['a']!.floor, HStyle.marine);
      expect(back.houses['a']!.items[1].r, 1);
      expect(back.plans, {'fu_orrery', 'fu_boat'});
      // Lo que se pisa (no debería pasar) vuelve al almacén; lo que no
      // existe, y los planos de lo que no lleva plano, se ignoran.
      final bad = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
      (bad['houses'] as Map)['a']['items']['2'] = {
        'id': 'fu_stool',
        'x': 5,
        'y': 5,
      };
      (bad['houses'] as Map)['a']['items']['3'] = {'id': 'fu_nada', 'x': 0};
      (bad['plans'] as Map)['fu_stool'] = true;
      final fixed = HState.fromJson(bad, _t0);
      expect(fixed.houses['a']!.items, hasLength(2));
      expect(fixed.count('fu_stool'), s.count('fu_stool') + 1);
      expect(fixed.plans, {'fu_orrery', 'fu_boat'});
    });
  });

  group('visitas (0.8.0)', () {
    test('la ficha de visita lleva nombre, personalidad y aspecto, y vuelve igual', () {
      final tama = sampleTama(
        id: '-Nabcdefghijklmnopqr',
        name: 'Mochi',
        personality: TamaPersonality.shy,
        look: const TamaLook(
          parts: {TamaPart.body: 3},
          color: '#9FE0C6',
          outfit: TamaOutfit(hat: 'hat_straw', accessories: ['acc_bell']),
        ),
      );
      // Pasa por JSON como si fuera y volviera de la base de datos.
      final raw = jsonDecode(jsonEncode(hatarakiVisitJson([tama])));
      final back = hatarakiVisitTamas(raw, 'uid-ana').single;
      expect(back.id, tama.id);
      expect(back.name, 'Mochi');
      expect(back.personality, TamaPersonality.shy);
      expect(back.look, tama.look);
      expect(back.keeper, 'uid-ana');
      // Solo eso: ni cuidados ni fechas.
      final entry = (raw as Map)['tamas'][tama.id] as Map;
      expect(entry.keys.toSet(), {'name', 'personality', 'look'});
    });

    test('una ficha rota o que falta no rompe la visita', () {
      expect(hatarakiVisitTamas(null, 'a'), isEmpty);
      expect(hatarakiVisitTamas({'tamas': 'x'}, 'a'), isEmpty);
      expect(hatarakiVisitTamas({'tamas': {'t1': 3}}, 'a'), isEmpty);
    });
  });
}
