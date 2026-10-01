// Ibasho — copiar al archivo las sugerencias ya decididas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uso:
//   dart run tool/archive_suggestions.dart          # ensena lo que copiaria
//   dart run tool/archive_suggestions.dart --write  # lo copia
//
// Requisitos: los mismos que `post_news.dart` (`.env` con IBASHO_PROJECT_ID y
// la CLI de Firebase autenticada).
//
// Por que existe: hasta la 0.8.x cada cuenta tenia una sola sugerencia en
// `/suggestions/{accountId}` y la siguiente pisaba la anterior. Desde la 0.9.0
// el admin archiva cada veredicto en `/suggestionHistory/{accountId}/{at}`,
// pero las que se decidieron antes solo estan en el nodo vivo. Esto las copia
// al archivo. Solo anade: la clave es el `at`, asi que lanzarlo dos veces no
// duplica nada, y no toca `/suggestions`.

import 'dart:convert';
import 'dart:io';

Future<int> main(List<String> args) async {
  final write = args.contains('--write');
  final env = _loadEnv(File('.env'));
  final projectId = env['IBASHO_PROJECT_ID'];
  if (projectId == null || projectId.isEmpty) {
    stderr.writeln('El .env no tiene IBASHO_PROJECT_ID.');
    return 78;
  }

  final live = await _dbGet(projectId, '/suggestions');
  if (live is! Map) {
    stdout.writeln('No hay sugerencias.');
    return 0;
  }

  final updates = <String, Object?>{};
  for (final e in live.entries) {
    final raw = e.value;
    if (raw is! Map) continue;
    final status = raw['status'];
    final at = raw['at'];
    if (status != 'accepted' && status != 'rejected') continue;
    if (at is! num || raw['title'] is! String || raw['body'] is! String) continue;
    final note = raw['note'];
    final decidedAt = raw['decidedAt'];
    final decidedBy = raw['decidedBy'];
    updates['${e.key}/${at.toInt()}'] = <String, Object?>{
      'title': raw['title'],
      'body': raw['body'],
      'at': at.toInt(),
      'status': status,
      if (note is String && note.isNotEmpty) 'note': note,
      if (decidedAt is num) 'decidedAt': decidedAt.toInt(),
      if (decidedBy is String && decidedBy.isNotEmpty) 'decidedBy': decidedBy,
    };
    stdout.writeln('$status  ${e.key}  ${raw['title']}');
  }

  if (updates.isEmpty) {
    stdout.writeln('Ninguna decidida que archivar.');
    return 0;
  }
  if (!write) {
    stdout.writeln('${updates.length} por archivar. Con --write se copian.');
    return 0;
  }
  final ok = await _dbUpdate(projectId, '/suggestionHistory', updates);
  stdout.writeln(ok ? '${updates.length} archivadas.' : 'No se han podido archivar.');
  return ok ? 0 : 1;
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

Future<bool> _dbUpdate(String projectId, String path, Map<String, Object?> value) async {
  final process = await Process.start(
    'firebase',
    ['database:update', path, '--project', projectId, '--force'],
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
