// Ibasho — la unica conexion persistente con la Realtime Database.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/env.dart';
import 'errors.dart';
import 'models.dart';

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

/// Cliente del protocolo de websocket de la Realtime Database (version 5), el
/// mismo que hablan los SDK oficiales: **una** conexion por app que lleva a la
/// vez todas las escuchas en tiempo real, las escrituras de la presencia y sus
/// encargos para la desconexion.
///
/// El plan gratis de Firebase solo aguanta cien conexiones a la vez en todo el
/// proyecto, y cada `text/event-stream` de REST es una. Con un stream por nodo
/// mirado (cada ficha de amigo eran cinco) diez personas ya llegaban al tope;
/// por aqui cada app abierta cuenta una sola.
///
/// Mensajes, todos JSON:
/// - control `{"t":"c","d":{"t":…}}`: `h` saludo, `r` cambio de host, `s`
///   cierre del servidor, `p` ping (se contesta con `o`);
/// - peticiones `{"t":"d","d":{"r":n,"a":accion,"b":cuerpo}}`, con respuesta
///   `{"t":"d","d":{"r":n,"b":{"s":"ok"|motivo}}}`. Acciones: `auth`, `q`
///   (escuchar), `n` (dejar de escuchar), `p` (escribir), `o` (encargar para
///   la desconexion), `oc` (anular);
/// - avisos del servidor `{"t":"d","d":{"a":…,"b":…}}`: `d` (sustituir) y `m`
///   (fusionar) con `{"p":ruta,"d":datos,"t":etiqueta?}`, `c` (escucha
///   revocada) y `ac` (credencial caducada);
/// - un mensaje largo llega partido: primero el numero de trozos, luego los
///   trozos.
/// El cliente manda `0` cada 45 s para que ningun intermediario cierre la
/// conexion por inactividad.
class RtdbSocket {
  RtdbSocket({Uri Function({String? host})? endpoint}) : _endpoint = endpoint ?? RtdbSocket.endpoint;

  final Uri Function({String? host}) _endpoint;

  static const Duration _keepAliveEvery = Duration(seconds: 45);
  static const Duration _reauthEvery = Duration(minutes: 45);
  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _maxBackoff = Duration(seconds: 30);

  final StreamController<bool> _connection = StreamController<bool>.broadcast();
  final Map<int, Completer<Map<Object?, Object?>>> _pending =
      <int, Completer<Map<Object?, Object?>>>{};
  final List<_Listen> _listens = <_Listen>[];

  /// Sin credencial (o si devuelve cadena vacia) se conecta como visitante y
  /// solo se lee lo publico.
  Future<String> Function()? _token;

  WebSocket? _socket;
  bool _started = false;
  bool _closed = false;
  bool _background = false;
  bool _ready = false;

  /// El cierre en curso lo ha pedido la app: se reconecta sin esperar.
  bool _requested = false;
  int _nextRequest = 1;
  int _nextTag = 1;
  String? _host;
  Completer<void>? _hello;
  Completer<void>? _wake;
  int _framesLeft = 0;
  final StringBuffer _frames = StringBuffer();

  /// `true` cuando hay conexion lista (autenticada si hay credencial).
  Stream<bool> get connection => _connection.stream;

  bool get isConnected => _ready;

  /// Escuchas abiertas ahora mismo (para depuracion y tests).
  int get listens => _listens.length;

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

  // --- Ciclo de vida -------------------------------------------------------

  /// Cambia de credencial (al entrar o salir de una cuenta). Si ya habia
  /// conexion se corta y se rehace con la nueva, escuchas incluidas: asi lo
  /// encargado por la cuenta anterior se ejecuta y nada se lee con permisos
  /// que ya no tocan.
  void useToken(Future<String> Function()? token) {
    _token = token;
    restart();
  }

  /// En segundo plano se cierra la conexion y no se reintenta hasta volver.
  /// Android las mata en reposo de todas formas; asi ademas no se despierta la
  /// radio para nada. Al cerrarse, el servidor ejecuta lo encargado.
  void setBackground(bool background) {
    if (background == _background) return;
    _background = background;
    if (background) {
      unawaited(_socket?.close());
    } else {
      _poke();
    }
  }

  /// Corta la conexion y vuelve a abrirla en el acto.
  void restart() {
    _requested = true;
    final socket = _socket;
    if (socket != null) {
      unawaited(socket.close());
    } else {
      _poke();
    }
  }

  /// Una conexion para la presencia. Comparte el socket con todo lo demas;
  /// cerrarla corta y rehace el socket para que el servidor ejecute lo
  /// encargado, igual que si se cerrase una conexion propia.
  PresenceLink presence() {
    _ensureStarted();
    return _PresenceHandle(this);
  }

  Future<void> close() async {
    _closed = true;
    _poke();
    await _socket?.close();
    for (final listen in List<_Listen>.of(_listens)) {
      await listen.controller.close();
    }
    _listens.clear();
    await _connection.close();
  }

