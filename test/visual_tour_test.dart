// Ibasho — recorrido visual: renderiza cada pantalla y la guarda como PNG.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// No compara contra golden files: su trabajo es dejar en `build/screenshots/`
// una imagen de cada pantalla al tamano exacto del lienzo, para poder mirarlas
// y juzgarlas.
//
//   flutter test test/visual_tour_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

const String _outputDir = 'build/screenshots';

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  late Directory output;

  setUpAll(() async {
    output = Directory(_outputDir)..createSync(recursive: true);
    // flutter_test pinta con Ahem, donde cada letra es un bloque. Para juzgar
    // la estetica y los desbordes de verdad hacen falta las fuentes reales.
    Future<ByteData> bytes(String file) async =>
        ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync());
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

  Future<void> boot(
    WidgetTester tester, {
    required FakeIbashoBackend backend,
    bool signedIn = true,
    Preferences preferences = const Preferences(),
  }) async {
    tester.view.physicalSize = T.canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = FakeSettingsStore()..saved = preferences;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          secureStoreProvider.overrideWithValue(
            FakeSecureStore(session: signedIn ? backend.tokens : null),
          ),
          settingsStoreProvider.overrideWithValue(settings),
          initialPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const RepaintBoundary(child: IbashoApp()),
      ),
    );
  }

  /// Avanza el tiempo sin quedarse atrapado en animaciones que no paran
  /// (el reloj late cada segundo).
  Future<void> settle(WidgetTester tester, [int frames = 40]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    // Leer pixeles es trabajo asincrono de verdad: bajo el reloj simulado de
    // los tests de widgets no termina nunca si no se sale con runAsync.
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${output.path}/$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    });
  }

  testWidgets('splash', (tester) async {
    await boot(tester, backend: FakeIbashoBackend(), signedIn: false);
    await tester.pump(const Duration(milliseconds: 1500));
    await shoot(tester, '01-splash');
    await settle(tester, 80);
  });

  testWidgets('login', (tester) async {
    await boot(tester, backend: FakeIbashoBackend(), signedIn: false);
    await settle(tester, 100);
    await shoot(tester, '02-login');
  });

  testWidgets('cambio de contrasena', (tester) async {
    await boot(
      tester,
      backend: FakeIbashoBackend(mustChangePassword: true),
    );
    await settle(tester, 100);
    await shoot(tester, '03-cambio-contrasena');
  });

  testWidgets('entorno: equilibrado, superior grande, inferior grande',
      (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await shoot(tester, '04-entorno-equilibrado');

    final magnify = find.byKey(const ValueKey<String>('magnify'));
    expect(magnify, findsOneWidget);

    await tester.tap(magnify);
    await settle(tester, 20);
    await shoot(tester, '05-entorno-superior');

    await tester.tap(magnify);
    await settle(tester, 20);
    await shoot(tester, '06-entorno-inferior');

    await tester.tap(magnify);
    await settle(tester, 20);
  });

  testWidgets('apertura de canal a medias y del todo', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);

    await tester.tap(find.byKey(const ValueKey<String>('channel.settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 210));
    await shoot(tester, '07-apertura-canal');
    await settle(tester, 40);
    await shoot(tester, '08-ajustes');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -260));
    await settle(tester, 10);
    await shoot(tester, '08b-ajustes-musica');
  });

  testWidgets('perfil', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.profile')));
    await settle(tester, 60);
    await shoot(tester, '09-perfil');
  });

  testWidgets('administracion', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.admin')));
    await settle(tester, 60);
    await shoot(tester, '10-administracion');
  });

  testWidgets('depuracion', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.debug')));
    await settle(tester, 60);
    await shoot(tester, '13-depuracion');
  });

  testWidgets('selector de zona horaria', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.profile')));
    await settle(tester, 60);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await settle(tester, 10);
    await tester.tap(find.text('Madrid'));
    await settle(tester, 20);
    await shoot(tester, '14-zona-horaria');
  });

  testWidgets('ranura libre', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.slot-0')));
    await settle(tester, 60);
    await shoot(tester, '11-proximamente');
  });

  testWidgets('entorno a 1920x1080, sin bandas', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    tester.view.physicalSize = const Size(1920, 1080);
    await settle(tester, 100);
    await shoot(tester, '15-entorno-1920x1080');
  });

  testWidgets('entorno en ingles y sin bateria', (tester) async {
    await boot(
      tester,
      backend: FakeIbashoBackend(link: LinkQuality.fair, locale: 'en'),
      preferences: const Preferences(localeCode: 'en'),
    );
    await settle(tester, 100);
    await shoot(tester, '12-entorno-en');
  });
}
