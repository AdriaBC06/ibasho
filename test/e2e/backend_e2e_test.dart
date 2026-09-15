// Ibasho — recorrido de extremo a extremo contra el emulador de Firebase.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Usa el backend REST de verdad, el controlador de sesion de verdad y las
// reglas de verdad; solo cambia el servidor. Se lanza con:
//
//   ./tool/test_e2e.sh
//
// Sin IBASHO_USE_EMULATOR=true se salta: nunca toca el proyecto real.

@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ibasho/backend/errors.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/rest_ibasho_backend.dart';
import 'package:ibasho/backend/rtdb_socket.dart';
import 'package:ibasho/backend/social.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/core/env.dart';
import 'package:ibasho/core/friend_code.dart';
import 'package:ibasho/state/admin.dart';
import 'package:ibasho/state/friends.dart';
import 'package:ibasho/state/presence.dart';
import 'package:ibasho/state/preferences.dart';
import 'package:ibasho/state/profile.dart';
import 'package:ibasho/state/session.dart';
import 'package:ibasho/state/tamas.dart';
import 'package:ibasho/storage/settings_store.dart';

import '../support/fakes.dart';

void main() {
  // Nada de TestWidgetsFlutterBinding: su HttpClient de mentira devolveria 400
  // a todo y aqui se quiere red de verdad contra el emulador.
  final skip = Env.useEmulator ? null : 'solo contra el emulador (IBASHO_USE_EMULATOR)';

  final backend = RestIbashoBackend();

  SessionController newSession() => SessionController(
        backend: backend,
        store: FakeSecureStore(),
        preferences: PreferencesController(FakeSettingsStore(), const Preferences()),
      );

  /// Escribe saltandose las reglas, como hace `tool/bootstrap_admin.dart` con
  /// la CLI en produccion.
  Future<void> ownerPut(String path, Object? value) async {
    final res = await http.put(
      Uri.parse('${Env.databaseRoot}$path.json?${Env.databaseQuerySuffix}'),
      headers: const {'Authorization': 'Bearer owner'},
      body: jsonEncode(value),
    );
    expect(res.statusCode, 200, reason: res.body);
  }

  final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
  final adminName = 'admin$stamp';
  final memberName = 'mireia$stamp';

  test('flujo completo de cuentas', skip: skip, () async {
    // --- 0. Primer arranque: el bootstrap del administrador -----------------
    final adminPassword = generatePassword();
    final admin0 = await backend.provisionAccount(
      username: adminName,
      password: adminPassword,
    );
    await ownerPut('/allowlist/${admin0.uid}', {
      'accountId': admin0.uid,
      'username': adminName,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'createdBy': 'bootstrap',
      'disabled': false,
      'mustChangePassword': true,
      'generation': 1,
    });
    await ownerPut('/admins/${admin0.uid}', true);
    await ownerPut('/usernames/$adminName', admin0.uid);

    // --- 1. El admin entra y se le obliga a cambiar la contrasena ----------
    final adminSession = newSession();
    await adminSession.signIn(username: adminName, password: adminPassword);
    expect(adminSession.state.phase, SessionPhase.mustChangePassword);
    expect(adminSession.state.isAdmin, isTrue);

    await adminSession.completePasswordChange('una-contrasena-larga');
    expect(adminSession.state.phase, SessionPhase.active);

    // La contrasena de un solo uso ya no sirve.
    await expectLater(
      newSession().signIn(username: adminName, password: adminPassword),
      throwsA(isA<IbashoException>().having(
          (e) => e.failure, 'failure', IbashoFailure.invalidCredentials)),
    );

    // --- 2. Streaming SSE desde Dart puro -----------------------------------
    final events = <DatabaseEvent>[];
    final sub = backend
        .watch('/allowlist', token: adminSession.freshToken)
        .listen(events.add);
    await _until(() => events.isNotEmpty, 'evento inicial del stream');

    // --- 3. El admin crea una cuenta sin perder su sesion -------------------
    final adminController =
        AdminController(backend: backend, session: adminSession);
    addTearDown(adminController.dispose);

    final adminUidBefore = adminSession.state.uid;
    final created = await adminController.createAccount(memberName);
    expect(adminSession.state.uid, adminUidBefore,
        reason: 'accounts:signUp no debe tocar la sesion del admin');
    expect(adminSession.state.phase, SessionPhase.active);
    expect(created.password.length, 16);

    // El stream en vivo ve la nueva entrada.
    await _until(
      () => events.any((e) =>
          e.path.contains(created.uid) ||
          (e.data is Map && (e.data! as Map).containsKey(created.uid))),
      'la cuenta nueva llegando por SSE',
    );
    await sub.cancel();

    // --- 4. El usuario nuevo entra con la credencial copiada ---------------
    final member = newSession();
    await member.signIn(username: memberName, password: created.password);
    expect(member.state.phase, SessionPhase.mustChangePassword);
    expect(member.state.isAdmin, isFalse);
    await member.completePasswordChange('otra-contrasena-larga');
    expect(member.state.phase, SessionPhase.active);

    // Su perfil se crea en la primera entrada y se puede editar.
    final profile = ProfileController(
      backend: backend,
      session: member,
      defaultLocale: 'es',
      cardOf: _plainCard,
    );
    addTearDown(profile.dispose);
    await _until(() => profile.state.profile != null, 'perfil inicial');
    final saved = await profile.save(profile.state.profile!.copyWith(
      displayName: 'Mireia',
      statusMessage: 'hola',
      accentColor: '#E8A33D',
      locale: 'en',
      birthday: '2001-02-03',
    ));
    expect(saved, isTrue);

    // Un perfil que rompe la validacion no entra.
    expect(
      await profile.save(profile.state.profile!.copyWith(displayName: 'x' * 25)),
      isFalse,
    );

    // No puede escribir en el nodo de otro ni en la allowlist.
    await expectLater(
      backend.write('/users/${adminSession.state.uid}/profile/displayName', 'x',
          idToken: await member.freshToken()),
      throwsA(isA<IbashoException>()),
    );
    await expectLater(
      backend.write('/allowlist/${member.state.uid}/disabled', false,
          idToken: await member.freshToken()),
      throwsA(isA<IbashoException>()),
    );

    // --- 5. Una cuenta creada saltandose la app no hace nada ---------------
    final orphanName = 'huerfano$stamp';
    final orphan = await backend.provisionAccount(
      username: orphanName,
      password: 'lo-que-sea-123',
    );
    await expectLater(
      newSession().signIn(username: orphanName, password: 'lo-que-sea-123'),
      throwsA(isA<IbashoException>()
          .having((e) => e.failure, 'failure', IbashoFailure.notAllowed)),
    );
    final orphanTokens = (await backend.signIn(
      username: orphanName,
      password: 'lo-que-sea-123',
    ))
        .tokens;
    for (final path in [
      '/allowlist',
      '/allowlist/${orphan.uid}',
      '/users/${member.state.uid}/profile',
      '/usernames',
      '/system',
    ]) {
      await expectLater(
        backend.read(path, idToken: orphanTokens.idToken),
        throwsA(isA<IbashoException>()),
        reason: 'lectura de $path',
      );
    }
    await expectLater(
      backend.write('/users/${orphan.uid}/profile', {'displayName': 'x'},
          idToken: orphanTokens.idToken),
      throwsA(isA<IbashoException>()),
    );

    // --- 6. Regenerar credencial: la vieja deja de valer, la nueva entra ----
    final entry = adminController.state.accounts
        .firstWhere((a) => a.username == memberName);
    final regenerated = await adminController.regenerateCredential(entry);
    expect(adminSession.state.uid, adminUidBefore);

    await expectLater(
      newSession().signIn(username: memberName, password: 'otra-contrasena-larga'),
      throwsA(isA<IbashoException>()),
    );
    final again = newSession();
    await again.signIn(username: memberName, password: regenerated.password);
    expect(again.state.phase, SessionPhase.mustChangePassword);
    expect(again.state.uid, isNot(member.state.uid),
        reason: 'la credencial regenerada es una identidad nueva');
    expect(again.state.accountId, member.state.accountId,
        reason: 'pero cuelga de la misma cuenta');
    await again.completePasswordChange('la-de-despues-de-olvidarla');
    expect(again.state.phase, SessionPhase.active);

    // Nada se ha perdido: el perfil sigue ahi y se puede seguir editando.
    final kept = ProfileController(
      backend: backend,
      session: again,
      defaultLocale: 'es',
      cardOf: _plainCard,
    );
    addTearDown(kept.dispose);
    await _until(() => kept.state.profile != null, 'perfil tras regenerar');
    expect(kept.state.profile!.displayName, 'Mireia');
    expect(kept.state.profile!.accentColor, '#E8A33D');
    expect(kept.state.profile!.birthday, '2001-02-03');
    expect(
      await kept.save(kept.state.profile!.copyWith(statusMessage: 'sigo aqui')),
      isTrue,
    );

    // La lista de administracion ensena una sola fila por persona.
    expect(
      adminController.state.accounts.where((a) => a.username == memberName),
      hasLength(1),
    );

    // --- 6-bis. Cambiar la contrasena propia desde Ajustes ------------------
    await expectLater(
      again.changeOwnPassword(
        currentPassword: 'no-es-esta',
        newPassword: 'una-nueva-de-verdad',
      ),
      throwsA(isA<IbashoException>().having(
          (e) => e.failure, 'failure', IbashoFailure.invalidCredentials)),
    );
    await again.changeOwnPassword(
      currentPassword: 'la-de-despues-de-olvidarla',
      newPassword: 'una-nueva-de-verdad',
    );
    expect(again.state.uid, regenerated.uid, reason: 'mismo uid, nada cambia');
    final afterChange = newSession();
    await afterChange.signIn(username: memberName, password: 'una-nueva-de-verdad');
    expect(afterChange.state.phase, SessionPhase.active);

    // --- 7. Deshabilitar corta el acceso; rehabilitar lo devuelve ----------
    final current = adminController.state.accounts
        .firstWhere((a) => a.uid == regenerated.uid);
    await adminController.setDisabled(current, true);
    await expectLater(
      newSession().signIn(username: memberName, password: 'una-nueva-de-verdad'),
      throwsA(isA<IbashoException>()
          .having((e) => e.failure, 'failure', IbashoFailure.accountDisabled)),
    );
    await adminController.setDisabled(current, false);
    await newSession().signIn(username: memberName, password: 'una-nueva-de-verdad');

    // --- 8. Renovar el token funciona ---------------------------------------
    final renewed = await backend.refresh(adminSession.state.tokens!.refreshToken);
    expect(renewed.uid, adminUidBefore);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Tamas de extremo a extremo', skip: skip, () async {
    // Dos cuentas ya activas, dadas de alta como lo haria el bootstrap.
    Future<SessionController> account(String name) async {
      final created = await backend.provisionAccount(username: name, password: 'tama-$name-123');
      await ownerPut('/allowlist/${created.uid}', {
        'accountId': created.uid,
        'username': name,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdBy': 'bootstrap',
        'disabled': false,
        'mustChangePassword': false,
        'generation': 1,
      });
      final session = newSession();
      await session.signIn(username: name, password: 'tama-$name-123');
      expect(session.state.phase, SessionPhase.active);
      return session;
    }

    final alba = await account('alba$stamp');
    final bruno = await account('bruno$stamp');

    // Dos equipos de la misma cuenta: lo que se hace en uno llega al otro.
    Future<UserCard> tamaCard(String? id, String? color) async =>
        UserCard(displayName: 'alba', tamaId: id);
    final desk = TamasController(backend: backend, session: alba, cardOf: tamaCard);
    final laptop = TamasController(backend: backend, session: alba, cardOf: tamaCard);
    addTearDown(desk.dispose);
    addTearDown(laptop.dispose);
    await _until(() => desk.state.loaded && laptop.state.loaded, 'listas iniciales');

    const look = TamaLook(parts: {TamaPart.body: 2, TamaPart.crown: 3}, color: '#F47AA6');
    final (id, failure) = await desk.create(
      name: 'Tommy',
      personality: TamaPersonality.playful,
      voice: const TamaVoice(pitch: 70),
      look: look,
    );
    expect(failure, isNull);
    expect(id, isNotNull);
    await _until(() => laptop.state.byId(id) != null, 'el Tama nuevo en el otro equipo');
    await _until(() => laptop.state.profileTamaId == id, 'el Tama de perfil en el otro equipo');
    final token = await alba.freshToken();
    expect(await backend.read('/users/${alba.state.accountId}/tamaCount', idToken: token), 1);

    // Editar el aspecto se ve en vivo en el otro equipo.
    await desk.saveIdentity(desk.state.byId(id)!.copyWith(
      look: look.withColor('#6B4F3A', TamaColorMode.hex).withPart(TamaPart.eyes, 5),
      name: 'Tomasa',
    ));
    await _until(
      () => laptop.state.byId(id)?.look.color == '#6B4F3A' &&
          laptop.state.byId(id)?.look.colorMode == TamaColorMode.hex &&
          laptop.state.byId(id)?.name == 'Tomasa',
      'la edicion llegando por SSE',
    );

    // Cuidar escribe una marca de tiempo del servidor, y nada mas.
    final before = DateTime.now().millisecondsSinceEpoch;
    await laptop.pet(id!);
    await _until(() => desk.state.byId(id)?.care.lastPetted != null, 'el mimo en el otro equipo');
    final petted = await backend.read('/tamas/$id/care/lastPetted', idToken: await alba.freshToken());
    expect(petted, isA<num>());
    expect((petted! as num).toInt(), greaterThanOrEqualTo(before - 60000));

    // Otra cuenta no lo ve ni lo toca.
    final other = await bruno.freshToken();
    await expectLater(backend.read('/tamas/$id', idToken: other), throwsA(isA<IbashoException>()));
    await expectLater(
      backend.write('/tamas/$id/look/color', '#000000', idToken: other),
      throwsA(isA<IbashoException>()),
    );
    await expectLater(
      backend.read('/tamas',
          idToken: other,
          query: DatabaseQuery(orderByChild: 'keeper', equalTo: alba.state.accountId)),
      throwsA(isA<IbashoException>()),
    );
    expect(
      await backend.read('/tamas',
          idToken: other,
          query: DatabaseQuery(orderByChild: 'keeper', equalTo: bruno.state.accountId)),
      anyOf(isNull, isEmpty),
    );

    // El tope: con 99 en el contador ni la app ni una llamada directa crean otro.
    await ownerPut('/users/${alba.state.accountId}/tamaCount', 99);
    final (full, reason) = await desk.create(
      name: 'Sobra',
      personality: TamaPersonality.calm,
      voice: const TamaVoice(),
      look: look,
    );
    expect(full, isNull);
    expect(reason, TamaCreateFailure.full);
    const sneaky = '-SinPermiso000000001';
    await expectLater(
      backend.merge('/', {
        'tamas/$sneaky': {
          'schema': 1,
          'creator': alba.state.accountId,
          'keeper': alba.state.accountId,
          'name': 'Sobra',
          'personality': 'calm',
          'voice': const TamaVoice().toJson(),
          'look': look.toJson(),
          'createdAt': serverTimestamp,
          'updatedAt': serverTimestamp,
        },
        'users/${alba.state.accountId}/tamaCount': 100,
        'users/${alba.state.accountId}/tamaLastChange': sneaky,
      }, idToken: await alba.freshToken()),
      throwsA(isA<IbashoException>()
          .having((e) => e.failure, 'failure', IbashoFailure.permissionDenied)),
    );
    await ownerPut('/users/${alba.state.accountId}/tamaCount', 1);

    // Borrar baja el contador y suelta el perfil en la misma operacion.
    expect(await desk.delete(id), isTrue);
    await _until(() => laptop.state.byId(id) == null, 'el borrado en el otro equipo');
    final after = await alba.freshToken();
    expect(await backend.read('/users/${alba.state.accountId}/tamaCount', idToken: after), 0);
    expect(await backend.read('/users/${alba.state.accountId}/tama', idToken: after), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('amigos y presencia de extremo a extremo', skip: skip, () async {
    // Tres cuentas activas, con su codigo de amigo dado como lo daria el admin.
    var counter = 100000 + stamp;
    Future<SessionController> account(String name) async {
      final created = await backend.provisionAccount(username: name, password: 'amigo-$name-123');
      final code = FriendCode.forCounter(counter++);
      await ownerPut('/allowlist/${created.uid}', {
        'accountId': created.uid,
        'username': name,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdBy': 'bootstrap',
        'disabled': false,
        'mustChangePassword': false,
        'generation': 1,
      });
      await ownerPut('/friendCodes/$code', created.uid);
      await ownerPut('/users/${created.uid}/friendCode', code);
      final session = newSession();
      await session.signIn(username: name, password: 'amigo-$name-123');
      // La primera entrada crea el perfil y su ficha.
      final profile = ProfileController(
        backend: backend,
        session: session,
        defaultLocale: 'es',
        cardOf: _plainCard,
      );
      addTearDown(profile.dispose);
      await _until(() => profile.state.profile != null, 'perfil de $name');
      return session;
    }

    final carla = await account('carla$stamp');
    final dani = await account('dani$stamp');
    final eva = await account('eva$stamp');

    final carlaFriends = FriendsController(backend: backend, session: carla);
    final daniFriends = FriendsController(backend: backend, session: dani);
    addTearDown(carlaFriends.dispose);
    addTearDown(daniFriends.dispose);
    await _until(() => carlaFriends.state.loaded && daniFriends.state.loaded, 'amigos');
    final daniCode = daniFriends.state.code!;

    // Buscar: un digito mal da invalido sin preguntar; bien, la ficha reducida.
    final typo = daniCode.replaceRange(0, 1, daniCode[0] == '1' ? '2' : '1');
    expect((await carlaFriends.lookup(typo)).outcome, LookupOutcome.invalid);
    final found = await carlaFriends.lookup(FriendCode.format(daniCode));
    expect(found.outcome, LookupOutcome.found);
    expect(found.card?.displayName, 'dani$stamp');

    // Antes de ser amigos, nada del perfil ni de la presencia.
    Future<void> denied(SessionController who, String path) async => expectLater(
          backend.read(path, idToken: await who.freshToken()),
          throwsA(isA<IbashoException>()),
          reason: path,
        );
    await denied(carla, '/users/${dani.state.accountId}/profile');
    await denied(carla, '/users/${dani.state.accountId}/presence');

    expect(await carlaFriends.sendRequest(dani.state.accountId), isNull);
    await _until(() => daniFriends.state.hasIncoming(carla.state.accountId), 'solicitud por SSE');
    // Quien la manda no puede aceptarla por el otro.
    expect(await carlaFriends.accept(dani.state.accountId), FriendFailure.rejected);
    expect(await daniFriends.accept(carla.state.accountId), isNull);
    await _until(() => carlaFriends.state.isFriend(dani.state.accountId), 'amistad por SSE');

    final profile = await backend.read('/users/${dani.state.accountId}/profile',
        idToken: await carla.freshToken());
    expect((profile! as Map)['username'], 'dani$stamp');
    // Un tercero sigue fuera, y no se cuela en la lista.
    await denied(eva, '/users/${dani.state.accountId}/profile');
    await expectLater(
      backend.write('/users/${dani.state.accountId}/friends/${eva.state.accountId}',
          {'since': serverTimestamp}, idToken: await eva.freshToken()),
      throwsA(isA<IbashoException>()),
    );

    // Muro: un mensaje por año, el segundo lo rechazan las reglas.
    final year = DateTime.now().year;
    expect(await carlaFriends.postOnWall(dani.state.accountId, year, '¡feliz cumple!'), isTrue);
    expect(await carlaFriends.postOnWall(dani.state.accountId, year, 'otra vez'), isFalse);

    // Presencia con la conexion persistente de verdad.
    final presence = PresenceController(backend: backend, session: dani, active: true);
    Future<Map<Object?, Object?>?> seenByCarla() async =>
        await backend.read('/users/${dani.state.accountId}/presence',
            idToken: await carla.freshToken()) as Map<Object?, Object?>?;
    for (var i = 0; i < 150 && (await seenByCarla())?['state'] != 'online'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect((await seenByCarla())?['state'], 'online');

    await presence.setMode(PresenceMode.invisible);
    for (var i = 0; i < 100 && (await seenByCarla())?['state'] != 'offline'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final hidden = await seenByCarla();
    expect(hidden?.keys.toSet(), {'state', 'lastSeen'});
    expect(hidden?['state'], 'offline');
    // Cerrar estando invisible no mueve la marca.
    presence.dispose();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await seenByCarla(), hidden);

    // Criterio 7: un proceso que se conecta y muere de golpe. Nadie escribe
    // nada; el servidor deja la presencia en desconectado.
    final holder = await Process.start('dart', [
      'run',
      'test/e2e/presence_holder.dart',
      RtdbSocket.endpoint().toString(),
      await dani.freshToken(),
      '/users/${dani.state.accountId}/presence',
    ]);
    final ready = Completer<String>();
    // `dart run` escribe antes sus propios avisos: se espera a la linea del
    // proceso.
    holder.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final text = line.replaceAll(RegExp(r'^.*Running build hooks\.*'), '').trim();
      if (!ready.isCompleted && (text == 'listo' || text.startsWith('fallo'))) {
        ready.complete(text);
      }
    });
    holder.stderr.drain<void>();
    expect(await ready.future.timeout(const Duration(seconds: 60)), 'listo');
    expect((await seenByCarla())?['state'], 'online');
    holder.kill(ProcessSignal.sigkill);
    await holder.exitCode;
    Map<Object?, Object?>? after;
    for (var i = 0; i < 150; i++) {
      after = await seenByCarla();
      if (after?['state'] == 'offline') break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(after?['state'], 'offline');
    expect((after!['lastSeen']! as num) > (hidden!['lastSeen']! as num), isTrue);

    // Dejar de ser amigos cierra el perfil otra vez.
    expect(await carlaFriends.unfriend(dani.state.accountId), isNull);
    await denied(carla, '/users/${dani.state.accountId}/profile');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Ficha sin Tama de perfil, para cuentas que aun no tienen ninguno.
Future<UserCard> _plainCard(UserProfile profile) async =>
    UserCard(displayName: profile.displayName, accentColor: profile.accentColor);

Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Tiempo agotado esperando: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
