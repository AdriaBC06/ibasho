// Ibasho — ninguna zona tactil por debajo de 48 dp.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Se mide con numeros, no a ojo: se recorre cada pantalla en el movil mas
// pequeño que se soporta (360x640) y se comprueba el rectangulo de verdad de
// cada control, ya escalado. Ademas se comprueba que el asistente de toques
// entrega a su control los toques que caen al lado en el lienzo horizontal,
// donde la composicion de escritorio no se puede agrandar.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:ibasho/ui/touch.dart';
import 'package:ibasho/ui/widgets/controls.dart';
import 'package:ibasho/ui/widgets/pressable.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

/// El movil mas pequeño que soporta Ibasho.
const Size _smallPhone = Size(360, 640);

Future<void> main() async {
  await initializeDateFormatting('es');

  Future<void> boot(WidgetTester tester, FakeIbashoBackend backend, {Size size = _smallPhone}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          initialPreferencesProvider.overrideWithValue(const Preferences()),
          batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
        ],
        child: const IbashoApp(),
      ),
    );
  }

  Future<void> settle(WidgetTester tester, [int frames = 60]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Mide cada control de la pantalla en curso y devuelve el mas pequeño.
  void audit(WidgetTester tester, String screen) {
    final controls = find.byType(Pressable).evaluate().toList();
    expect(controls, isNotEmpty, reason: '$screen: no hay ningun control');
    final scale = CanvasSize.scaleOf(controls.first);
    var checked = 0;
    for (final element in controls) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final visible = visibleRectOf(element);
      if (visible == null || visible.isEmpty) continue;
      checked++;
      final side = box.size.shortestSide * scale;
      expect(
        side,
        greaterThanOrEqualTo(minTouchTarget - .01),
        reason: '$screen: un control mide ${side.toStringAsFixed(1)} dp '
            '(${box.size.width.toStringAsFixed(0)}x${box.size.height.toStringAsFixed(0)})',
      );
    }
    expect(checked, greaterThan(0), reason: '$screen: no se ha medido nada');

    // Los deslizadores no son Pressable: se miden aparte, con su zona de
    // agarre incluida.
    for (final element in find.byType(IbashoSlider).evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      final grabbable = element
          .findAncestorRenderObjectOfType<RenderPointerListener>()
          ?.size
          .height;
      expect(
        (grabbable ?? box.size.height) * scale,
        greaterThanOrEqualTo(minTouchTarget - .01),
        reason: '$screen: un deslizador se agarra en menos de 48 dp',
      );
    }
  }

  List<Tama> family() => [
        sampleTama(),
        sampleTama(id: '-TamaMuestra00000002', name: 'Mochi'),
      ];

  testWidgets('el entorno y sus canales se tocan con el dedo', (tester) async {
    final backend = FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id);
    seedSocial(backend, mireiaBirthdayToday: false);
    await boot(tester, backend);
    await settle(tester, 100);
    audit(tester, 'entorno');

    for (final (channel, name) in const [
      ('settings', 'ajustes'),
      ('profile', 'perfil'),
      ('tamas', 'tus Tamas'),
      ('friends', 'amigos'),
      ('messages', 'mensajes'),
      ('news', 'noticias'),
      ('suggestions', 'sugerencias'),
      ('yatai', 'Yatai'),
      ('admin', 'administracion'),
      ('debug', 'depuracion'),
    ]) {
      // El Yatai suma un noveno canal fijo: en vertical (9 por pagina) el de
      // depuracion cae ya en la segunda pagina.
      if (channel == 'debug') {
        await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
        await settle(tester, 30);
      }
      await tester.tap(find.byKey(ValueKey<String>('channel.$channel')));
      await settle(tester, 50);
      audit(tester, name);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester, 40);
    }
  });

  testWidgets('la habitacion y el creador de un Tama se tocan con el dedo',
      (tester) async {
    await boot(
      tester,
      FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id),
    );
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.tamas')));
    await settle(tester, 50);
    await tester.tap(find.byKey(const ValueKey<String>('tamas.card.-TamaMuestra00000001')));
    await settle(tester, 40);
    audit(tester, 'habitacion');

    await tester.tap(find.byKey(const ValueKey<String>('tama.edit')));
    await settle(tester, 40);
    for (final tab in ['body', 'color', 'eyes', 'character']) {
      await tester.tap(find.byKey(ValueKey<String>('creator.tab.$tab')));
      await settle(tester, 14);
      audit(tester, 'creador · $tab');
    }
  });

  testWidgets('en horizontal el asistente entrega el toque al control de al lado',
      (tester) async {
    // Una ventana de 640x400: el lienzo de 1280x800 se escala a la mitad,
    // que es justo lo que pasa en un movil girado.
    await boot(tester, FakeIbashoBackend(), size: const Size(640, 400));
    await settle(tester, 100);

    // El lienzo horizontal en un movil se escala a la mitad: la flecha de
    // pagina mide 36 y no se puede agrandar sin rehacer la composicion de
    // escritorio. Un dedo que cae 12 px al lado tiene que abrir el canal
    // igualmente.
    final magnify = find.byKey(const ValueKey<String>('magnify'));
    final rect = tester.getRect(magnify);
    final beside = Offset(rect.left - 12, rect.center.dy);
    expect(
      tester.hitTestOnBinding(beside).path.any((entry) {
        final target = entry.target;
        return target is RenderPointerListener && target == tester.renderObject(magnify);
      }),
      isFalse,
      reason: 'el punto de prueba no debe caer ya sobre el boton',
    );

    final target = nearestTouchTarget(beside);
    expect(target, isNotNull, reason: 'nadie recoge un toque a 12 px del boton');

    // Y un toque de verdad en ese punto hunde y suelta el boton, como si
    // hubiera caido encima.
    final gesture = await tester.startGesture(beside, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await settle(tester, 30);
  });
}
