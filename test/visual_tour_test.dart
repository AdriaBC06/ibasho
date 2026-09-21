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

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/core/friend_code.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/screens/channels/coming_soon_channel.dart';
import 'package:ibasho/ui/social/business_card.dart';
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
          batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
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
    final backend = FakeIbashoBackend()
      ..seed('/system/update', {'minVersion': '0.3.0', 'url': 'https://ibasho.top/descargar'});
    await boot(tester, backend: backend);
    await settle(tester, 100);
    // El Yatai llena la primera pagina de ocho canales: administracion cae en
    // la segunda.
    await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
    await settle(tester, 30);
    await tester.tap(find.byKey(const ValueKey<String>('channel.admin')));
    await settle(tester, 60);
    await shoot(tester, '10-administracion');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -330));
    await settle(tester, 10);
    await shoot(tester, '10b-administracion-version');
  });

  testWidgets('version antigua bloqueada', (tester) async {
    final backend = FakeIbashoBackend()
      ..seed('/system/update', {'minVersion': '0.4.0', 'url': 'https://ibasho.top/descargar'});
    await boot(tester, backend: backend, signedIn: false);
    await settle(tester, 100);
    await shoot(tester, '35-actualizar');
  });

  testWidgets('depuracion', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
    await settle(tester, 30);
    await tester.tap(find.byKey(const ValueKey<String>('channel.debug')));
    await settle(tester, 60);
    await shoot(tester, '13-depuracion');
  });

  testWidgets('yatai', (tester) async {
    final backend = FakeIbashoBackend()
      ..seed('/shop/prices', {'game_minesweeper': 0, 'food_cookie': 3, 'food_candy': 3});
    await boot(tester, backend: backend);
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.yatai')));
    await settle(tester, 60);
    await shoot(tester, '12-yatai');
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

  testWidgets('con un regalo en la rejilla, la segunda pagina se puede tocar',
      (tester) async {
    final backend = FakeIbashoBackend();
    backend.seed('/users/${backend.uid}/games/minesweeper', {
      'state': 'gift',
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    await boot(tester, backend: backend);
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
    await settle(tester, 30);
    await tester.tap(find.byKey(const ValueKey<String>('channel.slot-0')));
    await settle(tester, 60);
    expect(find.byType(ComingSoonChannel), findsOneWidget);
  });

  // Con el dedo un toque sin destino lo recoge `TouchAssist`, asi que solo un
  // raton de verdad delata una pagina cuyos canales no reciben el clic.
  testWidgets('con raton, la segunda pagina tambien se abre', (tester) async {
    final backend = FakeIbashoBackend();
    await boot(tester, backend: backend);
    await settle(tester, 100);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final next = tester.getCenter(find.byKey(const ValueKey<String>('grid.next')));
    await mouse.moveTo(next);
    await mouse.down(next);
    await mouse.up();
    await settle(tester, 30);

    final slot = tester.getCenter(find.byKey(const ValueKey<String>('channel.slot-0')));
    await mouse.moveTo(slot);
    await settle(tester, 10);
    await mouse.down(slot);
    await mouse.up();
    await settle(tester, 60);
    expect(find.byType(ComingSoonChannel), findsOneWidget);
  });

  testWidgets('ranura libre', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
    await settle(tester, 30);
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

  List<Tama> family() => [
        sampleTama(),
        sampleTama(
          id: '-TamaMuestra00000002',
          name: 'Mochi',
          personality: TamaPersonality.sleepy,
          look: const TamaLook(
            parts: {
              TamaPart.body: 4,
              TamaPart.eyes: 3,
              TamaPart.mouth: 0,
              TamaPart.crown: 3,
              TamaPart.cheeks: 2,
              TamaPart.pattern: 3,
              TamaPart.arms: 1,
            },
            color: '#74DDA2',
          ),
        ),
        sampleTama(
          id: '-TamaMuestra00000003',
          name: 'Bruma',
          personality: TamaPersonality.shy,
          lastPetted: DateTime.now().subtract(const Duration(days: 3)),
          lastFed: DateTime.now().subtract(const Duration(days: 3)),
          look: const TamaLook(
            parts: {
              TamaPart.body: 2,
              TamaPart.eyes: 5,
              TamaPart.mouth: 2,
              TamaPart.crown: 2,
              TamaPart.cheeks: 3,
              TamaPart.pattern: 4,
              TamaPart.feet: 1,
            },
            color: '#9F86E6',
          ),
        ),
      ];

  testWidgets('tamas: panel, canal, habitacion y creador', (tester) async {
    final backend = FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id);
    await boot(tester, backend: backend);
    await settle(tester, 100);
    await shoot(tester, '16-entorno-con-tama');

    await tester.tap(find.byKey(const ValueKey<String>('channel.tamas')));
    await settle(tester, 60);
    await shoot(tester, '17-tamas');

    await tester.tap(find.byKey(const ValueKey<String>('tamas.card.-TamaMuestra00000001')));
    await settle(tester, 40);
    await shoot(tester, '18-habitacion');
    await tester.tap(find.byKey(const ValueKey<String>('tama.feed.cookie')));
    await settle(tester, 14);
    await shoot(tester, '18b-habitacion-comiendo');
    await settle(tester, 40);

    await tester.tap(find.byKey(const ValueKey<String>('tama.edit')));
    await settle(tester, 40);
    await shoot(tester, '19-creador-cuerpo');
    for (final tab in ['color', 'eyes', 'mouth', 'crown', 'cheeks', 'limbs', 'character']) {
      await tester.tap(find.byKey(ValueKey<String>('creator.tab.$tab')));
      await settle(tester, 12);
      await shoot(tester, '19-creador-$tab');
    }
    await tester.tap(find.byKey(const ValueKey<String>('creator.tab.color')));
    await settle(tester, 8);
    await tester.tap(find.text('HEX libre'));
    await settle(tester, 12);
    await shoot(tester, '19-creador-color-hex');
  });

  testWidgets('tamas: la habitacion de uno melancolico', (tester) async {
    final backend = FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id);
    await boot(tester, backend: backend);
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.tamas')));
    await settle(tester, 60);
    // Tocar una ranura la elige; el escaparate de arriba cambia.
    await tester.tap(find.byKey(const ValueKey<String>('tamas.card.-TamaMuestra00000003')));
    await settle(tester, 20);
    await shoot(tester, '17b-tamas-elegido');
    await tester.tap(find.byKey(const ValueKey<String>('tamas.visit')));
    await settle(tester, 40);
    await shoot(tester, '20-habitacion-melancolico');
  });

  testWidgets('tamas: sin ninguno todavia', (tester) async {
    await boot(tester, backend: FakeIbashoBackend());
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.tamas')));
    await settle(tester, 60);
    await shoot(tester, '21-tamas-vacio');
    await tester.tap(find.byKey(const ValueKey<String>('tamas.createEmpty')));
    await settle(tester, 40);
    await shoot(tester, '22-creador-nuevo');
  });

  testWidgets('perfil con Tama', (tester) async {
    final backend = FakeIbashoBackend(tamas: family(), profileTamaId: family()[1].id);
    await boot(tester, backend: backend);
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.profile')));
    await settle(tester, 60);
    await shoot(tester, '23-perfil-con-tama');
  });

  /// La escena social con un amigo mas, pau, con su propio Tama.
  FakeIbashoBackend socialScene({bool birthday = true, String locale = 'es'}) {
    final backend = FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id, locale: locale);
    seedSocial(backend, mireiaBirthdayToday: birthday);
    final bolo = sampleTama(
      id: '-TamaPau000000000001',
      name: 'Bolo',
      creator: kPauUid,
      keeper: kPauUid,
      look: const TamaLook(
        parts: {TamaPart.body: 2, TamaPart.eyes: 4, TamaPart.crown: 3, TamaPart.arms: 2, TamaPart.feet: 2},
        color: '#F6CF4E',
      ),
    );
    final since = DateTime.now().subtract(const Duration(days: 20)).millisecondsSinceEpoch;
    backend
      ..seed('/users/$kAdminUid/card/tamaId', family().first.id)
      ..seed('/tamas/${bolo.id}', bolo.toJson())
      ..seed('/users/$kAdminUid/friends/$kPauUid', {'since': since})
      ..seed('/users/$kAdminUid/friendCount', 2)
      ..seed('/users/$kPauUid', {
        'card': {'displayName': 'Pau', 'accentColor': '#8CC96A', 'tamaId': bolo.id},
        'presence': {'state': 'away', 'lastSeen': since},
        'friends': {kAdminUid: {'since': since}},
      })
      ..seed('/users/$kMireiaUid/wall/${DateTime.now().year}/$kPauUid', {
        'text': '¡Feliz cumple, Mireia! Que Mochi te traiga muchas chuches',
        'at': DateTime.now().millisecondsSinceEpoch - 3600000,
      });
    return backend;
  }

  testWidgets('amigos: insignia, canal, añadir y perfil de cumpleaños', (tester) async {
    await boot(tester, backend: socialScene());
    await settle(tester, 100);
    await shoot(tester, '24-entorno-insignia-amigos');

    await tester.tap(find.byKey(const ValueKey<String>('channel.friends')));
    await settle(tester, 60);
    await shoot(tester, '25-amigos-recibidas');
    await tester.tap(find.text('amigos · 2'));
    await settle(tester, 30);
    await shoot(tester, '26-amigos');

    await tester.tap(find.byKey(const ValueKey<String>('friends.add')));
    await settle(tester, 40);
    final field = find.descendant(
      of: find.byKey(const ValueKey<String>('addFriend.field')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field, kLaiaCode.replaceRange(3, 4, kLaiaCode[3] == '1' ? '2' : '1'));
    await settle(tester, 20);
    await shoot(tester, '27-anadir-amigo-invalido');
    await tester.enterText(field, FriendCode.format(kLaiaCode));
    await settle(tester, 40);
    await shoot(tester, '28-anadir-amigo-ficha');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 30);

    await tester.tap(find.byKey(const ValueKey<String>('friends.friend.$kMireiaUid')));
    await settle(tester, 60);
    await shoot(tester, '29-perfil-amigo-cumple');
    await settle(tester, 80);
  });

  testWidgets('amigos: perfil sin cumpleaños, en ingles', (tester) async {
    await boot(
      tester,
      backend: socialScene(birthday: false, locale: 'en'),
      preferences: const Preferences(localeCode: 'en'),
    );
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey<String>('channel.friends')));
    await settle(tester, 60);
    await tester.tap(find.text('friends · 2'));
    await settle(tester, 30);
    await tester.tap(find.byKey(const ValueKey<String>('friends.friend.$kMireiaUid')));
    await settle(tester, 60);
    await shoot(tester, '30-perfil-amigo-en');
  });

  testWidgets('muro propio el dia del cumpleaños', (tester) async {
    final backend = socialScene();
    final now = DateTime.now();
    final madrid = now.toUtc().add(Duration(minutes: now.timeZoneOffset.inMinutes));
    backend
      ..seed('/users/$kAdminUid/profile/birthday',
          '1998-${madrid.month.toString().padLeft(2, '0')}-${madrid.day.toString().padLeft(2, '0')}')
      ..seed('/users/$kAdminUid/profile/timezone', 'UTC')
      ..seed('/users/$kAdminUid/wall/${now.toUtc().year}', {
        kMireiaUid: {'text': '¡Felicidades desde Tokio! 🎂 Mochi y yo te mandamos un abrazo enorme', 'at': now.millisecondsSinceEpoch - 7200000},
        kPauUid: {'text': 'que cumplas muchos más', 'at': now.millisecondsSinceEpoch - 3600000},
      })
      ..seed('/users/$kAdminUid/profile/birthday', '1998-${now.toUtc().month.toString().padLeft(2, '0')}-${now.toUtc().day.toString().padLeft(2, '0')}');
    await boot(tester, backend: backend);
    await settle(tester, 100);
    await shoot(tester, '31-entorno-cumple-propio');
    await tester.tap(find.byKey(const ValueKey<String>('channel.profile')));
    await settle(tester, 60);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
    await settle(tester, 10);
    await shoot(tester, '32-perfil-musica-y-muro');
    await tester.tap(find.byKey(const ValueKey<String>('profile.wall')));
    await settle(tester, 50);
    await shoot(tester, '33-muro-propio');
  });

  testWidgets('tarjeta de visita exportada', (tester) async {
    tester.view.physicalSize = const Size(700, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    for (final (name, accent, tama, wear) in [
      ('34-tarjeta', T.cyan, family().first, TamaWear.none),
      ('34b-tarjeta-cumple', const Color(0xFFEE7C96), family()[1], TamaWear.partyHat),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: BusinessCard(
                displayName: 'Adrià',
                accent: accent,
                code: kAdminCode,
                caption: 'código de amigo',
                tama: tama,
                wear: wear,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final png = await renderBusinessCard(key);
        File('${output.path}/$name.png').writeAsBytesSync(png, flush: true);
      });
    }
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
