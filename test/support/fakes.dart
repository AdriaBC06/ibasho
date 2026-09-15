// Ibasho — dobles de prueba del backend y del almacenamiento.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:ibasho/backend/errors.dart';
import 'package:ibasho/backend/ibasho_backend.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/storage/secure_store.dart';
import 'package:ibasho/storage/settings_store.dart';

const String kAdminUid = 'uid-admin';
const String kAdminUsername = 'adria';

/// Backend en memoria. Sirve para el recorrido visual y para los tests de
/// interfaz: responde igual que el de verdad sin tocar la red.
class FakeIbashoBackend implements IbashoBackend {
  FakeIbashoBackend({
    this.uid = kAdminUid,
    this.username = kAdminUsername,
    this.isAdmin = true,
    this.mustChangePassword = false,
    this.hasProfile = true,
    this.link = LinkQuality.strong,
    this.locale = 'es',
  });

  final String uid;
  final String username;
  final bool isAdmin;
  final bool mustChangePassword;
  final bool hasProfile;
  final LinkQuality link;
  final String locale;

  /// Escrituras recibidas, por si un test quiere comprobarlas.
  final List<(String path, Object? value)> writes = <(String, Object?)>[];

  AuthTokens get tokens => AuthTokens(
        uid: uid,
        idToken: 'id-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  Map<String, Object?> get _entry => AllowlistEntry(
        uid: uid,
        accountId: uid,
        username: username,
        createdAt: DateTime(2026, 9, 1),
        createdBy: 'bootstrap',
        disabled: false,
        mustChangePassword: mustChangePassword,
        generation: 1,
      ).toJson();

  Map<String, Object?> get _profile => UserProfile(
        username: username,
        displayName: 'Adrià',
        statusMessage: 'montando el CP1 a las tantas',
        birthday: '1998-09-14',
        timezone: 'Europe/Madrid',
        locale: locale,
        createdAt: DateTime(2026, 9, 1),
      ).toJson();

  @override
  Future<SignIn> signIn({
    required String username,
    required String password,
    int knownGeneration = 1,
  }) async {
    if (password == 'mal') {
      throw const IbashoException(IbashoFailure.invalidCredentials);
    }
    return SignIn(tokens: tokens, generation: 1);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async => tokens;

  @override
  Future<AuthTokens> changePassword({
    required AuthTokens session,
    required String newPassword,
  }) async =>
      tokens;

  @override
  Future<ProvisionedAccount> provisionAccount({
    required String username,
    required String password,
    int generation = 1,
  }) async =>
      ProvisionedAccount(uid: 'uid-$username', username: username, password: password);

  @override
  Future<Object?> read(String path, {required String idToken, bool shallow = false}) async {
    if (path == '/allowlist/$uid') return _entry;
    if (path == '/admins/$uid') return isAdmin;
    if (path == '/users/$uid/profile') return hasProfile ? _profile : null;
    if (path == '/allowlist') {
      return <String, Object?>{
        uid: _entry,
        'uid-mireia': AllowlistEntry(
          uid: 'uid-mireia',
          accountId: 'uid-mireia',
          username: 'mireia',
          createdAt: DateTime(2026, 9, 10),
          createdBy: uid,
          disabled: false,
          mustChangePassword: true,
          generation: 1,
        ).toJson(),
        'uid-pau': AllowlistEntry(
          uid: 'uid-pau',
          accountId: 'uid-pau',
          username: 'pau',
          createdAt: DateTime(2026, 9, 12),
          createdBy: uid,
          disabled: true,
          mustChangePassword: false,
          generation: 2,
        ).toJson(),
      };
    }
    if (path == '/system/announcement') {
      return <String, Object?>{'text': 'el CP2 trae los Tamas', 'updatedAt': 0};
    }
    return null;
  }

  @override
  Future<void> write(String path, Object? value, {required String idToken}) async {
    writes.add((path, value));
  }

  @override
  Future<void> merge(String path, Map<String, Object?> value,
      {required String idToken}) async {
    writes.add((path, value));
  }

  @override
  Future<void> remove(String path, {required String idToken}) async {
    writes.add((path, null));
  }

  @override
  Stream<DatabaseEvent> watch(String path,
          {required Future<String> Function() token}) =>
      const Stream<DatabaseEvent>.empty();

  @override
  Future<LinkQuality> probe() async => link;

  @override
  void dispose() {}
}

/// Almacen de secretos en memoria.
class FakeSecureStore implements SecureStore {
  FakeSecureStore({AuthTokens? session}) {
    if (session != null) {
      _values['ibasho.session.tokens'] = jsonEncode(session.toJson());
    }
  }

  final Map<String, String> _values = <String, String>{};

  @override
  String get backendName => 'memoria';

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Preferencias que no tocan el disco.
class FakeSettingsStore implements SettingsStore {
  Preferences saved = const Preferences();

  @override
  Future<Preferences> load() async => saved;

  @override
  Future<void> save(Preferences preferences) async => saved = preferences;
}
