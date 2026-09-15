// Ibasho — proceso de usar y tirar que se conecta y se deja matar.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Lo lanza el e2e de presencia:
//   dart run test/e2e/presence_holder.dart <ws> <idToken> <ruta>
// Habla el protocolo de websocket de la Realtime Database a pelo (sin nada de
// Flutter, para poder matarlo con SIGKILL): se autentica, encarga `offline`
// para la desconexion, publica `online`, escribe "listo" y espera. Cuando el
// test lo mata no hay cliente que escriba nada: si la presencia acaba en
// `offline`, lo ha hecho el servidor.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final socket = await WebSocket.connect(args[0]);
  final replies = <int, Completer<Object?>>{};
  var next = 1;
  final hello = Completer<void>();
  socket.listen((raw) {
    final message = jsonDecode('$raw');
    if (message is! Map) return;
    final d = message['d'];
    if (message['t'] == 'c' && d is Map && d['t'] == 'h') hello.complete();
    if (message['t'] == 'd' && d is Map && d['r'] is num) {
      replies.remove((d['r'] as num).toInt())?.complete((d['b'] as Map?)?['s']);
    }
  });
  Future<Object?> send(String action, Map<String, Object?> body) {
    final id = next++;
    final done = replies[id] = Completer<Object?>();
    socket.add(jsonEncode({'t': 'd', 'd': {'r': id, 'a': action, 'b': body}}));
    return done.future;
  }

  await hello.future;
  final path = args[2];
  final statuses = [
    await send('auth', {'cred': args[1]}),
    await send('o', {'p': path, 'd': {'state': 'offline', 'lastSeen': {'.sv': 'timestamp'}}}),
    await send('p', {'p': path, 'd': {'state': 'online', 'lastSeen': {'.sv': 'timestamp'}}}),
  ];
  stdout.writeln(statuses.every((s) => s == 'ok') ? 'listo' : 'fallo $statuses');
  Timer.periodic(const Duration(seconds: 40), (_) => socket.add('0'));
}
