// Ibasho — Tsumiki versus: invitar, responder y jugar contra un amigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart' show DatabaseEvent, serverTimestamp;
import '../backend/push_id.dart';
import '../backend/tsumiki_versus.dart';
import '../games/tsumiki/tsumiki_versus.dart';
import 'providers.dart';
import 'session.dart';

/// En qué punto está la sala, visto desde esta cuenta.
enum TsumikiVsPhase {
  /// Sin sala.
  idle,

  /// Mandando la invitación o la respuesta.
  sending,

  /// Esperando a que el otro acepte.
  waiting,

  /// El otro ha dicho que no.
  declined,

  /// Han pasado los 10 minutos.
  expired,

  /// Quien invitaba la ha retirado, o la sala ya es otra.
  cancelled,

  /// En juego.
  playing,

  /// Acabada: mirar [TsumikiVsState.winner].
  done,

  /// No se ha podido escribir.
  failed,
}

@immutable
class TsumikiVsState {
  const TsumikiVsState({
    this.phase = TsumikiVsPhase.idle,
    this.friend,
    this.matchId,
    this.room,
  });

  final TsumikiVsPhase phase;
  final String? friend;

  /// La partida que juega esta cuenta (la sala puede pasar a otra con la
  /// revancha).
  final String? matchId;
  final TsumikiRoom? room;

  String? get winner => room?.id == matchId ? room?.winner : null;

  /// El otro ha mandado una revancha a esta sala y aún no se ha aceptado.
  bool get rematchOffered =>
      room != null && room!.id != matchId && room!.state == TsumikiRoomState.wait && room!.host == friend;

  TsumikiVsState copyWith({
    TsumikiVsPhase? phase,
    String? friend,
    String? matchId,
    TsumikiRoom? room,
  }) =>
      TsumikiVsState(
        phase: phase ?? this.phase,
        friend: friend ?? this.friend,
        matchId: matchId ?? this.matchId,
        room: room ?? this.room,
      );
}

/// La sala de Tsumiki versus. Una sola a la vez: escucha `/tsumiki/{a_b}/live`
/// (una conexión) mientras dura y la suelta con [close].
///
/// La partida la lleva el canal con un `TsumikiDuel`: aquí solo se publica lo
/// propio ([publish], [send], [lose]) y llega lo del otro por [incoming].
class TsumikiVersusController extends StateNotifier<TsumikiVsState> {
  TsumikiVersusController({
    required IbashoBackend backend,
    required SessionController session,
    DateTime Function()? clock,
    math.Random? random,
  })  : _backend = backend,
        _session = session,
        _clock = clock ?? DateTime.now,
        _random = random ?? math.Random(),
        super(const TsumikiVsState());

  /// Cada cuánto se da señal de vida en partida.
  static const Duration heartbeatEvery = Duration(seconds: 5);

  final IbashoBackend _backend;
  final SessionController _session;
  final DateTime Function() _clock;
  final math.Random _random;

  final StreamController<TsumikiVsEvent> _incoming = StreamController<TsumikiVsEvent>.broadcast();
  StreamSubscription<DatabaseEvent>? _watch;
  Object? _tree;
  Timer? _heartbeat;
  final Set<String> _seen = <String>{};
  int? _lastPing;
  DateTime? _lastHeard;
  DateTime? _playStarted;
  bool _finishing = false;

  String get _me => _session.state.accountId;

  /// Lo que manda el otro (filas grises y sabotajes), cada cosa una vez.
  Stream<TsumikiVsEvent> get incoming => _incoming.stream;

  String _room(String friend) => tsumikiRoomPath(_me, friend);

  // --- Invitar y responder -------------------------------------------------

