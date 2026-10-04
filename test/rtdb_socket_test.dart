// Ibasho — el websocket compartido contra un servidor de mentira.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/live_tree.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/rtdb_socket.dart';

/// Habla lo justo del protocolo: saluda, acepta `auth`, guarda las escuchas y
/// deja empujar datos a mano.
class _FakeServer {
  late HttpServer _http;
  final List<WebSocket> sockets = <WebSocket>[];
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final StreamController<Map<String, Object?>> _requests = StreamController.broadcast();
  int connections = 0;

  /// Lo que contesta a cada `q` antes del `ok`, por ruta.
  final Map<String, Object?> initial = <String, Object?>{};
  final Set<String> denied = <String>{};

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      connections++;
      sockets.add(socket);
      socket.add(jsonEncode({
        't': 'c',
        'd': {
          't': 'h',
          'd': {'ts': 0, 'v': '5', 'h': 'localhost', 's': 'x'}
        }
      }));
      socket.listen((raw) {
        if (raw == '0') return;
        final msg = jsonDecode('$raw') as Map<String, Object?>;
        if (msg['t'] != 'd') return;
        final d = msg['d']! as Map<String, Object?>;
        requests.add(d);
        _requests.add(d);
        final body = d['b']! as Map<String, Object?>;
        final path = '${body['p'] ?? ''}';
        if (d['a'] == 'q') {
          if (denied.contains(path)) {
            reply(socket, d['r']! as int, 'permission_denied');
            return;
          }
          if (initial.containsKey(path)) {
            push(socket, 'd', path.substring(1), initial[path], tag: body['t'] as int?);
          }
        }
        reply(socket, d['r']! as int, 'ok');
      }, onDone: () => sockets.remove(socket));
    });
  }

  Uri endpoint({String? host}) => Uri.parse('ws://127.0.0.1:${_http.port}/.ws');

  WebSocket get last => sockets.last;

  void reply(WebSocket socket, int r, String status) => socket.add(jsonEncode({
        't': 'd',
        'd': {
          'r': r,
          'b': {'s': status, 'd': <String, Object?>{}}
        }
      }));

  void push(WebSocket socket, String action, String path, Object? data, {int? tag}) => socket.add(jsonEncode({
        't': 'd',
        'd': {
          'a': action,
          'b': {'p': path, 'd': data, 't': ?tag}
        }
      }));

  Future<Map<String, Object?>> next(String action) =>
      _requests.stream.firstWhere((d) => d['a'] == action).timeout(const Duration(seconds: 5));

  Future<void> stop() => _http.close(force: true);
}

/// Lo que va llegando a una escucha, como arbol.
class _Tree {
  _Tree(Stream<DatabaseEvent> stream) {
    sub = stream.listen((e) {
      tree = applyDatabaseEvent(tree, e);
      events.add(e);
      _changes.add(null);
    });
  }

  late final StreamSubscription<DatabaseEvent> sub;
  Object? tree;
  final List<DatabaseEvent> events = <DatabaseEvent>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Future<void> until(bool Function() test) async {
    if (test()) return;
    await _changes.stream.firstWhere((_) => test()).timeout(const Duration(seconds: 5));
  }
}

