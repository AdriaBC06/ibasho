// Ibasho — bloqueo de versiones antiguas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/core/version.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/state/update_gate.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/screens/channels/settings_channel.dart';
import 'package:ibasho/ui/screens/login_screen.dart';
import 'package:ibasho/ui/screens/shell_screen.dart';
import 'package:ibasho/ui/screens/update_required_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  Future<void> settle(WidgetTester tester, [int frames = 40]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<FakeIbashoBackend> boot(WidgetTester tester, FakeIbashoBackend backend, {bool signedIn = true}) async {
    tester.view.physicalSize = T.canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          secureStoreProvider.overrideWithValue(FakeSecureStore(session: signedIn ? backend.tokens : null)),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          initialPreferencesProvider.overrideWithValue(const Preferences()),
        ],
        child: const IbashoApp(),
      ),
    );
    await settle(tester, 100);
    return backend;
  }

  test('la version de la app es la de pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(appVersion, declared);
    expect(AppVersion.tryParse(appVersion), isNotNull);
  });

  test('las versiones se comparan por numero, no por texto', () {
    AppVersion v(String s) => AppVersion.tryParse(s)!;
    expect(v('0.3.0') < v('0.3.1'), isTrue);
    expect(v('0.3.9') < v('0.4.0'), isTrue);
    expect(v('0.9.0') < v('0.10.0'), isTrue, reason: 'no es orden alfabetico');
    expect(v('0.99.99') < v('1.0.0'), isTrue);
    expect(v('1.0.0') < v('1.0.0'), isFalse);
    expect(v('1.2.3'), v('1.2.3'));
    expect(AppVersion.tryParse('1.2'), isNull);
    expect(AppVersion.tryParse('v1.2.3'), isNull);

    final requirement = UpdateRequirement.fromJson({'minVersion': '0.4.0', 'url': 'https://ibasho.top'})!;
    expect(requirement.blocks(v('0.3.0')), isTrue);
    expect(requirement.blocks(v('0.4.0')), isFalse);
    expect(requirement.blocks(v('1.0.0')), isFalse);
    expect(requirement.url, 'https://ibasho.top');
    expect(UpdateRequirement.fromJson(null), isNull);
    expect(UpdateRequirement.fromJson({'minVersion': 'cualquiera'}), isNull);
  });

  testWidgets('una version antigua no pasa del aviso, ni siquiera al login', (tester) async {
    final backend = FakeIbashoBackend()..seed('/system/update', {'minVersion': '99.0.0'});
    await boot(tester, backend, signedIn: false);
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('99.0.0'), findsOneWidget);
    expect(find.text(appVersion), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('update.download')), findsNothing, reason: 'sin url no hay boton');
  });

  testWidgets('subir la version minima con la app abierta la bloquea al momento, y bajarla la abre',
      (tester) async {
    final backend = await boot(tester, FakeIbashoBackend());
    expect(find.byType(ShellScreen), findsOneWidget);

    // Con un canal abierto encima.
    await tester.tap(find.byKey(const ValueKey<String>('channel.settings')));
    await settle(tester, 30);
    expect(find.byType(SettingsChannel), findsOneWidget);

    backend.seed('/system/update', {'minVersion': '99.0.0', 'url': 'https://ibasho.top/descargar'});
    await settle(tester, 30);
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.byType(SettingsChannel), findsNothing, reason: 'se cierra lo que hubiera abierto');
    expect(find.byKey(const ValueKey<String>('update.download')), findsOneWidget);

    // La misma version o una menor deja entrar.
    backend.seed('/system/update', {'minVersion': appVersion});
    await settle(tester, 30);
    expect(find.byType(UpdateRequiredScreen), findsNothing);
    expect(find.byType(ShellScreen), findsOneWidget);
  });

  testWidgets('el admin exige la version de su build y la puede quitar', (tester) async {
    final backend = await boot(tester, FakeIbashoBackend());
    final container = ProviderScope.containerOf(tester.element(find.byType(IbashoApp)));
    final admin = container.read(adminProvider.notifier);

    await admin.requireVersion(appVersion, url: 'https://ibasho.top');
    await settle(tester, 20);
    expect(backend.peek('/system/update'), {'minVersion': appVersion, 'url': 'https://ibasho.top'});
    expect(container.read(updateLockedProvider), isFalse, reason: 'su propia build sigue entrando');
    expect(find.byType(ShellScreen), findsOneWidget);

    await admin.clearRequiredVersion();
    await settle(tester, 20);
    expect(backend.peek('/system/update'), isNull);
    expect(container.read(updateRequirementProvider).valueOrNull, isNull);
  });
}
