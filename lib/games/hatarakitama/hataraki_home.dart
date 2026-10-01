// Ibasho — Hatarakitama: las casas de los Tamas y sus muebles.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import '../../backend/tama.dart' show TamaPersonality;
import 'hataraki_town.dart' show HBuildCost, HDayRng;

/// El estilo de un mueble, de un suelo o de una pared.
enum HStyle {
  rustic,
  marine,
  elegant,
  magic,
  floral;

  static HStyle? byName(Object? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return null;
  }
}

/// El estilo que más le gusta a cada personalidad.
const Map<TamaPersonality, HStyle> hFavouriteStyle = {
  TamaPersonality.calm: HStyle.floral,
  TamaPersonality.playful: HStyle.marine,
  TamaPersonality.shy: HStyle.elegant,
  TamaPersonality.cheeky: HStyle.rustic,
  TamaPersonality.sleepy: HStyle.magic,
};

/// Un mueble: su estilo, lo que ocupa en la rejilla (sin girar), lo cómodo
/// que es (1–4) y si hace falta un plano para fabricarlo. Los que no se
/// fabrican se compran en la tienda y valen [value].
class HFurniture {
  const HFurniture(
    this.id,
    this.style, {
    this.w = 1,
    this.h = 1,
    this.comfort = 1,
    this.plan = true,
    this.value = 0,
  });

  final String id;
  final HStyle style;
  final int w;
  final int h;
  final int comfort;
  final bool plan;
  final int value;

  /// Ancho y fondo con el giro [r] (0–3): los giros impares los cruzan.
  (int, int) size(int r) => r.isOdd ? (h, w) : (w, h);
}

/// Todos los muebles. Los que se fabrican tienen su tarea en `hActions`.
const List<HFurniture> hFurnitureList = [
  // Rústico.
  HFurniture('fu_stool', HStyle.rustic, plan: false),
  HFurniture('fu_zabuton', HStyle.rustic, plan: false),
  HFurniture('fu_sign', HStyle.rustic, plan: false),
  HFurniture('fu_chabudai', HStyle.rustic, w: 2, comfort: 2),
  HFurniture('fu_bonsai', HStyle.rustic, comfort: 2),
  HFurniture('fu_futon', HStyle.rustic, h: 2, comfort: 3),
  HFurniture('fu_andon', HStyle.rustic, comfort: 2, plan: false, value: 160),
  // Marino.
  HFurniture('fu_boat', HStyle.marine, comfort: 2),
  HFurniture('fu_aquarium', HStyle.marine, comfort: 2),
  HFurniture('fu_rug_wave', HStyle.marine, w: 2, h: 2, comfort: 2),
  HFurniture('fu_hammock', HStyle.marine, w: 2, comfort: 3),
  HFurniture('fu_seachart', HStyle.marine, comfort: 3),
  HFurniture(
    'fu_shell_lamp',
    HStyle.marine,
    comfort: 2,
    plan: false,
    value: 160,
  ),
  // Elegante.
  HFurniture('fu_scroll', HStyle.elegant, comfort: 2),
  HFurniture('fu_rug_red', HStyle.elegant, w: 2, h: 2, comfort: 3),
  HFurniture('fu_tansu', HStyle.elegant, w: 2, comfort: 3),
  HFurniture('fu_celadon', HStyle.elegant, comfort: 4),
  HFurniture('fu_silk_futon', HStyle.elegant, h: 2, comfort: 4),
  HFurniture('fu_maneki', HStyle.elegant, comfort: 2, plan: false, value: 160),
  // Mágico.
  HFurniture('fu_lantern', HStyle.magic, comfort: 2, plan: false),
  HFurniture('fu_crystal', HStyle.magic, comfort: 3),
  HFurniture('fu_bookcase', HStyle.magic, w: 2, comfort: 3),
  HFurniture('fu_orrery', HStyle.magic, w: 2, h: 2, comfort: 4),
  HFurniture('fu_candles', HStyle.magic, comfort: 2, plan: false, value: 160),
  // Floral.
  HFurniture('fu_flowerbowl', HStyle.floral, plan: false),
  HFurniture('fu_noren', HStyle.floral, w: 2, comfort: 2),
  HFurniture('fu_blossom_lamp', HStyle.floral, comfort: 3),
  HFurniture('fu_ikebana', HStyle.floral, comfort: 3),
  HFurniture(
    'fu_flowerstand',
    HStyle.floral,
    comfort: 2,
    plan: false,
    value: 160,
  ),
];

