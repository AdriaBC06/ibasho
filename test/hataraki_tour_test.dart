// Ibasho — recorrido visual de Hatarakitama.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja en `build/screenshots/hataraki/<lienzo>/` el regalo, el resumen de
// «mientras no estabas», el pueblo con Tamas trabajando, los oficios, una
// tarea elegida, el almacén y las expediciones.
//
//   flutter test test/hataraki_tour_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/hatarakitama/hataraki_art.dart';
import 'package:ibasho/games/hatarakitama/hataraki_channel.dart';
import 'package:ibasho/games/hatarakitama/hataraki_data.dart';
import 'package:ibasho/games/hatarakitama/hataraki_engine.dart';
import 'package:ibasho/games/hatarakitama/hataraki_home.dart';
import 'package:ibasho/games/hatarakitama/hataraki_map.dart';
import 'package:ibasho/games/hatarakitama/hataraki_town.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/login_bonus.dart' show bonusDay;
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

const Map<String, Size> _canvases = <String, Size>{
  'horizontal': Size(1280, 800),
  'vertical-360x640': Size(360, 640),
  'vertical-411x914': Size(411, 914),
};

const List<String> _colors = ['#F6A8D0', '#9FE0C6', '#FFD36E', '#8EC5FF', '#C9A7F2'];

List<Tama> _tamas(int n) => [
      for (var i = 0; i < n; i++)
        sampleTama(
          id: '-TamaObrera00000000$i',
          name: 'Obrera $i',
          look: TamaLook(
            parts: {
              TamaPart.body: i % 6,
              TamaPart.eyes: (i + 2) % 6,
              TamaPart.mouth: i % 5,
              TamaPart.crown: (i * 2) % 6,
            },
            color: _colors[i % _colors.length],
          ),
        ),
    ];

