// Malla — el canal: contra tus Tamas y online por Ibasho.
// Copyright (C) 2026 Julio Solano
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
import '../../backend/malla.dart';
import '../../backend/missions.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/malla.dart';
import '../../state/providers.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/slot_tile.dart';
import '../../ui/widgets/text_field.dart';
import '../game_stage.dart';
import '../koen/koen_album.dart' show koenFriendName;
import 'malla_ai.dart';
import 'malla_board.dart';
import 'malla_game.dart';
import 'malla_store.dart';
import 'malla_widgets.dart';

/// Id del juego en la tienda, en `earnings` y en las reglas.
const String mallaGameId = 'malla';

/// Monedas de una partida: contra la máquina, al ganar (menos en fácil);
/// online, al ganador y algo a quien la acaba.
int mallaCpuReward({required bool won, required MallaDifficulty difficulty}) => !won ? 0 : (difficulty == MallaDifficulty.easy ? 1 : 3);

int mallaOnlineReward(MallaRecord record) => switch (record.end) {
  MallaEnd.left => 0,
  _ when record.won => 5,
  _ => 1,
};

enum _View { menu, cpu, online, game, history, achievements }

enum _Mode { cpu, online }

/// El canal de Malla.
///
/// Como Tsumiki, entra a un menú de tres puertas: contra tus Tamas (la
/// máquina juega con ellos), online (una sala con amigos o con un código) y
/// el historial; los logros y las reglas van debajo. Cada pantalla cabe
/// entera, sin desplazar: las listas van por páginas.
///
/// La partida es una sola escena: a un lado tu Tama con su bocadillo, las
/// fichas de los jugadores y los mandos; al otro, el tablero grande. En
/// vertical, el Tama y el turno arriba, las fichas en una franja, el tablero
/// en medio y los mandos abajo.
class MallaChannel extends ConsumerStatefulWidget {
  const MallaChannel({super.key});

  @override
  ConsumerState<MallaChannel> createState() => _MallaChannelState();
}

class _MallaChannelState extends ConsumerState<MallaChannel> {
  final math.Random _random = math.Random();
  final TextEditingController _joinCodeController = TextEditingController();
  final TamaViewController _tama = TamaViewController();
  late final MallaOnlineController _online;

  MallaStore? _store;
  MallaSaveData _save = MallaSaveData();
  bool _loading = true;
  _View _view = _View.menu;
  _Mode _mode = _Mode.cpu;

  // Contra tus Tamas.
  int _cpuOpponents = 1;
  int _cpuSize = 3;
  MallaDifficulty _cpuDifficulty = MallaDifficulty.normal;
  String _cpuStarter = 'random';
  bool _cpuChain = false;
  List<int> _cpuSeries = <int>[0, 0];
  int _cpuDraws = 0;
  int _cpuRound = 0;
  bool _botThinking = false;
  MallaGame? _cpuGame;
  List<MallaSeat> _cpuSeats = const <MallaSeat>[];

  // Online.
  bool _onlineJoinTab = false;
  int _onlinePlayers = 2;
  int _onlineSize = 3;
  bool _onlineChain = false;
  Set<int> _knownOut = const <int>{};

  // Partida visible.
  Set<int> _captured = const <int>{};
  String _hintKey = '';
  Timer? _hintTimer;
  String _gameId = '';
  String _seriesRecordedId = '';
  RewardOutcome? _reward;
  bool _rewardPending = false;
  bool _peek = false;

  // El Tama.
  String? _bubble;
  Timer? _bubbleTimer;
  double _joy = .3;

  // Páginas de las colecciones.
  int _historyPage = 0;
  int _friendsPage = 0;
  int _achPage = 0;
  String _achSelected = mallaAchievements.first.id;

  @override
  void initState() {
    super.initState();
    _online = ref.read(mallaOnlineProvider.notifier);
    _online.onFinished = _onOnlineFinished;
    unawaited(_boot());
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _bubbleTimer?.cancel();
    _online.onFinished = null;
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final store = await MallaStore.open();
      final save = await store.load();
      if (!mounted) return;
      _store = store;
      _save = save;
      _cpuOpponents = save.cpuOpponents;
      _cpuSize = save.cpuSize;
      _cpuDifficulty = save.cpuDifficulty;
      _cpuStarter = save.cpuStarter;
      _cpuChain = save.cpuChain;
      _onlineChain = save.onlineChain;
      setState(() => _loading = false);
      _refreshAchievements(showNew: false);
      // Se estaba en una sala al cerrar: si sigue, se vuelve a ella.
      final code = save.roomCode;
      if (code != null && ref.read(mallaOnlineProvider).phase == MallaPhase.idle) {
        _mode = _Mode.online;
        if (!await _online.join(code, me: _identity())) {
          _online.clearProblem();
          _mode = _Mode.cpu;
          _save.roomCode = null;
          unawaited(_persist());
        }
      } else if (ref.read(mallaOnlineProvider).phase != MallaPhase.idle) {
        _mode = _Mode.online;
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save(_save);
    } catch (_) {}
  }

  L get _l => L.of(context)!;

  Color get _myColor => Art.mallaPlayers[_save.color.clamp(0, Art.mallaPlayers.length - 1)];

  /// El Tama que acompaña: el de la ficha o, si no hay, el primero.
  Tama? _myTama() {
    final tamas = ref.read(tamasProvider);
    return tamas.profileTama ?? tamas.companions.firstOrNull;
  }

  /// Lo que se pone de uno mismo en la sala: nombre, Tama y color. La marca
  /// (que piden las reglas de la sala) es la inicial del nombre.
  MallaIdentity _identity() {
    final profile = ref.read(profileProvider).profile;
    final name = profile?.displayName ?? ref.read(sessionProvider).username;
    final tama = _myTama();
    return MallaIdentity(
      name: name,
      marker: name.isEmpty ? 'A' : String.fromCharCodes(name.runes.take(1)).toUpperCase(),
      color: mallaHex(_myColor),
      tama: tama == null ? null : MallaTama.of(tama),
    );
  }

  void _rememberOptions() {
    _save.cpuOpponents = _cpuOpponents;
    _save.cpuSize = _cpuSize;
    _save.cpuDifficulty = _cpuDifficulty;
    _save.cpuStarter = _cpuStarter;
    _save.cpuChain = _cpuChain;
    _save.onlineChain = _onlineChain;
    unawaited(_persist());
  }

  void _sound(Sfx effect) => AudioService.instance.play(effect);

  void _toast(String text) {
    if (mounted) showIbashoToast(context, text);
  }

