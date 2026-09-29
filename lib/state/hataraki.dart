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
    return report;
  }

  /// El paso del tiempo, con la experiencia apuntada en el día y la semana.
  HReport _advance(HState game) {
    final report = game.advance(_ms, _tamas);
    final gained = report.xp.values.fold(0, (a, b) => a + b);
    final now = _now();
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

  bool drinkTea(String item) => _apply((g) => g.drinkTea(item, _ms));

  bool equip(String item) => _apply((g) => g.equip(item));

  bool unequip(HGearSlot slot) => _apply((g) => g.unequip(slot));

  bool cancelExpedition() => _apply((g) => g.cancelExpedition());

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

  /// Gasta la comida más sencilla del almacén. Devuelve cuál, o `null`.
  String? takeMeal() {
    final game = state.game;
    if (game == null) return null;
    final foods = game.bank.keys.where((id) => hItem(id)?.kind == HItemKind.food).toList()
      ..sort((a, b) => hItem(a)!.food.compareTo(hItem(b)!.food));
    if (foods.isEmpty) return null;
    return _apply((g) => g.eat(foods.first)) ? foods.first : null;
  }

  bool startExpedition(String zone, List<String> tamaIds, String food) {
    final tamas = _tamas;
    final party = [
      for (final id in tamaIds) tamas[id],
    ].whereType<HTama>().toList();
    if (party.length != tamaIds.length) return false;
    return _apply((g) => g.startExpedition(zone, party, food, _ms));
  }

  // --- Canal de depuración (solo administración) ---------------------------

  /// Cambia la partida a mano y la guarda.
  void _debug(void Function(HState game) change) {
    final game = state.game;
    if (game == null) return;
    change(game);
    state = HatarakiState(game: game, version: state.version + 1, away: state.away, loaded: true);
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

  /// La expedición en curso vuelve ya, con su botín.
  void debugFinishTrip() => _debug((g) {
    final exp = g.expedition;
    if (exp == null) return;
    g.expedition = HExpedition(exp.zone, exp.tamaIds, exp.startedAt, _ms, exp.power);
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

  /// Partida nueva (todo a 0). Los tesoros y la hora del último canje se
  /// conservan: las reglas no dejan tocarlos.
  void debugReset() {
    final old = state.game;
    final game = HState.fresh(_ms)
      ..prizes = old?.prizes ?? 0
      ..claimAt = old?.claimAt ?? 0;
    state = HatarakiState(game: game, loaded: true);
    _dirty = true;
    unawaited(save());
  }

  /// Canjea un tesoro de expedición por un ticket gachaken: las reglas dejan
  /// uno por hora, con el ticket subiendo 1 y `prizes` bajando 1 a la vez.
  Future<void> _claimTreasure() async {
    final game = state.game;
    final tickets = _gachakenOf;
    if (game == null || tickets == null || _claiming || game.prizes <= 0) return;
    if (_ms - game.claimAt < hatarakiClaimGap.inMilliseconds) return;
    _claiming = true;
    final account = _session.state.accountId;
    try {
      await save();
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

  /// Escribe la partida entera si hay algo sin guardar.
  Future<void> save() async {
    final game = state.game;
    if (game == null || !_dirty) return;
    _dirty = false;
    _savedAt = _now();
    // Lo de un periodo que ya pasó no cuenta en el nuevo.
    final now = _now();
    final scores = (
      game.day == bonusDay(now) ? math.min(hatarakiMaxScore, game.dayMoney) : 0,
      game.week == gachaWeek(now) ? math.min(hatarakiMaxScore, game.weekMoney) : 0,
      math.min(hatarakiMaxScore, game.earned),
    );
    if (scores != _sentScores && scores.$3 > 0) {
      _sentScores = scores;
      _onScores?.call(scores.$1, scores.$2, scores.$3);
    }
    try {
      await _backend.write(
        _path,
        game.toJson(),
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar Hatarakitama ($e)');
      _dirty = true;
    }
  }

  @override
  void dispose() {
    unawaited(save());
    super.dispose();
  }
}
