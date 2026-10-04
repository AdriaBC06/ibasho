// Ibasho — Malla online: crear, entrar, invitar y jugar una sala.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/malla.dart';
import '../backend/models.dart' show DatabaseEvent, serverTimestamp;
import '../games/malla/malla_game.dart';
import 'providers.dart';
import 'session.dart';

/// En qué punto está la sala, vista desde esta cuenta.
enum MallaPhase {
  /// Sin sala.
  idle,

  /// Creando o entrando.
  joining,

  /// En la sala, esperando a empezar.
  lobby,

  /// En partida.
  playing,

  /// Acabada.
  done,

  /// Quien la creó la ha cerrado antes de empezar.
  closed,
}

/// Por qué no se ha podido entrar.
enum MallaProblem { notFound, full, started, network, broken }

@immutable
class MallaOnlineState {
  const MallaOnlineState({
    this.phase = MallaPhase.idle,
    this.code,
    this.room,
    this.game,
    this.problem,
    this.busy = false,
  });

  final MallaPhase phase;
  final String? code;
  final MallaRoom? room;

  /// La partida rejugada, desde que empieza.
  final MallaGame? game;
  final MallaProblem? problem;

  /// Hay una escritura en camino (una jugada, empezar…).
  final bool busy;

  MallaOnlineState copyWith({
    MallaPhase? phase,
    MallaRoom? room,
    MallaGame? game,
    MallaProblem? problem,
    bool clearProblem = false,
    bool? busy,
  }) =>
      MallaOnlineState(
        phase: phase ?? this.phase,
        code: code,
        room: room ?? this.room,
        game: game ?? this.game,
        problem: clearProblem ? null : (problem ?? this.problem),
        busy: busy ?? this.busy,
      );
}

/// Lo que se pone en la sala de uno mismo: nombre, Tama, marca y color.
@immutable
class MallaIdentity {
  const MallaIdentity({required this.name, required this.marker, required this.color, this.tama});

  final String name;
  final String marker;
  final String color;
  final MallaTama? tama;

  Map<String, Object?> toJson() => {
        'name': name.length > 24 ? name.substring(0, 24) : name,
        'marker': marker,
        'color': color,
        if (tama != null) 'tama': tama!.toJson(),
      };
}

/// Lo que se cobra al acabar: lo llama la pantalla, que es quien enseña el
/// premio.
typedef MallaFinished = void Function(MallaRecord record);

/// La sala de Malla. Una sola a la vez: escucha `/malla/{código}` por el
/// socket compartido (ninguna conexión nueva) mientras dura y la suelta con
/// [close].
class MallaOnlineController extends StateNotifier<MallaOnlineState> {
  MallaOnlineController({
    required IbashoBackend backend,
    required SessionController session,
    DateTime Function()? clock,
    math.Random? random,
  })  : _backend = backend,
        _session = session,
        _clock = clock ?? DateTime.now,
        _random = random ?? math.Random(),
        super(const MallaOnlineState());

  final IbashoBackend _backend;
  final SessionController _session;
  final DateTime Function() _clock;
  final math.Random _random;

  StreamSubscription<DatabaseEvent>? _watch;
  Object? _tree;
  Timer? _heartbeat;

  /// La última señal vista de cada cuenta y cuándo llegó, con el reloj de
  /// aquí: así no importa que el del servidor vaya distinto.
  final Map<String, int?> _lastPing = <String, int?>{};
  final Map<String, DateTime> _heard = <String, DateTime>{};
  final Set<String> _recorded = <String>{};

  /// Lo último que se ha puesto de uno mismo: para entrar solo en la
  /// revancha.
  MallaIdentity? _identity;

  /// A quien le avisa de que la partida ha acabado (para cobrar y guardar).
  MallaFinished? onFinished;

  String get _me => _session.state.accountId;

  /// Mi asiento en la partida, o -1.
  int get seat => state.room?.seatOf(_me) ?? -1;

  bool get isHost => state.room?.host == _me;

  // --- Crear, entrar, invitar ----------------------------------------------

