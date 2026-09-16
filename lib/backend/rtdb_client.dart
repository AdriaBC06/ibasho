// Ibasho — cliente REST y de streaming de la Realtime Database.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/env.dart';
import 'errors.dart';
import 'models.dart';

/// Realtime Database por REST, incluido el modo `text/event-stream`, que es lo
/// unico que funciona desde Dart puro en Linux.
class RtdbClient {
  RtdbClient(this._client);

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _maxBackoff = Duration(seconds: 30);

  // --- Segundo plano -----------------------------------------------------

  bool _background = false;
  final List<Completer<void>> _waitingForeground = <Completer<void>>[];
  final StreamController<bool> _backgroundChanges = StreamController<bool>.broadcast();

  /// En segundo plano se cierran las suscripciones abiertas y ninguna vuelve
  /// a intentarlo hasta que la app regresa. Android mata las conexiones en
  /// reposo de todas formas; asi ademas no se despierta la radio para nada.
  void setBackground(bool background) {
    if (background == _background) return;
    _background = background;
    _backgroundChanges.add(background);
    if (!background) {
      final waiting = List.of(_waitingForeground);
      _waitingForeground.clear();
      for (final completer in waiting) {
        completer.complete();
      }
    }
  }

  Future<void> _untilForeground() {
    if (!_background) return Future<void>.value();
    final completer = Completer<void>();
    _waitingForeground.add(completer);
    return completer.future;
  }

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

  /// Suscripcion en tiempo real con reconexion de retroceso exponencial.
  Stream<DatabaseEvent> watch(
    String path, {
    required Future<String> Function() token,
    DatabaseQuery? query,
  }) {
    late StreamController<DatabaseEvent> controller;
    var cancelled = false;
    StreamSubscription<String>? sub;
    var backoff = const Duration(seconds: 1);

    Future<void> connect() async {
      while (!cancelled) {
        if (_background) {
          await _untilForeground();
          backoff = const Duration(seconds: 1);
          if (cancelled) return;
        }
        StreamSubscription<bool>? sleeper;
        try {
          final request = http.Request(
              'GET', _uri(path, idToken: await token(), query: _queryParams(query)))
            ..headers['Accept'] = 'text/event-stream'
            ..followRedirects = true;
          final response = await _client.send(request).timeout(_timeout);
          if (response.statusCode != 200) {
            throw IbashoException(
              response.statusCode == 401 || response.statusCode == 403
                  ? IbashoFailure.permissionDenied
                  : IbashoFailure.unknown,
              'HTTP ${response.statusCode}',
            );
          }
          backoff = const Duration(seconds: 1);

          final done = Completer<void>();
          void finish([Object? error]) {
            if (done.isCompleted) return;
            error == null ? done.complete() : done.completeError(error);
          }

          // `cancel` y `auth_revoked` llegan como datos, no como errores: el
          // ensamblador los convierte en un cierre ordenado para que la
          // reconexion pida un token nuevo. Lanzar dentro del callback de
          // datos se escaparia como error asincrono sin capturar.
          final assembler = _SseAssembler(
            controller.add,
            onClose: (reason) {
              finish(IbashoException(IbashoFailure.tokenExpired, reason));
              unawaited(sub?.cancel());
            },
          );
          sub = response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
            (line) {
              try {
                assembler.feed(line);
              } catch (e) {
                finish(e);
                unawaited(sub?.cancel());
              }
            },
            onDone: finish,
            onError: (Object e) => finish(e),
            cancelOnError: true,
          );
          sleeper = _backgroundChanges.stream.where((b) => b).listen((_) {
            finish();
            unawaited(sub?.cancel());
          });
          await done.future;
        } catch (e) {
          if (cancelled) return;
          if (!_background) {
            debugPrint('Ibasho: stream $path caido ($e), reintento en '
                '${backoff.inSeconds} s');
          }
        } finally {
          await sleeper?.cancel();
        }
        if (cancelled) return;
        if (_background) continue;
        await Future<void>.delayed(backoff);
        final next = backoff * 2;
        backoff = next > _maxBackoff ? _maxBackoff : next;
      }
    }

    controller = StreamController<DatabaseEvent>(
      onListen: () => unawaited(connect()),
      onCancel: () async {
        cancelled = true;
        await sub?.cancel();
      },
    );
    return controller.stream;
  }
}

/// Reensambla los eventos de `text/event-stream` linea a linea.
///
/// La Realtime Database emite `put`, `patch`, `keep-alive`, `cancel` y
/// `auth_revoked`. Los dos ultimos cierran el flujo para que la capa de
/// reconexion vuelva a pedir un token fresco.
class _SseAssembler {
  _SseAssembler(this.emit, {required this.onClose});

  final void Function(DatabaseEvent) emit;

  /// El servidor ha cerrado la suscripcion (`cancel`, `auth_revoked`).
  final void Function(String reason) onClose;

  String? _event;
  final StringBuffer _data = StringBuffer();

  void feed(String line) {
    if (line.isEmpty) {
      _flush();
      return;
    }
    if (line.startsWith('event:')) {
      _event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (_data.isNotEmpty) _data.write('\n');
      _data.write(line.substring(5).trim());
    }
  }

  void _flush() {
    final event = _event;
    final payload = _data.toString();
    _event = null;
    _data.clear();
    if (event == null || payload.isEmpty) return;

    switch (event) {
      case 'put':
      case 'patch':
        final decoded = jsonDecode(payload);
        if (decoded is! Map) return;
        emit(DatabaseEvent(
          path: (decoded['path'] as String?) ?? '/',
          data: decoded['data'],
          isPatch: event == 'patch',
        ));
      case 'auth_revoked':
      case 'cancel':
        onClose(event);
      default:
        // keep-alive y cualquier cosa nueva: se ignoran a proposito.
        break;
    }
  }
}
