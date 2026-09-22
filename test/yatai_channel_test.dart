// Ibasho — el canal del Yatai: comprar comida y desenvolver el regalo de un
// juego recien comprado.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:ibasho/ui/screens/channel_tile.dart';
import 'package:ibasho/ui/screens/channels/channel.dart';
import 'package:ibasho/ui/screens/channels/yatai_channel.dart';
import 'package:ibasho/ui/widgets/glyphs.dart';

import 'support/fakes.dart';

/// Una cuenta ya identificada, como en `shop_test.dart`.
Future<ProviderContainer> _account(FakeIbashoBackend backend) async {
  final container = ProviderContainer(overrides: [
    backendProvider.overrideWithValue(backend),
    secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
    settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
    initialPreferencesProvider.overrideWithValue(const Preferences()),
  ]);
  await container.read(sessionProvider.notifier).restore();
  return container;
}

/// Espera a que el backend falso conteste. Dentro de `testWidgets` el reloj es
/// falso y un `Future.delayed` no vence nunca sin bombear, asi que la espera
/// corre en tiempo real con `runAsync`.
Future<void> _until(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
}

/// Monta `child` con el mismo armazon que el entorno de verdad: lienzo,
/// pantalla y navegador, para que dialogos y avisos funcionen.
Future<void> _boot(
  WidgetTester tester,
  Size size,
  ProviderContainer container,
  Widget child,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
        home: child,
      ),
    ),
  );
}

/// Desmonta el arbol, deja vencer los avisos y cierra la cuenta dentro del
/// test: si se cierra en `addTearDown`, el temporizador de refresco de la
/// sesion sigue pendiente cuando el framework comprueba que no queda ninguno.
Future<void> _finish(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
  container.dispose();
}

void main() {
  testWidgets('ancho: comprar comida sube la despensa y avisa', (tester) async {
    final backend = FakeIbashoBackend();
    backend
      ..seed('/shop/prices', {'food_cookie': 3, 'game_minesweeper': 0})
      ..seed('/users/${backend.uid}/coins', 100)
      ..seed('/users/${backend.uid}/pantry/cookie', 5);
    final container = await _account(backend);
    await _until(tester, () => container.read(shopProvider).loaded);
    await _until(tester, () => container.read(coinsProvider) == 100);

    await _boot(tester, const Size(1280, 800), container, const YataiChannel());
    await tester.pumpAndSettle();

    // Juegos es la pestaña por defecto: hay que pasar a Tamas para ver comida.
    await tester.tap(find.text('Tamas'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('yatai.item.food_cookie')));
    await tester.pumpAndSettle();
    expect(find.text('×5'), findsWidgets); // unidades actuales, en las baldosas
    expect(find.text('tienes 5'), findsOneWidget); // y en el escaparate

    await tester.tap(find.byKey(const ValueKey<String>('yatai.buy')));
    await tester.pumpAndSettle();

    // El paso de cantidad: se eligen ×5.
    await tester.tap(find.byKey(const ValueKey<String>('yatai.qty.5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('yatai.qty.confirm')));
    await tester.pump();

    // La descarga falsa dura ~2,5 s.
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpAndSettle();

    expect(container.read(pantryProvider)[TamaFood.cookie], 10);
    expect(find.textContaining('despensa'), findsOneWidget);

    await _finish(tester, container);
  });

  testWidgets('vertical: pestañas y rejilla se componen sin desbordar', (tester) async {
    final backend = FakeIbashoBackend();
    backend
      ..seed('/shop/prices', {'food_cookie': 3, 'game_minesweeper': 0})
      ..seed('/users/${backend.uid}/coins', 0);
    final container = await _account(backend);
    await _until(tester, () => container.read(shopProvider).loaded);

    await _boot(tester, const Size(360, 780), container, const YataiChannel());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tamas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gacha'));
    await tester.pumpAndSettle();
    expect(find.text('próximamente'), findsWidgets);

    expect(tester.takeException(), isNull);

    await _finish(tester, container);
  });

  testWidgets('el regalo de un juego se desenvuelve al tocarlo', (tester) async {
    final backend = FakeIbashoBackend();
    final now = DateTime.now().millisecondsSinceEpoch;
    backend.seed('/users/${backend.uid}/games/minesweeper', {
      'state': 'gift',
      'at': now,
    });
    final container = await _account(backend);
    await _until(tester, 
      () => container.read(shopProvider).games['minesweeper']?.isGift == true,
    );

    final spec = ChannelSpec(
      id: 'game-minesweeper',
      glyph: Glyph.mine,
      label: (l) => l.channelMinesweeper,
      builder: (_) => const SizedBox.shrink(),
      gift: true,
      gameId: 'minesweeper',
    );

    await _boot(
      tester,
      const Size(360, 780),
      container,
      Center(
        child: ChannelTile(
          key: const ValueKey<String>('channel.game-minesweeper'),
          spec: spec,
          width: 140,
          height: 110,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey<String>('channel.game-minesweeper')));
    // La animacion de desenvolver tarda ~620 ms; no abre el canal al tocarlo.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await _until(tester, 
      () => container.read(shopProvider).games['minesweeper']?.isGift == false,
    );
    expect(container.read(shopProvider).games['minesweeper']!.isGift, isFalse);

    await _finish(tester, container);
  });
}
