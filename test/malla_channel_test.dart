// Ibasho — el canal de Malla abre y se recorre en horizontal y en vertical.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/malla/malla_channel.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:ibasho/ui/screens/channel_route.dart';

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
        home: const MallaChannel(),
      ),
    ),
  );
  // La partida guardada se lee del disco: hace falta tiempo de verdad.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key));
  expect(target, findsOneWidget, reason: key);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final size in const [Size(1280, 800), Size(360, 640)]) {
    testWidgets('abre y empieza una partida contra la maquina a ${size.width.toInt()}', (tester) async {
      await _boot(tester, size);
      expect(find.byType(ChannelScaffold), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('malla.cpu')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tap(tester, 'malla.cpu');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'malla.cpu.start');
      expect(tester.takeException(), isNull);
    });

    testWidgets('abre la pantalla de online a ${size.width.toInt()}', (tester) async {
      await _boot(tester, size);
      await _tap(tester, 'malla.online');
      expect(find.byKey(const ValueKey<String>('malla.create')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('abre el historial, los logros y las reglas a ${size.width.toInt()}', (tester) async {
      await _boot(tester, size);
      for (final page in const ['malla.history', 'malla.achievements']) {
        await _tap(tester, page);
        expect(tester.takeException(), isNull, reason: page);
        expect(find.byKey(const ValueKey<String>('malla.cpu')), findsNothing, reason: page);
        // Atrás vuelve al menú del canal, no lo cierra.
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey<String>('malla.cpu')), findsOneWidget, reason: page);
      }
      await _tap(tester, 'malla.rules');
      expect(find.byKey(const ValueKey<String>('malla.rules.close')), findsOneWidget);
      await _tap(tester, 'malla.page.next');
      await _tap(tester, 'malla.rules.close');
      expect(find.byKey(const ValueKey<String>('malla.rules.close')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
