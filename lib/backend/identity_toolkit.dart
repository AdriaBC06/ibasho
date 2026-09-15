// Ibasho — cliente REST de Identity Toolkit.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/env.dart';
import 'errors.dart';
import 'models.dart';

/// Acceso a la API REST de Identity Toolkit.
///
/// No hay plugins de FlutterFire por medio: no estan soportados en Linux.
class IdentityToolkit {
  IdentityToolkit(this._client);

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  Uri _accounts(String method) => Uri.parse(
        '${Env.identityRoot}/accounts:$method?key=${Env.apiKey}',
      );

  Future<Map<String, Object?>> _post(Uri uri, Map<String, Object?> body) async {
    late final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on SocketException catch (e) {
      throw IbashoException(IbashoFailure.network, e.message);
    } on http.ClientException catch (e) {
      throw IbashoException(IbashoFailure.network, e.message);
    } catch (e) {
      throw IbashoException(IbashoFailure.network, '$e');
    }

    final decoded = res.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(res.body) as Map<String, Object?>;
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final error = decoded['error'];
    final message = error is Map && error['message'] is String
        ? error['message'] as String
        : 'HTTP ${res.statusCode}';
    throw IbashoException(_classify(message), message);
  }

  static IbashoFailure _classify(String message) {
    final code = message.split(':').first.trim();
    return switch (code) {
      'EMAIL_NOT_FOUND' ||
      'INVALID_PASSWORD' ||
      'INVALID_LOGIN_CREDENTIALS' ||
      'MISSING_PASSWORD' =>
        IbashoFailure.invalidCredentials,
      'USER_DISABLED' => IbashoFailure.accountDisabled,
      'TOO_MANY_ATTEMPTS_TRY_LATER' => IbashoFailure.tooManyAttempts,
      'WEAK_PASSWORD' => IbashoFailure.weakPassword,
      'EMAIL_EXISTS' => IbashoFailure.usernameTaken,
      'TOKEN_EXPIRED' ||
      'INVALID_ID_TOKEN' ||
      'INVALID_REFRESH_TOKEN' ||
      'USER_NOT_FOUND' ||
      'CREDENTIAL_TOO_OLD_LOGIN_AGAIN' =>
        IbashoFailure.tokenExpired,
      _ => IbashoFailure.unknown,
    };
  }

  static AuthTokens _tokensFrom(Map<String, Object?> json) {
    final seconds = int.tryParse('${json['expiresIn'] ?? json['expires_in']}') ?? 3600;
    return AuthTokens(
      uid: (json['localId'] ?? json['user_id']) as String,
      idToken: (json['idToken'] ?? json['id_token']) as String,
      refreshToken: (json['refreshToken'] ?? json['refresh_token']) as String,
      expiresAt: DateTime.now().add(Duration(seconds: seconds)),
    );
  }

  Future<AuthTokens> signInWithPassword(String email, String password) async =>
      _tokensFrom(await _post(_accounts('signInWithPassword'), {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }));

  /// Crea una cuenta. Los tokens que devuelve son responsabilidad de quien
  /// llama: el panel de administracion los descarta.
  Future<AuthTokens> signUp(String email, String password) async =>
      _tokensFrom(await _post(_accounts('signUp'), {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }));

  Future<AuthTokens> updatePassword(String idToken, String newPassword) async =>
      _tokensFrom(await _post(_accounts('update'), {
        'idToken': idToken,
        'password': newPassword,
        'returnSecureToken': true,
      }));

  Future<AuthTokens> refresh(String refreshToken) async {
    final uri = Uri.parse('${Env.secureTokenRoot}/token?key=${Env.apiKey}');
    late final http.Response res;
    try {
      res = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      ).timeout(_timeout);
    } on SocketException catch (e) {
      throw IbashoException(IbashoFailure.network, e.message);
    } on http.ClientException catch (e) {
      throw IbashoException(IbashoFailure.network, e.message);
    }
    final decoded = jsonDecode(res.body) as Map<String, Object?>;
    if (res.statusCode >= 200 && res.statusCode < 300) return _tokensFrom(decoded);
    final error = decoded['error'];
    final message = error is Map
        ? '${error['message'] ?? error['status'] ?? 'HTTP ${res.statusCode}'}'
        : 'HTTP ${res.statusCode}';
    throw IbashoException(_classify(message), message);
  }
}
