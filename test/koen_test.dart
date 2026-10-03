// Ibasho — Tama Kōen: fichas y encuentros del día.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha_prizes.dart';
import 'package:ibasho/backend/koen.dart';
import 'package:ibasho/backend/koen_bonds.dart';
import 'package:ibasho/backend/koen_care.dart';
import 'package:ibasho/backend/koen_duo.dart';
import 'package:ibasho/backend/koen_rewards.dart';
import 'package:ibasho/backend/prizes.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/koen/koen_charm.dart';
import 'package:ibasho/games/koen/koen_mood.dart';
import 'package:ibasho/state/koen.dart';
import 'package:ibasho/state/tamas.dart';

KoenCard _card(String holder, String id, {int slot = 0, String? duo}) => KoenCard(
  holder: holder,
  slot: slot,
  tamaId: id,
  owner: holder,
  name: id,
  personality: TamaPersonality.calm,
  voice: const TamaVoice(),
  look: const TamaLook(),
  at: 1,
  duo: duo,
);

void main() {
  test('el hash es estable entre ejecuciones y plataformas', () {
    expect(koenHash(''), 0x811c9dc5);
    expect(koenHash('a'), 0xe40c292c);
  });

  test('cada pareja se decide sola: no depende de qué más se vea', () {
    final cards = [for (var i = 0; i < 12; i++) _card('acc${i % 4}', 't$i', slot: i % 3)];
    bool all(String a, String b) => true;
    final full = koenEncounters(day: 20000, cards: cards, friends: all);
    // Quien solo ve una parte del parque ve lo mismo de esas parejas.
    final part = koenEncounters(day: 20000, cards: cards.sublist(0, 5), friends: all);
    final ids = {for (final c in cards.sublist(0, 5)) c.tamaId};
    final fromFull = full.where((e) => ids.contains(e.a.tamaId) && ids.contains(e.b.tamaId));
    expect(part.map((e) => '${e.pairKey}:${e.zone}:${e.hour}'), fromFull.map((e) => '${e.pairKey}:${e.zone}:${e.hour}'));
    // Y otro día sale otra cosa.
    final other = koenEncounters(day: 20001, cards: cards, friends: all);
    expect(other.map((e) => e.pairKey), isNot(full.map((e) => e.pairKey)));
  });

  test('solo se juntan Tamas de la misma cuenta o de cuentas amigas', () {
    final cards = [_card('a', 'x1'), _card('a', 'x2', slot: 1), _card('b', 'y1'), _card('c', 'z1')];
    final seen = <String>{};
    for (var day = 0; day < 60; day++) {
      for (final e in koenEncounters(
        day: day,
        cards: cards,
        friends: (p, q) => {p, q}.containsAll(['a', 'b']),
      )) {
        seen.add(e.pairKey);
        expect(e.hour, inInclusiveRange(8, 21));
      }
    }
    expect(seen, containsAll([koenPairKey('x1', 'x2'), koenPairKey('x1', 'y1')]));
    expect(seen.any((k) => k.contains('z1')), isFalse);
  });

  test('las fichas del parque se leen como mapa o como lista', () {
    final json = _card('a', 'x1').toJson();
    expect(KoenCard.parkFromJson('a', {'1': json}).single.slot, 1);
    expect(KoenCard.parkFromJson('a', [null, null, json]).single.slot, 2);
    expect(KoenCard.parkFromJson('a', {'1': {'name': 'sin id'}}), isEmpty);
  });

  test('estaciones y luz del día', () {
    expect(koenSeason(DateTime(2026, 4, 1)), KoenSeason.spring);
    expect(koenSeason(DateTime(2026, 12, 1)), KoenSeason.winter);
    expect(koenSeason(DateTime(2026, 12, 1), south: true), KoenSeason.summer);
    expect(koenSeason(DateTime(2026, 4, 1), south: true), KoenSeason.autumn);
    expect(koenSouthern('ar'), isTrue);
    expect(koenSouthern('ES'), isFalse);
    expect(koenSouthern(null), isFalse);
    expect(koenDaylight(DateTime(2026, 1, 1, 12)), 1);
    expect(koenDaylight(DateTime(2026, 1, 1, 23)), 0);
    expect(koenDaylight(DateTime(2026, 1, 1, 20)), closeTo(.5, 1e-9));
  });

  test('los de la misma cuenta se conocen; la amistad va de 0 a 1', () {
    expect(koenCloseness(100, _card('a', 'x1'), _card('a', 'x2')), greaterThanOrEqualTo(.6));
    for (var day = 0; day < 40; day++) {
      final c = koenCloseness(day, _card('a', 'x1'), _card('b', 'y1'));
      expect(c, inInclusiveRange(0, 1));
      expect(c, koenCloseness(day, _card('b', 'y1'), _card('a', 'x1')));
    }
  });

  test('la conversación va por turnos y acaba en paz', () {
    final random = math.Random(3);
    for (var i = 0; i < 200; i++) {
      final lines = koenChat(
        first: TamaPersonality.values[i % 5],
        second: TamaPersonality.values[(i ~/ 5) % 5],
        closeness: (i % 11) / 10,
        random: random,
      );
      expect(lines.length, inInclusiveRange(3, 5));
      for (var j = 0; j < lines.length; j++) {
        expect(lines[j].first, j.isEven);
      }
      expect(lines.last.mood, isNot(anyOf(KoenMood.pout, KoenMood.surprise)));
    }
    // Entre desconocidos tímidos no hay cariño.
    final shy = koenChat(first: TamaPersonality.shy, second: TamaPersonality.shy, closeness: 0, random: random);
    expect(shy.map((l) => l.mood), isNot(contains(KoenMood.love)));
  });

  group('lo que da el parque', () {
    KoenEncounter meet(String ha, String hb, {double hour = 12, KoenZone zone = KoenZone.tree, bool inPlace = false, int at = 1}) =>
        KoenEncounter(
          a: KoenCard(holder: ha, slot: 0, tamaId: 'a', owner: ha, name: 'a', personality: TamaPersonality.calm,
              voice: const TamaVoice(), look: const TamaLook(), at: at),
          b: _card(hb, 'b'),
          zone: zone,
          hour: hour,
          variant: 0,
          inPlace: inPlace,
        );

    test('solo pagan los encuentros con Tamas de amigos', () {
      expect(koenPays(meet('me', 'friend'), 'me'), isTrue);
      expect(koenPays(meet('me', 'me'), 'me'), isFalse);
      expect(koenPays(meet('f1', 'f2'), 'me'), isFalse);
    });

    test('cuentan los que ya han pasado y con los dos en el parque', () {
      final now = DateTime(2026, 10, 2, 15);
      final early = meet('me', 'f', hour: 10);
      final late = meet('me', 'f', hour: 18);
      final arrivedAfter = meet('me', 'f', hour: 11, at: DateTime(2026, 10, 2, 13).millisecondsSinceEpoch);
      expect(koenDone([late, early, arrivedAfter], now), [early]);
    });

    test('la chuche del día es la misma desde cualquier móvil', () {
      expect(koenGiftFood(20000, 'me'), koenGiftFood(20000, 'me'));
      final foods = {for (var d = 0; d < 60; d++) koenGiftFood(20000 + d, 'me')};
      expect(foods.length, greaterThan(3));
    });

    test('los recuerdos salen de la zona, la estación y la hora', () {
      final m = koenMemoriesOf(
        meet('me', 'f', zone: KoenZone.tree, hour: 20.5),
        me: 'me',
        season: KoenSeason.spring,
        closeness: .8,
        paidToday: 3,
      );
      expect(m, containsAll([
        KoenMemory.first,
        KoenMemory.tree,
        KoenMemory.spring,
        KoenMemory.hanami,
        KoenMemory.fireflies,
        KoenMemory.besties,
        KoenMemory.busyDay,
      ]));
      expect(m, isNot(contains(KoenMemory.siblings)));
      final walk = koenMemoriesOf(meet('me', 'me', inPlace: true), me: 'me', season: KoenSeason.winter, closeness: 0);
      expect(walk, containsAll([KoenMemory.stroll, KoenMemory.winter, KoenMemory.siblings]));
      expect(walk, isNot(contains(KoenMemory.snowman)));
      expect(koenMemoriesOf(meet('f1', 'f2'), me: 'me', season: KoenSeason.summer, closeness: 0),
          {KoenMemory.friendsOfFriends});
      expect(KoenMemory.values.length, 25);
    });
  });

  group('amistades', () {
    test('solo se suma lo nuevo de hoy', () {
      const empty = KoenTally();
      final first = empty.count(100, 2);
      expect(first, const KoenTally(p: 2, d: 100, n: 2));
      expect(first.count(100, 2), first);
      expect(first.count(100, 1), first);
      expect(first.count(100, 3), const KoenTally(p: 3, d: 100, n: 3));
      expect(first.count(101, 1), const KoenTally(p: 3, d: 101, n: 1));
      expect(KoenTally.fromJson(first.toJson()), first);
      expect(KoenTally.fromJson('nada'), empty);
    });

    test('niveles entre Tamas y entre jugadores', () {
      expect(koenBondLevel(0), 1);
      expect(koenBondLevel(3), 2);
      expect(koenBondLevel(24), 4);
      expect(koenBondLevel(25), 5);
      expect(koenBondLevel(999), 5);
      expect(koenBondCloseness(0), 0);
      expect(koenBondCloseness(0, siblings: true), .6);
      expect(koenBondCloseness(25), 1);
      // «inseparables» en el álbum sale desde muy amigos.
      expect(koenBondCloseness(15), greaterThanOrEqualTo(.7));
      expect(KoenFriendLevel.of(0), KoenFriendLevel.none);
      expect(KoenFriendLevel.of(1), KoenFriendLevel.acquainted);
      expect(KoenFriendLevel.of(20), KoenFriendLevel.friends);
      expect(KoenFriendLevel.of(149), KoenFriendLevel.good);
      expect(KoenFriendLevel.of(150), KoenFriendLevel.inseparable);
    });

    test('los premios de la amistad no salen en el gacha', () {
      expect(koenBondPrizes.values, ['bg_koen', 'momiji_red']);
      for (final key in koenBondPrizes.values) {
        expect(allGachaPrizeKeys, isNot(contains(key)));
        expect(gachaPrizeCategory(key), isNotNull, reason: key);
      }
    });

    test('lo de hoy por pareja: el encuentro que ya ha pasado y los forzados', () {
      final now = DateTime(2026, 10, 2, 15);
      final e = KoenEncounter(a: _card('me', 'a'), b: _card('f', 'b'), zone: KoenZone.pond, hour: 10, variant: 0);
      final later = KoenEncounter(a: _card('me', 'c'), b: _card('f', 'd'), zone: KoenZone.pond, hour: 18, variant: 0);
      final today = koenTodayByPair(
        all: [e, later],
        now: now,
        drags: (k) => k == e.pairKey ? 2 : (k == 'x_y' ? 1 : 0),
        draggedPairs: [e.pairKey, 'x_y'],
      );
      expect(today, {e.pairKey: 3, 'x_y': 1});
    });
  });

  group('cuidar a medias', () {
    Tama tama(String id, {String creator = 'me', String? carer, TamaCare care = const TamaCare()}) => Tama(
      id: id,
      creator: creator,
      keeper: creator,
      carer: carer,
      name: id,
      care: care,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('el cuidador va y vuelve en el json', () {
      final t = tama('t1', carer: 'f');
      expect(Tama.fromJson('t1', t.toJson()).carer, 'f');
      expect(Tama.fromJson('t1', tama('t1').toJson()).carer, isNull);
      expect(t.copyWith(clearCarer: true).shared, isFalse);
      expect(t.copyWith(name: 'x').carer, 'f');
    });

    test('el día cuenta con comida y mimo de hoy (UTC)', () {
      const day = 20000;
      final today = DateTime.fromMillisecondsSinceEpoch(day * 86400000 + 3600000);
      final yesterday = DateTime.fromMillisecondsSinceEpoch(day * 86400000 - 1);
      expect(koenCareDone(tama('a', care: TamaCare(lastFed: today, lastPetted: today)), day), isTrue);
      expect(koenCareDone(tama('a', care: TamaCare(lastFed: today, lastPetted: yesterday)), day), isFalse);
      expect(koenCareDone(tama('a', care: TamaCare(lastFed: today)), day), isFalse);
    });

    test('las ofertas del buzón: solo las que firma su creador', () {
      final card = _card('ana', 'x1').toJson();
      final offers = KoenOffer.listFrom({'ana': card, 'luis': card, 'raro': 'nada'});
      expect(offers.map((o) => o.from), ['ana']);
      expect(offers.single.tamaId, 'x1');
      expect(KoenOffer.listFrom(null), isEmpty);
    });

    test('los que se cuidan a medias acompañan, pero no son propios', () {
      final own = tama('a', carer: 'f');
      final theirs = tama('b', creator: 'g', carer: 'me');
      final state = TamasState(tamas: [own, tama('c')], cared: [theirs]);
      expect(state.companions.map((t) => t.id), ['a', 'c', 'b']);
      expect(state.byId('b'), isNull);
      expect(state.find('b'), theirs);
      expect(state.sharesWith('f'), isTrue);
      expect(state.sharesWith('g'), isTrue);
      expect(state.sharesWith('h'), isFalse);
    });

    test('un Tama que han traído los dos sale una vez en el parque', () {
      final mine = _card('me', 'x1');
      final park = KoenState(mine: [mine], friends: {
        'f': [_card('f', 'x1'), _card('f', 'y1', slot: 1)],
      });
      expect(park.all.map((c) => '${c.holder}:${c.tamaId}'), ['me:x1', 'f:y1']);
    });
  });

  group('dúos', () {
    Tama tama(String id, {String creator = 'me', String? carer, TamaCare care = const TamaCare()}) => Tama(
      id: id,
      creator: creator,
      keeper: creator,
      carer: carer,
      name: id,
      care: care,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('hay dúo cuando cada uno cuida a medias un Tama del otro', () {
      final mine = tama('a', carer: 'f');
      final theirs = tama('b', creator: 'f', carer: 'me');
      expect(koenDuoTamas('me', [mine], [theirs]).keys, ['f']);
      // Solo en un sentido, o con otro amigo, no.
      expect(koenDuoTamas('me', [mine], const []), isEmpty);
      expect(koenDuoTamas('me', [tama('a', carer: 'g')], [theirs]), isEmpty);
      expect(koenDuoKey('zz', 'aa'), 'aa_zz');
    });

    test('la casita: lo guardado si vale; si no, uno de cada uno con el de `a` a la izquierda', () {
      final duo = KoenDuo(
        me: 'me',
        friend: 'f',
        mine: [tama('a', carer: 'f'), tama('a2', carer: 'f')],
        theirs: [tama('b', creator: 'f', carer: 'me')],
      );
      expect(duo.key, 'f_me');
      expect((duo.left.id, duo.right.id), ('b', 'a'));
      final saved = duo.copyWith(data: const KoenDuoData(left: 'a2', right: 'b'));
      expect((saved.left.id, saved.right.id), ('a2', 'b'));
      expect(saved.mateOf('b'), 'a2');
      expect(saved.mateOf('a'), isNull);
      // Dos del mismo dueño, o uno que ya no se cuida a medias, no valen.
      expect(duo.copyWith(data: const KoenDuoData(left: 'a', right: 'a2')).left.id, 'b');
      expect(duo.copyWith(data: const KoenDuoData(left: 'zz', right: 'b')).left.id, 'b');
    });

    test('la racha sigue si ayer contó, vuelve a 1 si no y guarda la mejor', () {
      const s = KoenStreak(count: 6, day: 99, best: 6);
      expect(s.current(100), 6);
      expect(s.current(101), 0);
      expect(s.advance(100).toJson(), {'count': 7, 'day': 100, 'best': 7});
      expect(s.advance(102).toJson(), {'count': 1, 'day': 102, 'best': 6});
      expect(identical(s.advance(99), s), isTrue);
      expect(KoenStreak.fromJson({'count': 2, 'day': 5, 'best': 9}).best, 9);
    });

    test('el día cuenta con los dos Tamas comidos y mimados hoy', () {
      const day = 20000;
      final today = DateTime.fromMillisecondsSinceEpoch(day * 86400000 + 60000);
      final done = TamaCare(lastFed: today, lastPetted: today);
      final duo = KoenDuo(
        me: 'me',
        friend: 'f',
        mine: [tama('a', carer: 'f', care: done)],
        theirs: [tama('b', creator: 'f', carer: 'me', care: TamaCare(lastFed: today))],
      );
      expect(duo.caredOn(day), isFalse);
      expect(duo.copyWith(theirs: [tama('b', creator: 'f', carer: 'me', care: done)]).caredOn(day), isTrue);
    });

    test('la casita sube con la racha y la amistad, y cada nivel trae muebles', () {
      expect(koenHouseLevel(0, KoenFriendLevel.inseparable), 1);
      expect(koenHouseLevel(3, KoenFriendLevel.none), 2);
      expect(koenHouseLevel(7, KoenFriendLevel.acquainted), 2);
      expect(koenHouseLevel(7, KoenFriendLevel.friends), 3);
      expect(koenHouseLevel(30, KoenFriendLevel.good), 4);
      expect(koenHouseLevel(30, KoenFriendLevel.inseparable), 5);
      expect(koenDecorSpots(5), 6);
      expect(koenFurnitureFor(1, 0), [KoenFurniture.zabuton, KoenFurniture.andon]);
      expect(koenFurnitureFor(1, 30), contains(KoenFurniture.maneki));
      expect(koenFurnitureFor(5, 30).length, KoenFurniture.values.length);
    });

    test('lo del dúo se lee tal como llega, con los muebles en mapa o lista', () {
      final data = KoenDuoData.fromJson({
        'a': 'f',
        'b': 'me',
        'slots': {'left': 'b', 'right': 'a'},
        'streak': {'count': 3, 'day': 10, 'best': 4},
        'house': {
          'decor': ['kotatsu', null, 'nada'],
        },
      });
      expect(data.exists, isTrue);
      expect((data.left, data.right), ('b', 'a'));
      expect(data.streak.best, 4);
      expect(data.decor, {0: KoenFurniture.kotatsu});
      expect(KoenDuoData.fromJson(null).exists, isFalse);
    });

    test('los del dúo se encuentran todos los días y dejan su recuerdo', () {
      final a = _card('me', 'a', duo: 'b');
      final b = _card('f', 'b');
      for (var day = 0; day < 20; day++) {
        final today = koenEncounters(day: day, cards: [a, b], friends: (_, _) => true);
        expect(today.single.duo, isTrue);
      }
      expect(KoenCard.fromJson('me', 0, a.toJson())!.duo, 'b');
      final e = koenEncounters(day: 1, cards: [a, b], friends: (_, _) => true).single;
      expect(
        koenMemoriesOf(e, me: 'me', season: KoenSeason.spring, closeness: 0),
        contains(KoenMemory.duo),
      );
      final tamaA = tama('a');
      expect(a.staleFor(tamaA, duo: 'b'), isFalse);
      expect(a.staleFor(tamaA), isTrue);
    });
  });

  group('accesorio de pareja', () {
    test('el color sale de la pareja y la clave lleva forma, lado y color', () {
      final code = koenCharmCode(koenDuoKey('ana', 'luis'));
      expect(code, koenCharmCode(koenDuoKey('luis', 'ana')));
      expect(code, matches(RegExp(r'^[0-9a-f]{6}$')));
      expect(koenCharmCode(koenDuoKey('ana', 'otra')), isNot(code));
      final key = koenCharmKey(KoenCharm.pendant, left: true, code: code);
      expect(key, 'charm_pendant_l_$code');
      expect(TamaOutfit.keyPattern.hasMatch(key), isTrue);
      final half = koenCharmOf(key)!;
      expect((half.shape, half.left, half.code), (KoenCharm.pendant, true, code));
      expect(koenCharmOf('charm_anillo_l_$code'), isNull);
      expect(koenCharmOf('cap_red'), isNull);
    });

    test('cada mitad es un premio que se pone, con su sitio', () {
      final pendant = prizeItem('charm_pendant_r_00ff00')!;
      expect(pendant.slot, PrizeSlot.neck);
      expect(pendant.code, '00ff00');
      expect(pendant.key, 'charm_pendant_r_00ff00');
      expect(pendant.asset, 'assets/koen/charm_pendant_r.svg');
      expect(prizeItem('charm_twins_l_00ff00')!.slot, PrizeSlot.head);
      // El hilo se ata del lado del otro.
      expect(prizeItem('charm_thread_l_00ff00')!.slot, PrizeSlot.right);
      expect(prizeItem('charm_thread_r_00ff00')!.slot, PrizeSlot.left);
      for (final p in koenCharmPrizes) {
        for (final v in p.variants) {
          expect(File('assets/koen/${p.id}_$v.svg').existsSync(), isTrue, reason: '${p.id}_$v');
        }
      }
      // Ni el gacha ni el catálogo los dan.
      expect(allGachaPrizeKeys.where((k) => k.startsWith('charm_')), isEmpty);
    });

    test('encajan dos mitades de la misma pareja y lados distintos', () {
      final l = koenCharmKey(KoenCharm.twins, left: true, code: 'abcdef');
      final r = koenCharmKey(KoenCharm.twins, left: false, code: 'abcdef');
      expect(koenCharmMatch([l, 'cap_red'], [r])?.shape, KoenCharm.twins);
      expect(koenCharmMatch([l], [l]), isNull);
      expect(koenCharmMatch([l], [koenCharmKey(KoenCharm.twins, left: false, code: '123456')]), isNull);
      expect(koenCharmMatch([l], [koenCharmKey(KoenCharm.pendant, left: false, code: 'abcdef')]), isNull);
    });

    test('ponerse una mitad quita la otra y, en espejo, cambia de lado', () {
      const look = TamaLook(outfit: TamaOutfit(hat: 'cap_red', accessories: ['glasses_black']));
      final pendant = koenCharmKey(KoenCharm.pendant, left: true, code: 'abcdef');
      final twins = koenCharmKey(KoenCharm.twins, left: true, code: 'abcdef');
      final a = koenWithCharm(look, pendant)!;
      expect(a.outfit.accessories, ['glasses_black', pendant]);
      final b = koenWithCharm(a, twins)!;
      expect(b.outfit.hat, twins);
      expect(b.outfit.accessories, ['glasses_black']);
      expect(koenWithoutCharm(b).outfit, const TamaOutfit(accessories: ['glasses_black']));
      expect(koenMirrorCharm(b).outfit.hat, koenCharmKey(KoenCharm.twins, left: false, code: 'abcdef'));
      expect(koenMirrorCharm(look), same(look));
    });

    test('se gana siendo buenos amigos', () {
      expect(koenCharmLevel, KoenFriendLevel.good);
    });
  });
}
