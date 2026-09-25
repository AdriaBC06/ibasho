// Ibasho — la partida de Odori se compone, se juega con teclas y se pausa.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/odori/odori_board.dart';
import 'package:ibasho/games/odori/odori_butai.dart';
import 'package:ibasho/games/odori/odori_keys.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/odori/odori_catalog.dart';
import 'package:ibasho/games/odori/odori_channel.dart';
import 'package:ibasho/games/odori/odori_chart.dart';
import 'package:ibasho/games/odori/odori_engine.dart';
import 'package:ibasho/games/odori/odori_play.dart';
import 'package:ibasho/games/odori/odori_store.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';

import 'support/fakes.dart';

const _song = OdoriSong(
  id: 'kasa',
  title: 'Ame no Hi no Kasa',
  native: '雨の日の傘',
  versions: [OdoriVersion(songId: 'kasa', id: 'kasa')],
);

/// Con letra: Tamagoyaki en japones, que empieza a cantar a los 8,7 s.
const _sung = OdoriSong(
  id: 'tamagoyaki',
  title: 'Tamagoyaki',
  native: '卵焼き',
  versions: [OdoriVersion(songId: 'tamagoyaki', id: 'tamagoyaki_ja_teto', lang: 'ja', singer: 'teto')],
);

final _mochi = Tama(
  id: 'mochi',
  creator: 'a',
  keeper: 'a',
  name: 'Mochi',
  personality: TamaPersonality.playful,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _boot(WidgetTester tester, Size size, OdoriSetup? setup) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(FakeIbashoBackend()),
        secureStoreProvider.overrideWithValue(FakeSecureStore(session: null)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        initialPreferencesProvider.overrideWithValue(const Preferences()),
      ],
      child: RepaintBoundary(child: WidgetsApp(
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
          reducedMotion: true,
          child: VirtualCanvas(child: navigator!),
        ),
        home: setup == null ? const OdoriChannel() : OdoriPlayScreen(setup: setup),
      )),
    ),
  );
  // La partitura se lee del bundle de verdad.
  final ready = setup == null
      ? find.byKey(const ValueKey<String>('odori.play'))
      : find.byType(setup.butai ? ButaiStage : TakiBoard);
  for (var i = 0; i < 40 && ready.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  for (final (name, size, keys, flow) in [
    ('horizontal, 4 teclas', const Size(1280, 800), 4, TakiFlow.down),
    ('vertical, 7 teclas', const Size(360, 780), 7, TakiFlow.down),
    ('de izquierda a derecha', const Size(1280, 800), 5, TakiFlow.right),
    ('una tecla, hacia arriba', const Size(1280, 800), 1, TakiFlow.up),
  ]) {
    testWidgets('se juega y se pausa: $name', (tester) async {
      await _boot(
        tester,
        size,
        OdoriSetup(
          song: _song,
          version: _song.versions.first,
          keys: keys,
          difficulty: OdoriDifficulty.hard,
          flow: flow,
          look: NoteLook.values[keys % 3],
        ),
      );
      expect(find.byType(TakiBoard), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space, physicalKey: PhysicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space, physicalKey: PhysicalKeyboardKey.space);
      await tester.tapAt(tester.getCenter(find.byType(TakiBoard)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey<String>('odori.paused')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('odori.resume')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey<String>('odori.paused')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size, touch) in [
    ('horizontal', const Size(1280, 800), ButaiTouch.targets),
    ('vertical', const Size(360, 780), ButaiTouch.targets),
    ('vertical con botones', const Size(360, 780), ButaiTouch.pad),
  ]) {
    testWidgets('Butai se juega con teclas, dianas y botones: $name', (tester) async {
      await _boot(
        tester,
        size,
        OdoriSetup(
          song: _song,
          version: _song.versions.first,
          keys: butaiKeys,
          difficulty: OdoriDifficulty.hard,
          mode: OdoriMode.butai,
          butaiTouch: touch,
        ),
      );
      expect(find.byType(ButaiStage), findsOneWidget);
      // El escenario llena la pantalla.
      expect(tester.getSize(find.byType(ButaiStage)), size);
      expect(find.byType(TakiBoard), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD, physicalKey: PhysicalKeyboardKey.keyD);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD, physicalKey: PhysicalKeyboardKey.keyD);
      final withPad = size.width < 600 && touch == ButaiTouch.pad;
      final pad = find.byKey(const ValueKey<String>('odori.pad.2'));
      expect(pad, withPad ? findsOneWidget : findsNothing);
      if (withPad) await tester.tap(pad);
      // Un dedo en el escenario, aunque no haya diana, no rompe nada.
      await tester.tapAt(size.center(Offset.zero));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey<String>('odori.paused')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('con doble tecla, cada figura se toca con las dos', () {
    final one = OdoriSetup(
      song: _song,
      version: _song.versions.first,
      keys: butaiKeys,
      difficulty: OdoriDifficulty.normal,
      mode: OdoriMode.butai,
    );
    expect(one.laneOf(PhysicalKeyboardKey.keyJ), 2);
    expect(one.laneOf(PhysicalKeyboardKey.arrowUp), -1);
    final two = OdoriSetup(
      song: _song,
      version: _song.versions.first,
      keys: butaiKeys,
      difficulty: OdoriDifficulty.normal,
      mode: OdoriMode.butai,
      altKeys: butaiAltDefault,
    );
    expect(two.laneOf(PhysicalKeyboardKey.keyJ), 2);
    expect(two.laneOf(PhysicalKeyboardKey.arrowUp), 2);
    expect(two.laneOf(PhysicalKeyboardKey.arrowLeft), 0);
    expect(two.laneOf(PhysicalKeyboardKey.keyQ), -1);
  });

  testWidgets('el canal cambia a Butai y abre el escenario', (tester) async {
    await _boot(tester, const Size(1280, 800), null);
    await tester.ensureVisible(find.byKey(const ValueKey<String>('odori.mode.butai')));
    await tester.tap(find.byKey(const ValueKey<String>('odori.mode.butai')));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('odori.keys.4')), findsNothing, reason: 'Butai va con 4 fijas');
    // Las burbujas pueden llevar figuras o teclas en vez de flechas.
    await tester.ensureVisible(find.byKey(const ValueKey<String>('odori.mark.keys')));
    await tester.tap(find.byKey(const ValueKey<String>('odori.mark.keys')));
    await tester.pump();
    expect(
      tester.widgetList<ButaiSymbol>(find.byType(ButaiSymbol)).every((s) => s.mark == ButaiMark.keys && s.caps.length == 4),
      isTrue,
    );
    // Doble tecla: la leyenda muestra las dos.
    await tester.ensureVisible(find.byKey(const ValueKey<String>('odori.double.true')));
    await tester.tap(find.byKey(const ValueKey<String>('odori.double.true')));
    await tester.pump();
    expect(find.text('D · ←'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey<String>('odori.play')));
    await tester.tap(find.byKey(const ValueKey<String>('odori.play')));
    for (var i = 0; i < 40 && find.byType(ButaiStage).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(ButaiStage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('el canal elige cancion, dificultad y teclas y abre la partida', (tester) async {
    await _boot(tester, const Size(1280, 800), null);
    expect(find.byKey(const ValueKey<String>('odori.song.yako')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('odori.song.yako')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('odori.difficulty.extreme')));
    await tester.tap(find.byKey(const ValueKey<String>('odori.difficulty.extreme')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('odori.keys.6')));
    await tester.tap(find.byKey(const ValueKey<String>('odori.keys.6')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('odori.play')));
    await tester.tap(find.byKey(const ValueKey<String>('odori.play')));
    for (var i = 0; i < 40 && find.byType(TakiBoard).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(TakiBoard), findsOneWidget);
    expect(find.text('Yakō'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  // Capturas en build/screenshots/ para mirar el tablero con notas de verdad.
  group('capturas', () {
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

    for (final (name, size) in [
      ('odori-canal', const Size(1280, 800)),
      ('odori-canal-movil', const Size(390, 844)),
    ]) {
      testWidgets(name, (tester) async {
        await _boot(tester, size, null);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
        await tester.pump(const Duration(milliseconds: 600));
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          Directory('build/screenshots').createSync(recursive: true);
          File('build/screenshots/$name.png').writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
        });
      });
    }

    for (final (name, size, keys, look, mode, song, wait, mark, touch) in [
      ('odori-4k', const Size(1280, 800), 4, NoteLook.circle, OdoriMode.taki, _song, 6, ButaiMark.arrows, ButaiTouch.targets),
      ('odori-7k-movil', const Size(390, 844), 7, NoteLook.bar, OdoriMode.taki, _song, 6, ButaiMark.arrows, ButaiTouch.targets),
      ('odori-4k-flechas', const Size(1280, 800), 4, NoteLook.arrow, OdoriMode.taki, _song, 6, ButaiMark.arrows, ButaiTouch.targets),
      ('odori-letra', const Size(1280, 800), 5, NoteLook.circle, OdoriMode.taki, _sung, 12, ButaiMark.arrows, ButaiTouch.targets),
      ('odori-butai', const Size(1280, 800), 4, NoteLook.circle, OdoriMode.butai, _sung, 12, ButaiMark.arrows, ButaiTouch.targets),
      ('odori-butai-movil', const Size(390, 844), 4, NoteLook.circle, OdoriMode.butai, _sung, 12, ButaiMark.keys, ButaiTouch.targets),
      ('odori-butai-figuras', const Size(1280, 800), 4, NoteLook.circle, OdoriMode.butai, _sung, 12, ButaiMark.shapes, ButaiTouch.targets),
      ('odori-butai-botones', const Size(390, 844), 4, NoteLook.circle, OdoriMode.butai, _sung, 12, ButaiMark.shapes, ButaiTouch.pad),
    ]) {
      testWidgets(name, (tester) async {
        await _boot(
          tester,
          size,
          OdoriSetup(
            song: song,
            version: song.versions.first,
            keys: keys,
            difficulty: OdoriDifficulty.extreme,
            mode: mode,
            butaiMark: mark,
            butaiTouch: touch,
            look: look,
            tama: _mochi,
            assist: OdoriAssist.shield,
          ),
        );
        // El reloj es un cronometro de verdad: se deja correr hasta el
        // estribillo (o hasta que empieza a cantar).
        await tester.runAsync(() => Future<void>.delayed(Duration(seconds: wait)));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF, physicalKey: PhysicalKeyboardKey.keyF);
        await tester.pump(const Duration(milliseconds: 16));
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          Directory('build/screenshots').createSync(recursive: true);
          File('build/screenshots/$name.png').writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
        });
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF, physicalKey: PhysicalKeyboardKey.keyF);
      });
    }
  });
}
