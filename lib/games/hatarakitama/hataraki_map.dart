// Ibasho — Hatarakitama: el mapa del día de cada sitio de expedición.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'hataraki_data.dart';
import 'hataraki_town.dart' show HDayRng;

/// Lo que hay en una casilla del mapa.
enum HNodeKind {
  /// Botín del sitio.
  loot,

  /// Recolecta rara: a veces lo más raro del sitio.
  forage,

  /// Peligro: pide fuerza o una poción de cura; si no, se pierde tiempo y
  /// no se trae nada de ella.
  danger,

  /// Descanso: corto y sin gastar comida.
  rest,

  /// Tesoro: más probabilidad de ticket.
  treasure,

  /// Encargo: un paquete para el gran encargo del tablón. Hay uno en cada
  /// mapa.
  order,
}

/// Filas de cada columna del mapa (arriba, en medio y abajo).
const int hMapRows = 3;

/// Tiempo de cada casilla respecto a la media.
const Map<HNodeKind, double> _nodeTime = {
  HNodeKind.loot: 1,
  HNodeKind.forage: 1.1,
  HNodeKind.danger: 1.2,
  HNodeKind.rest: .5,
  HNodeKind.treasure: 1.3,
  HNodeKind.order: 1,
};

/// Lo que tarda de más una casilla de peligro que no se pasa.
const double hDangerDelay = .5;

/// Botín de más con porteador.
const double hPorterLoot = .5;

/// Tiempo de menos con carro y con poción de prisa.
const double hCartTime = .25;
const double hHasteTime = .2;

/// Probabilidad de tesoro con una poción de suerte y con una runa de suerte.
const double hLuckPotion = 2;
const double hLuckRune = 1.5;

/// Una casilla del mapa.
class HMapNode {
  const HMapNode(
    this.col,
    this.row,
    this.kind,
    this.minutes, {
    this.fog = false,
    this.threat = 0,
  });

  final int col;
  final int row;
  final HNodeKind kind;

  /// Minutos que se tarda en ella, antes de carro y prisa.
  final int minutes;

  /// Con niebla no se sabe qué hay hasta llegar (o revelarla).
  final bool fog;

  /// Fuerza que pide un peligro.
  final int threat;

  /// Se puede ir de esta casilla a [next].
  bool leadsTo(HMapNode next) =>
      next.col == col + 1 && (next.row - row).abs() <= 1;
}

/// El mapa de un sitio en un día: columnas de 2 o 3 casillas unidas con la
/// siguiente columna si están en la misma fila o en una de al lado. El mismo
/// para todos ese día.
class HZoneMap {
  const HZoneMap(this.zone, this.day, this.columns);

  final String zone;
  final int day;
  final List<List<HMapNode>> columns;

  HMapNode? node(int col, int row) {
    if (col < 0 || col >= columns.length) return null;
    return columns[col].where((n) => n.row == row).firstOrNull;
  }

  /// Las casillas de una ruta (una fila por columna).
  List<HMapNode> nodesOf(List<int> route) => [
    for (var c = 0; c < route.length; c++) node(c, route[c])!,
  ];

  /// Si [route] pasa por una casilla de cada columna, unidas entre sí.
  bool isValid(List<int> route) {
    if (route.length != columns.length) return false;
    for (var c = 0; c < route.length; c++) {
      final n = node(c, route[c]);
      if (n == null) return false;
      if (c > 0 && !node(c - 1, route[c - 1])!.leadsTo(n)) return false;
    }
    return true;
  }

  /// Ruta de partida: por la fila de en medio (o la más cercana), sin mirar
  /// lo que hay, que la niebla no se chiva.
  List<int> get defaultRoute {
    final route = <int>[];
    for (var c = 0; c < columns.length; c++) {
      final want = c == 0 ? 1 : route.last;
      final options = [
        for (final n in columns[c])
          if (c == 0 || node(c - 1, route.last)!.leadsTo(n)) n.row,
      ]..sort((a, b) => (a - want).abs().compareTo((b - want).abs()));
      route.add(options.first);
    }
    return route;
  }

  /// [route] pasando por la casilla ([col], [row]): las demás columnas se
  /// mueven lo justo para que la ruta siga unida.
  List<int> routeThrough(List<int> route, int col, int row) {
    if (node(col, row) == null) return route;
    final next = isValid(route) ? [...route] : defaultRoute;
    next[col] = row;
    int nearest(int c, int from, int want) {
      final options = [
        for (final n in columns[c])
          if ((n.row - from).abs() <= 1) n.row,
      ]..sort((a, b) => (a - want).abs().compareTo((b - want).abs()));
      return options.first;
    }

    for (var c = col + 1; c < columns.length; c++) {
      if ((next[c] - next[c - 1]).abs() > 1 || node(c, next[c]) == null) {
        next[c] = nearest(c, next[c - 1], next[c]);
      }
    }
    for (var c = col - 1; c >= 0; c--) {
      if ((next[c] - next[c + 1]).abs() > 1 || node(c, next[c]) == null) {
        next[c] = nearest(c, next[c + 1], next[c]);
      }
    }
    return next;
  }

