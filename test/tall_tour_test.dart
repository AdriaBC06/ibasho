// Ibasho — recorrido visual en vertical: cada pantalla en un movil pequeño y
// en uno grande.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja las imagenes en `build/screenshots/vertical-<ancho>x<alto>/`. Como
// cualquier desborde de maquetacion hace fallar el test, esto es a la vez el
// album y la red de seguridad de la composicion vertical.
//
//   flutter test test/tall_tour_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/prizes.dart';
import 'package:ibasho/ui/tama/tama_outfit.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/core/friend_code.dart';
import 'package:ibasho/crypto/keys.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/state/system_status.dart';
import 'package:ibasho/ui/widgets/controls.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

/// Un movil pequeño (360x640 dp, el minimo que se soporta) y el de prueba
/// (Galaxy A70: 411x914 dp con las barras del sistema ocultas).
const Map<String, Size> _phones = <String, Size>{
  'vertical-360x640': Size(360, 640),
  'vertical-411x914': Size(411, 914),
};

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

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

  for (final MapEntry(key: folder, value: phone) in _phones.entries) {
    final output = Directory('build/screenshots/$folder')..createSync(recursive: true);

    Future<void> boot(
      WidgetTester tester, {
      required FakeIbashoBackend backend,
      bool signedIn = true,
      Preferences preferences = const Preferences(),
    }) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            secureStoreProvider.overrideWithValue(
              FakeSecureStore(session: signedIn ? backend.tokens : null),
            ),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()..saved = preferences),
            initialPreferencesProvider.overrideWithValue(preferences),
            batteryWatchProvider.overrideWithValue(
              FakeBatteryWatch(const BatteryInfo(level: 78, charging: false)),
            ),
          ],
          child: const RepaintBoundary(child: IbashoApp()),
        ),
      );
    }

    Future<void> settle(WidgetTester tester, [int frames = 40]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${output.path}/$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
      });
    }

    List<Tama> family() => [
          sampleTama(),
          sampleTama(
            id: '-TamaMuestra00000002',
            name: 'Mochi',
            personality: TamaPersonality.sleepy,
            look: const TamaLook(
              parts: {TamaPart.body: 4, TamaPart.eyes: 3, TamaPart.crown: 3, TamaPart.pattern: 3},
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
              parts: {TamaPart.body: 2, TamaPart.eyes: 5, TamaPart.cheeks: 3, TamaPart.feet: 1},
              color: '#9F86E6',
            ),
          ),
        ];

    FakeIbashoBackend social() {
      final backend = FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id);
      seedSocial(backend, mireiaBirthdayToday: true);
      backend.seed('/users/$kAdminUid/card/tamaId', family().first.id);
      return backend;
    }

    group(folder, () {
      testWidgets('login', (tester) async {
        await boot(tester, backend: FakeIbashoBackend(), signedIn: false);
        await settle(tester, 100);
        await shoot(tester, '01-login');
      });

      testWidgets('entorno: los tres estados de ampliar', (tester) async {
        await boot(tester, backend: FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id));
        await settle(tester, 100);
        await shoot(tester, '02-entorno');
        await tester.tap(find.byKey(const ValueKey<String>('magnify')));
        await settle(tester, 20);
        await shoot(tester, '03-entorno-superior');
        await tester.tap(find.byKey(const ValueKey<String>('magnify')));
        await settle(tester, 20);
        await shoot(tester, '04-entorno-inferior');
      });

      testWidgets('ajustes y creditos', (tester) async {
        await boot(tester, backend: FakeIbashoBackend());
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.settings')));
        await settle(tester, 60);
        await shoot(tester, '05-ajustes');
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -320));
        await settle(tester, 10);
        await shoot(tester, '05b-ajustes-abajo');
      });

      testWidgets('perfil', (tester) async {
        await boot(tester, backend: FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id));
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.profile')));
        await settle(tester, 60);
        await shoot(tester, '06-perfil');
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -420));
        await settle(tester, 10);
        await shoot(tester, '06b-perfil-abajo');
      });

      testWidgets('tamas: canal, habitacion y creador', (tester) async {
        await boot(tester, backend: FakeIbashoBackend(tamas: family(), profileTamaId: family().first.id));
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.tamas')));
        await settle(tester, 60);
        await shoot(tester, '07-tamas');

        await tester.tap(find.byKey(const ValueKey<String>('tamas.card.-TamaMuestra00000001')));
        await settle(tester, 40);
        await shoot(tester, '08-habitacion');

        await tester.tap(find.byKey(const ValueKey<String>('tama.edit')));
        await settle(tester, 40);
        await shoot(tester, '09-creador-cuerpo');
        await tester.runAsync(() => PrizeArt.instance.preload([for (final p in wearablePrizes) ...p.items]));
        for (final tab in ['color', 'eyes', 'limbs', 'hats', 'accessories', 'character']) {
          await tester.ensureVisible(find.byKey(ValueKey<String>('creator.tab.$tab')));
          await tester.tap(find.byKey(ValueKey<String>('creator.tab.$tab')));
          await settle(tester, 12);
          await shoot(tester, '09-creador-$tab');
        }
      });

      testWidgets('amigos: canal, añadir y perfil', (tester) async {
        await boot(tester, backend: social());
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.friends')));
        await settle(tester, 60);
        await shoot(tester, '10-amigos-recibidas');
        await tester.tap(find.text('amigos · 1'));
        await settle(tester, 30);
        await shoot(tester, '11-amigos');

        await tester.tap(find.byKey(const ValueKey<String>('friends.add')));
        await settle(tester, 40);
        final field = find.descendant(
          of: find.byKey(const ValueKey<String>('addFriend.field')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(field, FriendCode.format(kLaiaCode));
        await settle(tester, 40);
        await shoot(tester, '12-anadir-amigo');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester, 30);

        await tester.tap(find.byKey(const ValueKey<String>('friends.friend.$kMireiaUid')));
        await settle(tester, 60);
        await shoot(tester, '13-perfil-amigo');
        await tester.dragFrom(Offset(phone.width / 2, phone.height * .7), const Offset(0, -300));
        await settle(tester, 20);
        await shoot(tester, '13b-perfil-amigo-muro');
        await settle(tester, 60);
      });

      testWidgets('mensajes: clave de respaldo, conversacion y stickers',
          (tester) async {
        final backend = social()
          // Sin clave publica del otro lado no se puede escribir, y esta
          // pantalla ensena justamente eso: la conversacion con el compositor
          // activo. La clave es de verdad, generada aqui.
          ..seed('/users/$kMireiaUid/keys/pub', IdentityKeys.generate().public.encoded);
        await boot(tester, backend: backend);
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.messages')));
        await settle(tester, 120);
        // Lo primero de todo es la clave de respaldo: la unica pantalla de
        // Ibasho que pide algo antes de dejar pasar.
        await shoot(tester, '14-clave-de-respaldo');

        await tester.tap(find.text('ya la he apuntado'));
        await settle(tester, 60);
        await shoot(tester, '15-mensajes');

        await tester.tap(find.text('Mireia'));
        await settle(tester, 80);
        await shoot(tester, '16-conversacion');

        // El selector de stickers: las ocho caras, pintadas con el Tama
        // elegido, que es lo que hay que ver antes de mandar una.
        await tester.tap(find.byKey(const ValueKey<String>('conversation.sticker')));
        await settle(tester, 80);
        await shoot(tester, '16b-stickers');
      });

      testWidgets('noticias y sugerencias', (tester) async {
        final now = DateTime.now();
        final backend = social()
          ..seed('/news/AAAAAAAAAAAAAAAAAAAA', {
            'kind': 'update',
            'title': 'Ibasho 0.4.0',
            'body': 'Mensajes cifrados, noticias, sugerencias y monedas.',
            'version': '0.4.0',
            'at': now.millisecondsSinceEpoch,
            'by': 'Ibasho',
          })
          ..seed('/news/BBBBBBBBBBBBBBBBBBBB', {
            'kind': 'poll',
            'title': 'Que viene despues',
            'at': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            'by': 'Ibasho',
            'options': {'0': 'Un minijuego', '1': 'Una tienda', '2': 'Una habitacion compartida'},
            'tally': {'0': 5, '1': 2, '2': 1},
            'closesAt': now.add(const Duration(days: 2)).millisecondsSinceEpoch,
          })
          ..seed('/acceptedSuggestions/AAAAAAAAAAAAAAAAAAAA', {
            'title': 'Musica en la habitacion',
            'by': 'Mireia',
            'at': now.millisecondsSinceEpoch,
          });
        await boot(tester, backend: backend);
        await settle(tester, 100);

        await tester.tap(find.byKey(const ValueKey<String>('channel.news')));
        await settle(tester, 80);
        await shoot(tester, '17-noticias');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester, 40);
        await tester.tap(find.byKey(const ValueKey<String>('channel.suggestions')));
        await settle(tester, 80);
        await shoot(tester, '18-sugerencias');
      });

      testWidgets('creditos, depuracion y zona horaria', (tester) async {
        await boot(tester, backend: FakeIbashoBackend());
        await settle(tester, 100);
        // El Yatai deja depuracion en la segunda pagina (nueve por pagina en
        // vertical, y ya hay diez canales fijos con un admin).
        await tester.tap(find.byKey(const ValueKey<String>('grid.next')));
        await settle(tester, 30);
        await tester.tap(find.byKey(const ValueKey<String>('channel.debug')));
        await settle(tester, 60);
        await shoot(tester, '15-depuracion');
        await tester.tap(find.byType(IconPill).last);
        await settle(tester, 40);

        // Volvemos a la primera pagina: ajustes vive antes de depuracion.
        await tester.tap(find.byKey(const ValueKey<String>('grid.previous')));
        await settle(tester, 30);
        await tester.tap(find.byKey(const ValueKey<String>('channel.settings')));
        await settle(tester, 60);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
        await settle(tester, 10);
        await shoot(tester, '15b-ajustes-cuenta');
        await tester.tap(find.text('créditos').last);
        await settle(tester, 40);
        await shoot(tester, '16-creditos');
      });

      testWidgets('salir: el dialogo de confirmacion', (tester) async {
        await boot(tester, backend: FakeIbashoBackend());
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.settings')));
        await settle(tester, 60);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
        await settle(tester, 10);
        await tester.tap(find.text('cerrar sesión').last);
        await settle(tester, 40);
        await shoot(tester, '17-dialogo');
      });

      testWidgets('muro propio', (tester) async {
        final backend = social();
        final now = DateTime.now();
        backend
          ..seed('/users/$kAdminUid/profile/birthday',
              '1998-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}')
          ..seed('/users/$kAdminUid/wall/${now.year}', {
            kMireiaUid: {
              'text': '¡Felicidades! Mochi y yo te mandamos un abrazo',
              'at': now.millisecondsSinceEpoch - 7200000,
            },
          });
        await boot(tester, backend: backend);
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.profile')));
        await settle(tester, 60);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -1200));
        await settle(tester, 10);
        await tester.tap(find.byKey(const ValueKey<String>('profile.wall')));
        await settle(tester, 50);
        await shoot(tester, '18-muro-propio');
      });

      testWidgets('version antigua', (tester) async {
        final backend = FakeIbashoBackend()
          ..seed('/system/update', {'minVersion': '9.0.0', 'url': 'https://ibasho.top/descargar'});
        await boot(tester, backend: backend, signedIn: false);
        await settle(tester, 100);
        await shoot(tester, '19-actualizar');
      });

      testWidgets('administracion', (tester) async {
        await boot(tester, backend: FakeIbashoBackend());
        await settle(tester, 100);
        await tester.tap(find.byKey(const ValueKey<String>('channel.admin')));
        await settle(tester, 60);
        await shoot(tester, '14-administracion');
      });
    });
  }
}
