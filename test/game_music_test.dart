// Ibasho — cada juego suena con la musica que elija la cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/audio/audio_service.dart';
import 'package:ibasho/games/game_music.dart';
import 'package:ibasho/games/minesweeper/minesweeper_channel.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';

import 'support/fakes.dart';

const String _music = '/users/$kAdminUid/music';

Future<(FakeIbashoBackend, FakeSettingsStore)> _boot(
  WidgetTester tester, {
  void Function(FakeIbashoBackend)? seed,
  Preferences preferences = const Preferences(),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeIbashoBackend();
  seed?.call(fake);
  final settings = FakeSettingsStore()..saved = preferences;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(fake),
        secureStoreProvider.overrideWithValue(FakeSecureStore(session: fake.tokens)),
        settingsStoreProvider.overrideWithValue(settings),
        initialPreferencesProvider.overrideWithValue(preferences),
      ],
      child: WidgetsApp(
        color: T.cyan,
        locale: const Locale('es'),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        pageRouteBuilder: <R>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<R>(
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
        home: const GameMusic(
          gameId: 'minesweeper',
          track: MusicTrack.plaza,
          child: MinesweeperChannel(),
        ),
      ),
    ),
  );
  // Fuera de IbashoApp nadie restaura la sesion: se hace aqui.
  final container = ProviderScope.containerOf(tester.element(find.byType(MinesweeperChannel)));
  await container.read(sessionProvider.notifier).restore();
  await _settle(tester);
  return (fake, settings);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _settle(tester);
}

void main() {
  testWidgets('se elige otra cancion para el juego y se vuelve a la de serie', (tester) async {
    final (fake, _) = await _boot(tester, seed: (b) => b.seed('$_music/unlocked/feria', true));
    expect(AudioService.instance.profileTrack, MusicTrack.plaza);

    // El boton ♪ lo pone la cabecera, sin que el juego haga nada.
    await _tap(tester, 'game.music');
    expect(find.byKey(const ValueKey<String>('game.music.default')), findsOneWidget);
    // Las de serie y las desbloqueadas; las que faltan, no.
    expect(find.byKey(const ValueKey<String>('game.music.calma')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('game.music.cenit')), findsNothing);

    await _tap(tester, 'game.music.feria');
    expect(AudioService.instance.profileTrack, MusicTrack.feria);
    expect(fake.peek('$_music/games/minesweeper'), 'feria');

    await _tap(tester, 'game.music.default');
    expect(AudioService.instance.profileTrack, MusicTrack.plaza);
    expect(fake.peek('$_music/games/minesweeper'), isNull);
    await _tap(tester, 'game.music.ok');
  });

  testWidgets('la eleccion guardada suena al abrir el juego', (tester) async {
    await _boot(tester, seed: (b) => b.seed('$_music/games/minesweeper', 'noche'));
    expect(AudioService.instance.profileTrack, MusicTrack.noche);
  });

  testWidgets('una pista que ya no existe vuelve a la de serie', (tester) async {
    await _boot(tester, seed: (b) => b.seed('$_music/games/minesweeper', 'quitada'));
    expect(AudioService.instance.profileTrack, MusicTrack.plaza);
  });

  testWidgets('la musica de Hatarakitama guardada en el equipo pasa a la cuenta', (tester) async {
    final (fake, settings) = await _boot(
      tester,
      seed: (b) => b.seed('$_music/unlocked/mizuba', true),
      preferences: const Preferences(hatarakiTrack: 'mizuba'),
    );
    expect(fake.peek('$_music/games/hataraki'), 'mizuba');
    expect(settings.saved.hatarakiTrack, isEmpty);
  });
}
