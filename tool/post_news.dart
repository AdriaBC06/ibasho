// Ibasho — publicar en el tablon de noticias desde la terminal.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uso:
//   dart run tool/post_news.dart --kind update --title "Ibasho 0.4.0" \
//       --version 0.4.0 --body "Mensajes cifrados, noticias y sugerencias." \
//       --title-en "Ibasho 0.4.0" --body-en "Encrypted messages, news, ideas."
//
// Cada entrada puede ir en los dos idiomas: `--title-en`, `--body-en` y un
// `--option-en` por cada `--option`, en el mismo orden. Sin ellos la app
// enseña la version castellana a todo el mundo.
//
//   dart run tool/post_news.dart --kind poll --title "¿Que viene despues?" \
//       --option "Un minijuego" --option "Una tienda" --closes 7
//
//   dart run tool/post_news.dart --list
//   dart run tool/post_news.dart --close <id>
//   dart run tool/post_news.dart --delete <id>
//
// Requisitos:
//   - Un `.env` relleno en la raiz (ver `.env.example`), por IBASHO_PROJECT_ID.
//   - La CLI de Firebase autenticada contra el proyecto (`firebase login`).
//
// Por que existe, habiendo un formulario en el canal de administracion: para
// poder anunciar una version sin tener que abrir la app, que es justo lo que
// hace falta el dia que se publica una. Escribe con la CLI de Firebase, con
// las credenciales del desarrollador, asi que no pasa por las reglas ni
// necesita una sesion; por eso `by` se pone a mano y por defecto dice
// "Ibasho".
//
// El recuento de las encuestas NO se toca desde aqui: los votos son anonimos
// y viven en el arbol de cada cual.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const Set<String> _kinds = <String>{'update', 'note', 'poll'};

const int _titleMax = 60;
const int _bodyMax = 600;
const int _optionMax = 40;
const int _optionsMax = 4;

Future<int> main(List<String> args) async {
  final options = _parse(args);
  final env = _loadEnv(File('.env'));
  final projectId = env['IBASHO_PROJECT_ID'];
  if (projectId == null || projectId.isEmpty) {
    stderr.writeln('El .env no tiene IBASHO_PROJECT_ID.');
    return 78;
  }

  if (options.flags.contains('list')) return _list(projectId);

  final close = options.single('close');
  if (close != null) {
    final ok = await _dbSet(projectId, '/news/$close/closed', true);
    stdout.writeln(ok ? 'Encuesta cerrada.' : 'No se ha podido cerrar.');
    return ok ? 0 : 70;
  }

  final remove = options.single('delete');
  if (remove != null) {
    final ok = await _dbSet(projectId, '/news/$remove', null);
    stdout.writeln(ok ? 'Entrada borrada.' : 'No se ha podido borrar.');
    return ok ? 0 : 70;
  }

  final kind = options.single('kind') ?? 'note';
  final title = options.single('title');
  final body = options.single('body') ?? '';
  final version = options.single('version');
  final by = options.single('by') ?? 'Ibasho';
  final optionList = options.all('option');
  final titleEn = options.single('title-en');
  final bodyEn = options.single('body-en');
  final optionsEn = options.all('option-en');

  if (!_kinds.contains(kind)) {
    stderr.writeln('--kind tiene que ser update, note o poll.');
    return 64;
  }
  if (title == null || title.isEmpty || title.length > _titleMax) {
    stderr.writeln('Falta --title, o pasa de $_titleMax caracteres.');
    return 64;
  }
  if (body.length > _bodyMax) {
    stderr.writeln('--body pasa de $_bodyMax caracteres.');
    return 64;
  }
  if (kind == 'poll' && (optionList.length < 2 || optionList.length > _optionsMax)) {
    stderr.writeln('Una encuesta necesita entre 2 y $_optionsMax --option.');
    return 64;
  }
  if (optionList.any((o) => o.isEmpty || o.length > _optionMax)) {
    stderr.writeln('Cada --option tiene que medir entre 1 y $_optionMax.');
    return 64;
  }
  if (kind != 'poll' && optionList.isNotEmpty) {
    stderr.writeln('Solo las encuestas llevan --option.');
    return 64;
  }
  if (titleEn != null && (titleEn.isEmpty || titleEn.length > _titleMax)) {
    stderr.writeln('--title-en pasa de $_titleMax caracteres.');
    return 64;
  }
  if (bodyEn != null && bodyEn.length > _bodyMax) {
    stderr.writeln('--body-en pasa de $_bodyMax caracteres.');
    return 64;
  }
  // O estan todas traducidas o ninguna: media encuesta en ingles y media en
  // castellano se lee peor que la original entera.
  if (optionsEn.isNotEmpty && optionsEn.length != optionList.length) {
    stderr.writeln('Hacen falta tantos --option-en como --option, o ninguno.');
    return 64;
  }
  if (optionsEn.any((o) => o.isEmpty || o.length > _optionMax)) {
    stderr.writeln('Cada --option-en tiene que medir entre 1 y $_optionMax.');
    return 64;
  }

  final closesDays = int.tryParse(options.single('closes') ?? '');
  final now = DateTime.now();
  final node = <String, Object?>{
    'kind': kind,
    'title': title,
    if (body.isNotEmpty) 'body': body,
    'version': ?version,
    'at': now.millisecondsSinceEpoch,
    'by': by,
    'titleEn': ?titleEn,
    'bodyEn': ?bodyEn,
    if (optionList.isNotEmpty)
      'options': <String, Object?>{
        for (var i = 0; i < optionList.length; i++) '$i': optionList[i],
      },
    if (optionsEn.isNotEmpty)
      'optionsEn': <String, Object?>{
        for (var i = 0; i < optionsEn.length; i++) '$i': optionsEn[i],
      },
    if (closesDays != null)
      'closesAt': now.add(Duration(days: closesDays)).millisecondsSinceEpoch,
  };

  final id = _pushId(now);
  stdout.writeln('Publicando en $projectId…');
  final ok = await _dbSet(projectId, '/news/$id', node);
  if (!ok) {
    stderr.writeln('No se ha podido publicar.');
    return 70;
  }
  stdout.writeln('Publicado: $id');
  return 0;
}

