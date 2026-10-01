// Ibasho — la partida de Hatarakitama de una cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/gacha.dart' show gachaWeek;
import '../backend/ibasho_backend.dart';
import '../backend/models.dart' show serverTimestamp;
import '../backend/tama.dart';
import '../games/hatarakitama/hataraki_data.dart';
import '../games/hatarakitama/hataraki_engine.dart';
import '../games/hatarakitama/hataraki_home.dart';
import '../games/hatarakitama/hataraki_map.dart';
import '../games/hatarakitama/hataraki_town.dart';
import 'login_bonus.dart' show bonusDay;
import 'session.dart';

/// Id del juego en `earnings` y en las reglas.
const String hatarakiGame = 'hataraki';

/// Lo mínimo entre dos tesoros canjeados por tickets (lo exigen las reglas).
const Duration hatarakiClaimGap = Duration(hours: 1, minutes: 1);

/// El tope de mon por tabla que dejan las reglas.
const int hatarakiMaxScore = 999999999;

/// Cada cuánto se guarda la partida mientras el canal está abierto.
const Duration hatarakiSaveEvery = Duration(minutes: 2);

/// `hataraki/visit`: lo que ven los amigos de cada Tama al visitar el pueblo
/// (nombre, personalidad y aspecto). Los amigos no leen `tamas`, así que va
/// con la partida y se reescribe cada vez que se guarda.
Map<String, Object> hatarakiVisitJson(List<Tama> tamas) => {
  'tamas': {
    for (final t in tamas)
      t.id: {
        'name': t.name,
        'personality': t.personality.name,
        'look': {
          for (final e in t.look.toJson().entries)
            if (e.value != null) e.key: e.value!,
        },
      },
  },
};