/// Una partida a medias: tres Tamas trabajando y el almacén con algo de todo.
/// La última vez fue hace tres horas, para que salga el resumen.
Map<String, Object> _game(List<Tama> tamas) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final game = HState(
    lastTick: now - 3 * 3600000,
    seed: 7,
    xp: {
      HSkill.woodcutting: hXpForLevel(24),
      HSkill.fishing: hXpForLevel(18),
      HSkill.foraging: hXpForLevel(12),
      HSkill.cooking: hXpForLevel(15),
      HSkill.mining: hXpForLevel(9),
      HSkill.expedition: hXpForLevel(11),
      HSkill.construction: hXpForLevel(12),
    },
    bank: {
      'log_sugi': 240,
      'log_matsu': 60,
      'fish_iwashi': 80,
      'ore_copper': 30,
      'ore_tin': 22,
      'gem_quartz': 2,
      'seed_rice': 14,
      'crop_rice': 40,
      'food_onigiri': 25,
      'food_iwashi': 12,
      'tea_sencha': 3,
      'gear_basket': 1,
      'gear_scarf': 1,
      'build_beam': 9,
      'potion_sight': 1,
      'rune_spark': 2,
      'fu_stool': 2,
      'fu_chabudai': 1,
      'fu_lantern': 1,
      'fu_flowerbowl': 2,
      'fu_rug_red': 1,
    },
    town: {HBuilding.shop: 2, HBuilding.market: 3, HBuilding.workshop: 1, HBuilding.kiln: 4, HBuilding.tower: 5, HBuilding.library: 3, HBuilding.dock: 2},
    // La primera Tama ya tiene su casa, a medio amueblar.
    houses: {
      tamas[0].id: HHouse(
        floor: HStyle.rustic,
        wall: HStyle.rustic,
        items: [
          HPlaced('fu_rug_wave', 1, 2),
          HPlaced('fu_futon', 0, 0),
          HPlaced('fu_bonsai', 5, 0),
          HPlaced('fu_chabudai', 2, 3),
          HPlaced('fu_zabuton', 2, 4),
          HPlaced('fu_andon', 5, 4, 1),
          HPlaced('fu_boat', 3, 0),
        ],
      ),
    },
    plans: {'fu_chabudai'},
  )..money = 14200;
  return {
    ...game.toJson(),
    // Con el nivel total (96) hay dos ranuras abiertas.
    'workers': {
      '0': {'tama': tamas[0].id, 'action': 'wc_matsu', 'progress': .3},
      '1': {'tama': tamas[1].id, 'action': 'fi_aji', 'progress': .7},
    },
  };
}

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  setUpAll(() async {
    Future<ByteData> bytes(String file) async => ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync());
    await (FontLoader('ZenKaku')
          ..addFont(bytes('ZenKakuGothicNew-Regular.ttf'))
          ..addFont(bytes('ZenKakuGothicNew-Medium.ttf'))
          ..addFont(bytes('ZenKakuGothicNew-Bold.ttf')))
        .load();
    await (FontLoader('Rounded')
          ..addFont(bytes('MPLUSRounded1c-Medium.ttf'))
          ..addFont(bytes('MPLUSRounded1c-Bold.ttf')))
        .load();
  });

  test('todos los objetos, oficios, sitios y recorridos tienen nombre', () async {
    for (final locale in const [Locale('es'), Locale('en')]) {
      final l = await L.delegate.load(locale);
      for (final i in hItems) {
        expect(l.hatarakiItemName(i.id), isNot('?'), reason: i.id);
      }
      for (final s in HSkill.values) {
        expect(l.hatarakiSkillName(s.name), isNot('?'), reason: s.name);
      }
      for (final z in hZones) {
        expect(l.hatarakiZoneName(z.id), isNot('?'), reason: z.id);
      }
      for (final a in hActionsOf(HSkill.agility)) {
        expect(l.hatarakiCourseName(a.id), isNot('?'), reason: a.id);
      }
    }
  });

  // Todos los dibujos juntos, para revisarlos de un vistazo.
  // Una habitación de cada estilo, con muebles de ese estilo.
  testWidgets('hoja de habitaciones', (tester) async {
    tester.view.physicalSize = const Size(1300, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    HHouse room(HStyle style) {
      final house = HHouse(floor: style, wall: style);
      var x = 0, y = 0;
      for (final f in hFurnitureList.where((f) => f.style == style)) {
        for (var r = 0; r < 2; r++) {
          if (house.fits(f.id, x, y, 0)) break;
          x += 2;
          if (x >= hRoomSize) {
            x = 0;
            y += 2;
          }
        }
        if (house.fits(f.id, x, y, 0)) house.items.add(HPlaced(f.id, x, y));
        x += f.w + 1;
        if (x >= hRoomSize) {
          x = 0;
          y += 2;
        }
      }
      return house;
    }

    await tester.pumpWidget(
      RepaintBoundary(
        child: ColoredBox(
          color: const Color(0xFFEFF3F7),
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              for (final style in HStyle.values)
                SizedBox(
                  width: 260,
                  height: 300,
                  child: CustomPaint(painter: HatarakiRoomPainter(room(style), selected: 0, grid: true)),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      Directory('build/screenshots/hataraki').createSync(recursive: true);
      File('build/screenshots/hataraki/habitaciones.png').writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    });
  });

  testWidgets('hoja de iconos', (tester) async {
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget cell(Widget icon) => SizedBox.square(dimension: 76, child: Center(child: icon));
    await tester.pumpWidget(
      RepaintBoundary(
        child: ColoredBox(
          color: const Color(0xFFEFF3F7),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                children: [
                  for (final i in hItems) cell(HatarakiItemIcon(i.id, size: 68)),
                  for (final s in HSkill.values) cell(HatarakiSkillIcon(s, size: 68)),
                  for (final z in hZones) cell(HatarakiZoneIcon(z.id, size: 68)),
                  for (final b in HBuilding.values) ...[
                    cell(HatarakiBuildingIcon(b, size: 68)),
                    cell(HatarakiBuildingIcon(b, size: 68, built: false)),
                  ],
                  for (final k in HNodeKind.values) cell(HatarakiNodeIcon('forest', k, size: 68)),
                  cell(const HatarakiHomeIcon(size: 68)),
                  cell(const HatarakiHomeIcon(size: 68, built: false)),
                  cell(const HatarakiPlanIcon('fu_orrery', size: 68)),
                  cell(const HatarakiNodeIcon('forest', HNodeKind.loot, size: 68, fog: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      Directory('build/screenshots/hataraki').createSync(recursive: true);
      File('build/screenshots/hataraki/iconos.png').writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    });
  });

  for (final MapEntry(key: folder, value: size) in _canvases.entries) {
    final output = Directory('build/screenshots/hataraki/$folder')..createSync(recursive: true);

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final list = _tamas(5);
      final backend = FakeIbashoBackend(tamas: list, profileTamaId: list.first.id);
      await backend.write('/users/$kAdminUid/hataraki', _game(list), idToken: '');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            initialPreferencesProvider.overrideWithValue(
              const Preferences(odoriOpened: true, ohiruneOpened: true, koroOpened: true),
            ),
            batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
          ],
          child: const RepaintBoundary(child: IbashoApp()),
        ),
      );
    }

    Future<void> settle(WidgetTester tester, [int frames = 40]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${output.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
      });
    }

    Future<void> tapKey(WidgetTester tester, String key, [int frames = 30]) async {
      // En vertical caben menos ranuras: se pasa de página hasta encontrarla.
      final target = find.byKey(ValueKey<String>(key)).hitTestable();
      // Lo que está en la tarjeta, más abajo: se desplaza hasta verlo.
      final hidden = find.byKey(ValueKey<String>(key));
      if (target.evaluate().isEmpty && hidden.evaluate().isNotEmpty) {
        await tester.ensureVisible(hidden.first);
        await settle(tester, 12);
      }
      for (var i = 0; i < 6 && target.evaluate().isEmpty; i++) {
        await tester.tap(find.byKey(const ValueKey<String>('hataraki.page.next')).hitTestable().first);
        await settle(tester, 12);
      }
      await tester.tap(target.first);
      await settle(tester, frames);
    }

    group(folder, () {
      testWidgets('regalo, resumen, pueblo, oficios, almacén y expediciones', (tester) async {
        await boot(tester);
        await settle(tester, 100);
        final tile = find.byKey(const ValueKey<String>('channel.hataraki')).hitTestable();
        for (var i = 0; i < 4 && tile.evaluate().isEmpty; i++) {
          await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
          await settle(tester, 30);
        }
        expect(tile, findsOneWidget);
        await shoot(tester, 'h1-regalo');
        await tester.tap(tile);
        await settle(tester, 60);
        for (var i = 0; i < 3 && find.byKey(const ValueKey<String>('hataraki.tab.village')).evaluate().isEmpty; i++) {
          await tester.tap(tile);
          await settle(tester, 60);
        }
        await settle(tester, 40);
        await shoot(tester, 'h2-mientras');
        expect(find.byKey(const ValueKey<String>('hataraki.away.ok')), findsOneWidget);
        await tapKey(tester, 'hataraki.away.ok');
        await shoot(tester, 'h3-pueblo');
        await tapKey(tester, 'hataraki.help');
        await shoot(tester, 'h0-ayuda');
        await tapKey(tester, 'hataraki.help.next', 10);
        await tapKey(tester, 'hataraki.help.next', 10);
        await shoot(tester, 'h0-mana');
        await tapKey(tester, 'hataraki.help.ok');

        await tapKey(tester, 'hataraki.tab.skills');
        await shoot(tester, 'h4-oficios');
        await tapKey(tester, 'hataraki.skill.woodcutting');
        await tapKey(tester, 'hataraki.action.wc_take');
        await shoot(tester, 'h5-tarea');
        await tapKey(tester, 'hataraki.assign');
        await shoot(tester, 'h6-quien');
        await tapKey(tester, 'hataraki.pick.-TamaObrera000000002');
        await shoot(tester, 'h7-trabajando');

        await tapKey(tester, 'hataraki.tab.bank');
        await tapKey(tester, 'hataraki.item.tea_sencha');
        await shoot(tester, 'h8-almacen');

        await tapKey(tester, 'hataraki.tab.town');
        await tapKey(tester, 'hataraki.building.kiln');
        await shoot(tester, 'h11-pueblo');
        await tapKey(tester, 'hataraki.building.shop');
        await tapKey(tester, 'hataraki.enter');
        await tapKey(tester, 'hataraki.buy.one');
        await shoot(tester, 'h12-tienda');
        await tapKey(tester, 'hataraki.town.back');
        await tapKey(tester, 'hataraki.building.market');
        await tapKey(tester, 'hataraki.enter');
        await shoot(tester, 'h13-lonja');
        await tapKey(tester, 'hataraki.town.back');
        await tapKey(tester, 'hataraki.building.board');
        await tapKey(tester, 'hataraki.enter');
        await shoot(tester, 'h15-tablon');
        await tapKey(tester, 'hataraki.order.1');
        await shoot(tester, 'h16-encargo');
        await tapKey(tester, 'hataraki.town.back');
        await tapKey(tester, 'hataraki.building.shop');
        await tapKey(tester, 'hataraki.enter');
        await tapKey(tester, 'hataraki.offer.${hShopPlans(bonusDay(DateTime.now()), 2).first}');
        await shoot(tester, 'h17-plano');
        await tapKey(tester, 'hataraki.town.back');

        // La posada: la lista de habitaciones, una hecha, dentro y poner un mueble.
        await tapKey(tester, 'hataraki.building.inn');
        await shoot(tester, 'h18-casas');
        await tapKey(tester, 'hataraki.enter');
        await tapKey(tester, 'hataraki.home.-TamaObrera000000001');
        await shoot(tester, 'h19-sin-casa');
        await tapKey(tester, 'hataraki.home.go');
        await shoot(tester, 'h20-casa-nueva');
        await tapKey(tester, 'hataraki.home.back');
        await tapKey(tester, 'hataraki.home.-TamaObrera000000000');
        await tapKey(tester, 'hataraki.home.go');
        await shoot(tester, 'h21-habitacion');
        await tapKey(tester, 'hataraki.piece.fu_lantern');
        final room = tester.getRect(find.byKey(const ValueKey<String>('hataraki.room')));
        final (floor, cell) = hRoomLayout(room.size);
        await tester.tapAt(room.topLeft + floor.topLeft + Offset(cell * 4.5, cell * 2.5));
        await settle(tester, 20);
        await tester.tapAt(room.topLeft + floor.topLeft + Offset(cell * 2.5, cell * 3.5));
        await settle(tester, 20);
        await shoot(tester, 'h22-mueble');

        // De visita (a uno mismo, que es lo que hay en el falso): el pueblo,
        // un edificio, un Tama y su habitación. Solo mirar.
        openHatarakiVisit(tester.element(find.byKey(const ValueKey<String>('hataraki.tab.town')).first), kAdminUid);
        await settle(tester, 60);
        await shoot(tester, 'h23-visita');
        await tapKey(tester, 'hataraki.building.tower');
        await shoot(tester, 'h24-visita-edificio');
        await tapKey(tester, 'hataraki.visit.tama.-TamaObrera000000000');
        await shoot(tester, 'h25-visita-tama');
        await tapKey(tester, 'hataraki.visit.room');
        await shoot(tester, 'h26-visita-habitacion');
        Navigator.of(tester.element(find.byType(HatarakiVisitScreen))).pop();
        await settle(tester, 40);

        await tapKey(tester, 'hataraki.tab.expedition');
        await shoot(tester, 'h14-sitios');
        await tapKey(tester, 'hataraki.zone.forest');
        await tapKey(tester, 'hataraki.party.add.0');
        await tapKey(tester, 'hataraki.pick.-TamaObrera000000003');
        await tapKey(tester, 'hataraki.supply');
        await tapKey(tester, 'hataraki.rune');
        await tapKey(tester, 'hataraki.service.porter');
        await tapKey(tester, 'hataraki.node.1.0');
        await shoot(tester, 'h9-expedicion');
        await tapKey(tester, 'hataraki.go');
        await settle(tester, 40);
        await shoot(tester, 'h10-de-viaje');
      });
    });
  }
}
