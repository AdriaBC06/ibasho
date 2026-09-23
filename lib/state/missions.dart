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
    this.loaded = false,
  });

  /// Ultima vez que paso cada señal (dio de comer, jugo una partida, tiro del
  /// gacha, compro algo), en cualquier dia.
  final Map<MissionEvent, DateTime> signals;

  /// Misiones diarias ya cobradas, por dia UTC.
  final Map<int, Set<MissionEvent>> dailyClaims;

  /// Misiones semanales ya cobradas, por semana UTC.
  final Map<int, Set<WeeklyMission>> weeklyClaims;

  final bool loaded;

  bool _within(MissionEvent event, int start, int ms) {
    final at = signals[event];
    return at != null && at.millisecondsSinceEpoch >= start && at.millisecondsSinceEpoch < start + ms;
  }

  bool doneToday(MissionEvent event, int day) => _within(event, day * _dayMs, _dayMs);

  bool doneThisWeek(MissionEvent event, int week) => _within(event, week * _weekMs, _weekMs);

  bool claimedDaily(MissionEvent event, int day) => dailyClaims[day]?.contains(event) ?? false;

  bool claimedWeekly(WeeklyMission mission, int week) => weeklyClaims[week]?.contains(mission) ?? false;

  MissionsState copyWith({
    Map<MissionEvent, DateTime>? signals,
    Map<int, Set<MissionEvent>>? dailyClaims,
    Map<int, Set<WeeklyMission>>? weeklyClaims,
    bool? loaded,
  }) =>
      MissionsState(
        signals: signals ?? this.signals,
        dailyClaims: dailyClaims ?? this.dailyClaims,
        weeklyClaims: weeklyClaims ?? this.weeklyClaims,
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
    }
  }

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
    return MissionsState(signals: signals, dailyClaims: dailyClaims, weeklyClaims: weeklyClaims, loaded: true);
  }

  /// Marca que ha pasado [event] ahora mismo. Sin bloquear ni avisar si
  /// falla: se reintenta solo la proxima vez que pase.
  Future<void> mark(MissionEvent event) async {
    try {
      await _backend.write(
        '/users/$_me/missions/signal/${event.name}',
        {'at': serverTimestamp},
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido apuntar la señal de ${event.name} ($e)');
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
}