  /// Invita a [friend]: crea la sala en espera y deja la invitación en su
  /// buzón, en la misma escritura.
  Future<bool> invite(String friend) async {
    if (_me.isEmpty || friend == _me) return false;
    final id = generatePushId();
    final pair = tsumikiPairId(_me, friend);
    final (a, b) = _me.compareTo(friend) < 0 ? (_me, friend) : (friend, _me);
    _listen(friend, id, TsumikiVsPhase.sending);
    try {
      await _backend.merge('/', {
        'tsumiki/$pair/a': a,
        'tsumiki/$pair/b': b,
        'tsumiki/$pair/live': {
          'id': id,
          'seed': _random.nextInt(0x7fffffff),
          'host': _me,
          'guest': friend,
          'state': 'wait',
          'at': serverTimestamp,
          'p': {
            _me: {'ping': serverTimestamp},
          },
        },
        'users/$friend/tsumikiInbox/$_me': {'at': serverTimestamp, 'id': id},
      }, idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido mandar la invitación a Tsumiki ($e)');
      if (mounted && state.matchId == id) state = state.copyWith(phase: TsumikiVsPhase.failed);
      return false;
    }
  }

  /// Acepta [invite]: si la sala sigue esperando esa partida, pasa a juego.
  /// Si ya no, tira la invitación y devuelve `false`.
  Future<bool> accept(TsumikiInvite invite) async {
    if (_me.isEmpty) return false;
    final path = _room(invite.from);
    try {
      final token = await _session.freshToken();
      final room = TsumikiRoom.fromJson(await _backend.read('$path/live', idToken: token));
      if (room == null ||
          room.id != invite.id ||
          room.state != TsumikiRoomState.wait ||
          room.guest != _me ||
          !invite.freshAt(_clock())) {
        await _backend.remove('/users/$_me/tsumikiInbox/${invite.from}', idToken: token);
        return false;
      }
      _listen(invite.from, invite.id, TsumikiVsPhase.sending);
      await _backend.merge('/', {
        '${path.substring(1)}/live/state': 'play',
        '${path.substring(1)}/live/start': serverTimestamp,
        '${path.substring(1)}/live/p/$_me': {'ping': serverTimestamp, 'board': ''},
        'users/$_me/tsumikiInbox/${invite.from}': null,
      }, idToken: token);
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido aceptar la partida ($e)');
      if (mounted && state.matchId == invite.id) state = state.copyWith(phase: TsumikiVsPhase.failed);
      return false;
    }
  }

  /// Dice que no a [invite] (y la tira del buzón).
  Future<void> decline(TsumikiInvite invite) async {
    final path = _room(invite.from).substring(1);
    try {
      final token = await _session.freshToken();
      final room = TsumikiRoom.fromJson(await _backend.read('/$path/live', idToken: token));
      await _backend.merge('/', {
        if (room != null && room.id == invite.id && room.state == TsumikiRoomState.wait && room.guest == _me)
          '$path/live/state': 'no',
        'users/$_me/tsumikiInbox/${invite.from}': null,
      }, idToken: token);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido rechazar la partida ($e)');
    }
  }

  /// Quien invita la retira (o se le ha pasado el tiempo).
  Future<void> cancel({bool expired = false}) async {
    final friend = state.friend;
    final room = state.room;
    if (friend == null) return;
    if (room != null && room.id == state.matchId && room.state == TsumikiRoomState.wait && room.host == _me) {
      try {
        await _backend.merge('/', {
          '${_room(friend).substring(1)}/live/state': 'gone',
          'users/$friend/tsumikiInbox/$_me': null,
        }, idToken: await _session.freshToken());
      } catch (e) {
        debugPrint('Ibasho: no se ha podido retirar la invitación ($e)');
      }
    }
    if (mounted) state = state.copyWith(phase: expired ? TsumikiVsPhase.expired : TsumikiVsPhase.cancelled);
  }

  /// Revancha: si el otro ya la ha pedido, se acepta; si no, se le invita.
  Future<bool> rematch() async {
    final friend = state.friend;
    if (friend == null) return false;
    final room = state.room;
    if (state.rematchOffered) {
      return accept(TsumikiInvite(from: friend, id: room!.id, at: DateTime.fromMillisecondsSinceEpoch(room.at)));
    }
    return invite(friend);
  }

  // --- En partida ------------------------------------------------------------

  /// Publica lo propio: el tablero y los números, con señal de vida.
  Future<void> publish({
    required String board,
    required int lines,
    required int sent,
    required double meter,
    Set<TsumikiSabotage> fx = const <TsumikiSabotage>{},
  }) async {
    final friend = state.friend;
    if (friend == null || state.phase != TsumikiVsPhase.playing) return;
    try {
      await _backend.write('${_room(friend)}/live/p/$_me', {
        'board': board,
        'ping': serverTimestamp,
        'lines': lines,
        'sent': sent,
        'meter': (meter * 10).round() / 10,
        'over': false,
        'fx': {for (final s in fx) s.name: true},
      }, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido publicar el tablero ($e)');
    }
  }

  /// Manda al otro unas filas grises o un sabotaje.
  Future<void> send(TsumikiVsEvent event) async {
    final friend = state.friend;
    if (friend == null || state.phase != TsumikiVsPhase.playing) return;
    try {
      await _backend.write('${_room(friend)}/live/atk/$_me/${generatePushId()}', event.toJson(),
          idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido mandar el ataque ($e)');
    }
  }

  /// Me he llenado: gana el otro.
  Future<bool> lose({required int lines, required int sent}) =>
      _finish(winner: state.friend!, end: TsumikiEnd.top, lines: lines, sent: sent);

  /// Me voy a media partida: gana el otro.
  Future<bool> leave({int lines = 0, int sent = 0}) =>
      _finish(winner: state.friend!, end: TsumikiEnd.leave, lines: lines, sent: sent);

  /// Da señal de vida y mira si el otro sigue: tras [tsumikiQuitAfter] sin
  /// saber de él, gano por abandono. Lo llama un temporizador en partida.
  Future<void> heartbeat({int lines = 0, int sent = 0}) async {
    final friend = state.friend;
    if (friend == null || state.phase != TsumikiVsPhase.playing) return;
    final heard = _lastHeard;
    if (heard != null && _clock().difference(heard) > tsumikiQuitAfter) {
      await _finish(winner: _me, end: TsumikiEnd.quit, lines: lines, sent: sent);
      return;
    }
    try {
      await _backend.write('${_room(friend)}/live/p/$_me/ping', serverTimestamp, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: sin señal de vida en Tsumiki ($e)');
    }
  }

  /// Escribe el final: resultado, historial y marcador a la vez. Si el otro
  /// ya lo había escrito, las reglas lo rechazan y vale el suyo.
  Future<bool> _finish({required String winner, required TsumikiEnd end, required int lines, required int sent}) async {
    final friend = state.friend;
    final room = state.room;
    if (friend == null || room == null || room.id != state.matchId || room.state != TsumikiRoomState.play) return false;
    if (_finishing) return false;
    _finishing = true;
    final base = _room(friend).substring(1);
    try {
      final token = await _session.freshToken();
      final had = await _backend.read('/$base/score/$winner', idToken: token);
      final other = room.seat(friend);
      final started = _playStarted ?? _clock();
      await _backend.merge('/', {
        '$base/live/result': {'w': winner, 'why': end.name, 'at': serverTimestamp},
        '$base/live/state': 'done',
        '$base/history/${room.id}': {
          'w': winner,
          'why': end.name,
          'at': serverTimestamp,
          'dur': _clock().difference(started).inSeconds.clamp(0, 86400),
          's': {_me: sent, friend: other.sent},
          'l': {_me: lines, friend: other.lines},
        },
        '$base/score/$winner': (had is num ? had.toInt() : 0) + 1,
      }, idToken: token);
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cerrar la partida ($e)');
      return false;
    } finally {
      _finishing = false;
    }
  }

  // --- La sala ---------------------------------------------------------------

  void _listen(String friend, String matchId, TsumikiVsPhase phase) {
    final sameRoom = state.friend == friend && _watch != null;
    _seen.clear();
    _lastPing = null;
    _lastHeard = null;
    _playStarted = null;
    state = TsumikiVsState(phase: phase, friend: friend, matchId: matchId, room: sameRoom ? state.room : null);
    if (sameRoom) return;
    unawaited(_watch?.cancel());
    _tree = null;
    _watch = _backend
        .watch('${_room(friend)}/live', token: _session.freshToken)
        .listen((event) {
      _tree = applyDatabaseEvent(_tree, event);
      _onRoom(TsumikiRoom.fromJson(_tree));
    }, onError: (Object e) => debugPrint('Ibasho: la sala de Tsumiki se ha cortado ($e)'));
  }

  void _onRoom(TsumikiRoom? room) {
    if (!mounted || room == null) return;
    final mine = room.id == state.matchId;
    var phase = state.phase;
    if (mine) {
      phase = switch (room.state) {
        TsumikiRoomState.wait => room.host == _me ? TsumikiVsPhase.waiting : TsumikiVsPhase.sending,
        TsumikiRoomState.play => TsumikiVsPhase.playing,
        TsumikiRoomState.done => TsumikiVsPhase.done,
        TsumikiRoomState.no => TsumikiVsPhase.declined,
        TsumikiRoomState.gone => state.phase == TsumikiVsPhase.expired ? TsumikiVsPhase.expired : TsumikiVsPhase.cancelled,
      };
    } else if (phase != TsumikiVsPhase.done && phase != TsumikiVsPhase.sending) {
      // Otra partida ha pisado la sala sin que fuera la nuestra.
      phase = TsumikiVsPhase.cancelled;
    }
    if (phase == TsumikiVsPhase.playing) _onPlaying(room);
    if (phase != TsumikiVsPhase.playing) _stopHeartbeat();
    state = state.copyWith(phase: phase, room: room);
  }

  void _onPlaying(TsumikiRoom room) {
    final friend = room.other(_me);
    final now = _clock();
    _playStarted ??= now;
    _lastHeard ??= now;
    final ping = room.seat(friend).ping;
    if (ping != null && ping != _lastPing) {
      _lastPing = ping;
      _lastHeard = now;
    }
    for (final (key, event) in room.events[friend] ?? const <(String, TsumikiVsEvent)>[]) {
      if (_seen.add(key)) _incoming.add(event);
    }
    _heartbeat ??= Timer.periodic(heartbeatEvery, (_) => unawaited(heartbeat()));
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Si la invitación propia lleva más de 10 minutos esperando, la retira.
  /// La pantalla de espera lo mira con su reloj.
  Future<void> checkExpiry() async {
    final room = state.room;
    if (state.phase != TsumikiVsPhase.waiting || room == null) return;
    if (_clock().millisecondsSinceEpoch - room.at > tsumikiInviteTtl.inMilliseconds) {
      state = state.copyWith(phase: TsumikiVsPhase.expired);
      await cancel(expired: true);
    }
  }

  /// Sale de la sala: retira la invitación si esperaba, se rinde si jugaba y
  /// deja de escuchar.
  Future<void> close({int lines = 0, int sent = 0}) async {
    if (state.phase == TsumikiVsPhase.waiting) await cancel();
    if (state.phase == TsumikiVsPhase.playing) await leave(lines: lines, sent: sent);
    _stopHeartbeat();
    // Sin esperar: tras cancelar ya no llega nada y la pantalla vuelve ya.
    unawaited(_watch?.cancel());
    _watch = null;
    _tree = null;
    if (mounted) state = const TsumikiVsState();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    unawaited(_watch?.cancel());
    unawaited(_incoming.close());
    super.dispose();
  }
}

final tsumikiVersusProvider = StateNotifierProvider<TsumikiVersusController, TsumikiVsState>(
  (ref) => TsumikiVersusController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  ),
);

/// Las invitaciones del buzón que no han caducado. Salen de la conexión de
/// la cuenta; cada minuto se vuelve a mirar cuáles siguen vivas.
final tsumikiInvitesProvider = StreamProvider<List<TsumikiInvite>>((ref) async* {
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  final active = ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  if (me.isEmpty || !active) {
    yield const <TsumikiInvite>[];
    return;
  }
  final out = StreamController<List<TsumikiInvite>>();
  Object? tree;
  void emit() => out.add(TsumikiInvite.listFrom(tree, now: DateTime.now()));
  final sub = ref
      .read(backendProvider)
      .watch('/users/$me/tsumikiInbox', token: ref.read(sessionProvider.notifier).freshToken)
      .listen((event) {
    tree = applyDatabaseEvent(tree, event);
    emit();
  }, onError: (Object _) {});
  final tick = Timer.periodic(const Duration(minutes: 1), (_) => emit());
  ref.onDispose(() {
    tick.cancel();
    unawaited(sub.cancel());
    unawaited(out.close());
  });
  yield* out.stream;
});

/// Invitaciones sin responder: la insignia del canal de Tsumiki.
final pendingTsumikiInvitesProvider =
    Provider<int>((ref) => ref.watch(tsumikiInvitesProvider).valueOrNull?.length ?? 0);

/// Las partidas con [friend], la más nueva primero. Se lee al abrirlo.
final tsumikiHistoryProvider = FutureProvider.autoDispose.family<List<TsumikiMatchRecord>, String>((ref, friend) async {
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  if (me.isEmpty) return const <TsumikiMatchRecord>[];
  final raw = await ref.read(backendProvider).read('${tsumikiRoomPath(me, friend)}/history',
      idToken: await ref.read(sessionProvider.notifier).freshToken());
  return TsumikiMatchRecord.listFrom(raw);
});

/// El marcador con [friend]: lo que se pinta en su ficha y en la lista.
final tsumikiScoreProvider = FutureProvider.autoDispose.family<TsumikiScore, String>((ref, friend) async {
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  if (me.isEmpty) return const TsumikiScore();
  try {
    final raw = await ref.read(backendProvider).read('${tsumikiRoomPath(me, friend)}/score',
        idToken: await ref.read(sessionProvider.notifier).freshToken());
    return TsumikiScore.fromJson(raw, me: me, friend: friend);
  } catch (_) {
    return const TsumikiScore();
  }
});