  /// Crea una sala nueva y entra en ella. Prueba otro código si el primero
  /// está cogido.
  Future<bool> create({required int size, required int max, required bool chain, required MallaIdentity me}) async {
    if (_me.isEmpty) return false;
    _identity = me;
    for (var attempt = 0; attempt < 4; attempt++) {
      final code = generateMallaCode(_random);
      _listen(code, MallaPhase.joining);
      try {
        await _backend.write(mallaRoomPath(code), {
          'host': _me,
          'at': serverTimestamp,
          'size': size,
          'max': max,
          'chain': chain,
          'state': 'wait',
          'count': 1,
          'members': {
            _me: {...me.toJson(), 'at': serverTimestamp, 'ping': serverTimestamp},
          },
        }, idToken: await _session.freshToken());
        return true;
      } catch (e) {
        debugPrint('Ibasho: no se ha podido crear la sala de Malla $code ($e)');
      }
    }
    _stop();
    if (mounted) state = const MallaOnlineState(problem: MallaProblem.network);
    return false;
  }

  /// Entra en la sala [code]. Si ya estaba dentro (al volver a abrir la
  /// app), solo vuelve a escucharla.
  Future<bool> join(String code, {required MallaIdentity me}) async {
    if (_me.isEmpty || !mallaCodePattern.hasMatch(code)) {
      state = const MallaOnlineState(problem: MallaProblem.notFound);
      return false;
    }
    _identity = me;
    state = MallaOnlineState(phase: MallaPhase.joining, code: code);
    for (var attempt = 0; attempt < 3; attempt++) {
      MallaRoom? room;
      try {
        final token = await _session.freshToken();
        room = MallaRoom.fromJson(code, await _backend.read(mallaRoomPath(code), idToken: token));
      } catch (e) {
        // Una sala empezada sin mí no se puede leer.
        debugPrint('Ibasho: no se ha podido leer la sala de Malla $code ($e)');
        return _fail(MallaProblem.started);
      }
      if (room == null || room.phase == MallaRoomPhase.gone) return _fail(MallaProblem.notFound);
      if (room.members.containsKey(_me)) {
        if (room.phase == MallaRoomPhase.wait || room.seatOf(_me) >= 0) {
          _listen(code, MallaPhase.joining);
          return true;
        }
        return _fail(MallaProblem.started);
      }
      if (room.phase != MallaRoomPhase.wait) return _fail(MallaProblem.started);
      if (room.full) return _fail(MallaProblem.full);
      try {
        _listen(code, MallaPhase.joining);
        await _backend.merge('/', {
          'malla/$code/members/$_me': {...me.toJson(), 'at': serverTimestamp, 'ping': serverTimestamp},
          'malla/$code/count': room.members.length + 1,
        }, idToken: await _session.freshToken());
        return true;
      } catch (e) {
        // Otro ha entrado a la vez: se vuelve a mirar.
        debugPrint('Ibasho: no se ha podido entrar en la sala de Malla ($e)');
      }
    }
    return _fail(MallaProblem.full);
  }

  bool _fail(MallaProblem problem) {
    _stop();
    if (mounted) state = MallaOnlineState(problem: problem);
    return false;
  }

