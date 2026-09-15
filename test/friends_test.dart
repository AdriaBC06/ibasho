// Ibasho — amigos y perfiles: criterios de aceptacion del checkpoint 3.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/audio/audio_service.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/social.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/core/birthday.dart';
import 'package:ibasho/core/friend_code.dart';
import 'package:ibasho/core/timezones.dart';
import 'package:ibasho/l10n/gen/app_localizations_en.dart';
import 'package:ibasho/l10n/gen/app_localizations_es.dart';
import 'package:ibasho/state/friends.dart';
import 'package:ibasho/state/presence.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/social/business_card.dart';
import 'package:ibasho/ui/social/friend_code_input.dart';
import 'package:ibasho/ui/social/social_widgets.dart';
import 'package:ibasho/ui/tama/tama_painter.dart';
import 'package:ibasho/ui/tama/tama_view.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'support/fakes.dart';

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');
  final es = LEs();
  final en = LEn();

  Future<void> settle(WidgetTester tester, [int frames = 40]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<(FakeIbashoBackend, FakeSettingsStore)> boot(
    WidgetTester tester, {
    FakeIbashoBackend? backend,
    Preferences preferences = const Preferences(),
    bool birthday = true,
  }) async {
    tester.view.physicalSize = T.canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = backend ?? (FakeIbashoBackend()..let((b) => seedSocial(b, mireiaBirthdayToday: birthday)));
    final settings = FakeSettingsStore()..saved = preferences;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(fake),
          secureStoreProvider.overrideWithValue(FakeSecureStore(session: fake.tokens)),
          settingsStoreProvider.overrideWithValue(settings),
          initialPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const IbashoApp(),
      ),
    );
    await settle(tester, 100);
    return (fake, settings);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IbashoApp)));

  Future<void> tapKey(WidgetTester tester, String key, [int frames = 30]) async {
    final finder = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester, frames);
  }

  Future<void> closeTop(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 30);
  }

  Future<void> typeCode(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('addFriend.field')),
        matching: find.byType(EditableText),
      ),
      text,
    );
    await settle(tester, 20);
  }

  /// Una cuenta sin interfaz sobre la base compartida.
  Future<ProviderContainer> account(FakeIbashoBackend backend) async {
    final container = ProviderContainer(overrides: [
      backendProvider.overrideWithValue(backend),
      secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      initialPreferencesProvider.overrideWithValue(const Preferences()),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).restore();
    return container;
  }

  Future<void> until(bool Function() condition, String what) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Tiempo agotado esperando: $what');
  }

  // --- Criterio 1 ----------------------------------------------------------------

  test('dos cuentas se encuentran por codigo, se mandan solicitud y la aceptan', () async {
    final adriaDb = FakeIbashoBackend();
    final mireiaDb = adriaDb.sharing(uid: kMireiaUid, username: 'mireia');
    adriaDb
      ..seed('/allowlist/$kMireiaUid/mustChangePassword', false)
      ..seed('/friendCodes/$kAdminCode', kAdminUid)
      ..seed('/friendCodes/$kMireiaCode', kMireiaUid)
      ..seed('/users/$kAdminUid/friendCode', kAdminCode)
      ..seed('/users/$kAdminUid/card', {'displayName': 'Adrià', 'accentColor': '#5BC8F5'})
      ..seed('/users/$kMireiaUid/friendCode', kMireiaCode)
      ..seed('/users/$kMireiaUid/card', {'displayName': 'Mireia', 'accentColor': '#EE7C96'});

    final adria = await account(adriaDb);
    final mireia = await account(mireiaDb);
    final adriaFriends = adria.read(friendsProvider.notifier);
    final mireiaFriends = mireia.read(friendsProvider.notifier);
    await until(() => adria.read(friendsProvider).loaded && mireia.read(friendsProvider).loaded,
        'amigos cargados');
    expect(adria.read(friendsProvider).code, kAdminCode);

    final found = await adriaFriends.lookup(FriendCode.format(kMireiaCode));
    expect(found.outcome, LookupOutcome.found);
    expect(found.accountId, kMireiaUid);
    expect(found.card?.displayName, 'Mireia');
    expect(found.relation, FriendRelation.none);
    expect((await adriaFriends.lookup(kAdminCode)).outcome, LookupOutcome.self);

    expect(await adriaFriends.sendRequest(kMireiaUid), isNull);
    await until(() => mireia.read(friendsProvider).hasIncoming(kAdminUid), 'solicitud recibida');
    expect(adria.read(friendsProvider).hasOutgoing(kMireiaUid), isTrue);
    expect((await mireiaFriends.lookup(kAdminCode)).relation, FriendRelation.requestedYou);

    expect(await mireiaFriends.accept(kAdminUid), isNull);
    await until(
      () => adria.read(friendsProvider).isFriend(kMireiaUid) && mireia.read(friendsProvider).isFriend(kAdminUid),
      'amistad en los dos lados',
    );
    expect(adria.read(friendsProvider).incoming, isEmpty);
    expect(mireia.read(friendsProvider).outgoing, isEmpty);
    expect(adriaDb.peek('/users/$kAdminUid/friendCount'), 1);
    expect(adriaDb.peek('/users/$kMireiaUid/friendCount'), 1);
    expect(adriaDb.peek('/users/$kAdminUid/requests'), isNull);

    // Solicitudes cruzadas: mandar a quien ya te la mando os hace amigos.
    final laiaDb = adriaDb.sharing(uid: kLaiaUid, username: 'laia');
    adriaDb
      ..seed('/users/$kLaiaUid/friendCode', kLaiaCode)
      ..seed('/allowlist/$kLaiaUid', {
        'accountId': kLaiaUid,
        'username': 'laia',
        'createdAt': 1,
        'createdBy': kAdminUid,
        'disabled': false,
      });
    final laia = await account(laiaDb);
    await until(() => laia.read(friendsProvider).loaded, 'laia');
    expect(await laia.read(friendsProvider.notifier).sendRequest(kAdminUid), isNull);
    await until(() => adria.read(friendsProvider).hasIncoming(kLaiaUid), 'solicitud de laia');
    expect(await adriaFriends.sendRequest(kLaiaUid), isNull);
    await until(() => laia.read(friendsProvider).isFriend(kAdminUid), 'cruzadas: amigos');
    expect(adriaDb.peek('/users/$kAdminUid/friendCount'), 2);

    // Y dejar de ser amigos lo deshace en los dos lados.
    expect(await mireiaFriends.unfriend(kAdminUid), isNull);
    await until(() => !adria.read(friendsProvider).isFriend(kMireiaUid), 'ya no amigos');
    expect(adriaDb.peek('/users/$kAdminUid/friendCount'), 1);
    expect(adriaDb.peek('/users/$kMireiaUid/friendCount'), 0);
  });

  // --- Criterio 2 ----------------------------------------------------------------

  testWidgets('un digito mal tecleado se rechaza en local y distinto de un codigo inexistente',
      (tester) async {
    final (fake, _) = await boot(tester);
    await tapKey(tester, 'channel.friends', 40);
    await tapKey(tester, 'friends.add', 30);

    final typo = kMireiaCode.replaceRange(5, 6, kMireiaCode[5] == '7' ? '8' : '7');
    expect(FriendCode.isValid(typo), isFalse);
    final readsBefore = fake.reads.length;
    await typeCode(tester, typo);
    expect(find.text(es.addFriendInvalid), findsOneWidget);
    expect(find.text(es.addFriendNotFound), findsNothing);
    expect(fake.reads.skip(readsBefore).where((p) => p.startsWith('/friendCodes')), isEmpty,
        reason: 'un codigo invalido no toca la red');

    // Bien escrito, pero de nadie: otro mensaje, y esta vez si se pregunta.
    final nobody = FriendCode.forCounter(4242);
    await typeCode(tester, nobody);
    await settle(tester, 20);
    expect(find.text(es.addFriendNotFound), findsOneWidget);
    expect(find.text(es.addFriendInvalid), findsNothing);
    expect(fake.reads, contains('/friendCodes/$nobody'));

    // Pegado con espacios: los guiones se ponen solos y aparece la ficha.
    await typeCode(tester, '${kLaiaCode.substring(0, 4)} ${kLaiaCode.substring(4, 8)} ${kLaiaCode.substring(8)}');
    await settle(tester, 20);
    expect(find.text(FriendCode.format(kLaiaCode)), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('addFriend.card')), findsOneWidget);
    expect(find.text('Laia'), findsWidgets);
    // Laia ya habia mandado una: el boton la acepta.
    expect(find.text(es.addFriendAcceptTheirs), findsOneWidget);
    // Y de ella solo se ha leido la ficha, nada mas.
    expect(fake.reads.where((p) => p.startsWith('/users/$kLaiaUid/')), everyElement('/users/$kLaiaUid/card'));

    await tapKey(tester, 'addFriend.send', 30);
    expect(fake.peek('/users/$kAdminUid/friends/$kLaiaUid'), isNotNull);
    expect(fake.peek('/users/$kLaiaUid/friends/$kAdminUid'), isNotNull);
    await settle(tester, 90);
  });

  test('el campo del codigo pone los guiones y acepta pegar con o sin ellos', () {
    const formatter = FriendCodeFormatter();
    TextEditingValue type(String text) => formatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
        );
    expect(type('1234').text, '1234');
    expect(type('12345').text, '1234-5');
    expect(type('123456789012').text, '1234-5678-9012');
    expect(type('1234-5678-9012').text, '1234-5678-9012');
    expect(type(' 1234 5678 9012\n').text, '1234-5678-9012');
    expect(type('1234567890123456').text, '1234-5678-9012');
    expect(type('12a34').text, '1234');
    expect(type('12345').selection.baseOffset, 6);
  });

  // --- Insignia y canal -----------------------------------------------------------

  testWidgets('el icono de amigos lleva el numero de solicitudes pendientes', (tester) async {
    final (fake, _) = await boot(tester);
    expect(find.byKey(const ValueKey<String>('channel.friends.badge')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey<String>('channel.friends.badge')), matching: find.text('1')),
      findsOneWidget,
    );

    // Al responderla desde el canal, la insignia se va.
    await tapKey(tester, 'channel.friends', 40);
    expect(find.byKey(ValueKey<String>('friends.request.$kLaiaUid')), findsOneWidget,
        reason: 'con solicitudes pendientes, el canal abre en esa pestaña');
    await tapKey(tester, 'friends.dismiss.$kLaiaUid', 20);
    expect(fake.peek('/users/$kAdminUid/requests/in/$kLaiaUid'), isNull);
    expect(fake.peek('/users/$kLaiaUid/requests/out/$kAdminUid'), isNull, reason: 'rechazar no deja rastro');
    await closeTop(tester);
    expect(find.byKey(const ValueKey<String>('channel.friends.badge')), findsNothing);
  });

  testWidgets('el canal ensena el codigo grande y lo copia', (tester) async {
    await boot(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tapKey(tester, 'channel.friends', 40);
    expect(find.text(FriendCode.format(kAdminCode)), findsWidgets);
    await tapKey(tester, 'friends.tabs', 5);
    await tester.tap(find.text(es.friendsTabFriends(1)));
    await settle(tester, 20);
    expect(find.byKey(ValueKey<String>('friends.friend.$kMireiaUid')), findsOneWidget);
    await tapKey(tester, 'friends.copy', 10);
    expect(copied, FriendCode.format(kAdminCode));
    await settle(tester, 90);
  });

  // --- Perfil ajeno, hora local y musica (criterio 10) -------------------------------

  testWidgets('el perfil de un amigo: hora local, presencia, cumpleaños y musica silenciable',
      (tester) async {
    final (fake, settings) = await boot(tester);
    await tapKey(tester, 'channel.friends', 40);
    await tester.tap(find.text(es.friendsTabFriends(1)));
    await settle(tester, 20);
    await tapKey(tester, 'friends.friend.$kMireiaUid', 40);

    expect(find.text('Mireia'), findsWidgets);
    expect(find.text('desde Tokio'), findsOneWidget);
    expect(find.textContaining(es.presenceOnline), findsWidgets);

    final now = DateTime.now();
    final tokyo = wallClockIn('Asia/Tokyo', now);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey<String>('friend.localTime'))).data,
      DateFormat('HH:mm').format(tokyo),
    );
    final difference = zoneDifference('Asia/Tokyo', 'Europe/Madrid', now);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey<String>('friend.timeDifference'))).data,
      zoneDifferenceLabel(es, difference),
    );

    // Hoy cumple: se viste de fiesta y su Tama lleva gorrito.
    expect(find.byKey(const ValueKey<String>('friend.party')), findsOneWidget);
    expect(
      tester.widgetList<TamaView>(find.byType(TamaView)).any((v) => v.wear == TamaWear.partyHat),
      isTrue,
    );
    expect(find.text(es.badgeBirthday), findsOneWidget);
    expect(find.text(es.badgeOldFriend), findsOneWidget);

    // Suena su pista en lugar de la de ambiente.
    expect(AudioService.instance.profileTrack, MusicTrack.noche);

    // Silenciar la quita al momento y se recuerda.
    await tapKey(tester, 'friend.mute', 10);
    expect(AudioService.instance.profileTrack, isNull);
    expect(settings.saved.profileMusicMuted, isTrue);

    // Al salir vuelve la de ambiente; al volver a entrar sigue callada.
    await closeTop(tester);
    expect(AudioService.instance.profileTrack, isNull);
    await tapKey(tester, 'friends.friend.$kMireiaUid', 40);
    expect(AudioService.instance.profileTrack, isNull, reason: 'el silencio es persistente');

    await tapKey(tester, 'friend.mute', 10);
    expect(AudioService.instance.profileTrack, MusicTrack.noche);
    expect(settings.saved.profileMusicMuted, isFalse);
    await closeTop(tester);
    expect(AudioService.instance.profileTrack, isNull, reason: 'sale y vuelve la de ambiente');
    expect(fake.writes, isNotEmpty);
  });

  testWidgets('el muro deja un mensaje por año el dia del cumpleaños', (tester) async {
    final (fake, _) = await boot(tester);
    final year = wallClockIn('Asia/Tokyo', DateTime.now()).year;
    await tapKey(tester, 'channel.friends', 40);
    await tester.tap(find.text(es.friendsTabFriends(1)));
    await settle(tester, 20);
    await tapKey(tester, 'friends.friend.$kMireiaUid', 40);

    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey<String>('wall.field')), matching: find.byType(EditableText)),
      '¡felicidades desde casa!',
    );
    await settle(tester, 10);
    await tapKey(tester, 'wall.post', 30);
    final stored = fake.peek('/users/$kMireiaUid/wall/$year/$kAdminUid');
    expect(stored, isA<Map>());
    expect((stored! as Map)['text'], '¡felicidades desde casa!');
    // Ya no hay campo: el de este año esta dejado.
    expect(find.byKey(const ValueKey<String>('wall.field')), findsNothing);
    expect(find.text(es.wallAlreadyWrote), findsOneWidget);
    expect(find.text('¡felicidades desde casa!'), findsOneWidget);
    await settle(tester, 90);
  });

  testWidgets('fuera del cumpleaños el muro no deja escribir', (tester) async {
    await boot(tester, birthday: false);
    await tapKey(tester, 'channel.friends', 40);
    await tester.tap(find.text(es.friendsTabFriends(1)));
    await settle(tester, 20);
    await tapKey(tester, 'friends.friend.$kMireiaUid', 40);
    expect(find.byKey(const ValueKey<String>('friend.party')), findsNothing);
    expect(find.byKey(const ValueKey<String>('wall.field')), findsNothing);
    expect(find.textContaining(es.wallOpensOn('').trim()), findsOneWidget);
    expect(
      tester.widgetList<TamaView>(find.byType(TamaView)).every((v) => v.wear == TamaWear.none),
      isTrue,
    );
  });

  // --- Presencia (criterios 7 y 8) ----------------------------------------------

  test('cerrar la app deja la presencia en desconectado sin que el cliente escriba', () async {
    final db = FakeIbashoBackend();
    final me = await account(db);
    me.read(presenceProvider);
    await until(() => (db.peek('/users/$kAdminUid/presence') as Map?)?['state'] == 'online', 'online');
    final link = db.presenceLinks.single;
    expect(link.onDisconnect.keys, contains('/users/$kAdminUid/presence'),
        reason: 'la desconexion queda encargada al servidor al conectar');

    // El proceso muere: el cliente ya no hace nada, lo hace el servidor.
    final writesBefore = db.writes.length;
    await link.drop();
    final after = db.peek('/users/$kAdminUid/presence')! as Map;
    expect(after['state'], 'offline');
    expect(after['lastSeen'], isA<int>());
    expect(db.writes.length, writesBefore + 1, reason: 'la unica escritura es la del encargo');
  });

  test('invisible es indistinguible de desconectado', () async {
    Future<Map<Object?, Object?>> offlineBy({required bool invisible}) async {
      final db = FakeIbashoBackend();
      final observer = await account(db.sharing(uid: kMireiaUid, username: 'mireia'));
      final me = await account(db);
      me.read(presenceProvider);
      await until(() => (db.peek('/users/$kAdminUid/presence') as Map?)?['state'] == 'online', 'online');
      final link = db.presenceLinks.single;
      if (invisible) {
        await me.read(presenceProvider.notifier).setMode(PresenceMode.invisible);
        await until(() => (db.peek('/users/$kAdminUid/presence') as Map?)?['state'] == 'offline', 'invisible');
        expect(link.onDisconnect, isEmpty, reason: 'nada encargado que delate la desconexion real');
        final snapshot = Map.of(db.peek('/users/$kAdminUid/presence')! as Map);
        // Cerrar la app estando invisible no mueve nada.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await link.drop();
        expect(db.peek('/users/$kAdminUid/presence'), snapshot);
      } else {
        await link.drop();
      }
      final seen = Presence.fromJson(await observer.read(backendProvider).read(
            '/users/$kAdminUid/presence',
            idToken: 'x',
          ));
      expect(seen.state, PresenceState.offline);
      return db.peek('/users/$kAdminUid/presence')! as Map;
    }

    final closed = await offlineBy(invisible: false);
    final hidden = await offlineBy(invisible: true);
    expect(hidden.keys.toSet(), closed.keys.toSet(), reason: 'misma forma');
    expect(hidden['state'], closed['state']);
    expect(hidden.values.every((v) => v is String || v is int), isTrue);
    // Y la interfaz del otro dice exactamente lo mismo.
    final now = DateTime.now();
    String line(Map<Object?, Object?> raw) => presenceLine(
          es,
          Presence(state: Presence.fromJson(raw).state, lastSeen: now.subtract(const Duration(hours: 2))),
          now,
        );
    expect(line(hidden), line(closed));
  });

  test('entrar ya invisible no toca la presencia publicada', () async {
    final db = FakeIbashoBackend()
      ..seed('/users/$kAdminUid/presenceMode', 'invisible')
      ..seed('/users/$kAdminUid/presence', {'state': 'offline', 'lastSeen': 1234});
    final me = await account(db);
    me.read(presenceProvider);
    await until(() => me.read(presenceProvider).connected, 'conexion');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(db.peek('/users/$kAdminUid/presence'), {'state': 'offline', 'lastSeen': 1234});
    expect(db.writes.where((w) => w.$1.endsWith('/presence')), isEmpty);
  });

  test('ausente llega solo sin actividad y se va al primer movimiento', () async {
    final db = FakeIbashoBackend();
    final me = await account(db);
    final controller = PresenceController(
      backend: db,
      session: me.read(sessionProvider.notifier),
      active: true,
      idleAfter: Duration.zero,
    );
    addTearDown(controller.dispose);
    await until(() => controller.state.connected, 'conexion');
    expect(controller.state.published, PresenceState.online);
    // Sin tocar nada durante el umbral (aqui, cero) el reloj de inactividad salta.
    await Future<void>.delayed(const Duration(seconds: 16));
    expect(controller.state.published, PresenceState.away);
    expect((db.peek('/users/$kAdminUid/presence')! as Map)['state'], 'away');
    controller.activity();
    await until(() => (db.peek('/users/$kAdminUid/presence')! as Map)['state'] == 'online', 'vuelta');
    // Fijado a mano no se mueve con la actividad.
    await controller.setMode(PresenceMode.busy);
    controller.activity();
    await until(() => (db.peek('/users/$kAdminUid/presence')! as Map)['state'] == 'busy', 'ocupado');
  }, timeout: const Timeout(Duration(seconds: 40)));

  // --- Criterio 12 ----------------------------------------------------------------

  testWidgets('cambiar el idioma traduce el canal de amigos y los estados', (tester) async {
    await boot(tester);
    await tapKey(tester, 'channel.friends', 40);
    expect(find.text(es.friendsTitle), findsOneWidget);
    for (final label in [es.presenceOnline, es.presenceAway, es.presenceBusy, es.presenceInvisible]) {
      expect(find.text(label), findsOneWidget);
    }
    await containerOf(tester).read(preferencesProvider.notifier).setLocale('en');
    await settle(tester, 20);
    expect(find.text(en.friendsTitle), findsOneWidget);
    expect(find.text(es.friendsTitle), findsNothing);
    for (final label in [en.presenceOnline, en.presenceAway, en.presenceBusy, en.presenceInvisible]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text(es.presenceBusy), findsNothing);
    expect(find.text(en.friendsYourCode), findsOneWidget);
    expect(en.presenceOffline, isNot(es.presenceOffline));
  });

  test('cada cadena existe en español y en ingles', () {
    Set<String> keys(String path) => (jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>)
        .keys
        .where((k) => !k.startsWith('@'))
        .toSet();
    final spanish = keys('lib/l10n/app_es.arb');
    final english = keys('lib/l10n/app_en.arb');
    expect(spanish.difference(english), isEmpty);
    expect(english.difference(spanish), isEmpty);
  });

  // --- Criterio 9 ----------------------------------------------------------------

  testWidgets('la tarjeta de visita se exporta como un PNG nitido', (tester) async {
    tester.view.physicalSize = const Size(700, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: BusinessCard(
              displayName: 'Adrià',
              accent: T.cyan,
              code: kAdminCode,
              caption: es.friendsYourCode,
              tama: sampleTama(),
              wear: TamaWear.partyHat,
            ),
          ),
        ),
      ),
    );
    late Uint8List png;
    late ui.Image decoded;
    await tester.runAsync(() async {
      png = await renderBusinessCard(key);
      final codec = await ui.instantiateImageCodec(png);
      decoded = (await codec.getNextFrame()).image;
    });
    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10], reason: 'cabecera PNG');
    expect(decoded.width, (businessCardSize.width * businessCardPixelRatio).round());
    expect(decoded.height, (businessCardSize.height * businessCardPixelRatio).round());
    decoded.dispose();
    expect(find.text(FriendCode.format(kAdminCode)), findsOneWidget);
  });

  // --- Cumpleaños y gorrito ----------------------------------------------------------

  test('el cumpleaños se cuenta en la zona de quien cumple', () {
    UserProfile born(String birthday, String zone) =>
        UserProfile(username: 'x', displayName: 'x', birthday: birthday, timezone: zone, createdAt: DateTime(2026));
    // 15 de septiembre a las 20:00 UTC: en Tokio ya es dia 16, en Madrid aun 15.
    final instant = DateTime.utc(2026, 9, 15, 20);
    expect(isBirthdayToday(born('1999-09-16', 'Asia/Tokyo'), instant), isTrue);
    expect(isBirthdayToday(born('1999-09-16', 'Europe/Madrid'), instant), isFalse);
    expect(isBirthdayToday(born('1999-09-15', 'Europe/Madrid'), instant), isTrue);
    // Bisiestos: el 29 de febrero se celebra el 28 los años normales.
    expect(isBirthdayToday(born('2000-02-29', 'UTC'), DateTime.utc(2027, 2, 28, 12)), isTrue);
    expect(isBirthdayToday(born('2000-02-29', 'UTC'), DateTime.utc(2028, 2, 28, 12)), isFalse);
    expect(isBirthdayToday(born('', 'UTC'), instant), isFalse);
    // Diferencias horarias, con horario de verano.
    expect(zoneDifference('Asia/Tokyo', 'Europe/Madrid', DateTime.utc(2026, 7, 1)), const Duration(hours: 7));
    expect(zoneDifference('Asia/Tokyo', 'Europe/Madrid', DateTime.utc(2026, 1, 1)), const Duration(hours: 8));
    expect(zoneDifference('America/Mexico_City', 'Europe/Madrid', DateTime.utc(2026, 1, 1)),
        const Duration(hours: -7));
    expect(zoneDifferenceLabel(es, const Duration(hours: 7)), '7 h por delante de ti');
    expect(zoneDifferenceLabel(en, const Duration(hours: -5, minutes: -30)), '5 h 30 min behind you');
    expect(zoneDifferenceLabel(es, Duration.zero), es.timeSame);
  });

  testWidgets('el gorrito de fiesta cabe en el lienzo del Tama con cualquier cuerpo', (tester) async {
    const pad = 40.0;
    const size = 200.0;
    tester.view.physicalSize = const Size(size + pad * 2, size + pad * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (var body = 0; body < TamaPart.body.variants; body++) {
      for (final height in [0, 100]) {
        final look = const TamaLook()
            .withPart(TamaPart.body, body)
            .withPart(TamaPart.feet, 2)
            .withDial(TamaDial.bodyHeight, height);
        await tester.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.all(pad),
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: TamaPainter(look: look, wear: TamaWear.partyHat, shadow: false),
                ),
              ),
            ),
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
        late ui.Image image;
        late List<int> rgba;
        late List<int> bare;
        await tester.runAsync(() async {
          image = await boundary.toImage();
          rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        });
        var above = 0;
        for (var y = 0; y < pad; y++) {
          for (var x = 0; x < image.width; x++) {
            if (rgba[(y * image.width + x) * 4 + 3] > 0) above++;
          }
        }
        final width = image.width;
        image.dispose();
        expect(above, 0, reason: 'cuerpo $body, alto $height: el gorrito no sale por arriba');

        // Y se nota: sin el gorrito, la parte de arriba del lienzo cambia.
        await tester.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.all(pad),
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: TamaPainter(look: look, shadow: false),
                ),
              ),
            ),
          ),
        );
        final plain = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
        await tester.runAsync(() async {
          final img = await plain.toImage();
          bare = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
          img.dispose();
        });
        var changed = 0;
        for (var i = 0; i < width * (pad + size ~/ 2).toInt() * 4; i += 4) {
          if (rgba[i + 3] != bare[i + 3]) changed++;
        }
        expect(changed, greaterThan(200), reason: 'el gorrito se ve');
      }
    }
  });
}

extension<T> on T {
  T let(void Function(T) apply) {
    apply(this);
    return this;
  }
}
