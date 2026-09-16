// Ibasho — comportamiento del entorno.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/audio/audio_service.dart';
import 'package:ibasho/state/admin.dart';
import 'package:ibasho/state/music_library.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:ibasho/ui/screens/channels/settings_channel.dart';
import 'package:ibasho/ui/widgets/panel.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'support/fakes.dart';

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  Future<FakeIbashoBackend> boot(WidgetTester tester, {bool isAdmin = true}) async {
    tester.view.physicalSize = T.canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeIbashoBackend(isAdmin: isAdmin);
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
        child: const IbashoApp(),
      ),
    );
    await settle(tester, 100);
    return backend;
  }

  testWidgets('cambiar el idioma en caliente traduce la interfaz y la fecha larga',
      (tester) async {
    await boot(tester);
    final now = DateTime.now();

    expect(find.text(DateFormat.MMMMEEEEd('es').format(now)), findsOneWidget);
    expect(find.text('ajustes'), findsWidgets);

    await tester.tap(find.text('ES'));
    await settle(tester, 10);

    expect(find.text(DateFormat.MMMMEEEEd('en').format(now)), findsOneWidget);
    expect(find.text(DateFormat.MMMMEEEEd('es').format(now)), findsNothing);
    expect(find.text('settings'), findsWidgets);
    expect(find.text('ajustes'), findsNothing);
    expect(find.text('EN'), findsOneWidget);
  });

  testWidgets('el boton de ampliar recorre los tres estados', (tester) async {
    await boot(tester);
    final magnify = find.byKey(const ValueKey<String>('magnify'));

    double top() => tester.getSize(find.byType(ScreenPanel).at(0)).height;
    double bottom() => tester.getSize(find.byType(ScreenPanel).at(1)).height;

    expect(top(), T.panelBalanced);
    expect(bottom(), T.panelBalanced);

    await tester.tap(magnify);
    await settle(tester, 12);
    expect(top(), T.panelLarge);
    expect(bottom(), T.panelSmall);

    await tester.tap(magnify);
    await settle(tester, 12);
    expect(top(), T.panelSmall);
    expect(bottom(), T.panelLarge);

    await tester.tap(magnify);
    await settle(tester, 12);
    expect(top(), T.panelBalanced);
    expect(bottom(), T.panelBalanced);
  });

  testWidgets('abrir un canal lo lleva a pantalla completa y cerrarlo vuelve',
      (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey<String>('channel.settings')));
    await settle(tester, 20);
    expect(find.byType(SettingsChannel), findsOneWidget);
    expect(tester.getSize(find.byType(SettingsChannel)), T.canvas,
        reason: 'a 1280x800 el canal ocupa el lienzo entero');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 20);
    expect(find.byType(SettingsChannel), findsNothing);
  });

  testWidgets('el lienzo escala hacia arriba y hacia abajo con la ventana',
      (tester) async {
    await boot(tester);
    // 16:9 llena sin bandas; 16:10 exacto; mas estrecho que 16:10 deja bandas
    // arriba y abajo; ultrapanoramico pasa del tope y deja bandas a los lados.
    for (final window in const [
      Size(1920, 1080),
      Size(2560, 1600),
      Size(900, 700),
      Size(3440, 1440),
    ]) {
      tester.view.physicalSize = window;
      await settle(tester, 4);
      final canvasWidth = VirtualCanvas.widthFor(window);
      final scale = [window.width / canvasWidth, window.height / T.canvas.height]
          .reduce((a, b) => a < b ? a : b);
      final left = (window.width - canvasWidth * scale) / 2;
      final top = (window.height - T.canvas.height * scale) / 2;
      final panel = tester.getRect(find.byType(ScreenPanel).first);
      // El panel superior esta a 40 del borde y 12 de arriba en el lienzo.
      expect(panel.left, moreOrLessEquals(left + 40 * scale, epsilon: .5));
      expect(panel.top, moreOrLessEquals(top + 12 * scale, epsilon: .5));
      expect(panel.width, moreOrLessEquals((canvasWidth - 80) * scale, epsilon: .5));
    }
    // En 16:9 el lienzo llena la ventana entera: nada de bandas.
    expect(VirtualCanvas.widthFor(const Size(1920, 1080)),
        moreOrLessEquals(800 * 16 / 9, epsilon: .01));
  });

  testWidgets('el canal de administracion solo existe para un admin',
      (tester) async {
    await boot(tester, isAdmin: false);
    expect(find.byKey(const ValueKey<String>('channel.admin')), findsNothing);
    expect(find.byKey(const ValueKey<String>('channel.settings')), findsOneWidget);
  });

  test('la musica del menu empieza con las de serie y crece al escuchar', () {
    const fresh = MusicLibraryState(loaded: true);
    expect(fresh.available.map((t) => t.id), ['calma', 'aurora', 'brisa', 'noche']);
    expect(fresh.pending, 2);
    expect(fresh.isUnlocked(MusicTrack.plaza), isFalse);

    const later = MusicLibraryState(unlocked: {'bossa'}, loaded: true);
    // Se respeta el orden de la casa, no el de desbloqueo.
    expect(later.available.map((t) => t.id),
        ['bossa', 'calma', 'aurora', 'brisa', 'noche']);
    expect(later.pending, 1);
    expect(MusicTrack.fallback, MusicTrack.calma);
  });

  test('las contrasenas generadas tienen 16 caracteres y ninguno ambiguo', () {
    for (var i = 0; i < 500; i++) {
      final password = generatePassword();
      expect(password.length, 16);
      expect(password, isNot(matches(RegExp('[l1IO0]'))));
    }
  });
}

/// Avanza el reloj simulado sin esperar a que todo se quede quieto: el reloj
/// del entorno late cada segundo y `pumpAndSettle` no terminaria nunca.
Future<void> settle(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}