  /// Cambia la marca o el color propios mientras se espera.
  Future<void> updateMe(MallaIdentity me) async {
    final code = state.code;
    if (code == null || state.phase != MallaPhase.lobby) return;
    _identity = me;
    try {
      await _backend.merge('/', {
        for (final e in me.toJson().entries) 'malla/$code/members/$_me/${e.key}': e.value,
      }, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cambiar la marca en Malla ($e)');
    }
  }

  /// Deja el código en el buzón de [friend].
  Future<bool> invite(String friend) async {
    final code = state.code;
    if (code == null || friend == _me) return false;
    try {
      await _backend.write('/users/$friend/mallaInbox/$_me', {'at': serverTimestamp, 'code': code},
          idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido invitar a Malla ($e)');
      return false;
    }
  }

  /// Tira una invitación del buzón propio (al entrar o al rechazarla).
  Future<void> dropInvite(MallaInvite invite) async {
    try {
      await _backend.remove('/users/$_me/mallaInbox/${invite.from}', idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido tirar la invitación de Malla ($e)');
    }
  }

  // --- Partida ---------------------------------------------------------------

  /// Quien creó la sala la empieza con los que hay (dos o más).
  Future<bool> start() async {
    final room = state.room;
    final code = state.code;
    if (room == null || code == null || !isHost || room.phase != MallaRoomPhase.wait) return false;
    final seats = room.seats;
    if (seats.length < 2) return false;
    final first = _random.nextInt(seats.length);
    return _send({
      'malla/$code/state': 'play',
      'malla/$code/order': {for (var i = 0; i < seats.length; i++) '$i': seats[i].account},
      'malla/$code/start': first,
      'malla/$code/startAt': serverTimestamp,
      'malla/$code/turn': first,
      'malla/$code/n': 0,
    });
  }

  /// Juega la arista [key] si me toca. La partida se rejuega aquí antes de
  /// mandarla: el turno siguiente y el final salen de ella.
  Future<bool> play(String key) async {
    final room = state.room;
    final code = state.code;
    final game = state.game;
    final mine = seat;
    if (room == null || code == null || game == null || state.busy) return false;
    if (room.phase != MallaRoomPhase.play || game.finished || game.currentPlayer != mine || room.turn != mine) {
      return false;
    }
    final next = game.clone();
    if (!next.applyMove(key, mine).accepted) return false;
    return _send({
      'malla/$code/moves/${room.n}': {'k': key, 'p': mine},
      'malla/$code/n': room.n + 1,
      'malla/$code/turn': next.currentPlayer,
      if (next.finished) 'malla/$code/state': 'done',
    });
  }

  /// Deja fuera a [out] (yo al irme, u otro sin señal).
  Future<bool> _out(int out) async {
    final room = state.room;
    final code = state.code;
    final game = state.game;
    if (room == null || code == null || game == null || room.phase != MallaRoomPhase.play) return false;
    if (game.finished || game.out.contains(out)) return false;
    final next = game.clone()..applyOut(out);
    return _send({
      'malla/$code/moves/${room.n}': {'o': out},
      'malla/$code/n': room.n + 1,
      'malla/$code/turn': next.currentPlayer,
      if (next.finished) 'malla/$code/state': 'done',
    });
  }

  Future<bool> _send(Map<String, Object?> update) async {
    if (mounted) state = state.copyWith(busy: true);
    try {
      await _backend.merge('/', update, idToken: await _session.freshToken());
      return true;
    } catch (e) {
      // Lo normal: otro ha escrito antes (n ya no es el mismo). Lo suyo llega
      // por la escucha y se vuelve a intentar con la sala nueva.
      debugPrint('Ibasho: no se ha podido escribir en Malla ($e)');
      return false;
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Revancha: quien creó la sala abre otra igual y la apunta en esta; los
  /// demás entran solos al verla.
  Future<bool> rematch({required MallaIdentity me}) async {
    final room = state.room;
    final old = state.code;
    if (room == null || old == null || !isHost || room.phase != MallaRoomPhase.done) return false;
    final players = room.order.length;
    if (!await create(size: room.size, max: math.max(room.max, players), chain: room.chain, me: me)) return false;
    final code = state.code!;
    try {
      await _backend.write('${mallaRoomPath(old)}/next', code, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido apuntar la revancha de Malla ($e)');
    }
    return true;
  }

  // --- Señales de vida ---------------------------------------------------

  /// Da señal de vida y mira quién lleva demasiado sin darla. Lo llama un
  /// temporizador mientras hay sala.
  Future<void> heartbeat() async {
    final code = state.code;
    final room = state.room;
    if (code == null || room == null) return;
    if (room.phase == MallaRoomPhase.play) {
      final game = state.game;
      if (game != null && !game.finished && !game.out.contains(seat)) {
        final now = _clock();
        for (var i = 0; i < room.order.length; i++) {
          final heard = _heard[room.order[i]];
          if (i == seat || game.out.contains(i) || heard == null) continue;
          if (now.difference(heard) > mallaGoneAfter) {
            await _out(i);
            break;
          }
        }
      }
    }
    if (room.phase != MallaRoomPhase.wait && room.phase != MallaRoomPhase.play) return;
    try {
      await _backend.write('${mallaRoomPath(code)}/members/$_me/ping', serverTimestamp,
          idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: sin señal de vida en Malla ($e)');
    }
  }

  // --- La sala ---------------------------------------------------------------

  void _listen(String code, MallaPhase phase) {
    if (state.code == code && _watch != null) {
      state = state.copyWith(phase: phase, clearProblem: true);
      return;
    }
    _stop();
    _lastPing.clear();
    _heard.clear();
    state = MallaOnlineState(phase: phase, code: code);
    _watch = _backend.watch(mallaRoomPath(code), token: _session.freshToken).listen((event) {
      _tree = applyDatabaseEvent(_tree, event);
      _onRoom(code, MallaRoom.fromJson(code, _tree));
    }, onError: (Object e) {
      debugPrint('Ibasho: la sala de Malla se ha cortado ($e)');
      // Sin permiso para leerla: ha empezado sin mí.
      if (mounted && state.code == code && (state.phase == MallaPhase.lobby || state.phase == MallaPhase.joining)) {
        _stop();
        state = const MallaOnlineState(problem: MallaProblem.started);
      }
    });
    _heartbeat = Timer.periodic(mallaPingEvery, (_) => unawaited(heartbeat()));
  }

  void _onRoom(String code, MallaRoom? room) {
    if (!mounted || state.code != code) return;
    if (room == null) {
      // Borrada: si se estaba jugando o ya había acabado, se queda lo último.
      // Mientras se entra no cuenta: la primera respuesta de la escucha
      // puede llegar antes que la escritura que crea la sala.
      if (state.phase == MallaPhase.lobby) {
        state = state.copyWith(phase: MallaPhase.closed);
      }
      return;
    }
    final now = _clock();
    for (final m in room.members.values) {
      if (m.ping != _lastPing[m.account] || !_heard.containsKey(m.account)) {
        _lastPing[m.account] = m.ping;
        _heard[m.account] = now;
      }
    }
    MallaGame? game;
    if (room.started) {
      try {
        game = room.toGame();
      } catch (e) {
        debugPrint('Ibasho: la partida de Malla $code no cuadra ($e)');
        state = state.copyWith(room: room, problem: MallaProblem.broken);
        return;
      }
    }
    final phase = switch (room.phase) {
      MallaRoomPhase.wait => room.members.containsKey(_me) ? MallaPhase.lobby : state.phase,
      MallaRoomPhase.play => game!.finished ? MallaPhase.done : MallaPhase.playing,
      MallaRoomPhase.done => MallaPhase.done,
      MallaRoomPhase.gone => MallaPhase.closed,
    };
    state = MallaOnlineState(phase: phase, code: code, room: room, game: game, busy: state.busy);
    if (phase == MallaPhase.done && game != null) _finish(code, room, game);
    // La revancha: quien creó la sala ha abierto otra; los demás entran solos.
    final next = room.next;
    final me = _identity;
    if (next != null && room.host != _me && me != null && room.seatOf(_me) >= 0) {
      unawaited(join(next, me: me));
      return;
    }
    // Si a quien le toca lo han dejado fuera y nadie ha movido el turno (o
    // la partida ya ha acabado sin `done`), se arregla con una escritura.
    if (room.phase == MallaRoomPhase.play && game != null && game.finished && seat >= 0) {
      unawaited(_send({'malla/$code/state': 'done'}));
    }
  }

  void _finish(String code, MallaRoom room, MallaGame game) {
    final mine = room.seatOf(_me);
    if (mine < 0 || !_recorded.add(code)) return;
    final end = game.out.contains(mine)
        ? MallaEnd.left
        : game.lastStanding
            ? MallaEnd.last
            : MallaEnd.board;
    final seats = room.seats;
    final record = MallaRecord(
      code: code,
      at: _clock(),
      size: room.size,
      me: mine,
      end: end,
      players: [
        for (var i = 0; i < seats.length; i++)
          MallaHistoryPlayer(
            account: seats[i].account,
            name: seats[i].name,
            score: game.scores[i],
            tama: seats[i].tama,
            marker: seats[i].marker,
            color: seats[i].color,
          ),
      ],
      winners: game.winners,
    );
    unawaited(_saveRecord(record));
    onFinished?.call(record);
  }

  Future<void> _saveRecord(MallaRecord record) async {
    try {
      final token = await _session.freshToken();
      await _backend.write('/mallaHistory/$_me/${record.code}', record.toJson(serverTimestamp), idToken: token);
      // Solo las últimas [mallaHistoryKeep].
      final all = MallaRecord.listFrom(await _backend.read('/mallaHistory/$_me', idToken: token));
      if (all.length > mallaHistoryKeep) {
        await _backend.merge('/', {
          for (final old in all.skip(mallaHistoryKeep)) 'mallaHistory/$_me/${old.code}': null,
        }, idToken: token);
      }
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar la partida de Malla ($e)');
    }
  }

  void _stop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    unawaited(_watch?.cancel());
    _watch = null;
    _tree = null;
  }

  /// Sale de la sala: en la espera, se va (o la cierra quien la creó); en
  /// partida, queda fuera y la partida cuenta como dejada; acabada, quien la
  /// creó la borra si no hay revancha.
  Future<void> close() async {
    final code = state.code;
    final room = state.room;
    if (code != null && room != null) {
      try {
        final token = await _session.freshToken();
        switch (room.phase) {
          case MallaRoomPhase.wait when room.host == _me:
            await _backend.write('${mallaRoomPath(code)}/state', 'gone', idToken: token);
          case MallaRoomPhase.wait when room.members.containsKey(_me):
            await _backend.merge('/', {
              'malla/$code/members/$_me': null,
              'malla/$code/count': room.members.length - 1,
            }, idToken: token);
          case MallaRoomPhase.play when seat >= 0 && !(state.game?.out.contains(seat) ?? true):
            if (await _out(seat) && state.game != null) _finish(code, room, state.game!.clone()..applyOut(seat));
          case MallaRoomPhase.done when room.host == _me && room.next == null:
            await _backend.remove(mallaRoomPath(code), idToken: token);
          default:
            break;
        }
      } catch (e) {
        debugPrint('Ibasho: no se ha podido salir de la sala de Malla ($e)');
      }
    }
    _stop();
    if (mounted) state = const MallaOnlineState();
  }

  /// Olvida un problema ya enseñado.
  void clearProblem() {
    if (state.problem != null) state = state.copyWith(clearProblem: true);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

final mallaOnlineProvider = StateNotifierProvider<MallaOnlineController, MallaOnlineState>(
  (ref) => MallaOnlineController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  ),
);

/// Las invitaciones del buzón que no han caducado. Salen de la conexión de
/// la cuenta; cada minuto se vuelve a mirar cuáles siguen vivas.
final mallaInvitesProvider = StreamProvider<List<MallaInvite>>((ref) async* {
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  final active = ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  if (me.isEmpty || !active) {
    yield const <MallaInvite>[];
    return;
  }
  final out = StreamController<List<MallaInvite>>();
  Object? tree;
  void emit() => out.add(MallaInvite.listFrom(tree, now: DateTime.now()));
  final sub = ref
      .read(backendProvider)
      .watch('/users/$me/mallaInbox', token: ref.read(sessionProvider.notifier).freshToken)
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

/// Invitaciones sin responder: la insignia del canal de Malla.
final pendingMallaInvitesProvider = Provider<int>((ref) => ref.watch(mallaInvitesProvider).valueOrNull?.length ?? 0);

/// Las partidas online propias, la más nueva primero. Se lee al abrirlo.
final mallaHistoryProvider = FutureProvider.autoDispose<List<MallaRecord>>((ref) async {
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  if (me.isEmpty) return const <MallaRecord>[];
  final raw = await ref.read(backendProvider).read('/mallaHistory/$me',
      idToken: await ref.read(sessionProvider.notifier).freshToken());
  return MallaRecord.listFrom(raw);
});
