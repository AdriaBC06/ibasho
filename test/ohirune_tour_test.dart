// Ibasho — recorrido visual de Ohirune, el canal secreto.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja en `build/screenshots/ohirune/<lienzo>/` el regalo en la rejilla, el
// tablero recién abierto, los tableros (con los bloqueados por Tamas), una
// partida con X, un fallo y la victoria, y el canal sin Tamas suficientes.
//
//   flutter test test/ohirune_tour_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/ohirune/ohirune.dart';
import 'package:ibasho/games/ohirune/ohirune_channel.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

const Map<String, Size> _canvases = <String, Size>{
  'horizontal': Size(1280, 800),
  'vertical-360x640': Size(360, 640),
  'vertical-411x914': Size(411, 914),
};

const int _seed = 11;

const List<String> _colors = [
  '#F6A8D0',
  '#9FE0C6',
  '#FFD36E',
  '#8EC5FF',
  '#C9A7F2',
  '#FF9C86',
  '#A8D878',
  '#F2F2F2',
  '#6A78C8',
];

/// [n] Tamas distintos, cada uno de su color.
List<Tama> _tamas(int n) => [
      for (var i = 0; i < n; i++)
        sampleTama(
          id: '-TamaSiesta00000000$i',
          name: 'Siesta $i',
          look: TamaLook(
            parts: {
              TamaPart.body: i % 6,
              TamaPart.eyes: (i + 1) % 6,
              TamaPart.mouth: i % 5,
              TamaPart.crown: (i * 2) % 6,
              TamaPart.cheeks: i % 4,
            },
            color: _colors[i],
          ),
        ),
    ];

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
    debugOhiruneSeed = _seed;
  });

  for (final MapEntry(key: folder, value: size) in _canvases.entries) {
    final output = Directory('build/screenshots/ohirune/$folder')..createSync(recursive: true);

    Future<void> boot(WidgetTester tester, {required int tamas, bool opened = false}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final list = _tamas(tamas);
      final backend = FakeIbashoBackend(tamas: list, profileTamaId: list.isEmpty ? null : list.first.id);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            initialPreferencesProvider.overrideWithValue(Preferences(ohiruneOpened: opened, odoriOpened: true)),
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

    Future<Finder> findChannel(WidgetTester tester) async {
      final key = find.byKey(const ValueKey<String>('channel.ohirune')).hitTestable();
      for (var i = 0; i < 4 && key.evaluate().isEmpty; i++) {
        await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
        await settle(tester, 30);
      }
      return key;
    }

    /// Toca la baldosa hasta que el canal se abre.
    Future<void> enter(WidgetTester tester, Finder tile) async {
      bool inside() =>
          find.byKey(const ValueKey<String>('ohirune.board')).evaluate().isNotEmpty ||
          find.byKey(const ValueKey<String>('ohirune.locked')).evaluate().isNotEmpty;
      for (var i = 0; i < 3 && !inside(); i++) {
        await tester.tap(tile);
        await settle(tester, 60);
      }
    }

    group(folder, () {
      testWidgets('sin los Tamas del facil no aparece', (tester) async {
        await boot(tester, tamas: 4);
        await settle(tester, 100);
        for (var i = 0; i < 4; i++) {
          expect(find.byKey(const ValueKey<String>('channel.ohirune')), findsNothing);
          final next = find.byKey(const ValueKey<String>('grid.next')).hitTestable();
          if (next.evaluate().isEmpty) break;
          await tester.tap(next);
          await settle(tester, 30);
        }
      });

      testWidgets('regalo, tablero, fallo y siesta completa', (tester) async {
        await boot(tester, tamas: 6);
        await settle(tester, 100);
        final gift = await findChannel(tester);
        await shoot(tester, 'o1-regalo');
        await tester.tap(gift);
        await settle(tester, 60);
        await shoot(tester, 'o2-desenvuelto');
        await enter(tester, gift);
        await shoot(tester, 'o3-nuevo');

        final levels = find.byKey(const ValueKey<String>('ohirune.levels'));
        if (levels.evaluate().isNotEmpty) {
          await tester.tap(levels);
          await settle(tester, 30);
          await shoot(tester, 'o4-tableros');
          await tester.tap(find.byKey(const ValueKey<String>('ohirune.level.easy')).last);
          await settle(tester, 40);
        }

        final mirror = OhirunePuzzle.generate(OhiruneLevel.easy.size, seed: _seed);
        final board = find.byKey(const ValueKey<String>('ohirune.board'));
        Offset cell(int x, int y) {
          final rect = tester.getRect(board);
          final u = rect.width / mirror.size;
          return rect.topLeft + Offset((x + .5) * u, (y + .5) * u);
        }

        // X en la fila del primer Tama (menos su sitio), con el interruptor.
        await tester.tap(find.byKey(const ValueKey<String>('ohirune.mode.cross')));
        await settle(tester, 10);
        for (var x = 0; x < mirror.size; x++) {
          if (x == mirror.solution[0]) continue;
          await tester.tapAt(cell(x, 0));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.tap(find.byKey(const ValueKey<String>('ohirune.mode.nap')));
        await settle(tester, 10);
        await tester.tapAt(cell(mirror.solution[0], 0));
        await settle(tester, 6);
        await tester.tapAt(cell(mirror.solution[1], 1));
        await settle(tester, 20);
        // Un fallo que rompe una regla: la columna del primer Tama, en la
        // fila 3. Se enciende la columna en rojo.
        await tester.tapAt(cell(mirror.solution[0], 3));
        await settle(tester, 5);
        await shoot(tester, 'o5-fallo');
        await settle(tester, 30);
        await shoot(tester, 'o6-empezada');

        for (var y = 2; y < mirror.size; y++) {
          await tester.tapAt(cell(mirror.solution[y], y));
          await tester.pump(const Duration(milliseconds: 60));
        }
        await settle(tester, 14);
        await shoot(tester, 'o7-despiertan');
        await settle(tester, 80);
        await shoot(tester, 'o8-resultados');
        expect(find.byKey(const ValueKey<String>('ohirune.results')), findsOneWidget);
      });

      testWidgets('abierto y sin Tamas suficientes', (tester) async {
        await boot(tester, tamas: 3, opened: true);
        await settle(tester, 100);
        final channel = await findChannel(tester);
        await enter(tester, channel);
        await shoot(tester, 'o9-bloqueado');
        expect(find.byKey(const ValueKey<String>('ohirune.locked')), findsOneWidget);
      });
    });
  }
}
