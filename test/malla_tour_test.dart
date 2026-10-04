// Ibasho — recorrido visual de Malla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja en `build/screenshots/malla/<lienzo>/` el menú, los ajustes contra
// tus Tamas, una partida de principio a fin, la pantalla online, la sala de
// espera, el historial, los logros y las reglas.
//
//   flutter test test/malla_tour_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/malla.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/malla/malla_channel.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

const Map<String, Size> _canvases = <String, Size>{
  'horizontal': Size(1280, 800),
  'vertical-360x640': Size(360, 640),
  'vertical-411x914': Size(411, 914),
};

Future<void> main() async {
  await initializeDateFormatting('es');

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

  for (final MapEntry(key: folder, value: size) in _canvases.entries) {
    final output = Directory('build/screenshots/malla/$folder')..createSync(recursive: true);

    testWidgets('recorrido de Malla en $folder', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final backend = FakeIbashoBackend(
        tamas: [
          sampleTama(),
          sampleTama(id: '-TamaMuestra00000002', name: 'Kuro', look: const TamaLook(color: '#7FD4F5')),
          sampleTama(id: '-TamaMuestra00000003', name: 'Hana', look: const TamaLook(color: '#FFC58A')),
        ],
        profileTamaId: sampleTama().id,
      );
      seedSocial(backend);
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(backend),
          secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          initialPreferencesProvider.overrideWithValue(const Preferences()),
          batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
        ],
      );
      await tester.runAsync(() => container.read(sessionProvider.notifier).restore());
      final me = container.read(sessionProvider).accountId;
      final at = DateTime(2026, 10, 3, 21, 14).millisecondsSinceEpoch;
      for (var i = 0; i < 7; i++) {
        backend.seed('/mallaHistory/$me/ABC23${i + 2}', {
          'at': at - i * 3600000,
          'size': 3 + i % 3,
          'me': 0,
          'why': i == 5 ? 'left' : 'board',
          'p': {
            '0': {'a': me, 'name': 'Adrià', 's': 4 + i % 3, 'color': '#5bc8f5', 'tama': MallaTama.of(sampleTama()).toJson()},
            '1': {'a': kMireiaUid, 'name': 'mireia', 's': 3 + i % 4, 'color': '#f79a68', 'tama': MallaTama.of(mireiaTama()).toJson()},
            if (i.isEven) '2': {'a': kPauUid, 'name': 'pau', 's': 2, 'color': '#74dda2'},
          },
          'w': {(i % 3 == 0 ? '1' : '0'): true},
        });
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            child: WidgetsApp(
              color: T.cyan,
              locale: const Locale('es'),
              localizationsDelegates: L.localizationsDelegates,
              supportedLocales: L.supportedLocales,
              pageRouteBuilder: <R>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<R>(
                settings: settings,
                pageBuilder: (context, animation, secondary) => builder(context),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
              builder: (context, navigator) => IbashoSkin(
                accent: T.cyan,
                reducedMotion: false,
                child: VirtualCanvas(child: ColoredBox(color: T.shellBottom, child: navigator!)),
              ),
              home: const MallaChannel(),
            ),
          ),
        ),
      );

      Future<void> settle([int frames = 30]) async {
        for (var i = 0; i < frames; i++) {
          if (i % 10 == 0) await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      Future<void> shoot(String name) async {
        expect(tester.takeException(), isNull, reason: name);
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          File('${output.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
        });
      }

      Future<void> tap(String key) async {
        final target = find.byKey(ValueKey<String>(key));
        expect(target, findsOneWidget, reason: key);
        await tester.tap(target);
        await settle();
      }

      // Hasta que llegan los Tamas: son los rivales.
      for (var i = 0; i < 50 && container.read(tamasProvider).tamas.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await settle(40);
      await shoot('01-menu');

      await tap('malla.cpu');
      await tap('malla.rivals.2');
      await shoot('02-contra-tus-tamas');

      await tap('malla.cpu.start');
      await settle(40);
      await shoot('03-partida');

      // Se juega tocando por todo el tablero hasta que acaba.
      final board = tester.getRect(find.byKey(const ValueKey<String>('malla.board')));
      var shotMiddle = false;
      for (var round = 0; round < 6 && find.byKey(const ValueKey<String>('malla.results')).evaluate().isEmpty; round++) {
        for (var y = 0.0; y <= 1; y += .06) {
          for (var x = 0.0; x <= 1; x += .05) {
            if (find.byKey(const ValueKey<String>('malla.results')).evaluate().isNotEmpty) break;
            await tester.tapAt(Offset(board.left + board.width * x, board.top + board.height * y));
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pump(const Duration(milliseconds: 500));
          }
          if (!shotMiddle && y > .2) {
            shotMiddle = true;
            await settle(10);
            await shoot('04-a-medias');
          }
        }
      }
      await settle(40);
      await shoot('05-resultados');

      await tap('malla.leave');
      await tap('malla.online');
      await shoot('06-online');
      await tap('malla.tab.join');
      await shoot('07-unirse');
      await tap('malla.tab.create');
      await tap('malla.players.4');
      await tap('malla.create');
      await settle(40);
      await shoot('08-sala');

      await tap('malla.lobby.leave');
      await tap('malla.history');
      await settle(20);
      await shoot('09-historial');

      await tester.tap(find.byKey(const ValueKey<String>('malla.view.history')), warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();
      if (find.byKey(const ValueKey<String>('malla.achievements')).evaluate().isEmpty) {
        await tester.binding.handlePopRoute();
        await settle();
      }
      await tap('malla.achievements');
      await tap('malla.ach.first_win');
      await shoot('10-logros');

      await tester.binding.handlePopRoute();
      await settle();
      await tap('malla.rules');
      await shoot('11-reglas');

      // Fuera el canal y la cuenta: que no quede ningún reloj en marcha.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
