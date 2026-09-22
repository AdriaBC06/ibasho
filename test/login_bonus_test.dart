// Ibasho — el bono diario: la cuenta de cada dia, el cobro y la pantalla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El recorrido deja en `build/screenshots/bono/<lienzo>/` la pantalla al
// abrirse sola, el sello cayendo, las monedas volando y el final.
//
//   flutter test test/login_bonus_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/state/login_bonus.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

const Map<String, Size> _canvases = <String, Size>{
  'horizontal': Size(1280, 800),
  'vertical-360x640': Size(360, 640),
};

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  group('la cuenta', () {
    // La misma prueba que test/rules/rules_05.test.mjs, para que la app y las
    // reglas no se separen.
    test('viernes 10, fin de semana 15 y entre 3 y 7 el resto', () {
      final fri = bonusDay(DateTime.utc(2026, 9, 18));
      expect(bonusDate(fri).weekday, DateTime.friday);
      expect(loginBonusFor(fri), 10);
      expect(loginBonusFor(fri + 1), 15);
      expect(loginBonusFor(fri + 2), 15);
      // De lunes a jueves, lo mismo que comprueba el test de las reglas.
      expect([for (var d = 3; d <= 6; d++) loginBonusFor(fri + d)], [7, 5, 3, 6]);
    });

    test('el dia de la semana de la cuenta es el de verdad todo el año', () {
      final start = bonusDay(DateTime.utc(2026));
      for (var d = start; d < start + 366; d++) {
        final weekday = bonusDate(d).weekday;
        final amount = loginBonusFor(d);
        if (weekday == DateTime.friday) {
          expect(amount, 10);
        } else if (weekday >= DateTime.saturday) {
          expect(amount, 15);
        } else {
          expect(amount, inInclusiveRange(3, 7));
        }
      }
    });

    test('entre semana no sale siempre lo mismo', () {
      final start = bonusDay(DateTime.utc(2026, 9));
      final amounts = {
        for (var d = start; d < start + 30; d++)
          if (bonusDate(d).weekday < DateTime.friday) loginBonusFor(d),
      };
      expect(amounts.length, greaterThanOrEqualTo(4));
    });
  });

  group('el cobro', () {
    Future<ProviderContainer> account(FakeIbashoBackend backend) async {
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(backend),
          secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          initialPreferencesProvider.overrideWithValue(const Preferences()),
          batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
        ],
      );
      await container.read(sessionProvider.notifier).restore();
      return container;
    }

    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 100 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('cobra lo de hoy, lo apunta en el calendario y no deja repetir', () async {
      final backend = FakeIbashoBackend()..seed('/users/${FakeIbashoBackend().uid}/coins', 10);
      final container = await account(backend);
      addTearDown(container.dispose);
      container.read(coinsProvider);
      container.read(loginBonusProvider);
      await until(() => container.read(loginBonusProvider).loaded && container.read(coinsProvider) == 10);
      expect(container.read(loginBonusProvider).claimedToday, isFalse);

      final today = bonusDay();
      final got = await container.read(loginBonusProvider.notifier).claim();
      expect(got, loginBonusFor(today));
      expect(await backend.read('/users/${backend.uid}/coins', idToken: ''), 10 + got!);
      final node = await backend.read('/users/${backend.uid}/login', idToken: '') as Map;
      expect(node['last']['day'], today);
      expect(node['days']['$today'], true);
      expect(container.read(loginBonusProvider).claimedToday, isTrue);

      expect(await container.read(loginBonusProvider.notifier).claim(), isNull);
    });

    test('lo cobrado otros dias se lee para el calendario', () async {
      final backend = FakeIbashoBackend();
      final today = bonusDay();
      backend.seed('/users/${backend.uid}/login', {
        'last': {'day': today - 1, 'at': 1},
        'days': {'${today - 3}': true, '${today - 1}': true},
      });
      final container = await account(backend);
      addTearDown(container.dispose);
      container.read(loginBonusProvider);
      await until(() => container.read(loginBonusProvider).loaded);
      final state = container.read(loginBonusProvider);
      expect(state.claimedOn(today - 1), isTrue);
      expect(state.claimedOn(today - 3), isTrue);
      expect(state.claimedOn(today - 2), isFalse);
      expect(state.claimedToday, isFalse);
    });
  });

  group('la pantalla', () {
    setUpAll(() async {
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
    setUp(() => loginBonusAutoOpen = true);
    tearDown(() => loginBonusAutoOpen = false);

    for (final MapEntry(key: folder, value: size) in _canvases.entries) {
      final output = Directory('build/screenshots/bono/$folder')..createSync(recursive: true);

      Future<void> shoot(WidgetTester tester, String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          File('${output.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
        });
      }

      Future<void> settle(WidgetTester tester, [int frames = 40]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      testWidgets('$folder: se abre sola al entrar, se cobra y ya no vuelve', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final today = bonusDay();
        final backend = FakeIbashoBackend(tamas: [sampleTama()], profileTamaId: sampleTama().id)
          ..seed('/users/${FakeIbashoBackend().uid}/coins', 40)
          // Un par de dias de este mes ya cobrados, si los hay antes de hoy.
          ..seed('/users/${FakeIbashoBackend().uid}/login', {
            'last': {'day': today - 1, 'at': 1},
            'days': {
              if (bonusDate(today - 1).month == bonusDate(today).month) '${today - 1}': true,
              if (bonusDate(today - 2).month == bonusDate(today).month) '${today - 2}': true,
            },
          });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(backend),
              secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
              settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
              initialPreferencesProvider.overrideWithValue(const Preferences()),
              batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
            ],
            child: const RepaintBoundary(child: IbashoApp()),
          ),
        );
        await settle(tester, 100);
        expect(find.byKey(const ValueKey<String>('bonus.panel')), findsOneWidget);
        await shoot(tester, 'b1-abierto');

        await tester.tap(find.byKey(const ValueKey<String>('bonus.claim')));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 200));
        await shoot(tester, 'b2-sello');
        await settle(tester, 26);
        await shoot(tester, 'b3-monedas');
        await settle(tester, 40);
        await shoot(tester, 'b4-cobrado');

        final amount = loginBonusFor(today);
        expect(await backend.read('/users/${backend.uid}/coins', idToken: ''), 40 + amount);
        expect(find.text('+$amount'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey<String>('bonus.close')));
        await settle(tester, 20);
        expect(find.byKey(const ValueKey<String>('bonus.panel')), findsNothing);
      });
    }

    testWidgets('con el de hoy ya cobrado no se abre', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = bonusDay();
      final backend = FakeIbashoBackend(tamas: [sampleTama()], profileTamaId: sampleTama().id)
        ..seed('/users/${FakeIbashoBackend().uid}/login', {
          'last': {'day': today, 'at': 1},
          'days': {'$today': true},
        });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            initialPreferencesProvider.overrideWithValue(const Preferences()),
            batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
          ],
          child: const RepaintBoundary(child: IbashoApp()),
        ),
      );
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.byKey(const ValueKey<String>('bonus.panel')), findsNothing);
    });
  });
}
