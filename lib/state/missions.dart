// Ibasho — las misiones diarias y semanales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/gacha.dart';
import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/missions.dart';
import '../backend/models.dart';
import 'session.dart';

const int _dayMs = 86400000;
const int _weekMs = 604800000;

@immutable
class MissionsState {
  const MissionsState({
    this.signals = const <MissionEvent, DateTime>{},
    this.dailyClaims = const <int, Set<MissionEvent>>{},
    this.weeklyClaims = const <int, Set<WeeklyMission>>{},
    this.tallies = const <MissionEvent, (int, int)>{},
    this.repeatClaims = const <int, Map<RepeatMission, int>>{},
    this.loaded = false,
  });

  /// Ultima vez que paso cada señal (dio de comer, jugo una partida, tiro del
  /// gacha, compro algo), en cualquier dia.
  final Map<MissionEvent, DateTime> signals;

  /// Misiones diarias ya cobradas, por dia UTC.
  final Map<int, Set<MissionEvent>> dailyClaims;

  /// Misiones semanales ya cobradas, por semana UTC.
  final Map<int, Set<WeeklyMission>> weeklyClaims;

  /// Cuantas veces ha pasado cada señal en una semana: `(semana, veces)`.
  /// Solo se guarda la semana de la ultima vez.
  final Map<MissionEvent, (int, int)> tallies;

  /// Cuantas veces se ha cobrado cada repetible, por semana UTC.
  final Map<int, Map<RepeatMission, int>> repeatClaims;

  final bool loaded;

  bool _within(MissionEvent event, int start, int ms) {
    final at = signals[event];
    return at != null && at.millisecondsSinceEpoch >= start && at.millisecondsSinceEpoch < start + ms;
  }

  bool doneToday(MissionEvent event, int day) => _within(event, day * _dayMs, _dayMs);

  bool doneThisWeek(MissionEvent event, int week) => _within(event, week * _weekMs, _weekMs);

  bool claimedDaily(MissionEvent event, int day) => dailyClaims[day]?.contains(event) ?? false;

  bool claimedWeekly(WeeklyMission mission, int week) => weeklyClaims[week]?.contains(mission) ?? false;

  /// Veces que ha pasado [event] en la semana [week].
  int tally(MissionEvent event, int week) {
    final t = tallies[event];
    return t != null && t.$1 == week ? t.$2 : 0;
  }

  /// Veces cobrada [mission] en la semana [week].
  int repeatsClaimed(RepeatMission mission, int week) => repeatClaims[week]?[mission] ?? 0;

  /// Se puede cobrar otra vez [mission] esta semana.
  bool canClaimRepeat(RepeatMission mission, int week) {
    final claimed = repeatsClaimed(mission, week);
    return claimed < repeatMissionTimes && tally(mission.event, week) >= (claimed + 1) * mission.step;
  }

  MissionsState copyWith({
    Map<MissionEvent, DateTime>? signals,
    Map<int, Set<MissionEvent>>? dailyClaims,
    Map<int, Set<WeeklyMission>>? weeklyClaims,
    Map<MissionEvent, (int, int)>? tallies,
    Map<int, Map<RepeatMission, int>>? repeatClaims,
    bool? loaded,
  }) =>
      MissionsState(
        signals: signals ?? this.signals,
        dailyClaims: dailyClaims ?? this.dailyClaims,
        weeklyClaims: weeklyClaims ?? this.weeklyClaims,
        tallies: tallies ?? this.tallies,
        repeatClaims: repeatClaims ?? this.repeatClaims,
        loaded: loaded ?? this.loaded,
      );
}

