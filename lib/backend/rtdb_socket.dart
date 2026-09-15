// Ibasho — conexion persistente con la Realtime Database, para la presencia.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/env.dart';
import 'errors.dart';

/// Lo que la presencia necesita del servidor y REST no puede dar: dejarle
/// escrituras encargadas para cuando esta app se desconecte (`onDisconnect`).
///
/// Mientras la conexion vive, el servidor sabe que la app esta abierta; si el
/// proceso se cierra, se cuelga o se queda sin red, el servidor ejecuta lo
/// encargado por su cuenta, sin que el cliente tenga que hacer nada.
abstract interface class PresenceLink {
  /// `true` cuando hay conexion autenticada. Emite en cada cambio; tras una
  /// reconexion hay que volver a encargar todo, porque el servidor ya ejecuto
  /// lo anterior al notar la caida.
  Stream<bool> get connection;

  bool get isConnected;

  /// Escribe ahora.
  Future<void> set(String path, Object? value);

  /// Encarga al servidor escribir `value` en `path` cuando esta conexion se
  /// pierda.
  Future<void> setOnDisconnect(String path, Object? value);

  /// Anula lo encargado para `path`.
  Future<void> cancelOnDisconnect(String path);

  Future<void> close();
}

/// Cliente del protocolo de websocket de la Realtime Database (version 5),
/// reducido a lo que Ibasho usa: autenticarse, escribir y encargar escrituras
/// para la desconexion. Es el mismo protocolo que hablan los SDK oficiales.
///
/// Mensajes, todos JSON:
/// - control `{"t":"c","d":{"t":…}}`: `h` saludo, `r` cambio de host, `s`
///   cierre del servidor, `p` ping (se contesta con `o`);
/// - datos `{"t":"d","d":{"r":n,"a":accion,"b":cuerpo}}`, con respuesta
///   `{"t":"d","d":{"r":n,"b":{"s":"ok"|motivo}}}`. Acciones: `auth`, `p`
///   (escribir), `o` (encargar para la desconexion), `oc` (anular).
/// - Un mensaje largo llega partido: primero el numero de trozos, luego los
///   trozos.
/// El cliente manda `0` cada 45 s para que ningun intermediario cierre la
/// conexion por inactividad.
class RtdbSocket implements PresenceLink {
  RtdbSocket({required Future<String> Function() token}) : _token = token {
    unawaited(_run());
  }

  final Future<String> Function() _token;

  static const Duration _keepAliveEvery = Duration(seconds: 45);
  static const Duration _reauthEvery = Duration(minutes: 45);
  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _maxBackoff = Duration(seconds: 30);

  final StreamController<bool> _connection = StreamController<bool>.broadcast();
  final Map<int, Completer<Map<Object?, Object?>>> _pending =
      <int, Completer<Map<Object?, Object?>>>{};

  WebSocket? _socket;
  bool _closed = false;
  bool _ready = false;
  int _nextRequest = 1;
  String? _host;
  Completer<void>? _hello;
  int _framesLeft = 0;
  final StringBuffer _frames = StringBuffer();

  @override
  Stream<bool> get connection => _connection.stream;

  @override
  bool get isConnected => _ready;

  /// Direccion del websocket. En produccion el espacio de nombres es el primer
  /// trozo del host de la base; con emulador va en la query, como en REST.
  static Uri endpoint({String? host}) {
    if (Env.useEmulator) {
      return Uri(
        scheme: 'ws',
        host: Env.emulatorHost,
        port: Env.emulatorDbPort,
        path: '/.ws',
        queryParameters: {'v': '5', 'ns': '${Env.projectId}-default-rtdb'},
      );
    }
    final base = Uri.parse(Env.databaseUrl);
    return Uri(
      scheme: 'wss',
      host: host ?? base.host,
      path: '/.ws',
      queryParameters: {'v': '5', 'ns': base.host.split('.').first},
    );
  }