final Map<String, HFurniture> hFurniture = {
  for (final f in hFurnitureList) f.id: f,
};

/// Los muebles que se fabrican con plano, por orden de la lista.
final List<String> hPlanIds = [
  for (final f in hFurnitureList)
    if (f.plan) f.id,
];

/// Los que solo se compran en la tienda.
final List<String> hShopFurniture = [
  for (final f in hFurnitureList)
    if (!f.plan && f.value > 0) f.id,
];

// --- La habitación --------------------------------------------------------------

/// Lado de la rejilla de una habitación.
const int hRoomSize = 6;

/// Un mueble colocado: dónde (esquina de arriba a la izquierda) y cómo está
/// girado (0–3).
class HPlaced {
  HPlaced(this.id, this.x, this.y, [this.r = 0]);
  final String id;
  int x;
  int y;
  int r;

  (int, int) get size => hFurniture[id]!.size(r);

  bool covers(int cx, int cy) {
    final (w, h) = size;
    return cx >= x && cx < x + w && cy >= y && cy < y + h;
  }

  Map<String, Object> toJson() => {'id': id, 'x': x, 'y': y, 'r': r};

  static HPlaced? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || !hFurniture.containsKey(id)) return null;
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return HPlaced(id, n(raw['x']), n(raw['y']), n(raw['r']) & 3);
  }
}

/// La casa de un Tama: una habitación de 6×6 con su suelo, su pared y sus
/// muebles.
class HHouse {
  HHouse({
    this.floor = HStyle.rustic,
    this.wall = HStyle.rustic,
    List<HPlaced>? items,
  }) : items = items ?? [];

  HStyle floor;
  HStyle wall;
  final List<HPlaced> items;

  /// El mueble que ocupa la casilla ([x], [y]), si hay alguno.
  int? at(int x, int y) {
    for (var i = 0; i < items.length; i++) {
      if (items[i].covers(x, y)) return i;
    }
    return null;
  }

  /// Si [id] cabe con la esquina en ([x], [y]) y el giro [r], sin pisar a
  /// otro que no sea el [skip].
  bool fits(String id, int x, int y, int r, {int? skip}) {
    final def = hFurniture[id];
    if (def == null) return false;
    final (w, h) = def.size(r);
    if (x < 0 || y < 0 || x + w > hRoomSize || y + h > hRoomSize) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (i == skip) continue;
      for (var cx = x; cx < x + w; cx++) {
        for (var cy = y; cy < y + h; cy++) {
          if (items[i].covers(cx, cy)) return false;
        }
      }
    }
    return true;
  }

  Map<String, Object> toJson() => {
    'floor': floor.name,
    'wall': wall.name,
    if (items.isNotEmpty)
      'items': {for (var i = 0; i < items.length; i++) '$i': items[i].toJson()},
  };

  /// Lee una casa guardada. Los muebles que no caben (se pisan o se salen)
  /// se quedan fuera: los devuelve en [dropped] para volver al almacén.
  static HHouse fromJson(Object? raw, {List<String>? dropped}) {
    final m = raw is Map ? raw : const {};
    final house = HHouse(
      floor: HStyle.byName(m['floor']) ?? HStyle.rustic,
      wall: HStyle.byName(m['wall']) ?? HStyle.rustic,
    );
    final rawItems = m['items'];
    final list = rawItems is List
        ? rawItems
        : rawItems is Map
        ? [
            for (final k
                in (rawItems.keys.map((k) => '$k').toList()..sort(
                  (a, b) =>
                      (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
                )))
              rawItems[k],
          ]
        : const [];
    for (final e in list) {
      final p = HPlaced.fromJson(e);
      if (p == null) continue;
      if (house.fits(p.id, p.x, p.y, p.r)) {
        house.items.add(p);
      } else {
        dropped?.add(p.id);
      }
    }
    return house;
  }
}

