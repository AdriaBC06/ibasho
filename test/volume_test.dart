// Ibasho — silencio y volumen desde la barra de estado (0.8.0).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:ibasho/ui/screens/status_bar.dart';
import 'package:ibasho/ui/widgets/glyphs.dart';

import 'support/fakes.dart';

void main() {
  List<Override> overrides(FakeSettingsStore store, Preferences initial) => [
        backendProvider.overrideWithValue(FakeIbashoBackend()),
        secureStoreProvider.overrideWithValue(FakeSecureStore()),
        settingsStoreProvider.overrideWithValue(store),
        initialPreferencesProvider.overrideWithValue(initial),
        batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
      ];

  group('las preferencias', () {
    test('silenciar guarda el volumen y quitarlo lo devuelve', () async {
      final store = FakeSettingsStore();
      final container = ProviderContainer(overrides: overrides(store, const Preferences(musicVolume: .4)));
      addTearDown(container.dispose);
      final prefs = container.read(preferencesProvider.notifier);

      await prefs.toggleMusicMuted();
      expect(container.read(preferencesProvider).musicMuted, isTrue);
      expect(container.read(preferencesProvider).musicLevel, 0);
      expect(container.read(preferencesProvider).musicVolume, .4);
      expect(store.saved.musicMuted, isTrue, reason: 'se recuerda al volver a abrir');

      await prefs.toggleMusicMuted();
      expect(container.read(preferencesProvider).musicLevel, .4);

      // Los efectos van aparte.
      await prefs.toggleEffectsMuted();
      expect(container.read(preferencesProvider).effectsLevel, 0);
      expect(container.read(preferencesProvider).musicLevel, .4);
    });

    test('mover el volumen quita el silencio; a cero, el boton vuelve al de serie', () async {
      final container = ProviderContainer(
        overrides: overrides(FakeSettingsStore(), const Preferences(effectsMuted: true)),
      );
      addTearDown(container.dispose);
      final prefs = container.read(preferencesProvider.notifier);

      await prefs.setEffectsVolume(.3);
      expect(container.read(preferencesProvider).effectsMuted, isFalse);
      expect(container.read(preferencesProvider).effectsLevel, .3);

      await prefs.setMusicVolume(0);
      await prefs.toggleMusicMuted();
      expect(container.read(preferencesProvider).musicLevel, const Preferences().musicVolume);
    });

    test('el silencio viaja en el JSON y falta en los archivos viejos', () {
      final back = Preferences.fromJson(const Preferences(musicMuted: true).toJson());
      expect(back.musicMuted, isTrue);
      expect(back.effectsMuted, isFalse);
      expect(Preferences.fromJson(const {'musicVolume': .2}).musicMuted, isFalse);
    });
  });

  testWidgets('la barra silencia al tocar y la rueda sube y baja', (tester) async {
    tester.view.physicalSize = const Size(900, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = FakeSettingsStore();
    final container = ProviderContainer(overrides: overrides(store, const Preferences(musicVolume: .5)));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WidgetsApp(
          color: T.cyan,
          locale: const Locale('es'),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          builder: (context, _) => IbashoSkin(
            accent: T.cyan,
            reducedMotion: true,
            child: const VirtualCanvas(child: Center(child: StatusBar())),
          ),
        ),
      ),
    );
    await tester.pump();

    Finder glyph(Glyph g) => find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == g);
    expect(glyph(Glyph.note), findsOneWidget);
    expect(glyph(Glyph.speaker), findsOneWidget);

    // El servicio de audio encadena la musica en una cola de futuros de
    // verdad: los cambios se dejan correr fuera del reloj falso.
    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    await tester.tap(glyph(Glyph.note));
    await settle();
    expect(container.read(preferencesProvider).musicMuted, isTrue);
    expect(glyph(Glyph.noteOff), findsOneWidget);

    // Rueda hacia arriba: un paso por encima de cero, y quita el silencio.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final at = tester.getCenter(glyph(Glyph.noteOff));
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await settle();
    expect(container.read(preferencesProvider).musicMuted, isFalse);
    expect(container.read(preferencesProvider).musicLevel, closeTo(.05, 1e-9));

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await settle();
    expect(container.read(preferencesProvider).musicLevel, closeTo(.15, 1e-9));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await settle();
    expect(container.read(preferencesProvider).musicLevel, closeTo(.1, 1e-9));
    expect(store.saved.musicVolume, closeTo(.1, 1e-9));
    expect(find.text('10'), findsOneWidget, reason: 'la cifra sale al cambiarlo');

    // La cifra se va sola al rato.
    await tester.sendEventToBinding(pointer.removePointer());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('10'), findsNothing);

    // Fuera el arbol y los relojes de la barra (bateria, conexion).
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
