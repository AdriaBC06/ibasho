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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ibasho/backend/errors.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/rest_ibasho_backend.dart';
import 'package:ibasho/core/env.dart';
import 'package:ibasho/state/admin.dart';
import 'package:ibasho/state/preferences.dart';
import 'package:ibasho/state/profile.dart';
import 'package:ibasho/state/session.dart';
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
}

Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Tiempo agotado esperando: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