Future<int> _list(String projectId) async {
  final raw = await _dbGet(projectId, '/news');
  if (raw is! Map) {
    stdout.writeln('El tablon esta vacio.');
    return 0;
  }
  final ids = raw.keys.map((k) => '$k').toList()..sort();
  for (final id in ids.reversed) {
    final item = raw[id];
    if (item is! Map) continue;
    final at = item['at'];
    final when = at is num
        ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
            .toIso8601String()
            .substring(0, 16)
        : '?';
    final votes = item['tally'] is Map
        ? ' · votos ${(item['tally'] as Map).values.join('/')}'
        : '';
    stdout.writeln('$id  $when  [${item['kind']}] ${item['title']}$votes');
  }
  return 0;
}

/// El mismo formato de id que usa la app: 8 caracteres de tiempo y 12 de azar,
/// ordenables como texto. Aqui no hace falta el contador que evita colisiones
/// dentro del mismo milisegundo, porque esto publica una entrada y sale.
String _pushId(DateTime now) {
  const chars = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';
  var stamp = now.millisecondsSinceEpoch;
  final out = List<String>.filled(20, '-');
  for (var i = 7; i >= 0; i--) {
    out[i] = chars[stamp % 64];
    stamp = stamp ~/ 64;
  }
  final random = Random.secure();
  for (var i = 8; i < 20; i++) {
    out[i] = chars[random.nextInt(64)];
  }
  return out.join();
}

class _Options {
  _Options(this.values, this.flags);

  final Map<String, List<String>> values;
  final Set<String> flags;

  String? single(String name) => values[name]?.last;

  List<String> all(String name) => values[name] ?? const <String>[];
}

_Options _parse(List<String> args) {
  final values = <String, List<String>>{};
  final flags = <String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final name = arg.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      values.putIfAbsent(name, () => <String>[]).add(args[++i]);
    } else {
      flags.add(name);
    }
  }
  return _Options(values, flags);
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

Future<bool> _dbSet(String projectId, String path, Object? value) async {
  final process = await Process.start(
    'firebase',
    ['database:set', path, '--project', projectId, '--force'],
  );
  process.stdin.write(jsonEncode(value));
  await process.stdin.close();

  final out = await process.stdout.transform(utf8.decoder).join();
  final err = await process.stderr.transform(utf8.decoder).join();
  if (await process.exitCode != 0) {
    stderr.writeln(out);
    stderr.writeln(err);
    return false;
  }
  return true;
}