  /// Minutos de la ruta sin carro ni prisa, y los que comen (el descanso no
  /// gasta comida).
  int minutesOf(List<int> route) =>
      nodesOf(route).fold(0, (sum, n) => sum + n.minutes);

  int eatingMinutesOf(List<int> route) => nodesOf(
    route,
  ).where((n) => n.kind != HNodeKind.rest).fold(0, (sum, n) => sum + n.minutes);
}

/// Columnas del mapa de un sitio: de 4 en los primeros a 6 en los últimos.
int hMapColumns(HZone zone) => 4 + hZones.indexOf(zone) ~/ 3;

final Map<(String, int), HZoneMap> _maps = {};

/// El mapa de [zoneId] el día [day] (el mismo en todos los aparatos).
HZoneMap hZoneMap(String zoneId, int day) => _maps[(zoneId, day)] ??= () {
  if (_maps.length > 64) _maps.clear();
  final zone = hZoneById[zoneId]!;
  final index = hZones.indexOf(zone);
  final rng = HDayRng(day, 10 + index);
  final cols = hMapColumns(zone);
  final base = zone.minutes / cols;
  final fogChance = .15 + index * .03;
  HNodeKind pick(int col) {
    // Al principio no hay peligros; al final, más tesoros.
    final weights = col == 0
        ? const {HNodeKind.loot: 7, HNodeKind.forage: 3}
        : col == cols - 1
        ? const {HNodeKind.treasure: 4, HNodeKind.danger: 3, HNodeKind.loot: 3}
        : const {
            HNodeKind.loot: 7,
            HNodeKind.forage: 3,
            HNodeKind.danger: 5,
            HNodeKind.rest: 3,
            HNodeKind.treasure: 2,
          };
    var roll = rng.nextInt(weights.values.fold(0, (a, b) => a + b));
    for (final e in weights.entries) {
      if (roll < e.value) return e.key;
      roll -= e.value;
    }
    return HNodeKind.loot;
  }

  final columns = <List<HMapNode>>[];
  for (var c = 0; c < cols; c++) {
    // Casi siempre tres casillas; a veces falta una.
    final gap = rng.nextInt(3) == 0 ? rng.nextInt(hMapRows) : -1;
    columns.add([
      for (var r = 0; r < hMapRows; r++)
        if (r != gap)
          () {
            final kind = pick(c);
            final fog = c > 0 && rng.nextDouble() < fogChance;
            final threat = kind == HNodeKind.danger
                ? (zone.difficulty * (.7 + rng.nextInt(7) * .1)).round()
                : 0;
            return HMapNode(
              c,
              r,
              kind,
              max(1, (base * _nodeTime[kind]!).round()),
              fog: fog,
              threat: threat,
            );
          }(),
    ]);
  }
  // Una casilla de encargo en alguna columna de en medio.
  final c = 1 + rng.nextInt(cols - 2);
  final k = rng.nextInt(columns[c].length);
  final old = columns[c][k];
  columns[c][k] = HMapNode(
    c,
    old.row,
    HNodeKind.order,
    max(1, base.round()),
    fog: old.fog,
  );
  return HZoneMap(zoneId, day, columns);
}();

// --- Servicios de viaje -----------------------------------------------------

/// Guía: enseña todo el mapa del sitio ese día.
int hGuidePrice(HZone zone) => zone.xp * 2;

/// Porteador: más botín en cada casilla.
int hPorterPrice(HZone zone) => zone.xp * 3 ~/ 2;

/// Carro: un 25 % menos de tiempo.
int hCartPrice(HZone zone) => zone.xp;

/// Lo que se elige al salir además del grupo y la comida.
class HTripPlan {
  const HTripPlan({
    required this.zone,
    required this.route,
    required this.food,
    this.supply,
    this.rune,
    this.porter = false,
    this.cart = false,
  });

  final String zone;
  final List<int> route;
  final String food;

  /// Una poción o un mapa (se gasta al salir).
  final String? supply;

  /// Una runa (se gasta al salir).
  final String? rune;
  final bool porter;
  final bool cart;

  /// Ginmon que cuestan el porteador y el carro.
  int get price {
    final z = hZoneById[zone]!;
    return (porter ? hPorterPrice(z) : 0) + (cart ? hCartPrice(z) : 0);
  }

  /// Si la poción o la runa enseñan la niebla.
  bool get reveals => [supply, rune].any((id) {
    final effect = id == null ? null : hItem(id)?.effect;
    return effect == 'sight' || effect == 'reveal';
  });
}