/// Las señales y los cobros de misiones de la cuenta.
class MissionsController extends StateNotifier<MissionsState> {
  MissionsController({
    required IbashoBackend backend,
    required SessionController session,
    required int Function(TicketKind) ticketsOf,
  })  : _backend = backend,
        _session = session,
        _ticketsOf = ticketsOf,
        super(const MissionsState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    } else {
      _ready.complete();
    }
  }

  /// Se completa al acabar la primera lectura, salga bien o mal: los
  /// recuentos no se pueden sumar sin saber por donde iban.
  final Completer<void> _ready = Completer<void>();

  final IbashoBackend _backend;
  final SessionController _session;

  /// Tickets guardados ahora mismo (los lee de `gachaProvider`): hace falta
  /// para que el cobro escriba el total nuevo, no solo el incremento.
  final int Function(TicketKind) _ticketsOf;

  StreamSubscription<DatabaseEvent>? _watch;
  Object? _tree;

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final raw = await _backend.read('/users/$_me/missions', idToken: await _session.freshToken());
      _tree = raw;
      if (mounted) state = _parse(raw);
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer las misiones ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    _ready.complete();
    if (!mounted) return;
    _watch = _backend.watch('/users/$_me/missions', token: _session.freshToken).listen((event) {
      _tree = applyDatabaseEvent(_tree, event);
      if (mounted) state = _parse(_tree);
    }, onError: (Object e) => debugPrint('Ibasho: stream de misiones ($e)'));
  }

  static MissionsState _parse(Object? raw) {
    if (raw is! Map) return const MissionsState(loaded: true);
    final signals = <MissionEvent, DateTime>{};
    final signalsRaw = raw['signal'];
    if (signalsRaw is Map) {
      for (final e in MissionEvent.values) {
        final at = (signalsRaw[e.name] as Map?)?['at'];
        if (at is num) signals[e] = DateTime.fromMillisecondsSinceEpoch(at.toInt());
      }
    }
    final dailyClaims = <int, Set<MissionEvent>>{};
    final dailyRaw = raw['daily'];
    if (dailyRaw is Map) {
      for (final dayEntry in dailyRaw.entries) {
        final day = int.tryParse('${dayEntry.key}');
        final claims = dayEntry.value;
        if (day == null || claims is! Map) continue;
        dailyClaims[day] = {
          for (final e in MissionEvent.values)
            if (claims.containsKey(e.name)) e,
        };
      }
    }
    final weeklyClaims = <int, Set<WeeklyMission>>{};
    final weeklyRaw = raw['weekly'];
    if (weeklyRaw is Map) {
      for (final weekEntry in weeklyRaw.entries) {
        final week = int.tryParse('${weekEntry.key}');
        final claims = weekEntry.value;
        if (week == null || claims is! Map) continue;
        weeklyClaims[week] = {
          for (final m in WeeklyMission.values)
            if (claims.containsKey(m.event.name)) m,
        };
      }
    }
    final tallies = <MissionEvent, (int, int)>{};
    final tallyRaw = raw['tally'];
    if (tallyRaw is Map) {
      for (final e in MissionEvent.values) {
        final t = tallyRaw[e.name];
        if (t is! Map) continue;
        final week = t['week'];
        final n = t['n'];
        if (week is num && n is num) tallies[e] = (week.toInt(), n.toInt());
      }
    }
    final repeatClaims = <int, Map<RepeatMission, int>>{};
    final repeatRaw = raw['repeat'];
    if (repeatRaw is Map) {
      for (final weekEntry in repeatRaw.entries) {
        final week = int.tryParse('${weekEntry.key}');
        final claims = weekEntry.value;
        if (week == null || claims is! Map) continue;
        repeatClaims[week] = {
          for (final m in RepeatMission.values)
            if (claims[m.event.name] is num) m: (claims[m.event.name] as num).toInt(),
        };
      }
    }
    return MissionsState(
      signals: signals,
      dailyClaims: dailyClaims,
      weeklyClaims: weeklyClaims,
      tallies: tallies,
      repeatClaims: repeatClaims,
      loaded: true,
    );
  }

  /// Marca que ha pasado [event] ahora mismo, y lo suma al recuento de la
  /// semana. Sin bloquear ni avisar si falla: se reintenta solo la proxima
  /// vez que pase.
  ///
  /// Van de una en una: el recuento se escribe como total y las reglas
  /// exigen que suba justo 1, asi que dos a la vez se pisarian.
  Future<void> mark(MissionEvent event) {
    final next = _marks.then((_) => _mark(event));
    _marks = next;
    return next;
  }

  Future<void> _marks = Future<void>.value();

  Future<void> _mark(MissionEvent event) async {
    await _ready.future;
    if (!mounted) return;
    final week = gachaWeek();
    final n = state.tally(event, week) + 1;
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/missions/signal/${event.name}': {'at': serverTimestamp},
          'users/$_me/missions/tally/${event.name}': {'week': week, 'n': n, 'at': serverTimestamp},
        },
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      // Con un recuento que no cuadra (u otras reglas sin recuentos), al
      // menos la señal: las diarias y las semanales de una vez siguen
      // contando.
      debugPrint('Ibasho: no se ha podido sumar al recuento de ${event.name} ($e)');
      try {
        await _backend.write(
          '/users/$_me/missions/signal/${event.name}',
          {'at': serverTimestamp},
          idToken: await _session.freshToken(),
        );
      } catch (e) {
        debugPrint('Ibasho: no se ha podido apuntar la señal de ${event.name} ($e)');
        return;
      }
      if (mounted) state = state.copyWith(signals: {...state.signals, event: DateTime.now()});
      return;
    }
    if (mounted) {
      state = state.copyWith(
        signals: {...state.signals, event: DateTime.now()},
        tallies: {...state.tallies, event: (week, n)},
      );
    }
  }

  /// Cobra la mision diaria de [event] del dia [day]. `false` si no se puede
  /// (no cumplida, ya cobrada o rechazada).
  ///
  /// Escribe un unico recibo (`missions/claim`, como `shop/last`/`gacha/last`)
  /// ademas del sello de "ya cobrada" (`missions/daily/$day/$event`): las
  /// reglas no pueden calcular el dia de hoy con un `floor`, asi que el sello
  /// remite siempre al recibo fresco de al lado para saber que vale.
  Future<bool> claimDaily(MissionEvent event, int day) async {
    if (!state.doneToday(event, day) || state.claimedDaily(event, day)) return false;
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/missions/claim': {
            'kind': 'daily',
            'event': event.name,
            'day': day,
            'amount': dailyMissionReward,
            'ticketKind': TicketKind.gachaken.name,
            'at': serverTimestamp,
          },
          'users/$_me/missions/daily/$day/${event.name}': true,
          'users/$_me/tickets/${TicketKind.gachaken.name}': _ticketsOf(TicketKind.gachaken) + dailyMissionReward,
        },
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar la mision de ${event.name} ($e)');
      return false;
    }
    if (mounted) {
      state = state.copyWith(dailyClaims: {
        ...state.dailyClaims,
        day: {...?state.dailyClaims[day], event},
      });
    }
    return true;
  }

  /// Cobra la mision semanal [mission] de la semana [week].
  Future<bool> claimWeekly(WeeklyMission mission, int week) async {
    if (!state.doneThisWeek(mission.event, week) || state.claimedWeekly(mission, week)) return false;
    final (kind, amount) = weeklyMissionReward[mission]!;
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/missions/claim': {
            'kind': 'weekly',
            'event': mission.event.name,
            'week': week,
            'amount': amount,
            'ticketKind': kind.name,
            'at': serverTimestamp,
          },
          'users/$_me/missions/weekly/$week/${mission.event.name}': true,
          'users/$_me/tickets/${kind.name}': _ticketsOf(kind) + amount,
        },
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar la mision semanal de ${mission.name} ($e)');
      return false;
    }
    if (mounted) {
      state = state.copyWith(weeklyClaims: {
        ...state.weeklyClaims,
        week: {...?state.weeklyClaims[week], mission},
      });
    }
    return true;
  }

  /// Cobra otra vez la repetible [mission] de la semana [week].
  Future<bool> claimRepeat(RepeatMission mission, int week) async {
    if (!state.canClaimRepeat(mission, week)) return false;
    final count = state.repeatsClaimed(mission, week) + 1;
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/missions/claim': {
            'kind': 'repeat',
            'event': mission.event.name,
            'week': week,
            'amount': repeatMissionReward,
            'ticketKind': TicketKind.gachaken.name,
            'at': serverTimestamp,
          },
          'users/$_me/missions/repeat/$week/${mission.event.name}': count,
          'users/$_me/tickets/${TicketKind.gachaken.name}': _ticketsOf(TicketKind.gachaken) + repeatMissionReward,
        },
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar la repetible de ${mission.name} ($e)');
      return false;
    }
    if (mounted) {
      state = state.copyWith(repeatClaims: {
        ...state.repeatClaims,
        week: {...?state.repeatClaims[week], mission: count},
      });
    }
    return true;
  }
}
