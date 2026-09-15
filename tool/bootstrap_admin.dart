// Ibasho — creacion de la primera cuenta de administracion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uso:
//   dart run tool/bootstrap_admin.dart --username adria
//   dart run tool/bootstrap_admin.dart --username adria --password <la-que-sea>
//
// Requisitos:
//   - Un `.env` relleno en la raiz del repositorio (ver `.env.example`).
//   - La CLI de Firebase autenticada contra el proyecto (`firebase login`).
//
// Que hace:
//   1. Crea la cuenta en Identity Toolkit por REST, con la API key publica.
//   2. Escribe /allowlist/<uid>, /admins/<uid>, /usernames/<usuario> y su
//      codigo de amigo (/friendCodes, /users/<uid>/friendCode y el contador) usando
//      la CLI de Firebase, que trabaja con las credenciales del desarrollador
//      y por eso puede saltarse las reglas. Es la unica manera de romper el
//      huevo y la gallina: sin un admin ya existente, las reglas no dejan
//      escribir en /admins.
//
// A partir de aqui el flujo normal de la app cubre todo lo demas: esta cuenta
// entra, cambia la contrasena de un solo uso y puede crear al resto.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ibasho/core/friend_code.dart';

const String _alphabet =
    'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,16}$');

Future<int> main(List<String> args) async {
  final options = _parse(args);
  final username = options['username'];
  if (username == null || !_usernamePattern.hasMatch(username)) {
    stderr.writeln('Falta --username, o no cumple ^[a-z0-9_]{3,16}\$');
    stderr.writeln('Uso: dart run tool/bootstrap_admin.dart --username <nombre>');
    return 64;
  }

  final env = _loadEnv(File('.env'));
  final apiKey = env['IBASHO_API_KEY'];
  final projectId = env['IBASHO_PROJECT_ID'];
  final domain = env['IBASHO_EMAIL_DOMAIN'] ?? 'ibasho.top';
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('El .env no tiene IBASHO_API_KEY. Copia .env.example y rellenalo.');
    return 78;
  }
  if (projectId == null || projectId.isEmpty) {
    stderr.writeln('El .env no tiene IBASHO_PROJECT_ID.');
    return 78;
  }

  final password = options['password'] ?? _generatePassword();
  final email = '$username@$domain';

  stdout.writeln('Creando la cuenta $username en $projectId…');
  String uid;
  try {
    uid = await _signUp(apiKey: apiKey, email: email, password: password);
  } on _BootstrapError catch (e) {
    if (!e.message.startsWith('EMAIL_EXISTS')) {
      stderr.writeln('No se ha podido crear la cuenta: ${e.message}');
      return 70;
    }
    // La cuenta ya existe en Identity Toolkit, normalmente porque una pasada
    // anterior murio despues de crearla. Si la contrasena que nos han dado es
    // la suya, se recupera el uid y se sigue: asi esto se puede relanzar.
    stdout.writeln('  la cuenta ya existia, recuperando su uid…');
    try {
      uid = await _signIn(apiKey: apiKey, email: email, password: password);
    } on _BootstrapError catch (e2) {
      stderr.writeln('Existe una cuenta con ese nombre y la contrasena no es');
      stderr.writeln('la que has pasado (${e2.message}). Vuelve a lanzarlo con');
      stderr.writeln('--password <la buena>, o elige otro --username.');
      return 70;
    }
  }
  stdout.writeln('  uid: $uid');

  final now = DateTime.now().millisecondsSinceEpoch;
  // La primera identidad de la cuenta presta su uid como identificador estable
  // de la cuenta: ahi colgaran sus datos aunque se regenere la credencial.
  final entry = <String, Object?>{
    'accountId': uid,
    'username': username,
    'createdAt': now,
    'createdBy': 'bootstrap',
    'disabled': false,
    'mustChangePassword': true,
    'generation': 1,
  };

  // El orden importa: la regla de /usernames exige que la cuenta a la que
  // apunta ya este en la allowlist.
  // El codigo de amigo sale del contador, como en cualquier alta. Si el
  // arranque se relanza para una cuenta que ya tenia codigo, no se le da otro.
  final existingCode = await _dbGet(projectId, '/users/$uid/friendCode');
  final counterRaw = await _dbGet(projectId, '/system/friendCodeCounter');
  final counter = counterRaw is num ? counterRaw.toInt() : 1;
  final code = FriendCode.forCounter(counter);

  final ok = await _dbSet(projectId, '/allowlist/$uid', entry) &&
      await _dbSet(projectId, '/admins/$uid', true) &&
      await _dbSet(projectId, '/usernames/$username', uid) &&
      (existingCode is String ||
          (await _dbSet(projectId, '/friendCodes/$code', uid) &&
              await _dbSet(projectId, '/users/$uid/friendCode', code) &&
              await _dbSet(projectId, '/system/friendCodeCounter', counter + 1)));
  if (!ok) {
    stderr.writeln('');
    stderr.writeln('La cuenta existe en Identity Toolkit pero no se ha podido');
    stderr.writeln('escribir en la base. Comprueba `firebase login` y vuelve a');
    stderr.writeln('lanzar esto con --password ${_quote(password)} para no');
    stderr.writeln('perder la credencial.');
    return 70;
  }

  stdout
    ..writeln('')
    ..writeln('Listo. Apunta esto, no se vuelve a mostrar:')
    ..writeln('')
    ..writeln('  usuario:     $username')
    ..writeln('  contrasena:  $password')
    ..writeln('')
    ..writeln('Al entrar por primera vez la app pedira cambiarla.');
  return 0;
}

