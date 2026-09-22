// Ibasho — recorrido visual del Yatai y de sus juegos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja en `build/screenshots/juegos/<lienzo>/` cada estado de la tienda y del
// juego: escaparate de cada pestaña, la compra a medias, el regalo en la
// rejilla, una partida de buscaminas empezada, perdida y ganada, una de
// Tsumiki de principio a fin y una ronda de Nihongo con aciertos y fallos. La partida usa una
// semilla fija y una copia de la logica para saber donde tocar.
//
//   flutter test test/games_tour_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/minesweeper/minesweeper.dart';
import 'package:ibasho/games/minesweeper/minesweeper_channel.dart';
import 'package:ibasho/games/nihongo/nihongo_channel.dart';
import 'package:ibasho/games/nihongo/nihongo_widgets.dart';
import 'package:ibasho/games/tsumiki/tsumiki_channel.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

const Map<String, Size> _canvases = <String, Size>{
  'horizontal': Size(1280, 800),
  'vertical-360x640': Size(360, 640),
  'vertical-411x914': Size(411, 914),
};

const int _seed = 7;

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  setUpAll(() async {
    Future<ByteData> bytes(String file) async =>
        ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync());
    await (FontLoader('ZenKaku')
          ..addFont(bytes('ZenKakuGothicNew-Regular.ttf'))
          ..addFont(bytes('ZenKakuGothicNew-Medium.ttf'))
          ..addFont(bytes('ZenKakuGothicNew-Bold.ttf')))
        .load();
    await (FontLoader('Rounded')
          ..addFont(bytes('MPLUSRounded1c-Medium.ttf'))
          ..addFont(bytes('MPLUSRounded1c-Bold.ttf')))
        .load();
    debugMinesweeperSeed = _seed;
    debugTsumikiSeed = _seed;
    debugNihongoSeed = _seed;
  });

  for (final MapEntry(key: folder, value: size) in _canvases.entries) {
    final output = Directory('build/screenshots/juegos/$folder')
      ..createSync(recursive: true);

    Future<void> boot(
      WidgetTester tester, {
      required FakeIbashoBackend backend,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            secureStoreProvider.overrideWithValue(
              FakeSecureStore(session: backend.tokens),
            ),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            initialPreferencesProvider.overrideWithValue(const Preferences()),
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
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${output.path}/$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
      });
    }

    FakeIbashoBackend shopBackend({String? game, String gameId = 'minesweeper', int coins = 40}) {
      final backend = FakeIbashoBackend(
        tamas: [sampleTama()],
        profileTamaId: sampleTama().id,
      )
        ..seed('/shop/prices', {
          'game_minesweeper': 0,
          'game_tsumiki': 10,
          'game_nihongo': 150,
          for (final food in TamaFood.values) 'food_${food.name}': 3,
        })
        ..seed('/users/${FakeIbashoBackend().uid}/coins', coins);
      if (game != null) {
        backend.seed('/users/${backend.uid}/games/$gameId', {
          'state': game,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return backend;
    }

    Future<void> openChannel(WidgetTester tester, String id) async {
      final key = find.byKey(ValueKey<String>('channel.$id')).hitTestable();
      for (var i = 0; i < 3 && key.evaluate().isEmpty; i++) {
        await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
        await settle(tester, 30);
      }
      await tester.tap(key);
      await settle(tester, 60);
    }

    group(folder, () {
      testWidgets('yatai: pestañas y compra', (tester) async {
        await boot(tester, backend: shopBackend());
        await settle(tester, 100);
        await openChannel(tester, 'yatai');
        await shoot(tester, 'y1-juegos');

        await tester.tap(find.text('Tamas').last);
        await settle(tester, 30);
        await shoot(tester, 'y2-tamas');
        await tester.tap(find.byKey(const ValueKey<String>('yatai.buy')));
        await settle(tester, 30);
        await shoot(tester, 'y2b-cantidad');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester, 30);

        await tester.tap(find.text('gacha').last);
        await settle(tester, 30);
        await shoot(tester, 'y3-gacha');

        await tester.tap(find.text('juegos').last);
        await settle(tester, 30);
        await tester.tap(find.byKey(const ValueKey<String>('yatai.buy')));
        await settle(tester, 30);
        await shoot(tester, 'y4-confirmar');
        await tester.tap(find.text('conseguir').last);
        await settle(tester, 30);
        await shoot(tester, 'y5-comprando');
        await settle(tester, 80);
        await shoot(tester, 'y6-comprado');
        await settle(tester, 80);
      });

      testWidgets('regalo en la rejilla', (tester) async {
        await boot(tester, backend: shopBackend(game: 'gift'));
        await settle(tester, 100);
        final gift = find.byKey(const ValueKey<String>('channel.game-minesweeper')).hitTestable();
        for (var i = 0; i < 3 && gift.evaluate().isEmpty; i++) {
          await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
          await settle(tester, 30);
        }
        await shoot(tester, 'g1-regalo');
        await tester.tap(gift);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await shoot(tester, 'g2-revolviendose');
        await tester.pump(const Duration(milliseconds: 700));
        await shoot(tester, 'g2b-desenvolviendo');
        await tester.pump(const Duration(milliseconds: 600));
        await shoot(tester, 'g2c-asomando');
        await settle(tester, 40);
        await shoot(tester, 'g3-desenvuelto');
      });

      testWidgets('buscaminas: nueva, empezada, perdida y ganada', (tester) async {
        await boot(tester, backend: shopBackend(game: 'open'));
        await settle(tester, 100);
        await openChannel(tester, 'game-minesweeper');
        await shoot(tester, 'm1-nueva');

        // El tablero del dia, y vuelta al facil.
        final levels = find.byKey(const ValueKey<String>('minesweeper.levels'));
        if (levels.evaluate().isNotEmpty) {
          await tester.tap(levels);
          await settle(tester, 30);
          await shoot(tester, 'm0-tableros');
        }
        await tester.tap(find.byKey(const ValueKey<String>('minesweeper.level.daily')));
        await settle(tester, 40);
        await shoot(tester, 'm5-del-dia');
        if (levels.evaluate().isNotEmpty) {
          await tester.tap(levels);
          await settle(tester, 30);
        }
        await tester.tap(find.byKey(const ValueKey<String>('minesweeper.level.easy')));
        await settle(tester, 40);

        final board = find.byKey(const ValueKey<String>('minesweeper.board'));
        Offset cellCentre(MinesweeperGame g, int x, int y) {
          final rect = tester.getRect(board);
          final cw = rect.width / g.width;
          final ch = rect.height / g.height;
          return rect.topLeft + Offset((x + .5) * cw, (y + .5) * ch);
        }

        // Una copia de la partida con la misma semilla: dice donde estan las
        // minas despues del primer toque.
        var mirror = MinesweeperGame(MinesweeperLevel.easy, seed: _seed);
        const first = (4, 4);
        mirror.reveal(first.$1, first.$2);
        await tester.tapAt(cellCentre(mirror, first.$1, first.$2));
        await settle(tester, 10);

        // Dos banderas bien puestas: minas que ya tocan una casilla abierta.
        var flags = 0;
        for (var y = 0; y < mirror.height && flags < 2; y++) {
          for (var x = 0; x < mirror.width && flags < 2; x++) {
            final c = mirror.cellAt(x, y);
            if (!c.mine) continue;
            final touches = [
              for (var dy = -1; dy <= 1; dy++)
                for (var dx = -1; dx <= 1; dx++)
                  if (mirror.inBounds(x + dx, y + dy) &&
                      mirror.cellAt(x + dx, y + dy).revealed)
                    true,
            ].isNotEmpty;
            if (!touches) continue;
            mirror.toggleFlag(x, y);
            await tester.longPressAt(cellCentre(mirror, x, y));
            await settle(tester, 6);
            flags++;
          }
        }
        await settle(tester, 20);
        await shoot(tester, 'm2-empezada');

        // Perder: tocar una mina sin bandera.
        (int, int)? mine;
        for (var y = 0; y < mirror.height && mine == null; y++) {
          for (var x = 0; x < mirror.width && mine == null; x++) {
            final c = mirror.cellAt(x, y);
            if (c.mine && !c.flagged) mine = (x, y);
          }
        }
        await tester.tapAt(cellCentre(mirror, mine!.$1, mine.$2));
        await settle(tester, 12);
        await shoot(tester, 'm3-boom');
        await settle(tester, 40);
        await shoot(tester, 'm3b-perdida');

        // Ganar: nueva partida y destapar todo lo seguro.
        await tester.tap(find.byKey(const ValueKey<String>('minesweeper.restart')));
        await settle(tester, 30);
        mirror = MinesweeperGame(MinesweeperLevel.easy, seed: _seed);
        mirror.reveal(first.$1, first.$2);
        await tester.tapAt(cellCentre(mirror, first.$1, first.$2));
        await settle(tester, 4);
        for (var y = 0; y < mirror.height; y++) {
          for (var x = 0; x < mirror.width; x++) {
            final c = mirror.cellAt(x, y);
            if (c.mine || c.revealed) continue;
            mirror.reveal(x, y);
            await tester.tapAt(cellCentre(mirror, x, y));
            await tester.pump(const Duration(milliseconds: 40));
          }
        }
        await settle(tester, 14);
        await shoot(tester, 'm4-victoria');
        await settle(tester, 60);
        await shoot(tester, 'm4b-ganada');
        expect(mirror.status, MinesweeperStatus.won);
      });
      testWidgets('tsumiki: salida, cuenta, partida, pausa y final', (tester) async {
        await boot(tester, backend: shopBackend(game: 'open', gameId: 'tsumiki'));
        await settle(tester, 100);
        await openChannel(tester, 'game-tsumiki');
        await shoot(tester, 't1-salida');
        await tester.tap(find.byKey(const ValueKey<String>('tsumiki.level.5')));
        await settle(tester, 10);
        await tester.tap(find.byKey(const ValueKey<String>('tsumiki.start')));
        await settle(tester, 20);
        await shoot(tester, 't2-cuenta');
        await settle(tester, 40);

        // Unas piezas repartidas a izquierda y derecha.
        for (var i = 0; i < 9; i++) {
          final key = i.isEven ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
          for (var k = 0; k < i % 4 + 1; k++) {
            await tester.sendKeyEvent(key);
          }
          if (i % 3 == 0) await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await settle(tester, 4);
        }
        await tester.pump(const Duration(milliseconds: 90));
        await shoot(tester, 't3-jugando');

        await tester.tap(find.byKey(const ValueKey<String>('tsumiki.pause')));
        await settle(tester, 20);
        await shoot(tester, 't4-pausa');
        await tester.tap(find.byKey(const ValueKey<String>('tsumiki.resume')));
        await settle(tester, 6);

        for (var i = 0; i < 60 && find.byKey(const ValueKey<String>('tsumiki.results')).evaluate().isEmpty; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await settle(tester, 3);
          if (i == 14) await shoot(tester, 't5-alta');
        }
        await settle(tester, 14);
        await shoot(tester, 't6-fin');
        await settle(tester, 40);
        await shoot(tester, 't7-resultados');
        expect(find.byKey(const ValueKey<String>('tsumiki.results')), findsOneWidget);
      });

      testWidgets('nihongo: menu, aciertos, fallo, resultados y escribir', (tester) async {
        await boot(tester, backend: shopBackend(game: 'open', gameId: 'nihongo'));
        await settle(tester, 100);
        await openChannel(tester, 'game-nihongo');
        await shoot(tester, 'n1-menu');
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.category.kanji')));
        await settle(tester, 20);
        await shoot(tester, 'n1b-proximamente');
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.chart')));
        await settle(tester, 20);
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.chart.か')));
        await settle(tester, 10);
        await shoot(tester, 'n1c-tabla');
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.chart.script.katakana')));
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.chart.group.combo')));
        await settle(tester, 10);
        await shoot(tester, 'n1d-tabla-combinados');
        expect(find.byKey(const ValueKey<String>('nihongo.chart.キャ')), findsOneWidget);
        await tester.tap(find.text('menú').last);
        await settle(tester, 20);
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.category.hiragana')));
        await settle(tester, 10);
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.group.dakuten')));
        await settle(tester, 10);
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.start')));
        await settle(tester, 30);
        await shoot(tester, 'n2-tarjeta');

        String reading() => tester.widget<KanaCard>(find.byType(KanaCard).last).reading;
        Finder choice({required bool right}) {
          final r = reading();
          for (var i = 0; i < 4; i++) {
            final f = find.byKey(ValueKey<String>('nihongo.choice.$i'));
            final label = tester.widget<AnswerTile>(f).label;
            if ((label == r) == right) return f;
          }
          throw StateError('sin opcion');
        }

        await tester.tap(choice(right: true));
        await settle(tester, 8);
        await shoot(tester, 'n3-acierto');
        await settle(tester, 30);
        await tester.tap(choice(right: false));
        await settle(tester, 14);
        await shoot(tester, 'n4-fallo');
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.next')));
        await settle(tester, 20);
        for (var i = 0; i < 8; i++) {
          await tester.tap(choice(right: true));
          await settle(tester, 30);
        }
        await settle(tester, 20);
        await shoot(tester, 'n5-resultados');

        // Modo escribir.
        await tester.tap(find.text('menú').last);
        await settle(tester, 20);
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.category.katakana')));
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.mode.write')));
        await settle(tester, 10);
        await shoot(tester, 'n6-menu-katakana');
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.start')));
        await settle(tester, 30);
        await tester.enterText(find.byType(EditableText), 'xx');
        await tester.tap(find.byKey(const ValueKey<String>('nihongo.check')));
        await settle(tester, 20);
        await shoot(tester, 'n7-escribir-fallo');
      });
    });
  }
}