  void _ensureStarted() {
    if (_started || _closed) return;
    _started = true;
    unawaited(_run());
  }

  void _poke() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Espera a [delay] o a que algo pida reconectar ya.
  Future<void> _sleep(Duration? delay) {
    final wake = _wake ??= Completer<void>();
    if (delay == null) return wake.future;
    return Future.any<void>([wake.future, Future<void>.delayed(delay)]);
  }

  Future<void> _run() async {
    var backoff = const Duration(seconds: 1);
    while (!_closed) {
      if (_background) {
        await _sleep(null);
        backoff = const Duration(seconds: 1);
        continue;
      }
      Timer? keepAlive;
      Timer? reauth;
      var failed = false;
      try {
        final socket = await WebSocket.connect(_endpoint(host: _host).toString()).timeout(_timeout);
        if (_closed || _background) {
          await socket.close();
          continue;
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
        for (final listen in _listens) {
          _sendListen(listen);
        }
        _connection.add(true);

        keepAlive = Timer.periodic(_keepAliveEvery, (_) => _send('0'));
        reauth = Timer.periodic(_reauthEvery, (_) => unawaited(_reauthQuietly()));
        await done.future;
      } catch (e) {
        failed = true;
        if (!_closed && !_background) debugPrint('Ibasho: websocket caido ($e)');
      } finally {
        keepAlive?.cancel();
        reauth?.cancel();
        final wasReady = _ready;
        _ready = false;
        _failPending();
        for (final listen in _listens) {
          listen.retry?.cancel();
          listen.retry = null;
          listen.backoff = const Duration(seconds: 1);
        }
        await _socket?.close().catchError((_) {});
        _socket = null;
        if (wasReady && !_closed) _connection.add(false);
      }
      if (_closed) break;
      // Un cierre pedido (cambio de cuenta, presencia, otro host) vuelve en
      // el acto; una caida espera su retroceso.
      final requested = _requested && !failed;
      _requested = false;
      if (!requested && !_background) {
        await _sleep(backoff);
        final next = backoff * 2;
        backoff = next > _maxBackoff ? _maxBackoff : next;
      }
    }
  }

  Future<void> _authenticate() async {
    final token = _token;
    if (token == null) return;
    final credential = await token();
    if (credential.isEmpty) return;
    final reply = await _request('auth', {'cred': credential});
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

  // --- Escuchas ------------------------------------------------------------

  /// El nodo [path] en tiempo real, con los mismos eventos que un
  /// `text/event-stream`: primero un `put` de la raiz con todo (o `null`) y
  /// luego `put` y `patch` relativos. Si las reglas no dejan, se reintenta con
  /// retroceso sin dar error, como hacia el stream de REST.
  ///
  /// Cada ruta y consulta debe escucharse una sola vez a la vez: de repartirla
  /// se encargan `SharedWatches` y `UserNodeMux`.
  Stream<DatabaseEvent> watch(String path, {DatabaseQuery? query}) {
    late final _Listen listen;
    final controller = StreamController<DatabaseEvent>(
      onListen: () {
        _listens.add(listen);
        _ensureStarted();
        if (_ready) _sendListen(listen);
      },
      onCancel: () {
        _listens.remove(listen);
        listen.retry?.cancel();
        listen.retry = null;
        if (_ready && listen.sent) {
          unawaited(_request('n', listen.body(withHash: false)).then((_) {}, onError: (_) {}));
        }
      },
    );
    listen = _Listen(
      segments: _segmentsOf(path),
      query: query,
      tag: query == null ? null : _nextTag++,
      controller: controller,
    );
    return controller.stream;
  }

  void _sendListen(_Listen listen) {
    listen.sent = true;
    listen.gotData = false;
    _request('q', listen.body(withHash: true)).then((reply) {
      if (!_listens.contains(listen)) return;
      final status = reply['s'];
      if (status == 'ok') {
        listen.backoff = const Duration(seconds: 1);
        // Un nodo vacio puede no traer datos: se entrega `null`, como el
        // primer `put` del stream de REST.
        if (!listen.gotData) listen.emit(const DatabaseEvent(path: '/', data: null, isPatch: false));
        return;
      }
      debugPrint('Ibasho: escucha ${listen.path} rechazada ($status)');
      _retryLater(listen);
    }, onError: (Object _) {
      // Sin conexion: al volver se reenvian todas.
    });
  }

  void _retryLater(_Listen listen) {
    listen.sent = false;
    listen.retry?.cancel();
    final wait = listen.backoff;
    final next = wait * 2;
    listen.backoff = next > _maxBackoff ? _maxBackoff : next;
    listen.retry = Timer(wait, () {
      listen.retry = null;
      if (_ready && _listens.contains(listen)) _sendListen(listen);
    });
  }

  /// Reparte un aviso de datos entre las escuchas a las que toca.
  void _dispatch(Map<Object?, Object?> body, {required bool merge}) {
    final at = _segmentsOf('${body['p'] ?? ''}');
    final data = body['d'];
    final tag = body['t'];
    if (tag is num) {
      for (final listen in _listens) {
        if (listen.tag == tag.toInt()) listen.deliver(at, data, merge: merge);
      }
      return;
    }
    for (final listen in _listens) {
      if (listen.tag == null) listen.deliver(at, data, merge: merge);
    }
  }

  // --- Escrituras ----------------------------------------------------------

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

  // --- Cable ---------------------------------------------------------------

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
        restart();
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
    final body = message['b'];
    switch (message['a']) {
      case 'd' when body is Map:
        _dispatch(body, merge: false);
      case 'm' when body is Map:
        _dispatch(body, merge: true);
      case 'c' when body is Map:
        // Las reglas ya no dejan leerlo (p. ej. alguien deja de ser amigo).
        final path = _segmentsOf('${body['p'] ?? ''}').join('/');
        for (final listen in List<_Listen>.of(_listens)) {
          if (listen.segments.join('/') == path) _retryLater(listen);
        }
      case 'ac':
        // Credencial caducada o revocada: se vuelve a autenticar con una fresca.
        unawaited(_reauthQuietly());
      default:
        break;
    }
  }
}

List<String> _segmentsOf(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList(growable: false);

/// Una escucha: su ruta, su consulta y quien recibe lo que llega.
class _Listen {
  _Listen({required this.segments, required this.query, required this.tag, required this.controller});

  final List<String> segments;
  final DatabaseQuery? query;

  /// Las consultas llevan etiqueta: el servidor la devuelve con sus datos,
  /// que si no se confundirian con los de una escucha del nodo entero.
  final int? tag;
  final StreamController<DatabaseEvent> controller;

  bool sent = false;
  bool gotData = false;
  Timer? retry;
  Duration backoff = const Duration(seconds: 1);

  String get path => '/${segments.join('/')}';

  Map<String, Object?> body({required bool withHash}) {
    final q = query;
    return {
      'p': path,
      if (q != null)
        'q': {
          'i': q.orderByChild,
          'sp': q.equalTo,
          'sin': true,
          'ep': q.equalTo,
          'ein': true,
        },
      if (tag != null) 't': tag,
      if (withHash) 'h': '',
    };
  }

  void emit(DatabaseEvent event) {
    gotData = true;
    if (!controller.isClosed) controller.add(event);
  }

  /// Traduce un aviso en [at] (ruta absoluta) a eventos relativos a esta
  /// escucha, si le toca.
  void deliver(List<String> at, Object? data, {required bool merge}) {
    if (_startsWith(at, segments)) {
      final rel = at.sublist(segments.length);
      emit(DatabaseEvent(path: '/${rel.join('/')}', data: data, isPatch: merge));
      return;
    }
    if (!_startsWith(segments, at)) return;
    // El aviso cae por encima: se baja hasta esta escucha.
    final below = segments.sublist(at.length);
    if (!merge) {
      emit(DatabaseEvent(path: '/', data: _descend(data, below), isPatch: false));
      return;
    }
    if (data is! Map) return;
    for (final entry in data.entries) {
      final key = _segmentsOf('${entry.key}');
      if (_startsWith(below, key)) {
        emit(DatabaseEvent(path: '/', data: _descend(entry.value, below.sublist(key.length)), isPatch: false));
      } else if (_startsWith(key, below)) {
        final rel = key.sublist(below.length);
        emit(DatabaseEvent(path: '/${rel.join('/')}', data: entry.value, isPatch: false));
      }
    }
  }

  static bool _startsWith(List<String> path, List<String> prefix) {
    if (prefix.length > path.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (path[i] != prefix[i]) return false;
    }
    return true;
  }

  static Object? _descend(Object? node, List<String> path) {
    var current = node;
    for (final segment in path) {
      current = current is Map ? current[segment] : null;
    }
    return current;
  }
}

/// La presencia sobre el socket compartido.
class _PresenceHandle implements PresenceLink {
  _PresenceHandle(this._socket) {
    _forward = _socket.connection.listen((up) {
      if (!_out.isClosed) _out.add(up);
    });
    // Si el socket ya estaba listo, quien escucha se entera igual.
    if (_socket.isConnected) scheduleMicrotask(() => _out.isClosed ? null : _out.add(true));
  }

  final RtdbSocket _socket;
  final StreamController<bool> _out = StreamController<bool>.broadcast();
  late final StreamSubscription<bool> _forward;
  bool _closed = false;

  @override
  Stream<bool> get connection => _out.stream;

  @override
  bool get isConnected => !_closed && _socket.isConnected;

  @override
  Future<void> set(String path, Object? value) => _socket._command('p', path, value);

  @override
  Future<void> setOnDisconnect(String path, Object? value) => _socket._command('o', path, value);

  @override
  Future<void> cancelOnDisconnect(String path) => _socket._command('oc', path);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _forward.cancel();
    await _out.close();
    // Lo encargado solo se ejecuta al caer la conexion: se rehace.
    if (_socket.isConnected) _socket.restart();
  }
}
