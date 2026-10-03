// Ibasho — rellenar las tablas de siempre con lo que ya hay.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uso:
//   dart run tool/backfill_alltime.dart          # ensena lo que escribiria
//   dart run tool/backfill_alltime.dart --write  # lo escribe
//
// Requisitos: los mismos que `post_news.dart` (`.env` con IBASHO_PROJECT_ID y
// la CLI de Firebase autenticada).
//
// Por que existe: hasta la 0.8.x solo Hatarakitama tenia tabla de siempre.
// Desde la 0.9.0 todos los juegos la tienen (la mejor partida de cada cuenta),
// pero las partidas de antes solo estan en las tablas diarias y semanales.
// Esto recorre todas, se queda con la mejor de cada cuenta en cada juego y la
// escribe en `/leaderboards/{juego}/alltime`, solo si mejora la que ya hubiera:
// lanzarlo dos veces no cambia nada. Hatarakitama no se toca (acumula, y ya
// tenia la suya). Las cuentas de admin se saltan, como en las reglas.

import 'dart:convert';
import 'dart:io';

/// Por tiempo: menor es mejor.
bool _lowerIsBetter(String game) => game.startsWith('minesweeper_') || game == 'ohirune';

Future<int> main(List<String> args) async {
  final write = args.contains('--write');
  final env = _loadEnv(File('.env'));
  final projectId = env['IBASHO_PROJECT_ID'];
  if (projectId == null || projectId.isEmpty) {
    stderr.writeln('El .env no tiene IBASHO_PROJECT_ID.');
    return 78;
  }

  final boards = await _dbGet(projectId, '/leaderboards');
  if (boards is! Map) {
    stdout.writeln('No hay clasificaciones.');
    return 0;
  }
  final admins = await _adminAccounts(projectId);

  final updates = <String, Object?>{};
  for (final g in boards.entries) {
    final game = '${g.key}';
    if (game == 'hataraki' || g.value is! Map) continue;
    final lower = _lowerIsBetter(game);
    bool better(int a, int b) => lower ? a < b : a > b;
    final board = g.value as Map;

    // La mejor de cada cuenta, con el `at` de cuando la hizo.
    final best = <String, (int, int)>{};
    for (final span in ['daily', 'weekly']) {
      final periods = board[span];
      final list = periods is Map ? periods.values : (periods is List ? periods : const []);
      for (final period in list) {
        if (period is! Map) continue;
        final scores = period['scores'];
        if (scores is! Map) continue;
        final at = period['at'] is Map ? period['at'] as Map : const {};
        for (final s in scores.entries) {
          final who = '${s.key}';
          if (s.value is! num || admins.contains(who)) continue;
          final score = (s.value as num).toInt();
          final when = at[who] is num ? (at[who] as num).toInt() : 0;
          final had = best[who];
          if (had == null || better(score, had.$1)) best[who] = (score, when);
        }
      }
    }

    final current = board['alltime'] is Map ? (board['alltime'] as Map)['scores'] : null;
    for (final e in best.entries) {
      final had = current is Map ? current[e.key] : null;
      if (had is num && !better(e.value.$1, had.toInt())) continue;
      updates['$game/alltime/scores/${e.key}'] = e.value.$1;
      updates['$game/alltime/at/${e.key}'] = e.value.$2;
      stdout.writeln('$game  ${e.key}  ${e.value.$1}${had is num ? '  (antes $had)' : ''}');
    }
  }

  if (updates.isEmpty) {
    stdout.writeln('Nada que rellenar.');
    return 0;
  }
  if (!write) {
    stdout.writeln('${updates.length ~/ 2} por escribir. Con --write se escriben.');
    return 0;
  }
  final ok = await _dbUpdate(projectId, '/leaderboards', updates);
  stdout.writeln(ok ? '${updates.length ~/ 2} escritas.' : 'No se han podido escribir.');
  return ok ? 0 : 1;
}

/// Los `accountId` de las cuentas de admin (`/admins` va por uid).
Future<Set<String>> _adminAccounts(String projectId) async {
  final admins = await _dbGet(projectId, '/admins');
  if (admins is! Map) return const <String>{};
  final out = <String>{};
  for (final uid in admins.keys) {
    final id = await _dbGet(projectId, '/allowlist/$uid/accountId');
    if (id is String) out.add(id);
  }
  return out;
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
