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
import 'package:ibasho/games/hatarakitama/hataraki_data.dart';
import 'package:ibasho/games/hatarakitama/hataraki_engine.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
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
    },
  );
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

        await tapKey(tester, 'hataraki.tab.expedition');
        await tapKey(tester, 'hataraki.party.add.0');
        await tapKey(tester, 'hataraki.pick.-TamaObrera000000003');
        await shoot(tester, 'h9-expedicion');
        await tapKey(tester, 'hataraki.go');
        await shoot(tester, 'h10-de-viaje');
      });
    });
  }
}