  Future<void> _run() async {
    var backoff = const Duration(seconds: 1);
    while (!_closed) {
      Timer? keepAlive;
      Timer? reauth;
      try {
        final socket = await WebSocket.connect(endpoint(host: _host).toString())
            .timeout(_timeout);
        if (_closed) {
          await socket.close();
          return;
        }
        _socket = socket;
        _hello = Completer<void>();
        final done = Completer<void>();
        socket.listen(
          (message) => _receive('$message'),
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          onError: (Object e) {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );

        await _hello!.future.timeout(_timeout);
        await _authenticate();
        if (_closed) return;
        _ready = true;
        backoff = const Duration(seconds: 1);
        _connection.add(true);

        keepAlive = Timer.periodic(_keepAliveEvery, (_) => _send('0'));
        reauth = Timer.periodic(_reauthEvery, (_) => unawaited(_reauthQuietly()));
        await done.future;
      } catch (e) {
        if (!_closed) debugPrint('Ibasho: websocket de presencia caido ($e)');
      } finally {
        keepAlive?.cancel();
        reauth?.cancel();
        final wasReady = _ready;
        _ready = false;
        _failPending();
        await _socket?.close().catchError((_) {});
        _socket = null;
        if (wasReady && !_closed) _connection.add(false);
      }
      if (_closed) break;
      await Future<void>.delayed(backoff);
      final next = backoff * 2;
      backoff = next > _maxBackoff ? _maxBackoff : next;
    }
  }

  Future<void> _authenticate() async {
    final reply = await _request('auth', {'cred': await _token()});
    final status = reply['s'];
    if (status != 'ok') {
      throw IbashoException(IbashoFailure.permissionDenied, 'auth: $status');
    }
  }

  Future<void> _reauthQuietly() async {
    try {
      await _authenticate();
    } catch (e) {
      debugPrint('Ibasho: no se ha podido renovar la autenticacion del websocket ($e)');
      await _socket?.close();
    }
  }

  void _send(String text) {
    try {
      _socket?.add(text);
    } catch (_) {
      // El bucle de conexion se entera por onDone.
    }
  }

  Future<Map<Object?, Object?>> _request(String action, Map<String, Object?> body) {
    final id = _nextRequest++;
    final completer = Completer<Map<Object?, Object?>>();
    _pending[id] = completer;
    _send(jsonEncode({
      't': 'd',
      'd': {'r': id, 'a': action, 'b': body},
    }));
    return completer.future.timeout(_timeout, onTimeout: () {
      _pending.remove(id);
      throw const IbashoException(IbashoFailure.network, 'timeout');
    });
  }

  void _failPending() {
    final pending = Map.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(const IbashoException(IbashoFailure.network, 'desconectado'));
      }
    }
  }

  void _receive(String raw) {
    // Un mensaje partido: primero llega cuantos trozos vienen.
    if (_framesLeft == 0 && raw.length <= 6) {
      final count = int.tryParse(raw);
      if (count != null) {
        _framesLeft = count;
        _frames.clear();
        return;
      }
    }
    if (_framesLeft > 0) {
      _frames.write(raw);
      _framesLeft--;
      if (_framesLeft > 0) return;
      raw = _frames.toString();
      _frames.clear();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final data = decoded['d'];
    if (data is! Map) return;

    if (decoded['t'] == 'c') {
      _control(data);
    } else if (decoded['t'] == 'd') {
      _data(data);
    }
  }

  void _control(Map<Object?, Object?> message) {
    switch (message['t']) {
      case 'h':
        if (!(_hello?.isCompleted ?? true)) _hello!.complete();
      case 'r':
        // El servidor manda a otro host: se reconecta alli.
        if (message['d'] is String) _host = message['d'] as String;
        unawaited(_socket?.close());
      case 'p':
        _send(jsonEncode({
          't': 'c',
          'd': {'t': 'o', 'd': <String, Object?>{}},
        }));
      case 's':
        debugPrint('Ibasho: el servidor cierra el websocket (${message['d']})');
        unawaited(_socket?.close());
      default:
        break;
    }
  }

  void _data(Map<Object?, Object?> message) {
    final id = message['r'];
    if (id is num) {
      final completer = _pending.remove(id.toInt());
      final body = message['b'];
      if (completer != null && !completer.isCompleted) {
        completer.complete(body is Map ? body : const <Object?, Object?>{});
      }
      return;
    }
    if (message['a'] == 'ac') {
      // Credencial caducada o revocada: se vuelve a autenticar con una fresca.
      unawaited(_reauthQuietly());
    }
  }

  Future<void> _command(String action, String path, [Object? value]) async {
    if (!_ready) throw const IbashoException(IbashoFailure.network, 'sin conexion');
    final reply = await _request(action, {
      'p': path.startsWith('/') ? path : '/$path',
      if (action != 'oc') 'd': value,
    });
    final status = reply['s'];
    if (status == 'ok') return;
    throw IbashoException(
      status == 'permission_denied' ? IbashoFailure.permissionDenied : IbashoFailure.unknown,
      '$action $path: $status',
    );
  }

  @override
  Future<void> set(String path, Object? value) => _command('p', path, value);

  @override
  Future<void> setOnDisconnect(String path, Object? value) => _command('o', path, value);

  @override
  Future<void> cancelOnDisconnect(String path) => _command('oc', path);

  @override
  Future<void> close() async {
    _closed = true;
    await _socket?.close();
    await _connection.close();
  }
}