// --- Comodidad ------------------------------------------------------------------

/// Puntos de comodidad con los que la parte de «cuántos muebles» está llena.
const int hComfortFull = 24;

/// Lo que cuenta cada parte de la comodidad: muebles, que combinen y que
/// el estilo le guste.
const double hComfortPieces = .5;
const double hComfortMatch = .25;
const double hComfortLiked = .25;

/// Muebles a partir de los que empieza a contar que combinen.
const int hMatchFrom = 3;

/// La comodidad de una casa, por partes (cada una de 0 a 1).
class HComfort {
  const HComfort(this.pieces, this.match, this.liked, this.points);

  /// Lo lleno que está (los puntos de los muebles, hasta [hComfortFull]).
  final double pieces;

  /// Lo que combinan: la parte del estilo que más se repite.
  final double match;

  /// Lo que hay del estilo que le gusta al Tama.
  final double liked;

  /// Los puntos de los muebles, sin tope.
  final int points;

  /// De 0 a 1.
  double get value =>
      pieces * hComfortPieces + match * hComfortMatch + liked * hComfortLiked;

  /// De 0 a 100, para enseñarla.
  int get percent => (value * 100).round();
}

/// La comodidad de [house] para un Tama de personalidad [personality]. El
/// suelo y la pared cuentan como un mueble más al mirar los estilos, pero
/// no dan puntos.
HComfort hComfort(HHouse house, TamaPersonality personality) {
  final styles = [
    house.floor,
    house.wall,
    for (final p in house.items) hFurniture[p.id]!.style,
  ];
  final points = house.items.fold(0, (s, p) => s + hFurniture[p.id]!.comfort);
  final byStyle = <HStyle, int>{};
  for (final s in styles) {
    byStyle[s] = (byStyle[s] ?? 0) + 1;
  }
  final top = byStyle.values.fold(0, max);
  // Con un tercio del mismo estilo aún no combina; con todo igual, del todo.
  final match = house.items.length < hMatchFrom
      ? 0.0
      : ((top / styles.length - 1 / 3) * 1.5).clamp(0.0, 1.0);
  final fav = hFavouriteStyle[personality];
  final liked = house.items.isEmpty ? 0.0 : (byStyle[fav] ?? 0) / styles.length;
  return HComfort(
    min(points, hComfortFull) / hComfortFull,
    match,
    liked,
    points,
  );
}

/// El ánimo más bajo con el que trabaja un Tama con casa: descansar en ella
/// ya da algo, y cuanto más cómoda, más. Solo vale dentro de Hatarakitama.
double hRestMood(double comfort) => .25 + .55 * comfort;

// --- Construir casas -----------------------------------------------------------

/// Lo que cuesta la casa número [n] (0 = la primera, que es barata).
HBuildCost hHouseCost(int n) => switch (n) {
  0 => const HBuildCost(300, {'build_beam': 2}, 0),
  1 => const HBuildCost(2000, {'build_beam': 6}, 10),
  2 => const HBuildCost(8000, {'build_beam': 6, 'build_frame': 3}, 20),
  3 => const HBuildCost(25000, {'build_frame': 6, 'build_wall': 4}, 30),
  _ => HBuildCost(60000 * (n - 3), const {
    'build_wall': 6,
    'build_roof': 4,
  }, 40),
};

// --- Planos en la tienda ----------------------------------------------------------

/// Nivel de tienda con el que salen dos planos al día en vez de uno.
const int hShopTwoPlans = 3;

/// Los planos a la venta el día [day] con la tienda a nivel [level]: los
/// mismos para todos.
List<String> hShopPlans(int day, int level) {
  if (level <= 0) return const [];
  final pool = [...hPlanIds];
  HDayRng(day, 3).shuffle(pool);
  return pool.take(level >= hShopTwoPlans ? 2 : 1).toList();
}

/// Lo que cuesta el plano de [id], con [sellValue] como lo que vale el
/// mueble: ocho veces, redondeado a decenas y al menos 300.
int hPlanPrice(String id, int Function(String) sellValue) =>
    max(300, (sellValue(id) * 8 / 10).round() * 10);