void main() {
  late _FakeServer server;
  late RtdbSocket socket;

  setUp(() async {
    server = _FakeServer();
    await server.start();
    socket = RtdbSocket(endpoint: server.endpoint);
  });

  tearDown(() async {
    await socket.close();
    await server.stop();
  });

  test('todas las escuchas van por una sola conexion', () async {
    server.initial['/a'] = {'x': 1};
    server.initial['/b'] = 'hola';
    final a = _Tree(socket.watch('/a'));
    final b = _Tree(socket.watch('/b'));
    final c = _Tree(socket.watch('/c'));
    await a.until(() => a.tree != null);
    await b.until(() => b.tree != null);
    // Sin datos: un `put` de `null`, como el primero del stream de REST.
    await c.until(() => c.events.isNotEmpty);
    expect(c.events.single.data, isNull);
    expect(server.connections, 1);
    expect(a.tree, {'x': 1});
    expect(b.tree, 'hola');

    // Cambios por debajo y fusiones.
    server.push(server.last, 'd', 'a/y', 2);
    await a.until(() => (a.tree! as Map)['y'] == 2);
    server.push(server.last, 'm', 'a', {'x': null, 'z/w': 3});
    await a.until(() => (a.tree! as Map).containsKey('z'));
    expect(a.tree, {
      'y': 2,
      'z': {'w': 3}
    });
    expect(b.events, hasLength(1));
    await Future.wait([a.sub.cancel(), b.sub.cancel(), c.sub.cancel()]);
  });

  test('las consultas reciben lo suyo por etiqueta', () async {
    server.initial['/tamas'] = {
      't1': {'keeper': 'yo'}
    };
    final all = _Tree(socket.watch('/news'));
    final mine = _Tree(socket.watch('/tamas', query: const DatabaseQuery(orderByChild: 'keeper', equalTo: 'yo')));
    final q = await server.next('q');
    final body = q['b']! as Map<String, Object?>;
    // La primera puede ser cualquiera de las dos: se busca la de la consulta.
    final sent = server.requests.where((r) => (r['b']! as Map)['p'] == '/tamas').single['b']! as Map;
    expect(sent['q'], {'i': 'keeper', 'sp': 'yo', 'sin': true, 'ep': 'yo', 'ein': true});
    expect(sent['t'], isA<int>());
    expect(body, isNotNull);
    await mine.until(() => mine.tree != null);
    expect(mine.tree, {
      't1': {'keeper': 'yo'}
    });
    server.push(server.last, 'm', 'tamas', {
      't2': {'keeper': 'yo'}
    }, tag: sent['t']! as int);
    await mine.until(() => (mine.tree! as Map).length == 2);
    // Lo etiquetado no se cuela en otras escuchas.
    expect(all.events.where((e) => e.data != null), isEmpty);
    await Future.wait([all.sub.cancel(), mine.sub.cancel()]);
  });

  test('dejar de mirar manda `n` y reconectar reenvia lo que queda', () async {
    final a = _Tree(socket.watch('/a'));
    final b = _Tree(socket.watch('/b'));
    await a.until(() => a.events.isNotEmpty);
    await b.until(() => b.events.isNotEmpty);
    await b.sub.cancel();
    final n = await server.next('n');
    expect((n['b']! as Map)['p'], '/b');

    server.initial['/a'] = 'otra vez';
    final requeried = server.next('q');
    await server.last.close();
    final again = await requeried;
    expect((again['b']! as Map)['p'], '/a');
    await a.until(() => a.tree == 'otra vez');
    expect(server.connections, 2);
    expect(socket.listens, 1);
    await a.sub.cancel();
  });

  test('sin permiso no da error: reintenta', () async {
    server.denied.add('/x');
    final x = _Tree(socket.watch('/x'));
    await server.next('q');
    server.denied.clear();
    server.initial['/x'] = 5;
    await x.until(() => x.tree == 5);
    await x.sub.cancel();
  });

  test('la credencial se manda antes que las escuchas', () async {
    socket.useToken(() async => 'token-1');
    final a = _Tree(socket.watch('/a'));
    await a.until(() => a.events.isNotEmpty);
    final actions = server.requests.map((r) => r['a']).toList();
    expect(actions.indexOf('auth'), lessThan(actions.indexOf('q')));
    expect((server.requests.first['b']! as Map)['cred'], 'token-1');

    // Cambiar de cuenta rehace la conexion con la nueva credencial.
    final auth = server.next('auth');
    socket.useToken(() async => 'token-2');
    expect(((await auth)['b']! as Map)['cred'], 'token-2');
    expect(server.connections, 2);
    await a.sub.cancel();
  });

  test('la presencia comparte el socket y al cerrarla se rehace', () async {
    final a = _Tree(socket.watch('/a'));
    await a.until(() => a.events.isNotEmpty);
    final link = socket.presence();
    await link.connection.firstWhere((up) => up).timeout(const Duration(seconds: 5));
    await link.setOnDisconnect('/p', 'off');
    expect(server.connections, 1);
    await link.close();
    await server.next('q');
    expect(server.connections, 2);
    await a.sub.cancel();
  });

  test('en segundo plano se cierra y al volver reconecta', () async {
    final a = _Tree(socket.watch('/a'));
    await a.until(() => a.events.isNotEmpty);
    socket.setBackground(true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.sockets, isEmpty);
    expect(server.connections, 1);
    final q = server.next('q');
    socket.setBackground(false);
    await q;
    expect(server.connections, 2);
    await a.sub.cancel();
  });
}
