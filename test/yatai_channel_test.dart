// Ibasho — el canal del Yatai: comprar comida y desenvolver el regalo de un
// juego recien comprado.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
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
    // La pestana del gacha es un mostrador como los demas: solo vende
    // tickets. La maquina vive en su propio canal.
    await tester.tap(find.text('gacha'));
    await tester.pumpAndSettle();
    expect(find.text('gachaken'), findsWidgets);

    expect(tester.takeException(), isNull);

    await _finish(tester, container);
  });

  testWidgets('una canción de Odori ya comprada no enseña el precio en su baldosa', (tester) async {
    final backend = FakeIbashoBackend();
    backend
      ..seed('/shop/prices', {'odori_hanabi': 40, 'odori_kasa': 40})
      ..seed('/users/${backend.uid}/coins', 0)
      ..seed('/users/${backend.uid}/odori/songs/hanabi', true);
    final container = await _account(backend);
    await _until(tester, () => container.read(shopProvider).hasOdoriSong('hanabi'));

    await _boot(tester, const Size(1280, 800), container, const YataiChannel());
    await tester.pumpAndSettle();

    Finder inTile(String id, Finder f) =>
        find.descendant(of: find.byKey(ValueKey<String>('yatai.item.$id')), matching: f);
    // La rejilla va por páginas: se pasan hasta dar con las canciones.
    Future<void> pageTo(String id) async {
      for (var i = 0; i < 8 && find.byKey(ValueKey<String>('yatai.item.$id')).evaluate().isEmpty; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
      }
    }

    await pageTo('odori_hanabi');
    expect(inTile('odori_hanabi', find.text('en tu menú')), findsOneWidget);
    expect(inTile('odori_hanabi', find.textContaining('40')), findsNothing);
    await pageTo('odori_kasa');
    expect(inTile('odori_kasa', find.text('en tu menú')), findsNothing);

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

  for (final size in const [Size(1280, 800), Size(360, 640)]) {
    testWidgets('regalo diario (${size.width.toInt()}): se abre una vez y lo reparte', (tester) async {
      final backend = FakeIbashoBackend();
      backend
        ..seed('/shop/prices', {'food_cookie': 3})
        ..seed('/users/${backend.uid}/coins', 20)
        ..seed('/users/${backend.uid}/tickets', {'gachaken': 2, 'kinken': 0})
        ..seed('/users/${backend.uid}/pantry', {'cookie': 5, 'candy': 5});
      final container = await _account(backend);
      container
        ..read(coinsProvider)
        ..read(gachaProvider)
        ..read(pantryProvider)
        ..read(dailyGiftProvider);
      await _until(tester, () =>
          container.read(dailyGiftProvider).loaded &&
          container.read(coinsProvider) == 20 &&
          container.read(gachaProvider).ticketsOf(TicketKind.gachaken) == 2 &&
          container.read(pantryProvider)[TamaFood.cookie] == 5);

      await _boot(tester, size, container, const YataiChannel());
      await tester.pumpAndSettle();
      // Sin abrir: la pestaña lleva su punto.
      expect(find.byKey(const ValueKey<String>('yatai.tab.dot')), findsOneWidget);

      await tester.tap(find.text('regalo'));
      await tester.pumpAndSettle();
      expect(find.text('comida sorpresa'), findsOneWidget);
      expect(find.text('5–10'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('yatai.gift.open')));
      await _until(tester, () => container.read(dailyGiftProvider).claimedToday);
      await tester.pumpAndSettle();

      final gift = container.read(dailyGiftProvider).last!;
      expect(gift.coins, inInclusiveRange(5, 10));
      expect(await backend.read('/users/${backend.uid}/coins', idToken: ''), 20 + gift.coins);
      expect(await backend.read('/users/${backend.uid}/tickets/gachaken', idToken: ''), 3);
      final before = gift.food == TamaFood.cookie || gift.food == TamaFood.candy ? 5 : 0;
      expect(await backend.read('/users/${backend.uid}/pantry/${gift.food.name}', idToken: ''), before + 2);

      expect(find.byKey(const ValueKey<String>('yatai.tab.dot')), findsNothing);
      expect(find.text('abierto'), findsOneWidget);
      expect(find.text('+${gift.coins}'), findsOneWidget);
      expect(find.text('comida sorpresa'), findsNothing);
      expect(await container.read(dailyGiftProvider.notifier).claim(), isNull);
      expect(tester.takeException(), isNull);

      await _finish(tester, container);
    });
  }
}