  void _say(String? text, {Duration hold = const Duration(milliseconds: 2200)}) {
    _bubbleTimer?.cancel();
    _bubble = text;
    if (text == null) return;
    _bubbleTimer = Timer(hold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _go(_View view) {
    setState(() {
      _view = view;
      if (view == _View.menu && _mode == _Mode.cpu) {
        _cpuGame = null;
        _captured = const <int>{};
        _hintKey = '';
      }
      if (view == _View.cpu || view == _View.online || view == _View.menu) _say(_l.mallaBubbleHello);
    });
  }

  /// La cruz y el atrás del sistema: un paso atrás dentro del canal.
  void _back() {
    final net = ref.read(mallaOnlineProvider);
    if (_mode == _Mode.online && net.phase != MallaPhase.idle) {
      final game = net.game;
      if (net.phase == MallaPhase.playing && game != null && !game.finished && !game.out.contains(_online.seat)) {
        unawaited(_askLeave());
        return;
      }
      _sound(Sfx.back);
      unawaited(_leaveOnline());
      return;
    }
    _sound(Sfx.back);
    if (_view != _View.menu) {
      if (_view == _View.online) {
        _online.clearProblem();
        _mode = _Mode.cpu;
      }
      _go(_View.menu);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _askLeave() async {
    final l = _l;
    final yes = await askConfirmation(
      context,
      title: l.mallaLeaveTitle,
      body: l.mallaLeaveBody,
      confirmLabel: l.mallaLeaveConfirm,
      cancelLabel: l.mallaStay,
      width: 440,
    );
    if (yes && mounted) await _leaveOnline();
  }

  // -----------------------------------------------------------------------
  // Contra tus Tamas

  void _startCpu() {
    _rememberOptions();
    final total = _cpuOpponents + 1;
    final starter = switch (_cpuStarter) {
      'human' => 0,
      'cpu' => 1 + _random.nextInt(_cpuOpponents),
      _ => _random.nextInt(total),
    };
    _mode = _Mode.cpu;
    _cpuSeries = List<int>.filled(total, 0);
    _cpuDraws = 0;
    _cpuRound = 1;
    _cpuSeats = _pickRivals();
    _cpuGame = MallaGame(size: _cpuSize, playerCount: total, startSeat: starter, chain: _cpuChain);
    _newCpuRound();
    _view = _View.game;
    _sound(Sfx.open);
    _joy = .4;
    _say(_l.mallaBubbleHello);
    _tama.hop();
    setState(() {});
    _maybeRunBots();
  }

  /// Tú y tus rivales: otros Tamas de la cuenta, al azar, cada uno con un
  /// color de la paleta que no sea el tuyo.
  List<MallaSeat> _pickRivals() {
    final l = _l;
    final mine = _myTama();
    final pool = ref.read(tamasProvider).companions.where((t) => t.id != mine?.id).toList()..shuffle(_random);
    final colors = Art.mallaPlayers.where((c) => c != _myColor).toList();
    return <MallaSeat>[
      MallaSeat(name: l.mallaYou, color: _myColor, tama: mine == null ? null : MallaTama.of(mine), mine: true),
      for (var i = 0; i < _cpuOpponents; i++)
        MallaSeat(
          name: i < pool.length ? pool[i].name : (_cpuOpponents == 1 ? l.mallaBotName : l.mallaBotNameN(i + 1)),
          color: colors[i % colors.length],
          tama: i < pool.length ? MallaTama.of(pool[i]) : null,
        ),
    ];
  }

  void _newCpuRound({String suffix = ''}) {
    _gameId = 'cpu:${DateTime.now().microsecondsSinceEpoch}:$_cpuRound$suffix';
    _seriesRecordedId = '';
    _captured = const <int>{};
    _hintKey = '';
    _reward = null;
    _rewardPending = false;
    _peek = false;
  }

  void _nextCpuRound() {
    final old = _cpuGame;
    if (old == null) return;
    _cpuRound++;
    _cpuGame = MallaGame(size: old.size, playerCount: old.playerCount, startSeat: (old.startSeat + 1) % old.playerCount, chain: old.chain);
    _newCpuRound();
    _joy = .4;
    _say(_l.mallaBubbleHello);
    setState(() {});
    _maybeRunBots();
  }

  void _restartCpu() {
    final old = _cpuGame;
    if (old == null) return;
    _cpuGame = MallaGame(size: old.size, playerCount: old.playerCount, startSeat: old.startSeat, chain: old.chain);
    _newCpuRound(suffix: ':restart');
    setState(() {});
    _maybeRunBots();
  }

  void _playLocalEdge(String key) {
    final game = _cpuGame;
    if (game == null || _botThinking || game.finished || game.currentPlayer != 0) return;
    final edge = game.edges[key];
    if (edge == null) return;
    final lastTouch = game.lastTouchCapturesFor(edge, 0);
    final result = game.applyMove(key, 0);
    if (!result.accepted) return;
    _afterMove(result, lastTouch: lastTouch);
    _maybeRunBots();
  }

  void _maybeRunBots() {
    final game = _cpuGame;
    if (!mounted || game == null || _mode != _Mode.cpu || game.finished || game.currentPlayer == 0 || _botThinking) {
      return;
    }
    _botThinking = true;
    setState(() {});
    unawaited(_runBots());
  }

  Future<void> _runBots() async {
    while (mounted) {
      final game = _cpuGame;
      if (game == null || game.finished || game.currentPlayer == 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 360));
      if (!mounted || _cpuGame != game || game.finished || game.currentPlayer == 0) break;
      final player = game.currentPlayer;
      final key = MallaAi.choose(game, difficulty: _cpuDifficulty, player: player, random: _random);
      if (key == null) break;
      final edge = game.edges[key]!;
      final lastTouch = game.lastTouchCapturesFor(edge, player);
      final result = game.applyMove(key, player);
      if (!result.accepted) break;
      _afterMove(result, lastTouch: lastTouch);
      if (!game.finished && game.currentPlayer != 0) {
        await Future<void>.delayed(Duration(milliseconds: game.chain && result.captured > 0 ? 260 : 120));
      }
    }
    if (mounted) setState(() => _botThinking = false);
  }

  void _afterMove(MallaMoveResult result, {required int lastTouch}) {
    _captured = result.capturedHexes.toSet();
    if (lastTouch > 0) _save.stats.lastTouchCaptures += lastTouch;
    if (result.captured > 0) {
      _reactToCapture(mine: result.player == _localSeat);
    } else {
      HapticFeedback.selectionClick();
      _sound(Sfx.tick);
    }
    if (result.finished) {
      final game = _cpuGame!;
      final won = game.winners.length == 1 && game.winners.first == 0;
      _recordFinishedGame(game, online: false);
      unawaited(_claim(mallaCpuReward(won: won, difficulty: _cpuDifficulty)));
    }
    _refreshAchievements();
    unawaited(_persist());
    if (mounted) setState(() {});
  }

  /// Alguien conquista: si eres tú, el Tama lo celebra; si es otro, lo
  /// lamenta (no siempre, que cansa).
  void _reactToCapture({required bool mine}) {
    final l = _l;
    if (mine) {
      HapticFeedback.mediumImpact();
      _sound(Sfx.chime);
      _joy = .9;
      _say(l.mallaBubbleMine);
      _tama.hop();
      if (_save.stats.unlocked.add('first_hex')) _toast(l.mallaAchUnlocked(l.mallaAchFirstHex));
    } else {
      _sound(Sfx.tick);
      _joy = .0;
      if (_random.nextDouble() < .4) _say(l.mallaBubbleTheirs);
    }
  }

  Future<void> _claim(int coins) async {
    unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.play));
    if (coins <= 0) {
      if (mounted) setState(() => _reward = null);
      return;
    }
    setState(() => _rewardPending = true);
    final outcome = await ref.read(rewardsProvider.notifier).claim(game: mallaGameId, amount: coins);
    if (!mounted) return;
    setState(() {
      _reward = outcome;
      _rewardPending = false;
    });
  }

  // -----------------------------------------------------------------------
  // Online

  Future<void> _createRoom() async {
    _rememberOptions();
    _mode = _Mode.online;
    setState(() {});
    await _online.create(size: _onlineSize, max: _onlinePlayers, chain: _onlineChain, me: _identity());
  }

  Future<void> _joinRoom([String? raw]) async {
    final code = cleanMallaCode(raw ?? _joinCodeController.text);
    if (code.length != 6) {
      _toast(_l.mallaCodeShort);
      return;
    }
    _rememberOptions();
    _mode = _Mode.online;
    setState(() {});
    await _online.join(code, me: _identity());
  }

  Future<void> _showInvite(MallaInvite invite) async {
    final l = _l;
    final yes = await askConfirmation(
      context,
      title: l.mallaInviteFrom(koenFriendName(ref, invite.from)),
      body: l.mallaInviteBody,
      confirmLabel: l.mallaInviteYes,
      cancelLabel: l.mallaInviteNo,
      width: 440,
    );
    if (!mounted) return;
    unawaited(_online.dropInvite(invite));
    if (yes) await _joinRoom(invite.code);
  }

  Future<void> _leaveOnline() async {
    await _online.close();
    _save.roomCode = null;
    unawaited(_persist());
    if (!mounted) return;
    setState(() {
      _mode = _Mode.cpu;
      _view = _View.menu;
      _captured = const <int>{};
      _knownOut = const <int>{};
      _peek = false;
    });
  }

  /// La partida online ha acabado: estadísticas, monedas y misión.
  void _onOnlineFinished(MallaRecord record) {
    if (!mounted) return;
    final game = ref.read(mallaOnlineProvider).game;
    _gameId = 'on:${record.code}';
    if (game != null && record.end != MallaEnd.left) _recordFinishedGame(game, online: true);
    _reward = null;
    unawaited(_claim(mallaOnlineReward(record)));
  }

  /// Lo que cambia al llegar la sala: hexágonos nuevos, de quién es el
  /// turno, quién se ha ido y el código guardado para volver.
  void _onNet(MallaOnlineState? before, MallaOnlineState now) {
    final l = _l;
    if (now.phase != MallaPhase.idle && _mode != _Mode.online) _mode = _Mode.online;
    final code = switch (now.phase) {
      MallaPhase.lobby || MallaPhase.playing => now.code,
      _ => null,
    };
    if (code != _save.roomCode && (code != null || now.phase == MallaPhase.idle || now.phase == MallaPhase.done)) {
      _save.roomCode = code;
      unawaited(_persist());
    }
    final problem = now.problem;
    if (problem != null && problem != before?.problem) {
      _toast(switch (problem) {
        MallaProblem.notFound => l.mallaNotFound,
        MallaProblem.full => l.mallaFull,
        MallaProblem.started => l.mallaStarted,
        MallaProblem.network => l.mallaNetwork,
        MallaProblem.broken => l.mallaBroken,
      });
      if (now.phase == MallaPhase.idle) _view = _View.online;
    }
    if (now.phase == MallaPhase.lobby && before?.phase != MallaPhase.lobby) {
      _say(l.mallaBubbleLobby, hold: const Duration(seconds: 4));
      _friendsPage = 0;
    }
    if (now.phase == MallaPhase.closed && before?.phase != MallaPhase.closed) {
      _toast(l.mallaClosed);
      unawaited(_online.close());
      _view = _View.online;
    }
    if (now.code != before?.code) {
      _reward = null;
      _rewardPending = false;
      _knownOut = const <int>{};
      _peek = false;
    }
    final game = now.game;
    final old = before?.game;
    final seat = _online.seat;
    if (game != null && old != null && before?.code == now.code && old.hexes.length == game.hexes.length) {
      final captured = <int>{
        for (var i = 0; i < game.hexes.length; i++)
          if (old.hexes[i].owner == null && game.hexes[i].owner != null) i,
      };
      if (captured.isNotEmpty) {
        _captured = captured;
        _reactToCapture(mine: captured.any((i) => game.hexes[i].owner == seat));
        unawaited(_persist());
      } else if (game.moves.length != old.moves.length) {
        _sound(Sfx.tick);
      }
      if (!game.finished && game.currentPlayer == seat && old.currentPlayer != seat) {
        _say(l.mallaBubbleTurn);
        _tama.hop();
      }
    }
    if (game != null && game.finished && (old == null || !old.finished)) _celebrate(game, seat);
    if (game != null) {
      final gone = game.out.difference(_knownOut);
      final seats = now.room?.seats ?? const <MallaMember>[];
      for (final i in gone) {
        if (i == seat) {
          _toast(l.mallaYouAreOut);
        } else if (i < seats.length && !game.finished) {
          _toast(l.mallaPlayerOut(seats[i].name));
        }
      }
      _knownOut = Set<int>.of(game.out);
    }
  }

  // -----------------------------------------------------------------------
  // Estadísticas y logros

  int get _localSeat => _mode == _Mode.online ? _online.seat : 0;

  /// El Tama celebra o consuela al acabar.
  void _celebrate(MallaGame game, int me) {
    final l = _l;
    final winners = game.winners;
    if (winners.length > 1) {
      _joy = .5;
      _say(l.mallaBubbleDraw, hold: const Duration(seconds: 4));
      _tama.hop();
    } else if (winners.first == me) {
      _joy = 1;
      _say(l.mallaBubbleWin, hold: const Duration(seconds: 4));
      _tama
        ..cuddle()
        ..hop();
    } else {
      _joy = -.6;
      _say(l.mallaBubbleLose, hold: const Duration(seconds: 4));
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _tama.speak(ChirpKind.sigh);
        }),
      );
    }
  }

  void _recordFinishedGame(MallaGame game, {required bool online}) {
    if (!game.finished || _gameId.isEmpty) return;
    final stats = _save.stats;
    if (stats.recorded.contains(_gameId)) return;
    final me = _localSeat;
    if (me < 0) return;
    final mine = game.scores[me];
    final winners = game.winners;
    final won = winners.length == 1 && winners.first == me;
    final others = <int>[
      for (var i = 0; i < game.scores.length; i++)
        if (i != me) game.scores[i],
    ];
    final bestOther = others.isEmpty ? 0 : others.reduce(math.max);

    stats.games++;
    stats.hexes += mine;
    if (online && game.playerCount == 6) stats.fullTableGames++;
    if (winners.length > 1) stats.draws++;
    if (won) {
      stats.wins++;
      stats.streak++;
      stats.bestStreak = math.max(stats.bestStreak, stats.streak);
      if (online) {
        stats.onlineWins++;
      } else {
        stats.cpuWins++;
      }
      if (game.startSeat != me) stats.secondWins++;
      final margin = mine - bestOther;
      stats.maxMargin = math.max(stats.maxMargin, margin);
      if (margin == 1) stats.closeWins++;
      if (others.every((v) => v == 0)) stats.perfectWins++;
      if (game.size >= 5) stats.fiveWins++;
      if (online && game.playerCount >= 4) stats.multi4Wins++;
      if (online && game.playerCount >= 3 && mine > game.hexes.length / 2) stats.majorityWins++;
      _sound(Sfx.rare);
    } else {
      stats.streak = 0;
      _sound(winners.length > 1 ? Sfx.tick : Sfx.back);
    }
    stats.recorded.add(_gameId);
    if (stats.recorded.length > 80) stats.recorded.removeRange(0, stats.recorded.length - 80);

    if (!online) {
      if (_seriesRecordedId != _gameId) {
        if (winners.length == 1) {
          _cpuSeries[winners.first] += 1;
        } else {
          _cpuDraws++;
        }
        _seriesRecordedId = _gameId;
      }
      _celebrate(game, me);
    }
    _refreshAchievements();
    unawaited(_persist());
  }

  void _refreshAchievements({bool showNew = true}) {
    final stats = _save.stats;
    MallaAchievement? first;
    for (final achievement in mallaAchievements) {
      if (achievement.unlocked(stats) && stats.unlocked.add(achievement.id)) first ??= achievement;
    }
    if (showNew && first != null && mounted) {
      _toast(_l.mallaAchUnlocked(first.name(_l)));
      _sound(Sfx.epic);
    }
  }

  void _showHint(MallaGame? game) {
    if (game == null || game.finished || game.currentPlayer != _localSeat) return;
    final key = MallaAi.choose(game, difficulty: MallaDifficulty.hard, player: _localSeat, random: _random);
    if (key == null) return;
    _hintTimer?.cancel();
    setState(() => _hintKey = key);
    _hintTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _hintKey = '');
    });
  }

  // -----------------------------------------------------------------------
  // Interfaz

  @override
  Widget build(BuildContext context) {
    ref.listen<MallaOnlineState>(mallaOnlineProvider, (before, now) {
      _onNet(before, now);
      if (mounted) setState(() {});
    });
    final net = ref.watch(mallaOnlineProvider);
    final l = _l;
    final layout = Layout.of(context);
    final invites = ref.watch(mallaInvitesProvider).valueOrNull ?? const <MallaInvite>[];
    final online = _mode == _Mode.online && net.phase != MallaPhase.idle;
    final view = switch (net.phase) {
      _ when !online => _view,
      MallaPhase.playing || MallaPhase.done => _View.game,
      _ => null,
    };

    final Widget body;
    if (_loading) {
      body = Center(child: Text(l.mallaLoading, style: Ty.lead));
    } else if (view == null) {
      body = _lobby(context, net);
    } else {
      body = switch (view) {
        _View.menu => _menu(context, invites.length),
        _View.cpu => _setupScene(context, cpu: true),
        _View.online => _setupScene(context, cpu: false),
        _View.game => _gameScene(context, net),
        _View.history => _historyScene(context),
        _View.achievements => _achievementsScene(context),
      };
    }

    // El aviso de invitación, fuera de las partidas y de la sala.
    final notice = !online && view != _View.game && invites.isNotEmpty
        ? MallaInviteNotice(invite: invites.last, onOpen: () => unawaited(_showInvite(invites.last)))
        : null;

    return PopScope(
      canPop: !online && _view == _View.menu,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyH, control: true, alt: true): () => _showHint(_visibleGame(net)),
        },
        child: ChannelScaffold(
          title: l.mallaTitle,
          glyph: Glyph.hexagon,
          art: ArtIcon.malla,
          onClose: _back,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                  child: KeyedSubtree(key: ValueKey<String>('malla.view.${view?.name ?? 'lobby'}'), child: body),
                ),
              ),
              if (notice != null) Positioned(top: 4, left: 0, right: 0, child: Center(child: notice)),
            ],
          ),
        ),
      ),
    );
  }

  /// Arriba, en vertical, el hueco del aviso de invitación: solo si hay una.
  double get _noticeRoom => (ref.watch(mallaInvitesProvider).valueOrNull ?? const <MallaInvite>[]).isEmpty ? 12 : 56;

  MallaGame? _visibleGame(MallaOnlineState net) => _mode == _Mode.online ? net.game : _cpuGame;

  /// El Tama propio sobre su peana, con el bocadillo encima y el foco detrás.
  Widget _stage({required double size, double bubbleWidth = 260, bool bubble = true}) {
    final tama = ref.watch(tamasProvider.select((t) => t.profileTama ?? t.companions.firstOrNull));
    final face = tama == null ? GlossyFace(joy: _joy, size: size) : TamaOnStand(tama: tama, size: size, joy: _joy, controller: _tama);
    return StageLight(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (bubble) ...[
            Flexible(
              child: SpeechBubble(text: _bubble, maxWidth: bubbleWidth),
            ),
            const SizedBox(height: 6),
          ],
          KeyedSubtree(key: ValueKey<String>('malla.tama.${tama?.id}'), child: face),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // --- Menú ----------------------------------------------------------------

  Widget _menu(BuildContext context, int pending) {
    final l = _l;
    final layout = Layout.of(context);
    final stats = _save.stats;
    final tiles = <Widget>[
      MallaMenuTile(
        key: const ValueKey<String>('malla.cpu'),
        glyph: Glyph.hexagon,
        title: l.mallaCpu,
        hint: l.mallaCpuBody,
        onPressed: () => _go(_View.cpu),
      ),
      MallaMenuTile(
        key: const ValueKey<String>('malla.online'),
        glyph: Glyph.friends,
        title: l.mallaOnline,
        hint: l.mallaOnlineBody,
        badge: pending,
        accent: true,
        onPressed: () {
          _mode = _Mode.online;
          _go(_View.online);
        },
      ),
      MallaMenuTile(
        key: const ValueKey<String>('malla.history'),
        glyph: Glyph.clock,
        title: l.mallaHistory,
        hint: l.mallaHistoryBody,
        onPressed: () {
          _historyPage = 0;
          _go(_View.history);
        },
      ),
    ];
    final achievements = IbashoButton(
      key: const ValueKey<String>('malla.achievements'),
      label: layout.tall ? l.mallaAchievements : l.mallaAchButton(stats.unlocked.length, mallaAchievements.length),
      glyph: Glyph.trophy,
      expand: layout.tall,
      onPressed: () => _go(_View.achievements),
    );
    final rules = IbashoButton(
      key: const ValueKey<String>('malla.rules'),
      label: l.mallaHowTo,
      glyph: Glyph.info,
      expand: layout.tall,
      onPressed: () => unawaited(showMallaRules(context)),
    );
    if (layout.tall) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        child: Column(
          children: [
            // Hueco para el aviso de invitación, que va arriba.
            SizedBox(height: _noticeRoom - 12),
            for (final t in tiles) ...[
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 116),
                  child: SizedBox.expand(child: t),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(child: achievements),
                const SizedBox(width: 10),
                Expanded(child: rules),
              ],
            ),
            const SizedBox(height: 12),
            const DailyCoinsMeter(game: mallaGameId, height: 44),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ArtIconView(ArtIcon.malla, size: 110),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SizedBox(
              height: 220,
              child: Row(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 18), Expanded(child: tiles[i])],
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 280, child: DailyCoinsMeter(game: mallaGameId, height: 44)),
              const SizedBox(width: 18),
              achievements,
              const SizedBox(width: 10),
              rules,
            ],
          ),
        ],
      ),
    );
  }

  // --- Preparar la partida ---------------------------------------------------

  static const List<(int, String)> _sizes = <(int, String)>[(3, '3'), (4, '4'), (5, '5'), (6, '6'), (7, '7')];

  /// Preparar una partida: contra tus Tamas o una sala online. En
  /// horizontal, el Tama a la izquierda y la tarjeta de ajustes a la
  /// derecha; en vertical, solo los ajustes, con el botón abajo.
  Widget _setupScene(BuildContext context, {required bool cpu}) {
    final layout = Layout.of(context);
    final options = cpu ? _cpuOptions(context) : _onlineOptions(context);
    if (layout.tall) {
      return Padding(
        padding: EdgeInsets.fromLTRB(0, _noticeRoom, 0, 16),
        child: Column(children: options),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 352,
            child: Column(
              children: [
                Expanded(child: _stage(size: 170)),
                const DailyCoinsMeter(game: mallaGameId, height: 44),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: GlossSurface(
                  radius: 30,
                  elevation: 2,
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: options),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: Ty.title.copyWith(color: IbashoSkin.of(context).accentDeep)),
  );

  Widget _gapBox() => SizedBox(height: Layout.of(context).pick(14.0, 10.0));

  /// El hueco que sobra en vertical va antes del botón, para que quede al
  /// alcance del pulgar.
  Widget _spring() => Layout.of(context).tall ? const Spacer() : const SizedBox(height: 22);

  List<Widget> _cpuOptions(BuildContext context) {
    final l = _l;
    return [
      _title(l.mallaCpu),
      _gapBox(),
      MallaOptionRow(
        label: l.mallaRivals,
        child: MallaRail<int>(
          id: 'rivals',
          options: const <(int, String)>[(1, '1'), (2, '2'), (3, '3'), (4, '4'), (5, '5')],
          value: _cpuOpponents,
          onChanged: (value) => setState(() {
            _cpuOpponents = value;
            _cpuSize = math.min(7, value + 2);
          }),
        ),
      ),
      _gapBox(),
      MallaOptionRow(
        label: l.mallaBoard,
        child: MallaRail<int>(id: 'size', options: _sizes, value: _cpuSize, onChanged: (v) => setState(() => _cpuSize = v)),
      ),
      _gapBox(),
      MallaOptionRow(
        label: l.mallaDifficulty,
        child: MallaRail<MallaDifficulty>(
          options: <(MallaDifficulty, String)>[
            (MallaDifficulty.easy, l.mallaEasy),
            (MallaDifficulty.normal, l.mallaNormal),
            (MallaDifficulty.hard, l.mallaHard),
          ],
          value: _cpuDifficulty,
          onChanged: (value) => setState(() => _cpuDifficulty = value),
        ),
      ),
      _gapBox(),
      MallaOptionRow(
        label: l.mallaStarter,
        child: MallaRail<String>(
          options: <(String, String)>[('random', l.mallaStarterRandom), ('human', l.mallaStarterYou), ('cpu', l.mallaStarterCpu)],
          value: _cpuStarter,
          onChanged: (value) => setState(() => _cpuStarter = value),
        ),
      ),
      _gapBox(),
      _chainRow(_cpuChain, (value) => setState(() => _cpuChain = value)),
      _gapBox(),
      _colorRow(),
      _spring(),
      IbashoButton(
        key: const ValueKey<String>('malla.cpu.start'),
        label: l.mallaStartGame,
        glyph: Glyph.play,
        tone: ButtonTone.accent,
        expand: true,
        onPressed: _startCpu,
      ),
    ];
  }

  List<Widget> _onlineOptions(BuildContext context) {
    final l = _l;
    final busy = ref.watch(mallaOnlineProvider.select((n) => n.phase == MallaPhase.joining));
    final h = Layout.of(context).pick(42.0, 48.0);
    return [
      SegmentRail(
        height: h,
        children: [
          SegmentPill(
            key: const ValueKey<String>('malla.tab.create'),
            label: l.mallaCreate,
            glyph: Glyph.plus,
            height: h,
            selected: !_onlineJoinTab,
            onPressed: () => setState(() => _onlineJoinTab = false),
          ),
          SegmentPill(
            key: const ValueKey<String>('malla.tab.join'),
            label: l.mallaJoin,
            glyph: Glyph.send,
            height: h,
            selected: _onlineJoinTab,
            onPressed: () => setState(() => _onlineJoinTab = true),
          ),
        ],
      ),
      _gapBox(),
      if (!_onlineJoinTab) ...[
        MallaOptionRow(
          label: l.mallaPlayers,
          child: MallaRail<int>(
            id: 'players',
            options: const <(int, String)>[(2, '2'), (3, '3'), (4, '4'), (5, '5'), (6, '6')],
            value: _onlinePlayers,
            onChanged: (value) => setState(() {
              _onlinePlayers = value;
              _onlineSize = math.min(7, value + 1);
            }),
          ),
        ),
        _gapBox(),
        MallaOptionRow(
          label: l.mallaBoard,
          child: MallaRail<int>(options: _sizes, value: _onlineSize, onChanged: (v) => setState(() => _onlineSize = v)),
        ),
        _gapBox(),
        _chainRow(_onlineChain, (value) => setState(() => _onlineChain = value)),
        _gapBox(),
        _colorRow(),
        _spring(),
        IbashoButton(
          key: const ValueKey<String>('malla.create'),
          label: busy ? l.mallaCreating : l.mallaCreate,
          glyph: Glyph.plus,
          tone: ButtonTone.accent,
          expand: true,
          onPressed: busy ? null : () => unawaited(_createRoom()),
        ),
      ] else ...[
        IbashoTextField(
          key: const ValueKey<String>('malla.code'),
          controller: _joinCodeController,
          label: l.mallaCode,
          hint: 'ABC234',
          maxLength: 6,
          textStyle: Ty.credential,
          formatters: <TextInputFormatter>[
            TextInputFormatter.withFunction((oldValue, newValue) {
              final clean = cleanMallaCode(newValue.text);
              return TextEditingValue(
                text: clean,
                selection: TextSelection.collapsed(offset: clean.length),
              );
            }),
          ],
          onSubmitted: (_) {
            if (!busy) unawaited(_joinRoom());
          },
        ),
        _gapBox(),
        _colorRow(),
        _spring(),
        IbashoButton(
          key: const ValueKey<String>('malla.join'),
          label: busy ? l.mallaJoining : l.mallaEnter,
          glyph: Glyph.send,
          tone: ButtonTone.accent,
          expand: true,
          onPressed: busy ? null : () => unawaited(_joinRoom()),
        ),
      ],
    ];
  }

  Widget _chainRow(bool value, ValueChanged<bool> onChanged) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l.mallaChain,
              style: Ty.caption.copyWith(color: Ty.ink, fontWeight: FontWeight.w600),
            ),
            Text(_l.mallaChainHint, maxLines: 2, overflow: TextOverflow.ellipsis, style: Ty.micro),
          ],
        ),
      ),
      const SizedBox(width: 10),
      IbashoToggle(key: const ValueKey<String>('malla.chain'), value: value, onChanged: onChanged),
    ],
  );

  /// En vertical la etiqueta va encima: las seis fichas necesitan todo el
  /// ancho para tocarse con el dedo.
  Widget _colorRow() {
    final picker = MallaColorPicker(
      value: _save.color,
      onChanged: (i) {
        setState(() => _save.color = i);
        unawaited(_persist());
      },
    );
    if (!Layout.of(context).tall) return MallaOptionRow(label: _l.mallaColor, child: picker);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l.mallaColor,
          style: Ty.caption.copyWith(color: Ty.ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        picker,
      ],
    );
  }

  // --- Sala de espera --------------------------------------------------------

  Widget _lobby(BuildContext context, MallaOnlineState net) {
    final l = _l;
    final layout = Layout.of(context);
    final skin = IbashoSkin.of(context);
    final room = net.room;
    if (room == null) return Center(child: Text(l.mallaJoining, style: Ty.lead));
    final me = ref.read(sessionProvider).accountId;
    final host = room.host == me;
    final lobby = room.lobby;
    final hostName = room.members[room.host]?.name ?? '…';
    final inside = room.members.keys.toSet();
    final friends = ref
        .watch(friendsProvider.select((f) => f.friends))
        .where((f) => !inside.contains(f.accountId))
        .map((f) => f.accountId)
        .toList();
    final seats = <MallaSeat?>[
      for (var i = 0; i < room.max; i++) i < lobby.length ? _memberSeat(lobby[i], me: me, index: i, all: lobby) : null,
    ];

    final code = GlossSurface(
      radius: 24,
      recessed: true,
      padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.mallaCode, style: Ty.micro),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    room.code,
                    key: const ValueKey<String>('malla.lobby.code'),
                    style: Ty.numeral(layout.pick(34.0, 28.0), color: skin.accentDeep, weight: FontWeight.w700).copyWith(letterSpacing: 3),
                  ),
                ),
              ],
            ),
          ),
          IconPill(
            key: const ValueKey<String>('malla.copy'),
            glyph: Glyph.copy,
            diameter: layout.pill,
            semanticLabel: l.mallaCopyCode,
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: room.code)));
              _toast(l.mallaCodeCopied);
            },
          ),
        ],
      ),
    );
    final info = Text(
      l.mallaRoomInfo(room.members.length, room.max, room.size, room.chain ? l.mallaChainOn : l.mallaChainOff),
      style: Ty.caption,
    );
    final Widget start = host
        ? IbashoButton(
            key: const ValueKey<String>('malla.lobby.start'),
            label: lobby.length < 2 ? l.mallaNeedTwo : (net.busy ? l.mallaStarting : l.mallaStartGame),
            glyph: Glyph.play,
            tone: ButtonTone.accent,
            expand: true,
            onPressed: lobby.length >= 2 && !net.busy ? () => unawaited(_online.start()) : null,
          )
        : SizedBox(
            height: layout.button,
            child: Center(
              child: Text(l.mallaWaitingHost(hostName), textAlign: TextAlign.center, style: Ty.caption),
            ),
          );
    final leave = IbashoButton(
      key: const ValueKey<String>('malla.lobby.leave'),
      label: l.mallaLeaveRoom,
      tone: ButtonTone.quiet,
      expand: true,
      cue: Sfx.back,
      onPressed: () => unawaited(_leaveOnline()),
    );

    Widget seatsRow(double width, double height, int perRow) {
      final rows = <Widget>[];
      for (var r = 0; r * perRow < seats.length; r++) {
        if (r > 0) rows.add(const SizedBox(height: 8));
        rows.add(
          Row(
            mainAxisAlignment: Layout.of(context).tall ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              for (var i = r * perRow; i < math.min(seats.length, (r + 1) * perRow); i++) ...[
                if (i > r * perRow) const SizedBox(width: 8),
                MallaSeatTile(
                  key: ValueKey<String>('malla.seat.$i'),
                  seat: seats[i],
                  width: width,
                  height: height,
                  tag: seats[i] != null && i < lobby.length && lobby[i].account == room.host ? l.mallaHostTag : null,
                ),
              ],
            ],
          ),
        );
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    }

    Widget friendsGrid() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(l.mallaInviteFriends),
        const SizedBox(height: 8),
        Expanded(
          child: friends.isEmpty
              ? Center(
                  child: Text(
                    l.mallaNoFriends,
                    textAlign: TextAlign.center,
                    style: Ty.body.copyWith(color: Ty.inkSoft),
                  ),
                )
              : _paged(
                  count: friends.length,
                  page: _friendsPage,
                  onPage: (p) => setState(() => _friendsPage = p),
                  tileWidth: layout.pick(108.0, 96.0),
                  tileHeight: layout.pick(124.0, 108.0),
                  minHeight: 56,
                  builder: (i, w, h) => MallaFriendTile(
                    account: friends[i],
                    width: w,
                    height: h,
                    onPressed: () async {
                      final name = koenFriendName(ref, friends[i]);
                      if (await _online.invite(friends[i]) && mounted) _toast(_l.mallaInvited(name));
                    },
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(l.mallaShareHint, textAlign: TextAlign.center, maxLines: layout.pick(2, 1), overflow: TextOverflow.ellipsis, style: Ty.micro),
      ],
    );

    if (layout.tall) {
      final perRow = math.min(3, room.max);
      final tileW = math.min(104.0, (layout.width - layout.gutter * 2 - 8 * (perRow - 1)) / perRow);
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            code,
            const SizedBox(height: 4),
            Center(child: info),
            const SizedBox(height: 10),
            seatsRow(tileW, room.max > 3 ? 84 : 100, perRow),
            const SizedBox(height: 14),
            Expanded(child: friendsGrid()),
            const SizedBox(height: 10),
            start,
            const SizedBox(height: 6),
            leave,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 352,
            child: Column(
              children: [
                Expanded(child: _stage(size: 150)),
                code,
                const SizedBox(height: 6),
                info,
                const SizedBox(height: 14),
                start,
                const SizedBox(height: 8),
                leave,
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _title(l.mallaInRoom),
                const SizedBox(height: 10),
                seatsRow(room.max > 4 ? 118 : 132, 150, room.max),
                const SizedBox(height: 24),
                Expanded(child: friendsGrid()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Un miembro de la sala como asiento. Si su color ya lo lleva alguien de
  /// antes, se le pinta con el primero libre de la paleta.
  MallaSeat _memberSeat(MallaMember m, {required String me, required int index, required List<MallaMember> all}) {
    final taken = <Color>[for (var i = 0; i < index; i++) mallaColor(all[i].color)];
    var color = mallaColor(m.color);
    if (taken.contains(color)) color = Art.mallaPlayers.firstWhere((c) => !taken.contains(c), orElse: () => color);
    return MallaSeat(name: m.account == me ? _l.mallaYou : m.name, color: color, tama: m.tama, mine: m.account == me);
  }

  /// Una rejilla paginada que cabe en el sitio que le dan: tantas columnas
  /// y filas como quepan, las flechas abajo y huecos hundidos al final.
  Widget _paged({
    required int count,
    required int page,
    required ValueChanged<int> onPage,
    required double tileWidth,
    required double tileHeight,
    required double minHeight,
    required Widget Function(int index, double width, double height) builder,
    double gap = 10,
  }) => LayoutBuilder(
    builder: (context, box) {
      final cols = math.max(1, ((box.maxWidth + gap) / (tileWidth + gap)).floor());
      int rowsIn(double height) => math.max(1, ((height + gap) / (tileHeight + gap)).floor());
      // Las flechas solo si hacen falta: sin ellas cabe una fila más.
      var pagerH = 0.0;
      var rows = rowsIn(box.maxHeight);
      if (count > cols * rows) {
        pagerH = 56;
        rows = rowsIn(box.maxHeight - pagerH);
      }
      final roomH = box.maxHeight - pagerH;
      final h = math.max(minHeight, math.min(tileHeight, (roomH - gap * (rows - 1)) / rows));
      final per = cols * rows;
      final pages = math.max(1, (count / per).ceil());
      final p = page.clamp(0, pages - 1);
      return Column(
        children: [
          Expanded(
            child: PageSwipe(
              onPrevious: () {
                if (p > 0) onPage(p - 1);
              },
              onNext: () {
                if (p < pages - 1) onPage(p + 1);
              },
              child: Align(
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var r = 0; r < rows; r++) ...[
                      if (r > 0) SizedBox(height: gap),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var c = 0; c < cols; c++) ...[
                            if (c > 0) SizedBox(width: gap),
                            if (p * per + r * cols + c < count)
                              builder(p * per + r * cols + c, tileWidth, h)
                            else if (pages > 1 || r == 0)
                              EmptySlot(width: tileWidth, height: h)
                            else
                              SizedBox(width: tileWidth, height: h),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (pages > 1)
            SizedBox(
              height: pagerH,
              child: Center(
                child: MallaPager(page: p, pages: pages, onPage: onPage),
              ),
            ),
        ],
      );
    },
  );

  // --- Partida -----------------------------------------------------------------

  List<MallaSeat> _seatsOf(MallaOnlineState net) {
    if (_mode == _Mode.cpu) return _cpuSeats;
    final seats = net.room?.seats ?? const <MallaMember>[];
    final me = ref.read(sessionProvider).accountId;
    return [for (var i = 0; i < seats.length; i++) _memberSeat(seats[i], me: me, index: i, all: seats)];
  }

  bool _myTurn(MallaOnlineState net, MallaGame game) {
    if (game.finished) return false;
    if (_mode == _Mode.cpu) return !_botThinking && game.currentPlayer == 0;
    final seat = _online.seat;
    return net.phase == MallaPhase.playing &&
        !net.busy &&
        seat >= 0 &&
        !game.out.contains(seat) &&
        game.currentPlayer == seat &&
        net.room?.turn == seat;
  }

  String _status(MallaOnlineState net, MallaGame game, List<MallaSeat> seats) {
    final l = _l;
    final me = _localSeat;
    if (_mode == _Mode.online && me >= 0 && game.out.contains(me) && !game.finished) return l.mallaGameOver;
    if (game.finished) {
      final winners = game.winners;
      if (winners.length > 1) return l.mallaDraw;
      return winners.first == me ? l.mallaWon : l.mallaWinner(seats[winners.first].name);
    }
    if (net.busy && _mode == _Mode.online) return l.mallaSending;
    if (game.currentPlayer == me) return l.mallaYourTurn;
    final name = seats[game.currentPlayer].name;
    return _mode == _Mode.cpu ? l.mallaThinking(name) : l.mallaTurnOf(name);
  }

  Widget _gameScene(BuildContext context, MallaOnlineState net) {
    final l = _l;
    final layout = Layout.of(context);
    final game = _visibleGame(net);
    final seats = _seatsOf(net);
    if (game == null || seats.length != game.playerCount) return Center(child: Text(l.mallaJoining, style: Ty.lead));
    final mine = _myTurn(net, game);
    final online = _mode == _Mode.online;
    final colors = [for (final s in seats) s.color];
    final status = MallaStatusPill(text: _status(net, game, seats), mine: mine || (game.finished && game.winners.contains(_localSeat)));

    Widget tile(int i, {required bool compact}) => MallaPlayerTile(
      key: ValueKey<String>('malla.player.$i'),
      seat: seats[i],
      score: game.scores[i],
      current: !game.finished && game.currentPlayer == i,
      out: game.out.contains(i),
      note: game.out.contains(i) ? l.mallaOutTag : null,
      compact: compact,
    );

    final hint = IconPill(
      key: const ValueKey<String>('malla.hint'),
      glyph: Glyph.bulb,
      diameter: layout.pick(46.0, 48.0),
      semanticLabel: l.mallaHint,
      onPressed: mine ? () => _showHint(game) : null,
    );
    final rules = IconPill(
      key: const ValueKey<String>('malla.game.rules'),
      glyph: Glyph.info,
      diameter: layout.pick(46.0, 48.0),
      semanticLabel: l.mallaRules,
      onPressed: () => unawaited(showMallaRules(context)),
    );
    final action = online
        ? IbashoButton(
            key: const ValueKey<String>('malla.exit'),
            label: l.mallaExit,
            glyph: Glyph.cross,
            tone: ButtonTone.quiet,
            expand: true,
            cue: null,
            onPressed: _back,
          )
        : IbashoButton(
            key: const ValueKey<String>('malla.restart'),
            label: l.mallaRestart,
            glyph: Glyph.refresh,
            expand: true,
            onPressed: game.finished ? null : _restartCpu,
          );
    final controls = Row(
      children: [
        hint,
        const SizedBox(width: 10),
        rules,
        const SizedBox(width: 12),
        Expanded(child: action),
      ],
    );

    final board = _boardArea(net, game, colors, seats, mine: mine);

    if (layout.tall) {
      // El tablero se queda con lo que pide su ancho; lo que sobra de alto
      // es para el escenario, que con sitio crece y recupera el bocadillo.
      final n = game.size;
      final aspect = (math.sqrt(3) * (n + .5)) / (1.5 * n + .5);
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
        child: LayoutBuilder(
          builder: (context, box) {
            const fixed = 6 + 64 + 10 + 12 + 48.0;
            final boardH = math.min(box.maxWidth / aspect, box.maxHeight - fixed - 92);
            final stageH = box.maxHeight - fixed - boardH;
            final roomy = stageH > 170;
            return Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: stageH,
                      child: roomy
                          ? Row(
                              children: [
                                SizedBox(width: 150, child: _stage(size: math.min(110.0, stageH * .5), bubbleWidth: 150)),
                                const SizedBox(width: 8),
                                Expanded(child: Center(child: status)),
                              ],
                            )
                          : Row(
                              children: [
                                SizedBox(width: 92, child: _stage(size: 56, bubble: false)),
                                const SizedBox(width: 8),
                                Expanded(child: Center(child: status)),
                              ],
                            ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < game.playerCount; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(child: tile(i, compact: true)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: boardH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [Positioned.fill(child: board)],
                      ),
                    ),
                    const SizedBox(height: 12),
                    controls,
                  ],
                ),
                ..._resultsLayer(net, game, seats),
              ],
            );
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 352,
            child: Column(
              children: [
                Expanded(child: _stage(size: game.playerCount > 4 ? 120 : 150)),
                for (var i = 0; i < game.playerCount; i++) ...[tile(i, compact: false), const SizedBox(height: 8)],
                const SizedBox(height: 6),
                controls,
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              children: [
                status,
                const SizedBox(height: 12),
                Expanded(child: board),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// El tablero en su marco de plástico, del tamaño justo para la malla,
  /// con los resultados encima al acabar.
  Widget _boardArea(MallaOnlineState net, MallaGame game, List<Color> colors, List<MallaSeat> seats, {required bool mine}) {
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    final n = game.size;
    // Ancho entre alto de una malla de n×n hexágonos de punta arriba.
    final aspect = (math.sqrt(3) * (n + .5)) / (1.5 * n + .5);
    return LayoutBuilder(
      builder: (context, box) {
        final pad = tall ? 8.0 : 14.0;
        var w = box.maxWidth;
        var h = w / aspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * aspect;
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: w,
              height: h,
              child: GlossSurface(
                radius: tall ? 22 : 30,
                tint: skin.accentWash,
                elevation: 2,
                padding: EdgeInsets.all(pad),
                child: MallaBoardView(
                  game: game,
                  colors: colors,
                  enabled: mine,
                  onEdge: _mode == _Mode.online ? (key) => unawaited(_online.play(key)) : _playLocalEdge,
                  hintKey: _hintKey,
                  captured: _captured,
                ),
              ),
            ),
            // En vertical los resultados van sobre toda la escena (ver
            // [_resultsLayer]): sobre el tablero solo no caben.
            if (!tall) ..._resultsLayer(net, game, seats),
          ],
        );
      },
    );
  }

  /// Los resultados encima de lo que haya debajo, o el botón para volver a
  /// verlos si se ha apartado la tarjeta para mirar el tablero.
  List<Widget> _resultsLayer(MallaOnlineState net, MallaGame game, List<MallaSeat> seats) => [
    if (game.finished && !_peek) Positioned.fill(child: Center(child: _results(net, game, seats))),
    if (game.finished && _peek)
      Positioned(
        bottom: 8,
        left: 0,
        right: 0,
        child: Center(
          child: IbashoButton(
            key: const ValueKey<String>('malla.results.show'),
            label: _l.mallaSeeResults,
            glyph: Glyph.trophy,
            onPressed: () => setState(() => _peek = false),
          ),
        ),
      ),
  ];

  Widget _results(MallaOnlineState net, MallaGame game, List<MallaSeat> seats) {
    final l = _l;
    final winners = game.winners;
    final me = _localSeat;
    final online = _mode == _Mode.online;
    final host = net.room?.host == ref.read(sessionProvider).accountId;
    final hostName = net.room?.members[net.room?.host]?.name ?? '…';
    final title = winners.length > 1 ? l.mallaDraw : (winners.first == me ? l.mallaWon : l.mallaWinner(seats[winners.first].name));
    final score = game.playerCount == 2
        ? '${game.scores[0]} — ${game.scores[1]}'
        : [for (var i = 0; i < game.playerCount; i++) '${game.scores[i]}'].join(' · ');
    final String? series;
    if (online) {
      series = game.lastStanding ? l.mallaLastStanding : null;
    } else {
      final text = _cpuSeries.length == 2 ? '${_cpuSeries[0]} — ${_cpuSeries[1]}' : [for (final s in _cpuSeries) '$s'].join(' · ');
      series = _cpuDraws > 0 ? '${l.mallaSeries(text)} · ${l.mallaDraws(_cpuDraws)}' : l.mallaSeries(text);
    }
    final Widget? again = !online
        ? IbashoButton(
            key: const ValueKey<String>('malla.again'),
            label: l.mallaPlayAgain,
            glyph: Glyph.refresh,
            tone: ButtonTone.accent,
            expand: Layout.of(context).tall,
            onPressed: _nextCpuRound,
          )
        : host
        ? IbashoButton(
            key: const ValueKey<String>('malla.rematch'),
            label: l.mallaRematch,
            glyph: Glyph.refresh,
            tone: ButtonTone.accent,
            expand: Layout.of(context).tall,
            onPressed: net.busy ? null : () => unawaited(_online.rematch(me: _identity())),
          )
        : null;
    return MallaResultsCard(
      title: title,
      winners: [for (final w in winners) seats[w]],
      score: score,
      series: series,
      coins: _rewardPending || _reward != null ? rewardText(l, _reward, _rewardPending) : null,
      coinsGranted: _reward?.status == RewardStatus.granted,
      note: online && !host ? l.mallaWaitingRematch(hostName) : null,
      actions: [
        IconPill(
          key: const ValueKey<String>('malla.results.peek'),
          glyph: Glyph.eye,
          semanticLabel: l.mallaSeeBoard,
          onPressed: () => setState(() => _peek = true),
        ),
        IbashoButton(
          key: const ValueKey<String>('malla.leave'),
          label: l.mallaExit,
          cue: Sfx.back,
          expand: Layout.of(context).tall,
          onPressed: online ? () => unawaited(_leaveOnline()) : () => _go(_View.menu),
        ),
      ],
      primary: again,
    );
  }

  // --- Historial ---------------------------------------------------------------

  Widget _historyScene(BuildContext context) {
    final l = _l;
    final layout = Layout.of(context);
    final history = ref.watch(mallaHistoryProvider);
    final Widget content = switch (history) {
      AsyncData(value: final records) when records.isEmpty => _emptyHistory(),
      AsyncData(value: final records) => LayoutBuilder(
        builder: (context, box) {
          const pagerH = 56.0;
          final rowH = layout.pick(78.0, 72.0);
          final per = math.max(1, ((box.maxHeight - pagerH + 10) / (rowH + 10)).floor());
          final pages = math.max(1, (records.length / per).ceil());
          final p = _historyPage.clamp(0, pages - 1);
          return Column(
            children: [
              Expanded(
                child: PageSwipe(
                  onPrevious: () {
                    if (p > 0) setState(() => _historyPage = p - 1);
                  },
                  onNext: () {
                    if (p < pages - 1) setState(() => _historyPage = p + 1);
                  },
                  child: Column(
                    children: [
                      for (final (i, r) in records.skip(p * per).take(per).indexed) ...[
                        if (i > 0) const SizedBox(height: 10),
                        MallaRecordTile(record: r, height: rowH),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: pagerH,
                child: pages > 1
                    ? Center(
                        child: MallaPager(page: p, pages: pages, onPage: (v) => setState(() => _historyPage = v)),
                      )
                    : null,
              ),
            ],
          );
        },
      ),
      AsyncError() => Center(
        child: Text(l.mallaNetwork, textAlign: TextAlign.center, style: Ty.body),
      ),
      _ => Center(child: Text(l.mallaLoading, style: Ty.caption)),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(0, layout.pick(18.0, _noticeRoom), 0, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(l.mallaHistory),
              const SizedBox(height: 12),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyHistory() {
    final l = _l;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ArtIconView(ArtIcon.malla, size: 96),
          const SizedBox(height: 14),
          Text(
            l.mallaHistoryEmpty,
            textAlign: TextAlign.center,
            style: Ty.body.copyWith(color: Ty.inkSoft),
          ),
          const SizedBox(height: 18),
          IbashoButton(
            label: l.mallaOnline,
            glyph: Glyph.friends,
            tone: ButtonTone.accent,
            onPressed: () {
              _mode = _Mode.online;
              _go(_View.online);
            },
          ),
        ],
      ),
    );
  }

  // --- Logros ------------------------------------------------------------------

  Widget _achievementsScene(BuildContext context) {
    final l = _l;
    final layout = Layout.of(context);
    final skin = IbashoSkin.of(context);
    final stats = _save.stats;
    final picked = mallaAchievements.firstWhere((a) => a.id == _achSelected, orElse: () => mallaAchievements.first);
    final got = stats.unlocked.contains(picked.id);
    final summary = Text(
      l.mallaAchSummary(stats.unlocked.length, mallaAchievements.length, stats.games, stats.wins),
      textAlign: TextAlign.center,
      style: Ty.caption,
    );
    final chip = ResultChip(text: got ? l.mallaAchDone : l.mallaAchPending, accent: got);
    final grid = _paged(
      count: mallaAchievements.length,
      page: _achPage,
      onPage: (p) => setState(() => _achPage = p),
      tileWidth: layout.pick(124.0, 98.0),
      tileHeight: layout.pick(132.0, 108.0),
      minHeight: 84,
      builder: (i, w, h) {
        final a = mallaAchievements[i];
        return MallaAchievementTile(
          achievement: a,
          unlocked: stats.unlocked.contains(a.id),
          selected: a.id == _achSelected,
          width: w,
          height: h,
          onPressed: () {
            _sound(Sfx.tick);
            setState(() => _achSelected = a.id);
          },
        );
      },
    );

    if (layout.tall) {
      return Padding(
        padding: EdgeInsets.fromLTRB(0, _noticeRoom, 0, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 112,
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: StageLight(
                      child: Center(
                        child: MallaMedal(achievement: picked, unlocked: got, size: 72),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          picked.name(l),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.lead.copyWith(color: skin.accentDeep),
                        ),
                        Text(picked.description(l), maxLines: 3, overflow: TextOverflow.ellipsis, style: Ty.caption),
                        const SizedBox(height: 4),
                        chip,
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            summary,
            const SizedBox(height: 12),
            Expanded(child: grid),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 352,
            child: Column(
              children: [
                Expanded(
                  child: StageLight(
                    child: Center(
                      child: KeyedSubtree(
                        key: ValueKey<String>('malla.ach.show.${picked.id}'),
                        child: PopIn(
                          child: MallaMedal(achievement: picked, unlocked: got, size: 150),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  picked.name(l),
                  textAlign: TextAlign.center,
                  style: Ty.title.copyWith(color: skin.accentDeep),
                ),
                const SizedBox(height: 6),
                Text(picked.description(l), textAlign: TextAlign.center, maxLines: 3, style: Ty.body),
                const SizedBox(height: 10),
                chip,
                const SizedBox(height: 18),
                summary,
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _title(l.mallaAchievements),
                const SizedBox(height: 14),
                Expanded(child: grid),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
