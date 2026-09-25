// Ibasho — el gacha del Yatai: tickets, rarezas, categorias y el sorteo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Los dos tickets del gacha. Son la moneda «premium»: no se ganan jugando,
/// se compran en el Yatai con un tope semanal.
enum TicketKind {
  /// ガチャ券. El de cada semana, rojo y amarillo de feria.
  gachaken,

  /// 金券. El dorado: mucho mejores bolas, uno por semana.
  kinken;

  /// Id del articulo del catalogo y clave de `/shop/prices`.
  String get itemId => 'ticket_$name';

  static TicketKind? byName(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// Tope de tickets guardados de cada tipo. Las reglas exigen lo mismo.
const int maxTickets = 9999;

/// Lo que se puede comprar de cada ticket en una semana (UTC). Las reglas
/// exigen lo mismo.
const Map<TicketKind, int> weeklyTicketLimit = <TicketKind, int>{
  TicketKind.gachaken: 10,
  TicketKind.kinken: 1,
};

const int _weekMs = 604800000;

/// La semana UTC de [at]: `floor(ms / 604800000)`, como en las reglas. La
/// semana 0 empieza el jueves 1-1-1970, asi que cambian los jueves a las
/// 00:00 UTC.
int gachaWeek([DateTime? at]) => (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ _weekMs;

/// Cuando empieza la semana UTC [week].
DateTime gachaWeekStart(int week) =>
    DateTime.fromMillisecondsSinceEpoch(week * _weekMs, isUtc: true);

/// Las rarezas de una bola, de menos a mas. `mu` (無限) es la oculta: el
/// simbolo de infinito, una entre diez mil.
enum Rarity { n, r, sr, ssr, ur, mu;

  /// La sigla que se ensena en la cinta.
  String get label => switch (this) {
        Rarity.n => 'N',
        Rarity.r => 'R',
        Rarity.sr => 'SR',
        Rarity.ssr => 'SSR',
        Rarity.ur => 'UR',
        Rarity.mu => '∞',
      };

  static Rarity? byName(Object? raw) {
    for (final r in values) {
      if (r.name == raw) return r;
    }
    return null;
  }
}

/// Las categorias de premios, que son los agujeros del pinball de la fase
/// siguiente. Anadir una es anadirla aqui, ponerle texto en los dos `.arb` y
/// darle icono en [categoryArt]: las reglas aceptan cualquier clave de hasta
/// 16 letras, asi que no hay que tocarlas.
enum GachaCategory { hats, accessories, backdrops, music;

  static GachaCategory? byName(Object? raw) {
    for (final c in values) {
      if (c.name == raw) return c;
    }
    return null;
  }
}

/// Bolas jugadas en el pinball tras las que llega la bola dirigida del
/// Catalogo. Las reglas exigen lo mismo.
const int wishPulls = 70;

/// Cuantas bolas da una tirada de [multi] o sencilla, y cuantos tickets
/// cuesta. La de 11 bolas cuesta 10 tickets.
const int singlePullBalls = 1;
const int multiPullBalls = 11;
const int multiPullCost = 10;

/// Tiradas sueltas de golpe: de 1 a [maxLoosePull] bolas, un ticket cada una.
/// La de 10 tickets ya es la ×11 (10 + 1 de regalo).
const int maxLoosePull = 9;

bool isPullSize(int balls) => (balls >= 1 && balls <= maxLoosePull) || balls == multiPullBalls;

int pullCost(int balls) => balls == multiPullBalls ? multiPullCost : balls;

/// Hasta que rareza se puede pedir en el Catalogo. Las reglas exigen lo
/// mismo.
const Rarity maxWishRarity = Rarity.ur;

bool canWish(Rarity rarity) => rarity.index <= maxWishRarity.index;

/// Las tasas, en diezmilesimas (suman 10000).
const Map<TicketKind, Map<Rarity, int>> gachaOdds = <TicketKind, Map<Rarity, int>>{
  TicketKind.gachaken: <Rarity, int>{
    Rarity.n: 5999,
    Rarity.r: 2700,
    Rarity.sr: 1000,
    Rarity.ssr: 270,
    Rarity.ur: 30,
    Rarity.mu: 1,
  },
  TicketKind.kinken: <Rarity, int>{
    Rarity.n: 0,
    Rarity.r: 3500,
    Rarity.sr: 4200,
    Rarity.ssr: 1800,
    Rarity.ur: 480,
    Rarity.mu: 20,
  },
};

/// La garantia de la tirada de 11: si no ha salido nada de esta rareza o
/// mejor, la bola numero [guaranteedBall] sube hasta aqui.
Rarity guaranteedRarity(TicketKind kind) =>
    kind == TicketKind.kinken ? Rarity.ur : Rarity.ssr;

/// En que bola de la tirada de 11 entra la garantia (1 es la primera). En el
/// dorado entra en la decima, para que la ultima siga siendo una tirada
/// libre.
int guaranteedBall(TicketKind kind) => kind == TicketKind.kinken ? 10 : 11;

/// Una bola sorteada. Si [category] no es nula, es la bola dirigida del
/// Catalogo: en el pinball dara un premio de esa categoria (uno que no se
/// tenga, si queda alguno) caiga donde caiga.
@immutable
class GachaBall {
  const GachaBall(this.rarity, {this.category});

  final Rarity rarity;
  final GachaCategory? category;

  bool get isWish => category != null;
}

/// Como ha ido una tirada.
@immutable
class PullResult {
  const PullResult({required this.kind, required this.balls});

  final TicketKind kind;
  final List<GachaBall> balls;

  Rarity get best => balls.map((b) => b.rarity).reduce((a, b) => a.index >= b.index ? a : b);
}

/// El sorteo, que hoy vive en la app: las reglas no pueden sortear, solo
/// comprobar que los tickets bajan lo que toca y que salen tantas bolas como
/// tiradas. Si algun dia hay servidor, esto se muda tal cual.
List<GachaBall> rollPull({
  required TicketKind kind,
  required int balls,
  required math.Random random,
}) {
  final odds = gachaOdds[kind]!;
  final out = <GachaBall>[
    for (var i = 0; i < balls; i++) GachaBall(_rollOne(odds, random)),
  ];

  // Garantia de la tanda: si nada llega a la rareza prometida, sube la bola
  // que toca.
  if (balls == multiPullBalls) {
    final promised = guaranteedRarity(kind);
    if (!out.any((b) => b.rarity.index >= promised.index)) {
      out[guaranteedBall(kind) - 1] = GachaBall(promised);
    }
  }
  return out;
}

Rarity _rollOne(Map<Rarity, int> odds, math.Random random) {
  var roll = random.nextInt(10000);
  for (final rarity in Rarity.values) {
    roll -= odds[rarity] ?? 0;
    if (roll < 0) return rarity;
  }
  return Rarity.n;
}

/// El deseo puesto en el Catalogo del pinball.
@immutable
class GachaWish {
  const GachaWish({required this.category, required this.rarity, this.count = 0});

  final GachaCategory category;
  final Rarity rarity;

  /// Bolas jugadas en el pinball desde la ultima bola dirigida. Solo avanza
  /// si hay deseo puesto.
  final int count;

  int get left => math.max(0, wishPulls - count);

  static GachaWish? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final category = GachaCategory.byName(raw['category']);
    final rarity = Rarity.byName(raw['rarity']);
    final count = raw['count'];
    if (category == null || rarity == null) return null;
    return GachaWish(
      category: category,
      rarity: rarity,
      count: count is num ? count.toInt() : 0,
    );
  }

  Map<String, Object?> toJson() =>
      {'category': category.name, 'rarity': rarity.name, 'count': count};

  GachaWish copyWith({GachaCategory? category, Rarity? rarity, int? count}) => GachaWish(
        category: category ?? this.category,
        rarity: rarity ?? this.rarity,
        count: count ?? this.count,
      );
}
