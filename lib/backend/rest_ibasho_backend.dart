// Ibasho — implementacion REST del backend.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:http/http.dart' as http;

import '../core/env.dart';
import 'errors.dart';
import 'ibasho_backend.dart';
import 'identity_toolkit.dart';
import 'models.dart';
import 'rtdb_client.dart';
import 'rtdb_socket.dart';

/// Implementacion del contrato sobre las APIs REST de Firebase.
class RestIbashoBackend implements IbashoBackend {
  RestIbashoBackend({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null {
    _auth = IdentityToolkit(_client);
    _db = RtdbClient(_client);
  }

  final http.Client _client;
  final bool _ownsClient;
  late final IdentityToolkit _auth;
  late final RtdbClient _db;

  /// Hasta donde se busca una generacion de credencial al iniciar sesion.
  static const int maxGeneration = 4;

  static String emailFor(String username, int generation) {
    final user = username.trim().toLowerCase();
    final tag = generation <= 1 ? user : '$user+$generation';
    return '$tag@${Env.emailDomain}';
  }

  @override
  Future<SignIn> signIn({
    required String username,
    required String password,
    int knownGeneration = 1,
  }) async {
    // Se prueba primero la generacion que ya funciono en esta maquina y luego
    // el resto, de la mas reciente a la mas antigua.
    final order = <int>{
      knownGeneration.clamp(1, maxGeneration),
      for (var g = maxGeneration; g >= 1; g--) g,
    };

    IbashoException? last;
    for (final generation in order) {
      try {
        final tokens =
            await _auth.signInWithPassword(emailFor(username, generation), password);
        return SignIn(tokens: tokens, generation: generation);
      } on IbashoException catch (e) {
        last = e;
        // Solo tiene sentido seguir buscando si la credencial no cuadra con
        // esta generacion. Cualquier otro fallo se propaga tal cual.
        if (e.failure != IbashoFailure.invalidCredentials) rethrow;
      }
    }
    throw last ?? const IbashoException(IbashoFailure.invalidCredentials);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) => _auth.refresh(refreshToken);

  @override
  Future<AuthTokens> changePassword({
    required AuthTokens session,
    required String newPassword,
  }) =>
      _auth.updatePassword(session.idToken, newPassword);

  @override
  Future<ProvisionedAccount> provisionAccount({
    required String username,
    required String password,
    int generation = 1,
  }) async {
    // Cliente propio y de usar y tirar: nada de lo que pase aqui puede rozar
    // la sesion del administrador. Los tokens que devuelve `signUp` se
    // descartan sin llegar a salir de este metodo.
    final isolated = http.Client();
    try {
      final created = await IdentityToolkit(isolated)
          .signUp(emailFor(username, generation), password);
      return ProvisionedAccount(
        uid: created.uid,
        username: username,
        password: password,
      );
    } finally {
      isolated.close();
    }
  }

  @override
  Future<Object?> read(
    String path, {
    required String idToken,
    bool shallow = false,
    DatabaseQuery? query,
  }) =>
      _db.read(path, idToken: idToken, shallow: shallow, query: query);

  @override
  Future<void> write(String path, Object? value, {required String idToken}) =>
      _db.write(path, value, idToken: idToken);

  @override
  Future<void> merge(String path, Map<String, Object?> value, {required String idToken}) =>
      _db.merge(path, value, idToken: idToken);

  @override
  Future<void> remove(String path, {required String idToken}) =>
      _db.remove(path, idToken: idToken);

  @override
  Stream<DatabaseEvent> watch(
    String path, {
    required Future<String> Function() token,
    DatabaseQuery? query,
  }) =>
      _db.watch(path, token: token, query: query);

  @override
  PresenceLink openPresenceLink({required Future<String> Function() token}) =>
      RtdbSocket(token: token);

  @override
  Future<LinkQuality> probe() => _db.probe();

  @override
  void setBackground(bool background) => _db.setBackground(background);

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
