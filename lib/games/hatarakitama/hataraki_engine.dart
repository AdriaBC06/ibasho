// Ibasho — Hatarakitama: el motor idle, sin interfaz.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import '../../backend/tama.dart' show TamaPersonality;
import 'hataraki_data.dart';
import 'hataraki_home.dart';
import 'hataraki_map.dart';
import 'hataraki_orders.dart';
import 'hataraki_town.dart';

/// Nivel máximo de cada oficio y de cada maestría.
const int hMaxLevel = 99;

/// Lo más que se trabaja sin la app abierta.
const Duration hOfflineCap = Duration(hours: 12);

/// Lo que dura un té.
const Duration hTeaDuration = Duration(minutes: 30);

/// Nivel total que abre cada ranura de trabajo (la primera viene de serie).
const List<int> hSlotThresholds = [0, 40, 100, 200, 350, 550, 800, 1100];

/// Con una tetera en el almacén, el té dura esto más.
const double hTeapotBonus = .5;

/// Experiencia de más por cada nivel de estudio (en todo).
const double hStudyBonus = .001;

/// Tamas por expedición.
const int hMaxParty = 3;

/// Experiencia acumulada para llegar a cada nivel: se empieza en el 0, el 1
/// llega con la primera tanda de trabajo y del 2 al 99 es la curva de
/// RuneScape (el 92 es la mitad del 99). `_xpTable[n]` = experiencia del
/// nivel n.
final List<int> _xpTable = () {
  final table = <int>[0, hXpLevelOne];
  var points = 0.0;
  for (var level = 1; level < hMaxLevel; level++) {
    points += (level + 300 * pow(2, level / 7)).floorToDouble();
    table.add((points / 4).floor());
  }
  return table;
}();

/// Experiencia del nivel 1, a medio camino del 2 (83).
const int hXpLevelOne = 40;

/// Experiencia total que pide `level` (0–99).
int hXpForLevel(int level) => _xpTable[level.clamp(0, hMaxLevel)];