/// Los Tamas de una ficha de visita, como Tamas de [accountId] (sin cuidados:
/// solo sirven para dibujarlos).
List<Tama> hatarakiVisitTamas(Object? raw, String accountId) {
  final tamas = raw is Map ? raw['tamas'] : null;
  if (tamas is! Map) return const [];
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  return [
    for (final e in tamas.entries)
      if (e.value is Map)
        Tama(
          id: '${e.key}',
          creator: accountId,
          keeper: accountId,
          name: ((e.value as Map)['name'] as String?) ?? '',
          personality: TamaPersonality.byName((e.value as Map)['personality']),
          look: TamaLook.fromJson((e.value as Map)['look']),
          createdAt: epoch,
          updatedAt: epoch,
        ),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

/// Lo que se ve al visitar el pueblo de alguien: su partida tal y como la
/// guardó y sus Tamas.
@immutable
class HatarakiVisit {
  const HatarakiVisit({required this.game, required this.tamas});

  final HState game;
  final List<Tama> tamas;
}

@immutable
class HatarakiState {
  const HatarakiState({
    this.game,
    this.version = 0,
    this.away,
    this.loaded = false,
  });

  /// La partida. Es mutable por dentro: [version] sube con cada cambio para
  /// que la interfaz se entere.
  final HState? game;
  final int version;

  /// Lo que pasó mientras no había nadie mirando, para el resumen de entrada.
  /// Se borra al cerrarlo.
  final HReport? away;

  final bool loaded;
}

/// `/users/{cuenta}/hataraki`: el estado entero de la partida. Solo lo lee y
/// lo escribe su dueña; se lee una vez al entrar y se escribe entero cada
/// [hatarakiSaveEvery], al hacer algo y al salir. No abre ninguna conexión en
/// tiempo real: la partida solo cambia desde este aparato.
class HatarakiController extends StateNotifier<HatarakiState> {
  HatarakiController({
    required IbashoBackend backend,
    required SessionController session,
    required List<Tama> Function() tamasOf,
    required bool Function() tamasLoaded,
    void Function(int day, int week, int allTime)? onScores,
    int Function()? gachakenOf,
    DateTime Function()? now,
  }) : _backend = backend,
       _onScores = onScores,
       _gachakenOf = gachakenOf,
       _session = session,
       _tamasOf = tamasOf,
       _tamasLoaded = tamasLoaded,
       _now = now ?? DateTime.now,
       super(const HatarakiState()) {
    unawaited(_load());
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final List<Tama> Function() _tamasOf;
  final bool Function() _tamasLoaded;
  final DateTime Function() _now;

  /// Manda a la clasificación los mon ganados vendiendo en el día, en la
  /// semana y desde siempre: gana quien más se ha hecho rico.
  final void Function(int day, int week, int allTime)? _onScores;
  (int, int, int)? _sentScores;

  /// Tickets gachaken que tiene la cuenta, para canjear los tesoros.
  final int Function()? _gachakenOf;
  bool _claiming = false;

  bool _dirty = false;
  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);

  String get _path => '/users/${_session.state.accountId}/hataraki';

  int get _ms => _now().millisecondsSinceEpoch;

  /// El día de hoy para la tienda y la lonja (el mismo que el de las
  /// clasificaciones y el bono diario).
  int get today => bonusDay(_now());

  /// Personalidad y ánimo de un Tama ahora mismo, para las cuentas de la UI.
  HTama? tamaNow(String id) => _tamas[id];

  /// Personalidad y ánimo de cada Tama de la cuenta, ahora mismo.
  Map<String, HTama> get _tamas {
    final now = _now();
    return {
      for (final t in _tamasOf())
        t.id: HTama(t.id, t.personality, TamaMoodReading.of(t, now).value),
    };
  }

  Future<void> _load() async {
    if (_session.state.accountId.isEmpty) return;
    Object? raw;
    try {
      raw = await _backend.read(_path, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer Hatarakitama ($e)');
      // Sin red no se empieza de cero: se machacaría la partida guardada.
      if (mounted) state = const HatarakiState(loaded: true);
      return;
    }
    if (!mounted) return;
    final game = HState.fromJson(raw, _ms);
    state = HatarakiState(game: game, loaded: true);
  }

  /// Pone la partida al día. Lo llama el canal cada segundo mientras está
  /// abierto; la primera vez, lo que se ha acumulado fuera va al resumen.
  /// Sin los Tamas cargados no se avanza: se liberarían todas las ranuras.
  HReport? tick() {
    final game = state.game;
    if (game == null || !_tamasLoaded()) return null;
    final first = state.version == 0;
    final report = _advance(game);
    _dirty = true;
    final away = first && report.seconds >= 60 && !report.isEmpty
        ? report
        : state.away;
    state = HatarakiState(
      game: game,
      version: state.version + 1,
      away: away,
      loaded: true,
    );
    if (_now().difference(_savedAt) >= hatarakiSaveEvery) unawaited(save());
    unawaited(_claimTreasure());
    unawaited(_claimOrder());
    return report;
  }

  /// El paso del tiempo, con la experiencia apuntada en el día y la semana.
  HReport _advance(HState game) {
    final report = game.advance(_ms, _tamas);
    final gained = report.xp.values.fold(0, (a, b) => a + b);
    final now = _now();
    game.refreshOrders(bonusDay(now));
    game.countXp(gained, today: bonusDay(now), thisWeek: gachaWeek(now));
    return report;
  }

  void dismissAway() => state = HatarakiState(
    game: state.game,
    version: state.version + 1,
    loaded: state.loaded,
  );

  /// Aplica una orden del jugador y guarda si ha cambiado algo.
  bool _apply(bool Function(HState game) order) {
    final game = state.game;
    if (game == null || !_tamasLoaded()) return false;
    // Antes de cambiar nada, el tiempo hasta ahora con lo que había.
    _advance(game);
    final ok = order(game);
    state = HatarakiState(
      game: game,
      version: state.version + 1,
      away: state.away,
      loaded: true,
    );
    _dirty = true;
    unawaited(save());
    return ok;
  }

  bool assign(String tamaId, String actionId) =>
      _apply((g) => g.assign(tamaId, actionId));

  bool release(String tamaId) => _apply((g) {
    g.release(tamaId);
    return true;
  });

  bool setBoost(String tamaId, String? item) =>
      _apply((g) => g.setBoost(tamaId, item));

  bool drinkTea(String item) => _apply((g) => g.drinkTea(item, _ms));

  bool equip(String item) => _apply((g) => g.equip(item));

  bool unequip(HGearSlot slot) => _apply((g) => g.unequip(slot));

  bool cancelExpedition(String zone) => _apply((g) => g.cancelExpedition(zone));

  /// Vende [n] de [item] (todo lo que haya, como mucho). Devuelve los mon.
  int sell(String item, int n) {
    var got = 0;
    final now = _now();
    _apply((g) {
      got = g.sell(item, n, today: bonusDay(now), thisWeek: gachaWeek(now));
      return got > 0;
    });
    return got;
  }

  /// Sube [building] un nivel con ginmon y piezas del almacén.
  bool build(HBuilding building) => _apply((g) => g.build(building));

  /// Compra [n] de [item] en la tienda de hoy. Devuelve cuántas.
  int buy(String item, int n) {
    var got = 0;
    _apply((g) {
      got = g.buy(item, n, today);
      return got > 0;
    });
    return got;
  }

  /// Gasta la comida más sencilla del almacén. Devuelve cuál, o `null`.
  String? takeMeal() {
    final game = state.game;
    if (game == null) return null;
    final foods =
        game.bank.keys.where((id) => hItem(id)?.kind == HItemKind.food).toList()
          ..sort((a, b) => hItem(a)!.food.compareTo(hItem(b)!.food));
    if (foods.isEmpty) return null;
    return _apply((g) => g.eat(foods.first)) ? foods.first : null;
  }

  /// Los Tamas de [ids] como los ve el juego (sin los que ya no existen).
  List<HTama> partyOf(List<String> ids) {
    final tamas = _tamas;
    return [for (final id in ids) tamas[id]].whereType<HTama>().toList();
  }

  bool startExpedition(HTripPlan plan, List<String> tamaIds) {
    final party = partyOf(tamaIds);
    if (party.length != tamaIds.length) return false;
    return _apply((g) => g.startExpedition(plan, party, _ms, today));
  }

  /// Entrega el encargo [i] del tablón y, si era el grande, cobra su
  /// ticket.
  bool deliver(int i) {
    final now = _now();
    final ok = _apply(
      (g) => g.deliver(i, today: bonusDay(now), thisWeek: gachaWeek(now)),
    );
    if (ok) unawaited(_claimOrder());
    return ok;
  }

  /// Cambia el encargo [i] por otro (uno al día, con ginmon).
  bool swapOrder(int i) => _apply((g) => g.swapOrder(i, today));

  // --- Casas ------------------------------------------------------------------

  /// Le hace casa a [tamaId].
  bool buildHouse(String tamaId) => _apply((g) => g.buildHouse(tamaId));

  /// Pone [item] del almacén en la casa de [tamaId].
  bool placeFurniture(String tamaId, String item, int x, int y) =>
      _apply((g) => g.placeFurniture(tamaId, item, x, y));

  bool moveFurniture(String tamaId, int i, int x, int y) =>
      _apply((g) => g.moveFurniture(tamaId, i, x, y));

  bool rotateFurniture(String tamaId, int i) =>
      _apply((g) => g.rotateFurniture(tamaId, i));

  bool storeFurniture(String tamaId, int i) =>
      _apply((g) => g.storeFurniture(tamaId, i));

  bool decorate(String tamaId, {HStyle? floor, HStyle? wall}) =>
      _apply((g) => g.decorate(tamaId, floor: floor, wall: wall));

  /// Paga un guía que enseña hoy todo el mapa de [zone].
  bool hireGuide(String zone) => _apply((g) => g.hireGuide(zone, today));

  // --- Canal de depuración (solo administración) ---------------------------

  /// Cambia la partida a mano y la guarda.
  void _debug(void Function(HState game) change) {
    final game = state.game;
    if (game == null) return;
    change(game);
    state = HatarakiState(
      game: game,
      version: state.version + 1,
      away: state.away,
      loaded: true,
    );
    _dirty = true;
    unawaited(save());
  }

  /// Sube [levels] niveles cada oficio.
  void debugLevels(int levels) => _debug((g) {
    for (final s in HSkill.values) {
      g.xp[s] = hXpForLevel(math.min(hMaxLevel, g.levelOf(s) + levels));
    }
  });

  /// [n] de cada objeto al almacén.
  void debugFillBank(int n) => _debug((g) {
    for (final i in hItems) {
      g.bank[i.id] = g.count(i.id) + n;
    }
  });

  /// Mon como si se hubieran ganado vendiendo hoy (cuentan para las tablas).
  void debugGiveMoney(int mon) {
    final now = _now();
    // Se venden troncos de sugi hasta llegar: así cuentan igual que de verdad.
    final logs = (mon / hSellValue('log_sugi')).ceil();
    _debug((g) {
      g.bank['log_sugi'] = g.count('log_sugi') + logs;
      g.sell('log_sugi', logs, today: bonusDay(now), thisWeek: gachaWeek(now));
    });
  }

  /// Dos de cada mueble al almacén y todos los planos sabidos.
  void debugFurniture() => _debug((g) {
    for (final f in hFurnitureList) {
      g.bank[f.id] = g.count(f.id) + 2;
    }
    g.plans.addAll(hPlanIds);
  });

  /// Tablón nuevo: los encargos de hoy otra vez y el cambio del día libre.
  void debugOrders() => _debug((g) {
    g
      ..ordersDay = 0
      ..swapDay = 0
      ..refreshOrders(today);
  });

  /// Todos los edificios un nivel más (o al máximo).
  void debugTown() => _debug((g) {
    for (final b in HBuilding.values) {
      g.town[b] = math.min(hTownMaxLevel, g.townLevel(b) + 1);
    }
  });

  /// Los viajes en marcha llegan ya a todas sus casillas, con su botín.
  void debugFinishTrip() => _debug((g) {
    final now = _ms;
    for (var i = 0; i < g.expeditions.length; i++) {
      final e = g.expeditions[i];
      g.expeditions[i] = HExpedition(
        e.zone,
        e.tamaIds,
        e.startedAt,
        now,
        e.power,
        day: e.day,
        route: e.route,
        at: [for (final t in e.at) math.min(t, now)],
        fails: e.fails,
        done: e.done,
        porter: e.porter,
        luck: e.luck,
        log: e.log,
      );
    }
  });

  /// Cada viaje con mapa llega ya a su siguiente casilla (solo a esa).
  void debugTripStep() => _debug((g) {
    final now = _ms;
    for (var i = 0; i < g.expeditions.length; i++) {
      final e = g.expeditions[i];
      if (e.route.isEmpty || e.done >= e.at.length) continue;
      g.expeditions[i] = HExpedition(
        e.zone,
        e.tamaIds,
        e.startedAt,
        e.endsAt,
        e.power,
        day: e.day,
        route: e.route,
        at: [
          for (var j = 0; j < e.at.length; j++)
            j == e.done ? math.min(e.at[j], now) : e.at[j],
        ],
        fails: e.fails,
        done: e.done,
        porter: e.porter,
        luck: e.luck,
        log: e.log,
      );
    }
  });

  /// Un tesoro del gacha como si lo hubiera traído una expedición.
  void debugTreasure() => _debug((g) => g.prizes++);

  /// Hace como si se hubiera salido hace [hours] horas: al volver a entrar
  /// en el canal se simula ese rato y sale el resumen.
  void debugAway(int hours) {
    final game = state.game;
    if (game == null) return;
    game.lastTick -= hours * 3600000;
    state = HatarakiState(game: game, loaded: true);
    _dirty = true;
    unawaited(save());
  }

  /// Partida nueva (todo a 0). Los tesoros, la hora del último canje y el
  /// día del último ticket de encargo se conservan: las reglas no dejan
  /// tocarlos.
  void debugReset() {
    final old = state.game;
    final game = HState.fresh(_ms)
      ..prizes = old?.prizes ?? 0
      ..claimAt = old?.claimAt ?? 0
      ..orderDay = old?.orderDay ?? 0;
    state = HatarakiState(game: game, loaded: true);
    _dirty = true;
    unawaited(save());
  }

  /// Canjea un tesoro de expedición por un ticket gachaken: las reglas dejan
  /// uno por hora, con el ticket subiendo 1 y `prizes` bajando 1 a la vez.
  Future<void> _claimTreasure() async {
    final game = state.game;
    final tickets = _gachakenOf;
    if (game == null || tickets == null || _claiming || game.prizes <= 0) {
      return;
    }
    if (_ms - game.claimAt < hatarakiClaimGap.inMilliseconds) return;
    _claiming = true;
    final account = _session.state.accountId;
    try {
      await _write();
      final token = await _session.freshToken();
      await _backend.merge('/', {
        'users/$account/tickets/gachaken': tickets() + 1,
        'users/$account/hataraki/prizes': game.prizes - 1,
        'users/$account/hataraki/claimAt': serverTimestamp,
      }, idToken: token);
      game.prizes -= 1;
      // La hora buena es la del servidor: la próxima partida entera tiene que
      // llevar la misma o las reglas la rechazan.
      final at = await _backend.read('$_path/claimAt', idToken: token);
      game.claimAt = at is num ? at.toInt() : _ms;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido canjear el tesoro ($e)');
    } finally {
      _claiming = false;
    }
  }

  /// Cobra el ticket gachaken del gran encargo: las reglas dejan uno al
  /// día, con `orderDay` pasando a hoy y el ticket subiendo 1 a la vez.
  Future<void> _claimOrder() async {
    final game = state.game;
    final tickets = _gachakenOf;
    final day = today;
    if (game == null ||
        tickets == null ||
        _claiming ||
        !game.orderTicket ||
        game.orderDay >= day) {
      return;
    }
    _claiming = true;
    final account = _session.state.accountId;
    try {
      await _write();
      await _backend.merge('/', {
        'users/$account/tickets/gachaken': tickets() + 1,
        'users/$account/hataraki/orderDay': day,
      }, idToken: await _session.freshToken());
      game
        ..orderDay = day
        ..orderTicket = false;
      _dirty = true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar el ticket del encargo ($e)');
    } finally {
      _claiming = false;
    }
    if (mounted) unawaited(save());
  }

  /// Escribe la partida entera si hay algo sin guardar. Mientras se cobra un
  /// ticket no: la partida vieja pisaría `claimAt` u `orderDay`.
  Future<void> save() async {
    if (!_claiming) await _write();
  }

  Future<void> _write() async {
    final game = state.game;
    if (game == null || !_dirty) return;
    _dirty = false;
    _savedAt = _now();
    // Lo de un periodo que ya pasó no cuenta en el nuevo.
    final now = _now();
    final scores = (
      game.day == bonusDay(now) ? math.min(hatarakiMaxScore, game.dayMoney) : 0,
      game.week == gachaWeek(now)
          ? math.min(hatarakiMaxScore, game.weekMoney)
          : 0,
      math.min(hatarakiMaxScore, game.earned),
    );
    if (scores != _sentScores && scores.$3 > 0) {
      _sentScores = scores;
      _onScores?.call(scores.$1, scores.$2, scores.$3);
    }
    try {
      await _backend.write(_path, {
        ...game.toJson(),
        'visit': hatarakiVisitJson(_tamasOf()),
      }, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar Hatarakitama ($e)');
      _dirty = true;
    }
  }

  @override
  void dispose() {
    unawaited(_write());
    super.dispose();
  }
}