class _BootstrapError implements Exception {
  _BootstrapError(this.message);

  final String message;
}

Map<String, String> _parse(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final name = arg.substring(2);
    if (name.contains('=')) {
      final at = name.indexOf('=');
      options[name.substring(0, at)] = name.substring(at + 1);
    } else if (i + 1 < args.length) {
      options[name] = args[++i];
    }
  }
  return options;
}

Map<String, String> _loadEnv(File file) {
  if (!file.existsSync()) return const <String, String>{};
  final values = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final at = line.indexOf('=');
    if (at <= 0) continue;
    values[line.substring(0, at).trim()] = line.substring(at + 1).trim();
  }
  return values;
}

String _generatePassword() {
  final random = Random.secure();
  return String.fromCharCodes(
    List<int>.generate(16, (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length))),
  );
}

String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

Future<String> _signUp({
  required String apiKey,
  required String email,
  required String password,
}) =>
    _identity(
      'signUp',
      apiKey: apiKey,
      body: {'email': email, 'password': password, 'returnSecureToken': false},
    );

Future<String> _identity(
  String method, {
  required String apiKey,
  required Map<String, Object?> body,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:$method?key=$apiKey',
    );
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final payload = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(payload) as Map<String, Object?>;
    if (response.statusCode >= 300) {
      final error = decoded['error'];
      throw _BootstrapError(
        error is Map ? '${error['message']}' : 'HTTP ${response.statusCode}',
      );
    }
    return decoded['localId']! as String;
  } finally {
    client.close();
  }
}

Future<String> _signIn({
  required String apiKey,
  required String email,
  required String password,
}) =>
    _identity(
      'signInWithPassword',
      apiKey: apiKey,
      body: {'email': email, 'password': password, 'returnSecureToken': false},
    );

/// Lee un nodo con la CLI de Firebase. `null` si no existe o no se puede.
Future<Object?> _dbGet(String projectId, String path) async {
  final result = await Process.run(
    'firebase',
    ['database:get', path, '--project', projectId],
  );
  if (result.exitCode != 0) return null;
  try {
    return jsonDecode('${result.stdout}'.trim());
  } catch (_) {
    return null;
  }
}

/// Escribe un nodo con la CLI de Firebase, que usa las credenciales del
/// desarrollador y por eso no la frenan las reglas.
Future<bool> _dbSet(String projectId, String path, Object? value) async {
  stdout.writeln('  escribiendo $path');
  final process = await Process.start(
    'firebase',
    ['database:set', path, '--project', projectId, '--force'],
    mode: ProcessStartMode.normal,
  );
  process.stdin.write(jsonEncode(value));
  await process.stdin.close();

  final out = await process.stdout.transform(utf8.decoder).join();
  final err = await process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln(out);
    stderr.writeln(err);
    return false;
  }
  return true;
}