/// Nivel que da tanta experiencia (0–99).
int hLevelForXp(int xp) {
  var lo = 0, hi = _xpTable.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (_xpTable[mid] <= xp) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// Ranuras de trabajo con este nivel total.
int hSlotsFor(int totalLevel) =>
    hSlotThresholds.where((t) => totalLevel >= t).length;

/// Lo que el juego necesita saber de un Tama para ponerlo a trabajar.
class HTama {
  const HTama(this.id, this.personality, this.mood);
  final String id;
  final TamaPersonality personality;

  /// Ánimo de 0 a 1 (`TamaMoodReading.value`).
  final double mood;

  bool likes(HSkill skill) =>
      hAffinities[personality]?.contains(skill) ?? false;
}

/// Una ranura de trabajo: qué Tama hace qué y cuánto lleva.
class HWorker {
  HWorker(
    this.tamaId,
    this.actionId, {
    this.progress = 0,
    this.stalled = false,
    this.boost,
  });

  String tamaId;
  String actionId;

  /// Cebo, abono o mecha que gasta (uno por vez, si queda).
  String? boost;

  /// De 0 a 1: lo que lleva de la acción en curso.
  double progress;

  /// Se ha parado porque faltan materiales.
  bool stalled;

  Map<String, Object> toJson() => {
    'tama': tamaId,
    'action': actionId,
    'progress': progress,
    if (stalled) 'stalled': true,
    'boost': ?boost,
  };

  static HWorker? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tama = raw['tama'], action = raw['action'];
    if (tama is! String || action is! String) return null;
    if (hAction(action) == null) return null;
    final boost = raw['boost'];
    return HWorker(
      tama,
      action,
      progress: ((raw['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      stalled: raw['stalled'] == true,
      boost: boost is String && hItem(boost)?.kind == HItemKind.boost
          ? boost
          : null,
    );
  }
}

/// Una expedición en curso. Todo lo que depende de la ruta (cuándo se llega
/// a cada casilla y qué peligros no se pasan) se fija al salir; el botín se
/// echa a suertes al llegar a cada casilla.
class HExpedition {
  HExpedition(
    this.zone,
    this.tamaIds,
    this.startedAt,
    this.endsAt,
    this.power, {
    this.day = 0,
    this.route = const [],
    this.at = const [],
    this.fails = const {},
    this.done = 0,
    this.porter = false,
    this.luck = 1,
    List<Map<String, int>>? log,
  }) : log = log ?? [];

  final String zone;
  final List<String> tamaIds;
  final int startedAt;
  final int endsAt;
  final int power;

  /// Día del mapa y fila elegida en cada columna. Sin ruta, es un viaje de
  /// antes del mapa (0.7.0): todo se resuelve al volver.
  final int day;
  final List<int> route;

  /// Cuándo se termina cada casilla (ms desde epoch).
  final List<int> at;

  /// Casillas de peligro que no se pasan.
  final Set<int> fails;
  final bool porter;

  /// Por cuánto se multiplica la probabilidad de tesoro.
  final double luck;

  /// Casillas ya resueltas y lo que ha salido en cada una (objeto → n, y
  /// `prize` si trajo tesoro).
  int done;
  final List<Map<String, int>> log;

  HZoneMap get map => hZoneMap(zone, day);

  /// Cuándo pasa lo siguiente: la casilla que toca o, sin ruta, la vuelta.
  int get nextAt => route.isEmpty ? endsAt : at[done];

  Map<String, Object> toJson() => {
    'zone': zone,
    'tamas': tamaIds,
    'start': startedAt,
    'end': endsAt,
    'power': power,
    if (route.isNotEmpty) ...{
      'day': day,
      'route': route,
      'at': at,
      if (fails.isNotEmpty) 'fails': fails.toList()..sort(),
      'done': done,
      if (porter) 'porter': true,
      if (luck != 1) 'luck': luck,
      if (log.isNotEmpty)
        'log': {
          for (var i = 0; i < log.length; i++)
            if (log[i].isNotEmpty) '$i': log[i],
        },
    },
  };

  static HExpedition? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final zone = raw['zone'];
    if (zone is! String || hZoneById[zone] == null) return null;
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final day = n(raw['day']);
    var route = [for (final r in _list(raw['route'])) n(r)];
    var at = [for (final t in _list(raw['at'])) n(t)];
    // Una ruta que no encaja con el mapa se trata como un viaje de antes.
    if (route.isNotEmpty &&
        (at.length != route.length || !hZoneMap(zone, day).isValid(route))) {
      route = const [];
      at = const [];
    }
    final rawLog = _list(raw['log']);
    final done = route.isEmpty ? 0 : n(raw['done']).clamp(0, route.length);
    return HExpedition(
      zone,
      _list(raw['tamas']).whereType<String>().toList(),
      n(raw['start']),
      n(raw['end']),
      n(raw['power']),
      day: day,
      route: route,
      at: at,
      fails: {for (final f in _list(raw['fails'])) n(f)},
      done: done,
      porter: raw['porter'] == true,
      luck: (raw['luck'] as num?)?.toDouble() ?? 1,
      log: [
        for (var i = 0; i < done; i++)
          if (raw['log'] is Map)
            _counts((raw['log'] as Map)['$i'])
          else
            i < rawLog.length ? _counts(rawLog[i]) : <String, int>{},
      ],
    );
  }
}

Map<String, int> _counts(Object? v) => {
  if (v is Map)
    for (final e in v.entries)
      if (e.value is num && (e.value as num) > 0)
        '${e.key}': (e.value as num).toInt(),
};

/// Una casilla del mapa que se acaba de pasar, para los avisos en vivo.
class HNodeEvent {
  const HNodeEvent(this.zone, this.kind, this.items, {this.failed = false});
  final String zone;
  final HNodeKind kind;
  final Map<String, int> items;
  final bool failed;
}

/// Lo que ha pasado en un tramo de tiempo: para el resumen de «mientras no
/// estabas» y para los avisos en vivo.
class HReport {
  final Map<String, int> gained = {};
  final Map<String, int> spent = {};
  final Map<HSkill, int> xp = {};

  /// Oficio → nivel nuevo, solo si ha subido.
  final Map<HSkill, int> levelUps = {};
  final Set<String> stalledTamas = {};

  /// Expedición que ha vuelto en este tramo (con su éxito, 0–1).
  String? expeditionZone;
  double expeditionSuccess = 0;
  int prizes = 0;

  /// Casillas del mapa pasadas en este tramo.
  final List<HNodeEvent> nodes = [];

  /// Segundos simulados (con el tope aplicado).
  double seconds = 0;

  bool get isEmpty => gained.isEmpty && xp.isEmpty && expeditionZone == null;

  void _add(Map<String, int> into, String item, int n) =>
      into[item] = (into[item] ?? 0) + n;
}

/// La partida entera. Se guarda en `/users/{cuenta}/hataraki`.
class HState {
  HState({
    Map<HSkill, int>? xp,
    Map<String, int>? mastery,
    Map<String, int>? bank,
    List<HWorker>? workers,
    Map<HGearSlot, String>? kit,
    Map<HBuilding, int>? town,
    Map<String, int>? shopBought,
    this.shopDay = 0,
    this.tea,
    this.teaUntil = 0,
    List<HExpedition>? expeditions,
    Map<String, int>? guides,
    this.ordersDay = 0,
    List<HOrder>? orders,
    Map<String, HHouse>? houses,
    Set<String>? plans,
    this.swapDay = 0,
    this.orderTicket = false,
    this.orderDay = 0,
    required this.lastTick,
    this.seed = 1,
    this.prizes = 0,
    this.claimAt = 0,
    this.day = 0,
    this.dayXp = 0,
    this.week = 0,
    this.weekXp = 0,
    this.money = 0,
    this.earned = 0,
    this.dayMoney = 0,
    this.weekMoney = 0,
  }) : xp = xp ?? {},
       mastery = mastery ?? {},
       bank = bank ?? {},
       workers = workers ?? [],
       kit = kit ?? {},
       town = town ?? {},
       shopBought = shopBought ?? {},
       expeditions = expeditions ?? [],
       guides = guides ?? {},
       orders = orders ?? [],
       houses = houses ?? {},
       plans = plans ?? {};

  final Map<HSkill, int> xp;
  final Map<String, int> mastery;
  final Map<String, int> bank;
  final List<HWorker> workers;

  /// Equipo que se lleva a las expediciones (tiene que estar en el almacén).
  final Map<HGearSlot, String> kit;

  /// Nivel de cada edificio del pueblo (los que no están, sin hacer).
  final Map<HBuilding, int> town;

  /// Lo comprado en la tienda el día [shopDay] (la tienda cambia cada día).
  int shopDay;
  final Map<String, int> shopBought;
  String? tea;
  int teaUntil;

  /// Los viajes en marcha (dos a la vez con la posada a nivel 5).
  final List<HExpedition> expeditions;

  /// Sitio → día en que se pagó un guía (enseña el mapa entero ese día).
  final Map<String, int> guides;

  /// Los encargos del tablón del día [ordersDay]: el 0 es el gran encargo.
  int ordersDay;
  final List<HOrder> orders;

  /// La casa de cada Tama que tiene una (por su id).
  final Map<String, HHouse> houses;

  /// Los planos de muebles que ya se saben.
  final Set<String> plans;

  /// Día en que se cambió un encargo (uno al día).
  int swapDay;

  /// Gran encargo hecho y su ticket sin cobrar todavía.
  bool orderTicket;

  /// Día en que se cobró el ticket del gran encargo (lo vigilan las reglas:
  /// uno al día).
  int orderDay;

  /// Hasta dónde está simulada la partida (ms desde epoch).
  int lastTick;
  int seed;

  /// Premios del gacha traídos de expedición y aún sin entregar.
  int prizes;

  /// Cuándo se canjeó el último tesoro por un ticket (hora del servidor).
  int claimAt;

  /// Experiencia ganada en el día y la semana en curso (los números los pone
  /// quien llama): es lo que cuenta en la clasificación.
  int day;
  int dayXp;
  int week;
  int weekXp;

  /// Mon (la moneda del pueblo) que hay ahora y los ganados vendiendo desde
  /// siempre, en el día y en la semana: la clasificación va por riqueza.
  int money;
  int earned;
  int dayMoney;
  int weekMoney;

  /// Pasa al día [today] y a la semana [thisWeek], empezando de cero lo que
  /// cuenta en cada uno si han cambiado.
  void _roll(int today, int thisWeek) {
    if (day != today) {
      day = today;
      dayXp = 0;
      dayMoney = 0;
    }
    if (week != thisWeek) {
      week = thisWeek;
      weekXp = 0;
      weekMoney = 0;
    }
  }

  /// Suma [amount] de experiencia al día [today] y a la semana [thisWeek].
  void countXp(int amount, {required int today, required int thisWeek}) {
    _roll(today, thisWeek);
    dayXp += amount;
    weekXp += amount;
  }

  /// Vende [n] de [item] del almacén (lo que haya, si hay menos) y apunta
  /// los mon al día [today] y a la semana [thisWeek]. Devuelve lo ganado.
  int sell(String item, int n, {required int today, required int thisWeek}) {
    final units = min(n, count(item));
    final price = priceOf(item, today);
    if (units <= 0 || price <= 0) return 0;
    _take(item, units);
    final got = units * price;
    _earn(got, today, thisWeek);
    return got;
  }

  /// Ginmon ganados (vendiendo o con encargos): cuentan para la riqueza.
  void _earn(int got, int today, int thisWeek) {
    _roll(today, thisWeek);
    money += got;
    earned += got;
    dayMoney += got;
    weekMoney += got;
  }

  // ------------------------------------------------------------------
  // El tablón de encargos.

  /// Pone el tablón al día [today]: encargos nuevos si ha cambiado el día y
  /// los que falten si el tablón ha subido de nivel. Devuelve si ha cambiado.
  bool refreshOrders(int today) {
    var changed = false;
    if (ordersDay != today) {
      ordersDay = today;
      orders.clear();
      changed = true;
    }
    final want = 1 + hBoardSlots(townLevel(HBuilding.board));
    while (orders.length < want) {
      orders.add(_makeOrder(today, orders.length));
      changed = true;
    }
    return changed;
  }

  HOrder _makeOrder(int today, int slot, {int variant = 0}) => hMakeOrder(
    day: today,
    seed: seed,
    slot: slot,
    canDo: canDo,
    practised: (s) => (xp[s] ?? 0) > 0,
    sellValue: hSellValue,
    expeditionLevel: levelOf(HSkill.expedition),
    board: townLevel(HBuilding.board),
    avoid: {
      for (var i = 0; i < orders.length; i++)
        if (i != slot && i > 0)
          for (final item in orders[i].wants.keys) hItemSkill(item),
    },
    // Planos que aún no se saben ni paga otro encargo del tablón.
    plans: [
      for (final id in hPlanIds)
        if (!plans.contains(id) &&
            !orders.indexed.any((e) => e.$1 != slot && e.$2.plan == id))
          id,
    ],
    variant: variant,
  );

  /// Si se puede entregar el encargo [i] ya.
  bool canDeliver(int i) =>
      i >= 0 && i < orders.length && !orders[i].done && _has(orders[i].wants);

  /// Entrega el encargo [i]: gasta lo que pide y cobra. Lo ganado cuenta
  /// para la riqueza como si se hubiera vendido.
  bool deliver(int i, {required int today, required int thisWeek}) {
    if (!canDeliver(i)) return false;
    final o = orders[i];
    for (final e in o.wants.entries) {
      _take(e.key, e.value);
    }
    _earn(o.money, today, thisWeek);
    if (o.skill != null && o.xp > 0) {
      final report = HReport();
      _gainXp(o.skill!, o.xp, report);
      countXp(
        report.xp.values.fold(0, (a, b) => a + b),
        today: today,
        thisWeek: thisWeek,
      );
    }
    if (o.gift != null) _give(o.gift!, o.giftN);
    if (o.plan != null) plans.add(o.plan!);
    if (o.big) orderTicket = true;
    o.done = true;
    return true;
  }

  /// Si hoy aún se puede cambiar el encargo [i] (el grande no se cambia).
  bool canSwap(int i, int today) =>
      swapDay != today &&
      i > 0 &&
      i < orders.length &&
      !orders[i].done &&
      money >= orders[i].swapPrice;

  /// Cambia el encargo [i] por otro, pagando: uno al día.
  bool swapOrder(int i, int today) {
    if (ordersDay != today || !canSwap(i, today)) return false;
    money -= orders[i].swapPrice;
    swapDay = today;
    orders[i] = _makeOrder(today, i, variant: 1);
    return true;
  }

  /// Lo que se paga hoy por [item], con la lonja.
  int priceOf(String item, int today) {
    final base = hSellValue(item);
    if (base <= 0) return 0;
    return hMarketPrice(base, hMarketFactor(item, market(today)));
  }

  /// Lo que se mueve el día [day]: vale para todos, haya lonja o no.
  List<HMarketMove> market(int day) => hMarket(day);

  /// Lo que la lonja enseña del día [day] con el nivel que tiene.
  List<HMarketMove> marketSeen(int day) =>
      hMarketSeen(hMarket(day), townLevel(HBuilding.market));

  /// El tablón viene hecho; lo demás empieza sin hacer.
  int townLevel(HBuilding b) => town[b] ?? (b == HBuilding.board ? 1 : 0);

  /// Lo que falta para subir [b] un nivel (null si ya está al máximo).
  HBuildCost? nextBuildCost(HBuilding b) {
    final level = townLevel(b);
    return level >= hTownMaxLevel ? null : hBuildCost(b, level + 1);
  }

  /// Si hay de todo para subir [b] un nivel.
  bool canBuild(HBuilding b) {
    final cost = nextBuildCost(b);
    return cost != null &&
        money >= cost.money &&
        levelOf(HSkill.construction) >= cost.construction &&
        _has(cost.items);
  }

  /// Sube [b] un nivel: gasta ginmon y piezas. Gastar no quita riqueza de
  /// la clasificación, que cuenta lo ganado.
  bool build(HBuilding b) {
    if (!canBuild(b)) return false;
    final cost = nextBuildCost(b)!;
    money -= cost.money;
    for (final e in cost.items.entries) {
      _take(e.key, e.value);
    }
    town[b] = townLevel(b) + 1;
    return true;
  }

  /// La tienda de hoy: lo del día y, detrás, los planos de muebles.
  List<HOffer> shop(int today) => [
    ...hShop(today, townLevel(HBuilding.shop), hSellValue),
    for (final id in hShopPlans(today, townLevel(HBuilding.shop)))
      HOffer(id, hPlanPrice(id, hSellValue), 1, plan: true),
  ];

  /// Cuántas quedan hoy de [offer]. Un plano que ya se sabe no se vende.
  int stockLeft(HOffer offer, int today) => offer.plan
      ? (plans.contains(offer.item) ? 0 : 1)
      : offer.stock - (shopDay == today ? shopBought[offer.item] ?? 0 : 0);

  /// Compra [n] de [item] en la tienda de hoy (las que queden y se puedan
  /// pagar, como mucho). Devuelve cuántas.
  int buy(String item, int n, int today) {
    final offer = shop(today).where((o) => o.item == item).firstOrNull;
    if (offer == null) return 0;
    if (offer.plan) {
      if (plans.contains(item) || money < offer.price) return 0;
      money -= offer.price;
      plans.add(item);
      return 1;
    }
    if (shopDay != today) {
      shopDay = today;
      shopBought.clear();
    }
    final units = min(min(n, stockLeft(offer, today)), money ~/ offer.price);
    if (units <= 0) return 0;
    money -= units * offer.price;
    shopBought[item] = (shopBought[item] ?? 0) + units;
    _give(item, units);
    return units;
  }

  /// El edificio (y nivel) que pide [action], si lo pide y aún no lo hay.
  (HBuilding, int)? missingGate(HAction action) {
    final gate = hActionGates[action.id];
    if (gate == null || townLevel(gate.$1) >= gate.$2) return null;
    return gate;
  }

  /// El mueble de [action] si pide un plano que aún no se sabe.
  String? missingPlan(HAction action) {
    final out = action.outputs.keys.firstOrNull;
    final def = out == null ? null : hFurniture[out];
    return def != null && def.plan && !plans.contains(out) ? out : null;
  }

  /// Si [action] ya se puede hacer: nivel del oficio, edificio y plano.
  bool canDo(HAction action) =>
      levelOf(action.skill) >= action.level &&
      missingGate(action) == null &&
      missingPlan(action) == null;

  /// Cuántos Tamas caben en un viaje (cuatro con la posada a nivel 3).
  int get maxParty =>
      townLevel(HBuilding.inn) >= hInnFourth ? hMaxParty + 1 : hMaxParty;

  /// Viajes a la vez (dos con la posada a nivel 5).
  int get maxTrips => townLevel(HBuilding.inn) >= hTownMaxLevel ? 2 : 1;

  /// Comida (puntos) que pide un viaje de [minutes] minutos comiendo, con lo
  /// que ahorra la posada.
  int foodFor(int minutes, int party) =>
      (foodNeeded(minutes, party) * (1 - townLevel(HBuilding.inn) * hInnFood))
          .ceil();

  /// Si hoy se ve todo el mapa de [zone] (por un guía pagado).
  bool guided(String zone, int today) => guides[zone] == today;

  /// Paga un guía para [zone] hoy.
  bool hireGuide(String zone, int today) {
    final z = hZoneById[zone];
    if (z == null || guided(zone, today) || money < hGuidePrice(z)) {
      return false;
    }
    money -= hGuidePrice(z);
    guides
      ..removeWhere((_, day) => day != today)
      ..[zone] = today;
    return true;
  }

  // ------------------------------------------------------------------
  // Las casas.

  /// Lo que cuesta la siguiente casa (la primera es barata).
  HBuildCost get houseCost => hHouseCost(houses.length);

  /// Si hay de todo para hacerle casa a [tamaId] (que aún no tiene).
  bool canBuildHouse(String tamaId) {
    final cost = houseCost;
    return !houses.containsKey(tamaId) &&
        money >= cost.money &&
        levelOf(HSkill.construction) >= cost.construction &&
        _has(cost.items);
  }

  /// Le hace casa a [tamaId]: gasta ginmon y piezas.
  bool buildHouse(String tamaId) {
    if (!canBuildHouse(tamaId)) return false;
    final cost = houseCost;
    money -= cost.money;
    for (final e in cost.items.entries) {
      _take(e.key, e.value);
    }
    houses[tamaId] = HHouse();
    return true;
  }

  /// Saca [item] del almacén y lo pone en la casa de [tamaId], con la
  /// esquina en ([x], [y]) y el giro [r].
  bool placeFurniture(String tamaId, String item, int x, int y, [int r = 0]) {
    final house = houses[tamaId];
    if (house == null || count(item) <= 0 || !house.fits(item, x, y, r)) {
      return false;
    }
    _take(item, 1);
    house.items.add(HPlaced(item, x, y, r));
    return true;
  }

  /// Mueve el mueble [i] de la casa de [tamaId] a ([x], [y]).
  bool moveFurniture(String tamaId, int i, int x, int y) {
    final house = houses[tamaId];
    if (house == null || i < 0 || i >= house.items.length) return false;
    final p = house.items[i];
    if (!house.fits(p.id, x, y, p.r, skip: i)) return false;
    p
      ..x = x
      ..y = y;
    return true;
  }

  /// Gira el mueble [i] un cuarto de vuelta. Si así no cabe donde está, lo
  /// arrima hacia arriba y a la izquierda hasta que quepa.
  bool rotateFurniture(String tamaId, int i) {
    final house = houses[tamaId];
    if (house == null || i < 0 || i >= house.items.length) return false;
    final p = house.items[i];
    final r = (p.r + 1) & 3;
    for (var dy = 0; dy <= p.y; dy++) {
      for (var dx = 0; dx <= p.x; dx++) {
        if (house.fits(p.id, p.x - dx, p.y - dy, r, skip: i)) {
          p
            ..x -= dx
            ..y -= dy
            ..r = r;
          return true;
        }
      }
    }
    return false;
  }

  /// Guarda el mueble [i] de la casa de [tamaId] en el almacén.
  bool storeFurniture(String tamaId, int i) {
    final house = houses[tamaId];
    if (house == null || i < 0 || i >= house.items.length) return false;
    _give(house.items.removeAt(i).id, 1);
    return true;
  }

  /// Cambia el suelo o la pared de la casa de [tamaId].
  bool decorate(String tamaId, {HStyle? floor, HStyle? wall}) {
    final house = houses[tamaId];
    if (house == null) return false;
    if (floor != null) house.floor = floor;
    if (wall != null) house.wall = wall;
    return true;
  }

  /// La comodidad de la casa de [tama], si tiene.
  HComfort? comfortOf(HTama tama) {
    final house = houses[tama.id];
    return house == null ? null : hComfort(house, tama.personality);
  }

  /// El ánimo con el que trabaja [tama] aquí: el suyo o, si su casa le deja
  /// más descansado, el de la casa. No toca su ánimo de verdad.
  double moodFor(HTama tama) {
    final comfort = comfortOf(tama);
    final mood = tama.mood.clamp(0.0, 1.0);
    return comfort == null ? mood : max(mood, hRestMood(comfort.value));
  }

  int levelOf(HSkill skill) => hLevelForXp(xp[skill] ?? 0);

  int get totalLevel => HSkill.values.fold(0, (sum, s) => sum + levelOf(s));

  int get slots => hSlotsFor(totalLevel);

  int masteryOf(String action) => hLevelForXp(mastery[action] ?? 0);

  int count(String item) => bank[item] ?? 0;

  bool isBusy(String tamaId) =>
      workers.any((w) => w.tamaId == tamaId) || isTraveling(tamaId);

  bool isTraveling(String tamaId) =>
      expeditions.any((e) => e.tamaIds.contains(tamaId));

  /// El viaje en marcha a [zone], si lo hay.
  HExpedition? tripTo(String zone) =>
      expeditions.where((e) => e.zone == zone).firstOrNull;

  bool _has(Map<String, int> items, [int times = 1]) =>
      items.entries.every((e) => count(e.key) >= e.value * times);

  // ------------------------------------------------------------------
  // Órdenes del jugador. Devuelven false si no se puede.

  /// Pone a un Tama a hacer una acción (o le cambia la que hace).
  bool assign(String tamaId, String actionId) {
    final action = hAction(actionId);
    if (action == null || !canDo(action)) return false;
    if (isTraveling(tamaId)) return false;
    final current = workers.where((w) => w.tamaId == tamaId).firstOrNull;
    if (current != null) {
      if (current.actionId != actionId) current.progress = 0;
      current
        ..actionId = actionId
        ..stalled = false;
      if (hItem(current.boost ?? '')?.boostSkill != action.skill) {
        current.boost = null;
      }
      return true;
    }
    if (workers.length >= slots) return false;
    workers.add(HWorker(tamaId, actionId));
    return true;
  }

  void release(String tamaId) => workers.removeWhere((w) => w.tamaId == tamaId);

  /// Le pone a un Tama que trabaja un cebo, abono o mecha de su oficio
  /// ([item] null lo quita). Se gasta uno cada vez que termina; si se acaban,
  /// sigue sin ellos.
  bool setBoost(String tamaId, String? item) {
    final w = workers.where((w) => w.tamaId == tamaId).firstOrNull;
    if (w == null) return false;
    if (item == null) {
      w.boost = null;
      return true;
    }
    final def = hItem(item);
    if (def?.kind != HItemKind.boost ||
        def!.boostSkill != hAction(w.actionId)!.skill ||
        count(item) < 1) {
      return false;
    }
    w.boost = item;
    return true;
  }

  /// Lo que dura un té ahora (con tetera, más).
  Duration get teaDuration => count('pot_teapot') > 0
      ? hTeaDuration * (1 + hTeapotBonus)
      : hTeaDuration;

  /// Se toma un té: acelera durante media hora.
  bool drinkTea(String item, int now) {
    if (hItem(item)?.kind != HItemKind.tea || count(item) < 1) return false;
    _take(item, 1);
    tea = item;
    teaUntil = now + teaDuration.inMilliseconds;
    return true;
  }

  /// Un Tama se come una unidad de [item] (tiene que ser comida).
  bool eat(String item) {
    if (hItem(item)?.kind != HItemKind.food || count(item) < 1) return false;
    _take(item, 1);
    return true;
  }

  /// Quita del equipo de viaje lo que hay en [slot].
  bool unequip(HGearSlot slot) => kit.remove(slot) != null;

  /// Vuelve antes de tiempo con lo de las casillas ya pasadas; lo demás se
  /// pierde, y la comida ya se gastó al salir.
  bool cancelExpedition(String zone) {
    final trip = tripTo(zone);
    if (trip == null) return false;
    expeditions.remove(trip);
    return true;
  }

  /// Éxito de una expedición (0,3–1) con [power] frente a [zone].
  static double successFor(HZone zone, int power) =>
      (power / zone.difficulty).clamp(0.3, 1.0);

  bool equip(String item) {
    final def = hItem(item);
    if (def?.slot == null || count(item) < 1) return false;
    kit[def!.slot!] = item;
    return true;
  }

  /// Fuerza de un grupo con el equipo actual (en [zone], la ropa teñida de
  /// su color suma más).
  int partyPower(List<HTama> party, [String? zone]) {
    final level = levelOf(HSkill.expedition);
    var power = 0.0;
    for (final t in party) {
      power +=
          (5 + level) * (t.likes(HSkill.expedition) ? 1 + hAffinityBonus : 1);
    }
    for (final item in kit.values) {
      final def = hItem(item);
      if (def == null || count(item) <= 0) continue;
      power += def.power;
      if (def.zones.contains(zone)) power += def.zonePower;
    }
    return power.round();
  }

  /// Comida (puntos) que pide un viaje de [minutes] minutos comiendo.
  static int foodNeeded(int minutes, int party) =>
      (party * minutes / 10).ceil();

  /// Lo que falta para salir con [plan] y [party] hoy (`level`, `busy`,
  /// `party`, `route`, `food`, `supply`, `money`, `trips`), o null.
  String? tripProblem(HTripPlan plan, List<HTama> party, int today) {
    final zone = hZoneById[plan.zone];
    if (zone == null) return 'route';
    if (levelOf(HSkill.expedition) < zone.level) return 'level';
    if (expeditions.length >= maxTrips || tripTo(plan.zone) != null) {
      return 'trips';
    }
    if (party.isEmpty || party.length > maxParty) return 'party';
    if (party.any((t) => isBusy(t.id))) return 'busy';
    final map = hZoneMap(plan.zone, today);
    if (!map.isValid(plan.route)) return 'route';
    final foodDef = hItem(plan.food);
    if (foodDef == null || foodDef.food <= 0) return 'food';
    final units = foodUnits(plan, party.length, today);
    if (count(plan.food) < units) return 'food';
    final supply = plan.supply == null ? null : hItem(plan.supply!);
    if (plan.supply != null &&
        (supply == null ||
            (supply.kind != HItemKind.potion && supply.kind != HItemKind.map) ||
            count(plan.supply!) < 1)) {
      return 'supply';
    }
    if (plan.rune != null &&
        (hItem(plan.rune!)?.kind != HItemKind.rune || count(plan.rune!) < 1)) {
      return 'supply';
    }
    if (money < plan.price) return 'money';
    return null;
  }

  /// Unidades de [plan.food] que pide el viaje.
  int foodUnits(HTripPlan plan, int party, int today) {
    final foodDef = hItem(plan.food);
    if (foodDef == null || foodDef.food <= 0 || party == 0) return 0;
    final minutes = hZoneMap(plan.zone, today).eatingMinutesOf(plan.route);
    return (foodFor(minutes, party) / foodDef.food).ceil();
  }

  /// Fuerza de [party] con la runa de [plan].
  int tripPower(HTripPlan plan, List<HTama> party) =>
      partyPower(party, plan.zone) +
      (plan.rune == null ? 0 : hItem(plan.rune!)?.power ?? 0);

  /// Sale de expedición: gasta la comida, la poción o el mapa, la runa y los
  /// ginmon de los servicios, y fija cuándo se llega a cada casilla.
  bool startExpedition(HTripPlan plan, List<HTama> party, int now, int today) {
    if (tripProblem(plan, party, today) != null) return false;
    final map = hZoneMap(plan.zone, today);
    final power = tripPower(plan, party);
    _take(plan.food, foodUnits(plan, party.length, today));
    final effects = <String?>[];
    for (final id in [plan.supply, plan.rune]) {
      if (id == null) continue;
      _take(id, 1);
      effects.add(hItem(id)!.effect);
    }
    money -= plan.price;
    // Curas: una por poción; el elixir, todas.
    var heals = plan.supply == 'potion_elixir'
        ? 99
        : effects.where((e) => e == 'heal').length;
    final speed =
        (plan.cart ? 1 - hCartTime : 1) *
        (effects.contains('haste') ? 1 - hHasteTime : 1);
    final at = <int>[];
    final fails = <int>{};
    var t = now.toDouble();
    final nodes = map.nodesOf(plan.route);
    for (var i = 0; i < nodes.length; i++) {
      var minutes = nodes[i].minutes * speed;
      if (nodes[i].kind == HNodeKind.danger && power < nodes[i].threat) {
        if (heals > 0) {
          heals--;
        } else {
          fails.add(i);
          minutes *= 1 + hDangerDelay;
        }
      }
      t += minutes * 60000;
      at.add(t.round());
    }
    final luck =
        (plan.supply != null && hItem(plan.supply!)?.effect == 'luck'
            ? hLuckPotion
            : 1.0) *
        (plan.rune != null && hItem(plan.rune!)?.effect == 'luck'
            ? hLuckRune
            : 1.0);
    expeditions.add(
      HExpedition(
        plan.zone,
        [for (final t in party) t.id],
        now,
        at.last,
        power,
        day: today,
        route: [...plan.route],
        at: at,
        fails: fails,
        porter: plan.porter,
        luck: luck,
      ),
    );
    return true;
  }

  // ------------------------------------------------------------------
  // El paso del tiempo.

  /// Trabaja desde `lastTick` hasta `now` (con el tope de 12 h) y cierra la
  /// expedición si ya ha vuelto. `tamas` da personalidad y ánimo de cada uno;
  /// si un Tama ya no existe, su ranura se libera.
  HReport advance(int now, Map<String, HTama> tamas) {
    final report = HReport();
    workers.removeWhere((w) => !tamas.containsKey(w.tamaId));
    final rng = Random(seed);
    final levelsBefore = {for (final s in HSkill.values) s: levelOf(s)};

    final elapsed = (now - lastTick).clamp(0, hOfflineCap.inMilliseconds);
    final total = elapsed / 1000;
    report.seconds = total;
    final start = now - elapsed;

    // Los parados que ya tienen material (vendido, comprado, traído de
    // viaje…) vuelven al trabajo desde el principio del tramo.
    for (final w in workers) {
      if (w.stalled && _has(hAction(w.actionId)!.inputs)) {
        w
          ..stalled = false
          ..progress = 0;
      }
    }
    final active = workers.where((w) => !w.stalled).toList();
    final durations = <HWorker, double>{};
    final nextAt = <HWorker, double>{};
    for (final w in active) {
      durations[w] = _duration(w, tamas[w.tamaId]!, start);
      nextAt[w] = (1 - w.progress) * durations[w]!;
    }

    /// Vuelve a poner en marcha, en el segundo [t], a los parados que ya
    /// tienen material.
    void wake(double t) {
      for (final w in workers) {
        if (!w.stalled || !_has(hAction(w.actionId)!.inputs)) continue;
        w
          ..stalled = false
          ..progress = 0;
        final d = _duration(w, tamas[w.tamaId]!, start + (t * 1000).round());
        durations[w] = d;
        nextAt[w] = t + d;
      }
    }

    // Cada casilla de cada viaje pasa en su hora dentro del tramo, para que
    // su botín llegue a tiempo a quien lo espera. Lo que pasó antes de lo
    // simulado (más de 12 h fuera) cuenta desde el principio.
    double tripAt(HExpedition e) =>
        now < e.nextAt ? double.infinity : max(0.0, (e.nextAt - start) / 1000);

    // Cola de eventos: siempre acaba primero el que menos le queda, para que
    // dos Tamas que gastan lo mismo se lo repartan en orden.
    while (true) {
      HWorker? w;
      for (final other in nextAt.keys) {
        if (w == null || nextAt[other]! < nextAt[w]!) w = other;
      }
      HExpedition? trip;
      for (final e in expeditions) {
        if (trip == null || tripAt(e) < tripAt(trip)) trip = e;
      }
      final tripTime = trip == null ? double.infinity : tripAt(trip);
      if (tripTime <= total && (w == null || tripTime <= nextAt[w]!)) {
        _tripStep(trip!, rng, report);
        wake(tripTime);
        continue;
      }
      if (w == null) break;
      final t = nextAt[w]!;
      if (t > total) break;
      if (!_complete(w, rng, report)) {
        w
          ..stalled = true
          ..progress = 0;
        report.stalledTamas.add(w.tamaId);
        nextAt.remove(w);
        continue;
      }
      final d = _duration(w, tamas[w.tamaId]!, start + (t * 1000).round());
      durations[w] = d;
      nextAt[w] = t + d;
      wake(t);
    }
    for (final w in nextAt.keys) {
      w.progress = (1 - (nextAt[w]! - total) / durations[w]!).clamp(0.0, 1.0);
    }
    // Solo cuenta como parado quien sigue parado al final.
    report.stalledTamas.removeWhere(
      (id) => !workers.any((w) => w.tamaId == id && w.stalled),
    );

    for (final s in HSkill.values) {
      final after = levelOf(s);
      if (after > levelsBefore[s]!) report.levelUps[s] = after;
    }
    seed = rng.nextInt(1 << 31);
    lastTick = now;
    return report;
  }

  /// Segundos que tarda una vez la acción de este Tama en este momento.
  double _duration(HWorker w, HTama tama, int atMs) =>
      secondsFor(hAction(w.actionId)!, tama, atMs);

  /// Segundos que tarda [action] con [tama] en [atMs]: ánimo (o el descanso
  /// de su casa), maña,
  /// agilidad, té y maestría.
  double secondsFor(HAction action, HTama tama, int atMs) {
    var speed =
        (0.8 + 0.4 * moodFor(tama)) *
        (tama.likes(action.skill) ? 1 + hAffinityBonus : 1) *
        (1 + levelOf(HSkill.agility) * 0.001) *
        (1 + hTownSpeed(action.skill, town));
    final teaDef = tea == null ? null : hItem(tea!);
    if (teaDef != null &&
        atMs < teaUntil &&
        (teaDef.teaSkill == null || teaDef.teaSkill == action.skill)) {
      speed *= 1 + teaDef.teaBoost;
    }
    final mastery = 1 - masteryOf(action.id) * 0.002;
    return action.seconds * mastery / speed;
  }

  /// Termina una vez la acción. False si no hay materiales.
  bool _complete(HWorker w, Random rng, HReport report) {
    final action = hAction(w.actionId)!;
    if (!_has(action.inputs)) return false;
    for (final e in action.inputs.entries) {
      _take(e.key, e.value);
      report._add(report.spent, e.key, e.value);
    }
    // El cebo, abono o mecha: se gasta uno si queda.
    final boost = hItem(w.boost ?? '');
    var help = 0.0;
    if (boost != null &&
        boost.boostSkill == action.skill &&
        count(boost.id) > 0) {
      _take(boost.id, 1);
      report._add(report.spent, boost.id, 1);
      help = boost.boost;
    }
    // Con maestría (y cebo), a veces sale doble.
    final twice =
        masteryOf(action.id) / 400 +
        (action.skill == HSkill.fishing ? help : 0);
    final times = rng.nextDouble() < twice ? 2 : 1;
    // El abono da cosechas de más.
    final extra = action.skill == HSkill.farming ? help.round() : 0;
    for (final e in action.outputs.entries) {
      final n = e.value * times + extra;
      _give(e.key, n);
      report._add(report.gained, e.key, n);
    }
    // La mecha multiplica las gemas.
    final dropBoost = action.skill == HSkill.mining ? 1 + help : 1.0;
    for (final drop in action.drops) {
      final chance = drop.item.startsWith('gem_')
          ? drop.chance * dropBoost
          : drop.item == 'soot'
          ? drop.chance + townLevel(HBuilding.kiln) * hKilnSoot
          : drop.chance;
      if (rng.nextDouble() < chance) {
        _give(drop.item, 1);
        report._add(report.gained, drop.item, 1);
      }
    }
    _gainXp(action.skill, action.xp, report);
    // La maestría va a otro ritmo: una cuarta parte de la experiencia.
    mastery[action.id] = (mastery[action.id] ?? 0) + max(1, action.xp ~/ 4);
    return true;
  }

  /// Lo siguiente de un viaje: la casilla que toca o, sin ruta, la vuelta.
  void _tripStep(HExpedition exp, Random rng, HReport report) {
    final zone = hZoneById[exp.zone]!;
    final success = successFor(zone, exp.power);
    if (exp.route.isEmpty) {
      // Viaje de antes del mapa: todo el botín de golpe.
      for (final loot in zone.loot) {
        if (rng.nextDouble() >= loot.chance * success) continue;
        final n = loot.min + rng.nextInt(loot.max - loot.min + 1);
        _gift(loot.item, max(1, (n * success).round()), report);
      }
      _gainXp(HSkill.expedition, (zone.xp * success).round(), report);
      _finishTrip(exp, zone, success, rng, report);
      return;
    }
    final i = exp.done;
    final node = exp.map.node(i, exp.route[i])!;
    final got = <String, int>{};
    void give(String item, int n) {
      final amount = max(1, (n * (exp.porter ? 1 + hPorterLoot : 1)).round());
      got[item] = (got[item] ?? 0) + amount;
      _gift(item, amount, report);
    }

    /// Una cosa del botín del sitio, más a menudo lo que más cae.
    void loot() {
      final total = zone.loot.fold(0.0, (sum, l) => sum + l.chance);
      var roll = rng.nextDouble() * total;
      var pick = zone.loot.last;
      for (final l in zone.loot) {
        if (roll < l.chance) {
          pick = l;
          break;
        }
        roll -= l.chance;
      }
      final n = pick.min + rng.nextInt(pick.max - pick.min + 1);
      give(pick.item, max(1, (n * success).round()));
    }

    final failed = exp.fails.contains(i);
    switch (node.kind) {
      case HNodeKind.loot:
        loot();
      case HNodeKind.forage:
        // Lo más raro del sitio, a veces; si no, algo de lo de siempre.
        final rare = zone.loot.reduce((a, b) => a.chance <= b.chance ? a : b);
        if (rng.nextDouble() < min(1.0, rare.chance * 4) * success) {
          give(rare.item, 1);
        } else {
          loot();
        }
      case HNodeKind.danger:
        // Pasar un peligro también da botín; no pasarlo, nada.
        if (!failed) loot();
      case HNodeKind.rest:
        break;
      case HNodeKind.order:
        // Un paquete para el tablón (el porteador no lo duplica).
        got[hParcel] = 1;
        _gift(hParcel, 1, report);
      case HNodeKind.treasure:
        loot();
        if (rng.nextDouble() < zone.prizeChance * success * exp.luck) {
          prizes++;
          report.prizes++;
          got['prize'] = 1;
        }
    }
    _gainXp(
      HSkill.expedition,
      (zone.xp * success / exp.route.length).round(),
      report,
    );
    exp.log.add(got);
    exp.done++;
    report.nodes.add(
      HNodeEvent(exp.zone, node.kind, {
        for (final e in got.entries)
          if (e.key != 'prize') e.key: e.value,
      }, failed: failed),
    );
    if (exp.done >= exp.route.length) {
      _finishTrip(exp, zone, success, rng, report);
    }
  }

  /// La vuelta: la probabilidad de tesoro de siempre y el viaje se acaba.
  void _finishTrip(
    HExpedition exp,
    HZone zone,
    double success,
    Random rng,
    HReport report,
  ) {
    if (rng.nextDouble() < zone.prizeChance * success * exp.luck) {
      prizes++;
      report.prizes++;
    }
    report
      ..expeditionZone = zone.id
      ..expeditionSuccess = success;
    expeditions.remove(exp);
  }

  void _gift(String item, int n, HReport report) {
    _give(item, n);
    report._add(report.gained, item, n);
  }

  void _gainXp(HSkill skill, int base, HReport report) {
    // Lo estudiado se nota en todo.
    final library = skill == HSkill.study
        ? 1 + townLevel(HBuilding.library) * hLibraryStudy
        : 1;
    final amount = (base * (1 + levelOf(HSkill.study) * hStudyBonus) * library)
        .round();
    final cap = hXpForLevel(hMaxLevel) * 2;
    xp[skill] = min(cap, (xp[skill] ?? 0) + amount);
    report.xp[skill] = (report.xp[skill] ?? 0) + amount;
  }

  void _give(String item, int n) => bank[item] = count(item) + n;

  void _take(String item, int n) {
    final left = count(item) - n;
    if (left > 0) {
      bank[item] = left;
    } else {
      bank.remove(item);
      kit.removeWhere((_, id) => id == item);
    }
  }

  // ------------------------------------------------------------------
  // Guardado.

  Map<String, Object> toJson() => {
    'xp': {for (final e in xp.entries) e.key.name: e.value},
    'mastery': mastery,
    'bank': bank,
    'workers': {
      for (var i = 0; i < workers.length; i++) '$i': workers[i].toJson(),
    },
    'kit': {for (final e in kit.entries) e.key.name: e.value},
    if (town.isNotEmpty)
      'town': {for (final e in town.entries) e.key.name: e.value},
    if (shopBought.isNotEmpty) 'shop': {'day': shopDay, 'bought': shopBought},
    if (tea != null) 'tea': {'item': tea!, 'until': teaUntil},
    if (expeditions.isNotEmpty)
      'expeditions': {
        for (var i = 0; i < expeditions.length; i++)
          '$i': expeditions[i].toJson(),
      },
    if (guides.isNotEmpty) 'guides': guides,
    if (orders.isNotEmpty)
      'orders': {
        'day': ordersDay,
        if (swapDay > 0) 'swap': swapDay,
        if (orderTicket) 'ticket': true,
        'list': {
          for (var i = 0; i < orders.length; i++) '$i': orders[i].toJson(),
        },
      },
    if (orderDay > 0) 'orderDay': orderDay,
    if (houses.isNotEmpty)
      'houses': {for (final e in houses.entries) e.key: e.value.toJson()},
    if (plans.isNotEmpty) 'plans': {for (final id in plans) id: true},
    'last': lastTick,
    'seed': seed,
    'prizes': prizes,
    if (claimAt > 0) 'claimAt': claimAt,
    'money': money,
    'earned': earned,
    'period': {
      'day': day,
      'dayXp': dayXp,
      'week': week,
      'weekXp': weekXp,
      'dayMoney': dayMoney,
      'weekMoney': weekMoney,
    },
  };

  /// Partida nueva: todo a nivel 0 y un puñado de semillas para el huerto.
  factory HState.fresh(int now) =>
      HState(lastTick: now, seed: now & 0x7fffffff, bank: {'seed_rice': 5});

  static HState fromJson(Object? raw, int now) {
    if (raw is! Map) return HState.fresh(now);
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    Map<String, int> counts(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is num && (e.value as num) > 0)
            '${e.key}': (e.value as num).toInt(),
    };
    final xp = <HSkill, int>{};
    for (final e in counts(raw['xp']).entries) {
      final skill = HSkill.byName(e.key);
      if (skill != null) xp[skill] = e.value;
    }
    final kit = <HGearSlot, String>{};
    final rawKit = raw['kit'];
    if (rawKit is Map) {
      for (final slot in HGearSlot.values) {
        final item = rawKit[slot.name];
        if (item is String && hItem(item)?.slot == slot) kit[slot] = item;
      }
    }
    final town = <HBuilding, int>{};
    for (final e in counts(raw['town']).entries) {
      final b = HBuilding.byName(e.key);
      if (b != null) town[b] = min(e.value, hTownMaxLevel);
    }
    final shop = raw['shop'] is Map ? raw['shop'] as Map : const {};
    final tea = raw['tea'];
    final period = raw['period'] is Map ? raw['period'] as Map : const {};
    final orders = raw['orders'] is Map ? raw['orders'] as Map : const {};
    final bank = counts(raw['bank']);
    // Lo que no cabe en una casa (no debería pasar) vuelve al almacén.
    final dropped = <String>[];
    final houses = <String, HHouse>{
      if (raw['houses'] is Map)
        for (final e in (raw['houses'] as Map).entries)
          '${e.key}': HHouse.fromJson(e.value, dropped: dropped),
    };
    for (final id in dropped) {
      bank[id] = (bank[id] ?? 0) + 1;
    }
    final rawPlans = raw['plans'];
    return HState(
      day: n(period['day']),
      dayXp: n(period['dayXp']),
      week: n(period['week']),
      weekXp: n(period['weekXp']),
      dayMoney: n(period['dayMoney']),
      weekMoney: n(period['weekMoney']),
      money: n(raw['money']),
      earned: n(raw['earned']),
      xp: xp,
      mastery: counts(raw['mastery']),
      bank: bank,
      houses: houses,
      plans: {
        if (rawPlans is Map)
          for (final e in rawPlans.entries)
            if (e.value == true && hFurniture[e.key]?.plan == true) '${e.key}',
      },
      workers: _list(
        raw['workers'],
      ).map(HWorker.fromJson).whereType<HWorker>().toList(),
      kit: kit,
      town: town,
      shopDay: n(shop['day']),
      shopBought: counts(shop['bought']),
      tea: tea is Map && tea['item'] is String ? tea['item'] as String : null,
      teaUntil: tea is Map ? n(tea['until']) : 0,
      // Antes de la 0.8.0 había un solo viaje, en `expedition`.
      expeditions: [
        for (final e in [..._list(raw['expeditions']), raw['expedition']])
          ?HExpedition.fromJson(e),
      ].take(2).toList(),
      guides: counts(raw['guides']),
      ordersDay: n(orders['day']),
      orders: [
        for (final o in _list(orders['list'])) ?HOrder.fromJson(o),
      ].take(1 + hBoardSlots(hTownMaxLevel)).toList(),
      swapDay: n(orders['swap']),
      orderTicket: orders['ticket'] == true,
      orderDay: n(raw['orderDay']),
      lastTick: raw['last'] is num ? n(raw['last']) : now,
      seed: n(raw['seed']),
      prizes: n(raw['prizes']),
      claimAt: n(raw['claimAt']),
    );
  }
}

/// Mon que se dan por cada experiencia que costó hacer algo.
const double hMonPerXp = .2;

final Map<String, int> _prices = {};

/// Lo que vale un objeto al venderlo, en mon. Sale de lo que cuesta hacerlo:
/// lo que valen sus materiales más la experiencia de la tarea (repartido
/// entre lo que saca). Lo que solo cae (gemas, semillas, tesoros de viaje)
/// vale más cuanto menos cae. Siempre al menos 1.
int hSellValue(String id) => _prices[id] ??= hItem(id) == null
    ? 0
    : max(1, _price(id, <String>{}).round());

double _price(String id, Set<String> seen) {
  // Un objeto que se usa para hacerse a sí mismo (las semillas) no cuenta
  // dos veces.
  if (!seen.add(id)) return 0;
  var best = double.infinity;
  for (final a in hActions) {
    final out = a.outputs[id];
    if (out == null) continue;
    var cost = a.xp * hMonPerXp;
    for (final e in a.inputs.entries) {
      cost += _price(e.key, {...seen}) * e.value;
    }
    best = min(best, cost / out);
  }
  if (best.isFinite) return best;
  // Lo que cae de una tarea: una décima parte de lo que vale hacerla, entre
  // lo poco que cae.
  for (final a in hActions) {
    for (final d in a.drops) {
      if (d.item == id) best = min(best, a.xp * hMonPerXp * .1 / d.chance);
    }
  }
  // El botín de una expedición: la experiencia del viaje repartida entre lo
  // que se trae.
  for (final z in hZones) {
    for (final l in z.loot) {
      if (l.item != id) continue;
      final units = l.chance * (l.min + l.max) / 2;
      best = min(best, z.xp * hMonPerXp / z.loot.length / units);
    }
  }
  if (best.isFinite) return best;
  // Los muebles que solo se compran.
  final furniture = hFurniture[id];
  return furniture != null && furniture.value > 0
      ? furniture.value.toDouble()
      : 1;
}

/// La base de datos devuelve las listas como mapas con claves numéricas.
List<Object?> _list(Object? raw) {
  if (raw is List) return raw;
  if (raw is Map) {
    final keys = raw.keys.map((k) => '$k').toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return [for (final k in keys) raw[k]];
  }
  return const [];
}
