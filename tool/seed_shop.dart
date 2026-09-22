// Ibasho — carga los precios iniciales del Yatai.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uso:
//   dart run tool/seed_shop.dart
//
// Requisitos:
//   - Un `.env` relleno en la raiz (ver `.env.example`), por IBASHO_PROJECT_ID.
//   - La CLI de Firebase autenticada contra el proyecto (`firebase login`).
//
// Escribe /shop/prices entero con la CLI de Firebase, con las credenciales
// del desarrollador: se salta las reglas igual que `post_news.dart`. Un
// articulo sin precio no se puede comprar, asi que esto es lo que hace falta
// para que el Yatai tenga algo a la venta.

import 'dart:convert';
import 'dart:io';

/// Precios de partida: el buscaminas es gratis, Tsumiki cuesta 10 y Nihongo
/// 150, y las dos comidas de serie cuestan lo mismo. Ampliar el catalogo (mas juegos, mas comida desbloqueada)
/// es anadir aqui su precio, nada mas.
const Map<String, int> _prices = <String, int>{
  'game_minesweeper': 0,
  'game_tsumiki': 10,
  'game_nihongo': 150,
  'food_cookie': 3,
  'food_candy': 3,
};

Future<int> main() async {
  final env = _loadEnv(File('.env'));
  final projectId = env['IBASHO_PROJECT_ID'];
  if (projectId == null || projectId.isEmpty) {
    stderr.writeln('El .env no tiene IBASHO_PROJECT_ID.');
    return 78;
  }

  stdout.writeln('Cargando los precios del Yatai en $projectId…');
  final ok = await _dbSet(projectId, '/shop/prices', _prices);
  if (!ok) {
    stderr.writeln('No se han podido cargar los precios.');
    return 70;
  }
  for (final entry in _prices.entries) {
    stdout.writeln('  ${entry.key.padRight(20)} ${entry.value}');
  }
  stdout.writeln('Listo.');
  return 0;
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
