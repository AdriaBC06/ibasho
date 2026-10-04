// Ibasho — cliente REST y de streaming de la Realtime Database.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/env.dart';
import 'errors.dart';
import 'models.dart';

/// Realtime Database por REST: lecturas y escrituras. Lo que va en tiempo
/// real pasa por `RtdbSocket`.
class RtdbClient {
  RtdbClient(this._client);

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  Uri _uri(String path, {String? idToken, Map<String, String> query = const {}}) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final params = <String, String>{
      // Sin token (cadena vacia) se lee como visitante: solo lo publico.
      if (idToken != null && idToken.isNotEmpty) 'auth': idToken,
      ...query,
    };
    if (Env.useEmulator) params['ns'] = '${Env.projectId}-default-rtdb';
    return Uri.parse('${Env.databaseRoot}$normalized.json')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  /// Parametros REST de una consulta. Van codificados en JSON, comillas
  /// incluidas, como pide la API.
  static Map<String, String> _queryParams(DatabaseQuery? query) => query == null
      ? const {}
      : {
          'orderBy': jsonEncode(query.orderByChild),
          'equalTo': jsonEncode(query.equalTo),
        };

  Never _fail(int status, String body) {
    if (status == 401 || status == 403) {
      throw IbashoException(IbashoFailure.permissionDenied, body);
    }
    throw IbashoException(IbashoFailure.unknown, 'HTTP $status: $body');
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on IbashoException {
      rethrow;
    } on SocketException catch (e) {
      throw IbashoException(IbashoFailure.network, e.message);
    } on http.ClientException catch (e) {
      throw IbashoException(IbashoFailure.network, e.message);
    } on TimeoutException {
      throw const IbashoException(IbashoFailure.network, 'timeout');
    }
  }

  Future<Object?> read(
    String path, {
    required String idToken,
    bool shallow = false,
    DatabaseQuery? query,
  }) =>
      _guard(() async {
        final res = await _client
            .get(_uri(path, idToken: idToken, query: {
              if (shallow) 'shallow': 'true',
              ..._queryParams(query),
            }))
            .timeout(_timeout);
        if (res.statusCode != 200) _fail(res.statusCode, res.body);
        if (res.body.isEmpty || res.body == 'null') return null;
        return jsonDecode(res.body);
      });

  Future<void> write(String path, Object? value, {required String idToken}) =>
      _guard(() async {
        final res = await _client
            .put(
              _uri(path, idToken: idToken, query: const {'print': 'silent'}),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(value),
            )
            .timeout(_timeout);
        if (res.statusCode >= 300) _fail(res.statusCode, res.body);
      });

  Future<void> merge(String path, Map<String, Object?> value, {required String idToken}) =>
      _guard(() async {
        final res = await _client
            .patch(
              _uri(path, idToken: idToken, query: const {'print': 'silent'}),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(value),
            )
            .timeout(_timeout);
        if (res.statusCode >= 300) _fail(res.statusCode, res.body);
      });

  Future<void> remove(String path, {required String idToken}) => _guard(() async {
        final res = await _client
            .delete(_uri(path, idToken: idToken, query: const {'print': 'silent'}))
            .timeout(_timeout);
        if (res.statusCode >= 300) _fail(res.statusCode, res.body);
      });

  /// Mide la conexion real contra el endpoint de la base.
  ///
  /// Un 401 tambien cuenta como conectado: prueba que hay servidor al otro
  /// lado, que es justo lo que queremos saber. La calidad sale de la latencia.
  Future<LinkQuality> probe() async {
    final started = DateTime.now();
    try {
      final res = await _client
          .get(_uri('/.info/serverTimeOffset', query: const {'shallow': 'true'}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 500) return LinkQuality.weak;
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (ms < 220) return LinkQuality.strong;
      if (ms < 700) return LinkQuality.fair;
      return LinkQuality.weak;
    } catch (_) {
      return LinkQuality.offline;
    }
  }
}
