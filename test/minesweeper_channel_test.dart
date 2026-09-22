// Ibasho — el canal del buscaminas se compone en horizontal y en vertical.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/minesweeper/minesweeper_channel.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';

import 'support/fakes.dart';

Future<void> _boot(WidgetTester tester, Size size) async {
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
        home: const MinesweeperChannel(),
      ),
    ),
  );
}

void main() {
  testWidgets('se compone en horizontal y se puede tocar una casilla', (tester) async {
    await _boot(tester, const Size(1280, 800));
    await tester.pumpAndSettle();

    expect(find.text('buscaminas'), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // minas de la dificultad facil

    final board = find.byKey(const ValueKey<String>('minesweeper.board'));
    expect(board, findsOneWidget);
    await tester.tapAt(tester.getCenter(board));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('se compone en vertical y se puede tocar una casilla', (tester) async {
    await _boot(tester, const Size(360, 780));
    await tester.pumpAndSettle();

    expect(find.text('buscaminas'), findsOneWidget);

    final board = find.byKey(const ValueKey<String>('minesweeper.board'));
    expect(board, findsOneWidget);
    await tester.tapAt(tester.getCenter(board));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('el nivel dificil en vertical se desplaza con InteractiveViewer', (tester) async {
    await _boot(tester, const Size(360, 780));
    await tester.pumpAndSettle();

    // En vertical los tableros se eligen en un dialogo.
    await tester.tap(find.byKey(const ValueKey<String>('minesweeper.levels')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('minesweeper.level.hard')));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    final board = find.byKey(const ValueKey<String>('minesweeper.board'));
    expect(board, findsOneWidget);
    await tester.tapAt(tester.getCenter(board));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
