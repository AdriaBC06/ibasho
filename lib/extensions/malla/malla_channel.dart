// Malla — adaptación nativa completa para Kōbō/Ibasho.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/panel.dart';
import '../../ui/widgets/text_field.dart';
import '../content_models.dart';
import 'malla_ai.dart';
import 'malla_board.dart';
import 'malla_game.dart';
import 'malla_guard.dart';
import 'malla_online.dart';
import 'malla_store.dart';

enum _MallaPage {
  home,
  cpuSetup,
  onlineSetup,
  lobby,
  game,
  achievements,
  rules,
}

enum _MallaMode { cpu, online }

class MallaChannel extends StatefulWidget {
  const MallaChannel({
    super.key,
    required this.game,
    required this.levels,
    required this.localeCode,
    required this.text,
  });

  final ExtensionGame game;
  final List<ExtensionLevel> levels;
  final String localeCode;
  final String Function(String key, String fallback) text;

  @override
  State<MallaChannel> createState() => _MallaChannelState();
}

class _MallaChannelState extends State<MallaChannel> {
  static const List<String> _palette = <String>[
    '#397d79',
    '#bd6f57',
    '#7563a8',
    '#b38335',
    '#4f75a8',
    '#a44f70',
  ];
  static const List<String> _botMarkers = <String>[
    '🤖',
    '👾',
    '🦾',
    '🧠',
    '⚙️',
    '🛰️',
  ];

  final math.Random _random = math.Random();
  final TextEditingController _markerController = TextEditingController(
    text: 'A',
  );
  final TextEditingController _colorController = TextEditingController(
    text: '#397d79',
  );
  final TextEditingController _joinCodeController = TextEditingController();
  final MallaOnlineClient _online = MallaOnlineClient();

  MallaStore? _store;
  MallaSaveData _save = MallaSaveData();
  bool _loading = true;
  bool _busy = false;
  String _notice = '';
  _MallaPage _page = _MallaPage.home;
  _MallaMode _mode = _MallaMode.cpu;

  // Configuración CPU.
  int _cpuOpponents = 1;
  int _cpuSize = 3;
  MallaDifficulty _cpuDifficulty = MallaDifficulty.normal;
  String _cpuStarter = 'random';
  bool _cpuChain = false;
  List<int> _cpuSeries = <int>[0, 0];
  int _cpuDraws = 0;
  int _cpuRound = 0;
  bool _botThinking = false;

  // Configuración online.
  bool _onlineJoinTab = false;
  int _onlinePlayers = 2;
  int _onlineSize = 3;
  bool _onlineChain = false;
  MallaSession? _session;
  MallaRoomState? _room;
  List<int?> _presence = const <int?>[];
  List<bool> _lastRematch = const <bool>[];
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  bool _pollBusy = false;
  int _onlineFailures = 0;

  // Partida visible.
  MallaGame? _game;
  List<String> _markers = const <String>[];
  List<Color> _colors = const <Color>[];
  Set<int> _captured = const <int>{};
  String _hintKey = '';
  Timer? _hintTimer;
  String _gameId = '';
  String _seriesRecordedId = '';
  bool _focusBoard = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _stopPolling();
    _hintTimer?.cancel();
    _online.close();
    _markerController.dispose();
    _colorController.dispose();
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
      _markerController.text = save.marker;
      _colorController.text = save.color;
      _cpuOpponents = save.cpuOpponents;
      _cpuSize = save.cpuSize;
      _cpuDifficulty = save.cpuDifficulty;
      _cpuStarter = save.cpuStarter;
      _cpuChain = save.cpuChain;
      _onlineChain = save.onlineChain;
      setState(() => _loading = false);
      _refreshAchievements(showNew: false);
      if (save.session != null) await _resumeSession(save.session!);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notice = 'No se pudieron cargar los datos locales de Malla: $error';
      });
    }
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save(_save);
    } catch (_) {}
  }

  String get _marker => _firstGrapheme(_markerController.text, 'A');

  String get _colorHex {
    final value = _colorController.text.trim().toLowerCase();
    return RegExp(r'^#[0-9a-f]{6}$').hasMatch(value) ? value : _save.color;
  }

  void _rememberProfile() {
    _save.marker = _marker;
    _save.color = _colorHex;
    _save.cpuOpponents = _cpuOpponents;
    _save.cpuSize = _cpuSize;
    _save.cpuDifficulty = _cpuDifficulty;
    _save.cpuStarter = _cpuStarter;
    _save.cpuChain = _cpuChain;
    _save.onlineChain = _onlineChain;
    unawaited(_persist());
  }

  void _sound(Sfx effect) {
    if (_save.soundEnabled) AudioService.instance.play(effect);
  }

  void _go(_MallaPage page) {
    setState(() {
      _page = page;
      _notice = '';
      if (page != _MallaPage.game) _focusBoard = false;
      if (page == _MallaPage.home && _session == null) {
        _game = null;
        _captured = const <int>{};
        _hintKey = '';
      }
    });
  }

  // -----------------------------------------------------------------------
  // CPU

  void _startCpu() {
    _stopPolling();
    _rememberProfile();
    final total = _cpuOpponents + 1;
    final starter = switch (_cpuStarter) {
      'human' => 0,
      'cpu' => 1 + _random.nextInt(_cpuOpponents),
      _ => _random.nextInt(total),
    };
    _mode = _MallaMode.cpu;
    _cpuSeries = List<int>.filled(total, 0);
    _cpuDraws = 0;
    _cpuRound = 1;
    _markers = <String>[_marker, ..._cpuMarkers(_marker, _cpuOpponents)];
    _colors = <Color>[
      _parseColor(_colorHex),
      ..._cpuColors(_colorHex, _cpuOpponents).map(_parseColor),
    ];
    _game = MallaGame(
      size: _cpuSize,
      playerCount: total,
      startSeat: starter,
      chain: _cpuChain,
    );
    _gameId = 'cpu:${DateTime.now().microsecondsSinceEpoch}:$_cpuRound';
    _seriesRecordedId = '';
    _captured = const <int>{};
    _hintKey = '';
    _page = _MallaPage.game;
    _sound(Sfx.chime);
    setState(() {});
    _maybeRunBots();
  }

  void _nextCpuRound() {
    final old = _game;
    if (old == null) return;
    _cpuRound++;
    final starter = (old.startSeat + 1) % old.playerCount;
    _game = MallaGame(
      size: old.size,
      playerCount: old.playerCount,
      startSeat: starter,
      chain: old.chain,
    );
    _gameId = 'cpu:${DateTime.now().microsecondsSinceEpoch}:$_cpuRound';
    _seriesRecordedId = '';
    _captured = const <int>{};
    setState(() {});
    _maybeRunBots();
  }

  void _restartCpu() {
    final old = _game;
    if (old == null) return;
    _game = MallaGame(
      size: old.size,
      playerCount: old.playerCount,
      startSeat: old.startSeat,
      chain: old.chain,
    );
    _gameId = 'cpu:${DateTime.now().microsecondsSinceEpoch}:$_cpuRound:restart';
    _seriesRecordedId = '';
    _captured = const <int>{};
    setState(() {});
    _maybeRunBots();
  }

  void _playLocalEdge(String key) {
    final game = _game;
    if (game == null ||
        _mode != _MallaMode.cpu ||
        _botThinking ||
        game.finished)
      return;
    if (game.currentPlayer != 0) return;
    final edge = game.edges[key];
    if (edge == null) return;
    final lastTouch = game.lastTouchCapturesFor(edge, 0);
    final result = game.applyMove(key, 0);
    if (!result.accepted) return;
    _afterMove(result, lastTouch: lastTouch);
    _maybeRunBots();
  }

  void _maybeRunBots() {
    final game = _game;
    if (!mounted ||
        game == null ||
        _mode != _MallaMode.cpu ||
        game.finished ||
        game.currentPlayer == 0 ||
        _botThinking) {
      return;
    }
    _botThinking = true;
    setState(() {});
    unawaited(_runBots());
  }

  Future<void> _runBots() async {
    while (mounted) {
      final game = _game;
      if (game == null || game.finished || game.currentPlayer == 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted || _game != game || game.finished || game.currentPlayer == 0)
        break;
      final player = game.currentPlayer;
      final key = MallaAi.choose(
        game,
        difficulty: _cpuDifficulty,
        player: player,
        random: _random,
      );
      if (key == null) break;
      final edge = game.edges[key]!;
      final lastTouch = game.lastTouchCapturesFor(edge, player);
      final result = game.applyMove(key, player);
      if (!result.accepted) break;
      _afterMove(result, lastTouch: lastTouch);
      if (!game.finished && game.currentPlayer != 0) {
        await Future<void>.delayed(
          Duration(milliseconds: game.chain && result.captured > 0 ? 220 : 80),
        );
      }
    }
    if (mounted) setState(() => _botThinking = false);
  }

  // -----------------------------------------------------------------------
  // Online / protocolo web compartido

  Future<void> _createRoom() async {
    if (_busy) return;
    _rememberProfile();
    setState(() {
      _busy = true;
      _notice = 'Creando sala…';
    });
    try {
      final result = await _online.create(
        size: _onlineSize,
        playerCount: _onlinePlayers,
        marker: _marker,
        color: _colorHex,
        chain: _onlineChain,
      );
      _session = result.$1;
      _save.session = result.$1;
      await _persist();
      _applyRoom(result.$2, presence: const <int?>[]);
      _startPolling();
      _sound(Sfx.chime);
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinRoom() async {
    if (_busy) return;
    final code = _cleanCode(_joinCodeController.text);
    if (code.length != 6) {
      setState(() => _notice = 'Escribe un código de 6 caracteres.');
      return;
    }
    _rememberProfile();
    setState(() {
      _busy = true;
      _notice = 'Entrando a la sala…';
    });
    try {
      final result = await _online.join(
        code: code,
        marker: _marker,
        color: _colorHex,
      );
      _session = result.$1;
      _save.session = result.$1;
      await _persist();
      _applyRoom(result.$2, presence: const <int?>[]);
      _startPolling();
      _sound(Sfx.chime);
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumeSession(MallaSession session) async {
    try {
      final result = await _online.poll(session);
      if (!mounted) return;
      _session = session;
      _applyRoom(result.state, presence: result.presence);
      _startPolling();
    } catch (_) {
      _save.session = null;
      _session = null;
      await _persist();
    }
  }

  Future<void> _startOnlineGame() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      final state = await _online.start(session);
      _applyRoom(state, presence: _presence);
      _sound(Sfx.chime);
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playOnlineEdge(String key) async {
    final session = _session;
    final room = _room;
    if (session == null ||
        room == null ||
        _busy ||
        room.over ||
        room.turn != session.seat)
      return;
    final edge = _game?.edges[key];
    final lastTouch = edge == null
        ? 0
        : _game!.lastTouchCapturesFor(edge, session.seat);
    setState(() => _busy = true);
    try {
      final state = await _online.move(session, key);
      _applyRoom(state, presence: _presence);
      if (lastTouch > 0) {
        _save.stats.lastTouchCaptures += lastTouch;
        _refreshAchievements();
        unawaited(_persist());
      }
      _onlineFailures = 0;
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestRematch() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      final state = await _online.rematch(session);
      _applyRoom(state, presence: _presence);
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveOnline() async {
    final session = _session;
    _stopPolling();
    if (session != null) {
      try {
        await _online.leave(session);
      } catch (_) {}
    }
    _session = null;
    _room = null;
    _save.session = null;
    await _persist();
    if (!mounted) return;
    setState(() {
      _game = null;
      _page = _MallaPage.home;
      _notice = '';
    });
  }

  void _startPolling() {
    _stopPolling();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      final session = _session;
      if (session != null) unawaited(_online.heartbeat(session));
    });
    _schedulePoll(Duration.zero);
  }

  void _schedulePoll(Duration delay) {
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, () => unawaited(_pollOnce()));
  }

  Future<void> _pollOnce() async {
    final session = _session;
    if (session == null) return;
    if (_pollBusy) {
      _schedulePoll(const Duration(milliseconds: 300));
      return;
    }
    _pollBusy = true;
    try {
      final result = await _online.poll(session);
      if (!mounted || _session != session) return;
      _onlineFailures = 0;
      _applyRoom(result.state, presence: result.presence, fromPoll: true);
    } catch (error) {
      _onlineFailures++;
      if (mounted && _onlineFailures > 1) {
        setState(() => _notice = 'Reconectando… ${error.toString()}');
      }
    } finally {
      _pollBusy = false;
      if (_session == session) {
        final room = _room;
        final delay = _page == _MallaPage.lobby
            ? const Duration(milliseconds: 420)
            : _page == _MallaPage.game && room?.turn != session.seat
            ? const Duration(milliseconds: 320)
            : const Duration(milliseconds: 620);
        _schedulePoll(delay);
      }
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pollTimer = null;
    _heartbeatTimer = null;
    _pollBusy = false;
  }

  void _applyRoom(
    MallaRoomState state, {
    required List<int?> presence,
    bool fromPoll = false,
  }) {
    final oldRoom = _room;
    final oldGame = _game;
    final oldOwners =
        oldRoom != null &&
            oldGame != null &&
            oldRoom.round == state.round &&
            oldRoom.size == state.size
        ? <int?>[for (final hex in oldGame.hexes) hex.owner]
        : const <int?>[];
    final nextGame = state.started ? state.toGame() : null;
    final captured = <int>{};
    if (nextGame != null && oldOwners.length == nextGame.hexes.length) {
      for (var i = 0; i < nextGame.hexes.length; i++) {
        if (oldOwners[i] == null && nextGame.hexes[i].owner != null)
          captured.add(i);
      }
    }

    final newlyRematched = <int>[];
    if (state.over && state.endedReason.isEmpty) {
      for (var i = 0; i < state.rematch.length; i++) {
        final previous = i < _lastRematch.length && _lastRematch[i];
        if (state.rematch[i] && !previous && i != state.seat)
          newlyRematched.add(i);
      }
      _lastRematch = List<bool>.from(state.rematch);
    } else {
      _lastRematch = const <bool>[];
    }

    _room = state;
    _presence = presence;
    _mode = _MallaMode.online;
    _game = nextGame;
    _markers = <String>[
      for (var i = 0; i < state.playerCount; i++)
        state.markers[i] ?? '${i + 1}',
    ];
    _colors = <Color>[for (final color in state.colors) _parseColor(color)];
    _captured = captured;
    if (captured.isNotEmpty) {
      _sound(Sfx.chime);
      if (nextGame != null &&
          captured.any((i) => nextGame.hexes[i].owner == state.seat) &&
          _save.stats.unlocked.add('first_hex')) {
        _notice = 'Logro desbloqueado: Primer territorio';
        unawaited(_persist());
      }
    }
    _gameId = 'on:${state.code}:${state.round}:${state.seat}';
    _page = state.started ? _MallaPage.game : _MallaPage.lobby;
    if (newlyRematched.isNotEmpty) {
      final who = newlyRematched.map((i) => _markers[i]).join(' · ');
      _notice = newlyRematched.length == 1
          ? '$who pidió revancha'
          : '$who pidieron revancha';
      _sound(Sfx.tick);
    } else if (!fromPoll || _onlineFailures == 0) {
      _notice = '';
    }
    if (nextGame?.finished == true && state.naturalEnd) {
      _recordFinishedGame(online: true);
    }
    if (mounted) setState(() {});
  }

  // -----------------------------------------------------------------------
  // Movimiento, resultados, estadísticas y logros

  void _afterMove(MallaMoveResult result, {required int lastTouch}) {
    _captured = result.capturedHexes.toSet();
    if (lastTouch > 0) _save.stats.lastTouchCaptures += lastTouch;
    if (result.captured > 0) {
      HapticFeedback.mediumImpact();
      _sound(Sfx.chime);
      if (!_save.stats.unlocked.contains('first_hex') &&
          result.player == _localSeat) {
        _save.stats.unlocked.add('first_hex');
        _notice = 'Logro desbloqueado: Primer territorio';
      }
    } else {
      HapticFeedback.selectionClick();
      _sound(Sfx.tick);
    }
    if (result.finished) _recordFinishedGame(online: false);
    _refreshAchievements();
    unawaited(_persist());
    if (mounted) setState(() {});
  }

  int get _localSeat => _mode == _MallaMode.online ? (_session?.seat ?? 0) : 0;

  bool get _matchOver => _mode == _MallaMode.online
      ? (_room?.over ?? (_game?.finished ?? false))
      : (_game?.finished ?? false);

  void _recordFinishedGame({required bool online}) {
    final game = _game;
    if (game == null || !game.finished || _gameId.isEmpty) return;
    final stats = _save.stats;
    if (stats.recorded.contains(_gameId)) return;
    final me = _localSeat;
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
      if (online && game.playerCount >= 3 && mine > game.hexes.length / 2) {
        stats.majorityWins++;
      }
      _sound(Sfx.rare);
    } else {
      stats.streak = 0;
      _sound(winners.length > 1 ? Sfx.tick : Sfx.back);
    }
    stats.recorded.add(_gameId);
    if (stats.recorded.length > 80) {
      stats.recorded.removeRange(0, stats.recorded.length - 80);
    }

    if (!online && _seriesRecordedId != _gameId) {
      if (winners.length == 1) {
        _cpuSeries[winners.first] += 1;
      } else {
        _cpuDraws++;
      }
      _seriesRecordedId = _gameId;
    }
    _refreshAchievements();
    unawaited(_persist());
  }

  void _refreshAchievements({bool showNew = true}) {
    final stats = _save.stats;
    final newly = <_Achievement>[];
    for (final achievement in _achievements) {
      if (achievement.unlocked(stats) && stats.unlocked.add(achievement.id)) {
        newly.add(achievement);
      }
    }
    if (showNew && newly.isNotEmpty) {
      _notice = 'Logro desbloqueado: ${newly.first.name}';
      _sound(Sfx.epic);
    }
  }

  void _showHint() {
    final game = _game;
    if (game == null ||
        game.finished ||
        _busy ||
        game.currentPlayer != _localSeat)
      return;
    final key = MallaAi.choose(
      game,
      difficulty: MallaDifficulty.hard,
      player: _localSeat,
      random: _random,
    );
    if (key == null) return;
    _hintTimer?.cancel();
    setState(() => _hintKey = key);
    _sound(Sfx.tick);
    _hintTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _hintKey = '');
    });
  }

  // -----------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyH,
          control: true,
          alt: true,
        ): _showHint,
      },
      child: ChannelScaffold(
        title: widget.game.label(widget.localeCode),
        glyph: Glyph.blocks,
        child: _loading
            ? Center(child: Text('Cargando Malla…', style: Ty.lead))
            : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_page == _MallaPage.game && _focusBoard)
      return _gamePage(context, focused: true);
    final layout = Layout.of(context);
    return IbashoScroll(
      padding: EdgeInsets.fromLTRB(
        layout.gutter,
        layout.pick(24, 18),
        layout.gutter,
        42,
      ),
      child: Center(
        child: SizedBox(
          width: layout.pick(980, layout.column),
          child: switch (_page) {
            _MallaPage.home => _home(context),
            _MallaPage.cpuSetup => _cpuSetup(context),
            _MallaPage.onlineSetup => _onlineSetup(context),
            _MallaPage.lobby => _lobby(context),
            _MallaPage.game => _gamePage(context),
            _MallaPage.achievements => _achievementsPage(context),
            _MallaPage.rules => _rulesPage(context),
          },
        ),
      ),
    );
  }

  Widget _home(BuildContext context) {
    final stats = _save.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: Layout.of(context).pick(230, 260),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: .13,
                  child: MallaAmbientBoard(
                    colors: const <Color>[Color(0xFF397D79), Color(0xFFBD6F57)],
                    reducedMotion: IbashoSkin.of(context).reducedMotion,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 28, 26, 26),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Malla', style: Ty.display),
                      const SizedBox(height: 8),
                      Text(
                        'Conquista hexágonos reuniendo cuatro de sus seis aristas. Juega contra hasta cinco máquinas o entra en las mismas salas que Malla Web.',
                        textAlign: TextAlign.center,
                        style: Ty.caption,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${stats.games} partidas · ${stats.wins} victorias · ${stats.unlocked.length}/${_achievements.length} logros',
                        style: Ty.micro,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _MenuChoice(
          glyph: Glyph.globe,
          title: 'Jugar online',
          body: '2 a 6 jugadores · código compartido con mallagame.netlify.app',
          onPressed: () => _go(_MallaPage.onlineSetup),
        ),
        const SizedBox(height: 12),
        _MenuChoice(
          glyph: Glyph.dice,
          title: 'Contra la máquina',
          body: '1 a 5 rivales · fácil, normal o difícil · 3×3 a 7×7',
          onPressed: () => _go(_MallaPage.cpuSetup),
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            IbashoButton(
              label: 'Logros',
              glyph: Glyph.trophy,
              onPressed: () => _go(_MallaPage.achievements),
            ),
            IbashoButton(
              label: 'Cómo jugar',
              glyph: Glyph.info,
              onPressed: () => _go(_MallaPage.rules),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sonido', style: Ty.caption),
                const SizedBox(width: 8),
                IbashoToggle(
                  value: _save.soundEnabled,
                  onChanged: (value) {
                    setState(() => _save.soundEnabled = value);
                    unawaited(_persist());
                    if (value) _sound(Sfx.tick);
                  },
                ),
              ],
            ),
          ],
        ),
        if (_notice.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Notice(_notice),
        ],
      ],
    );
  }

  Widget _cpuSetup(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _BackRow(title: 'Contra la máquina', onBack: () => _go(_MallaPage.home)),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profileEditor(context),
            const SizedBox(height: 12),
            Text('Tablero', style: Ty.label),
            const SizedBox(height: 6),
            IbashoSegmented<int>(
              options: const <(int, String)>[
                (3, '3×3'),
                (4, '4×4'),
                (5, '5×5'),
                (6, '6×6'),
                (7, '7×7'),
              ],
              value: _cpuSize,
              onChanged: (value) => setState(() => _cpuSize = value),
            ),
            const SizedBox(height: 12),
            Text('Máquinas', style: Ty.label),
            const SizedBox(height: 6),
            IbashoSegmented<int>(
              options: const <(int, String)>[
                (1, '1'),
                (2, '2'),
                (3, '3'),
                (4, '4'),
                (5, '5'),
              ],
              value: _cpuOpponents,
              onChanged: (value) {
                setState(() {
                  _cpuOpponents = value;
                  _cpuSize = math.min(7, value + 2);
                });
              },
            ),
            const SizedBox(height: 12),
            Text('Dificultad', style: Ty.label),
            const SizedBox(height: 6),
            IbashoSegmented<MallaDifficulty>(
              options: const <(MallaDifficulty, String)>[
                (MallaDifficulty.easy, 'Fácil'),
                (MallaDifficulty.normal, 'Normal'),
                (MallaDifficulty.hard, 'Difícil'),
              ],
              value: _cpuDifficulty,
              onChanged: (value) => setState(() => _cpuDifficulty = value),
            ),
            const SizedBox(height: 12),
            Text('Quién empieza', style: Ty.label),
            const SizedBox(height: 6),
            IbashoSegmented<String>(
              options: const <(String, String)>[
                ('random', 'Aleatorio'),
                ('human', 'Tú'),
                ('cpu', 'Máquina'),
              ],
              value: _cpuStarter,
              onChanged: (value) => setState(() => _cpuStarter = value),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cadena', style: Ty.body),
                      Text(
                        'Conquistar permite volver a jugar.',
                        style: Ty.micro,
                      ),
                    ],
                  ),
                ),
                IbashoToggle(
                  value: _cpuChain,
                  onChanged: (value) => setState(() => _cpuChain = value),
                ),
              ],
            ),
            const SizedBox(height: 18),
            IbashoButton(
              label: 'Empezar partida',
              glyph: Glyph.play,
              tone: ButtonTone.accent,
              expand: true,
              onPressed: _startCpu,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _onlineSetup(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _BackRow(title: 'Jugar online', onBack: () => _go(_MallaPage.home)),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Las salas son las mismas de Malla Web: un código creado aquí puede abrirse en la web y uno creado en la web puede abrirse aquí.',
              style: Ty.caption,
            ),
            const SizedBox(height: 14),
            IbashoSegmented<bool>(
              options: const <(bool, String)>[
                (false, 'Crear sala'),
                (true, 'Unirme'),
              ],
              value: _onlineJoinTab,
              onChanged: (value) => setState(() {
                _onlineJoinTab = value;
                _notice = '';
              }),
            ),
            const SizedBox(height: 16),
            _profileEditor(context),
            const SizedBox(height: 8),
            if (!_onlineJoinTab) ...[
              Text('Jugadores', style: Ty.label),
              const SizedBox(height: 6),
              IbashoSegmented<int>(
                options: const <(int, String)>[
                  (2, '2'),
                  (3, '3'),
                  (4, '4'),
                  (5, '5'),
                  (6, '6'),
                ],
                value: _onlinePlayers,
                onChanged: (value) => setState(() {
                  _onlinePlayers = value;
                  _onlineSize = math.min(7, value + 1);
                }),
              ),
              const SizedBox(height: 12),
              Text('Tablero', style: Ty.label),
              const SizedBox(height: 6),
              IbashoSegmented<int>(
                options: const <(int, String)>[
                  (3, '3×3'),
                  (4, '4×4'),
                  (5, '5×5'),
                  (6, '6×6'),
                  (7, '7×7'),
                ],
                value: _onlineSize,
                onChanged: (value) => setState(() => _onlineSize = value),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cadena', style: Ty.body),
                        Text(
                          'Conquistar permite volver a jugar.',
                          style: Ty.micro,
                        ),
                      ],
                    ),
                  ),
                  IbashoToggle(
                    value: _onlineChain,
                    onChanged: (value) => setState(() => _onlineChain = value),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              IbashoButton(
                label: _busy ? 'Creando…' : 'Crear sala',
                glyph: Glyph.plus,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: _busy ? null : () => unawaited(_createRoom()),
              ),
            ] else ...[
              IbashoTextField(
                controller: _joinCodeController,
                label: 'Código de sala',
                hint: 'ABC123',
                maxLength: 6,
                textStyle: Ty.credential,
                formatters: <TextInputFormatter>[
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final clean = _cleanCode(newValue.text);
                    return TextEditingValue(
                      text: clean,
                      selection: TextSelection.collapsed(offset: clean.length),
                    );
                  }),
                ],
                onSubmitted: (_) {
                  if (!_busy) unawaited(_joinRoom());
                },
              ),
              const SizedBox(height: 4),
              IbashoButton(
                label: _busy ? 'Entrando…' : 'Entrar a la sala',
                glyph: Glyph.globe,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: _busy ? null : () => unawaited(_joinRoom()),
              ),
            ],
            if (_notice.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Notice(_notice),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _profileEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IbashoTextField(
          controller: _markerController,
          label: 'Tu símbolo',
          hint: 'A o un emoji',
          maxLength: 64,
          onChanged: (_) => _rememberProfile(),
        ),
        IbashoTextField(
          controller: _colorController,
          label: 'Tu color',
          hint: '#397d79',
          maxLength: 7,
          formatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
          ],
          onChanged: (value) {
            if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
              _rememberProfile();
              setState(() {});
            }
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in _palette)
              ColorChip(
                color: _parseColor(color),
                selected: _colorHex == color,
                onPressed: () {
                  _colorController.text = color;
                  _rememberProfile();
                  setState(() {});
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _lobby(BuildContext context) {
    final room = _room;
    final session = _session;
    if (room == null || session == null) return _home(context);
    final host = session.seat == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackRow(
          title: 'Sala ${room.code}',
          onBack: () => unawaited(_leaveOnline()),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.code,
                          style: Ty.clockSmall(
                            IbashoSkin.of(context).accentDeep,
                          ),
                        ),
                        Text(
                          '${room.joinedCount}/${room.playerCount} jugadores · ${room.size}×${room.size} · ${room.chain ? 'Cadena' : 'Sin cadena'}',
                          style: Ty.caption,
                        ),
                      ],
                    ),
                  ),
                  IbashoButton(
                    label: 'Código',
                    glyph: Glyph.copy,
                    onPressed: () {
                      unawaited(
                        Clipboard.setData(ClipboardData(text: room.code)),
                      );
                      setState(() => _notice = 'Código copiado');
                    },
                  ),
                  IbashoButton(
                    label: 'Invitación',
                    glyph: Glyph.send,
                    onPressed: () {
                      final url = _online.inviteUri(room.code).toString();
                      unawaited(Clipboard.setData(ClipboardData(text: url)));
                      setState(() => _notice = 'Enlace web copiado');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < room.playerCount; i++)
                    _LobbyPlayer(
                      marker: room.markers[i],
                      color: _parseColor(room.colors[i]),
                      label: i == session.seat ? 'Tú' : 'Jugador ${i + 1}',
                      presence: _presenceLabel(i),
                    ),
                ],
              ),
              if (_notice.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Notice(_notice),
              ],
              if (host) ...[
                const SizedBox(height: 14),
                IbashoButton(
                  label: room.joined
                      ? (_busy ? 'Iniciando…' : 'Empezar partida')
                      : 'Esperando jugadores…',
                  glyph: Glyph.play,
                  tone: ButtonTone.accent,
                  expand: true,
                  onPressed: room.joined && !_busy
                      ? () => unawaited(_startOnlineGame())
                      : null,
                ),
              ] else ...[
                const SizedBox(height: 14),
                Text(
                  room.joined
                      ? 'Sala completa. Esperando a quien creó la sala.'
                      : 'Esperando ${room.playerCount - room.joinedCount} jugador${room.playerCount - room.joinedCount == 1 ? '' : 'es'}…',
                  textAlign: TextAlign.center,
                  style: Ty.caption,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          child: MallaGuard(
            marker: room.markers[session.seat] ?? _marker,
            color: _parseColor(room.colors[session.seat]),
            best: _save.guardBest,
            soundEnabled: _save.soundEnabled,
            onBestChanged: (best) {
              _save.guardBest = best;
              unawaited(_persist());
            },
          ),
        ),
      ],
    );
  }

  Widget _gamePage(BuildContext context, {bool focused = false}) {
    final game = _game;
    if (game == null) return _home(context);
    final status = _gameStatus();

    Widget boardSurface() => GlossSurface(
      radius: 24,
      recessed: true,
      padding: const EdgeInsets.all(10),
      child: MallaBoardView(
        game: game,
        markers: _markers,
        colors: _colors,
        enabled:
            !_busy &&
            !_botThinking &&
            !_matchOver &&
            game.currentPlayer == _localSeat,
        onEdge: _mode == _MallaMode.online
            ? (key) => unawaited(_playOnlineEdge(key))
            : _playLocalEdge,
        hintKey: _hintKey,
        captured: _captured,
      ),
    );

    // Malla focus layout 0.5.3: board uses remaining bounded height.
    // ChannelScaffold has already consumed its header. In focus mode the
    // board therefore expands only into the space actually left in the
    // channel instead of using a height derived from the full Ibasho canvas.
    if (focused) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _playersBar(),
            const SizedBox(height: 10),
            _TurnBanner(
              title: status.$1,
              body: status.$2,
              mine:
                  !game.finished && game.currentPlayer == _localSeat && !_busy,
            ),
            if (_notice.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Notice(_notice),
            ],
            const SizedBox(height: 10),
            Expanded(child: boardSurface()),
            const SizedBox(height: 12),
            if (_matchOver) _resultCard(context) else _gameActions(true),
          ],
        ),
      );
    }

    final boardHeight = Layout.of(context).pick(510.0, 420.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackRow(
          title: _mode == _MallaMode.online
              ? 'Malla online'
              : 'Contra la máquina',
          onBack: _mode == _MallaMode.online
              ? () => unawaited(_leaveOnline())
              : () => _go(_MallaPage.home),
        ),
        const SizedBox(height: 10),
        _playersBar(),
        const SizedBox(height: 10),
        _TurnBanner(
          title: status.$1,
          body: status.$2,
          mine: !game.finished && game.currentPlayer == _localSeat && !_busy,
        ),
        if (_notice.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Notice(_notice),
        ],
        const SizedBox(height: 10),
        SizedBox(height: boardHeight, child: boardSurface()),
        const SizedBox(height: 12),
        if (_matchOver) _resultCard(context) else _gameActions(false),
      ],
    );
  }

  Widget _playersBar() {
    final game = _game!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < game.playerCount; i++)
          _PlayerScore(
            marker: _markers[i],
            color: _colors[i],
            score: game.scores[i],
            current: !game.finished && game.currentPlayer == i,
            mine: i == _localSeat,
            label: _mode == _MallaMode.cpu
                ? (i == 0
                      ? 'Tú'
                      : (game.playerCount == 2 ? 'Máquina' : 'Máquina $i'))
                : (i == _localSeat ? 'Tú' : 'Jugador ${i + 1}'),
          ),
      ],
    );
  }

  (String, String) _gameStatus() {
    final game = _game!;
    final room = _room;
    if (_mode == _MallaMode.online &&
        room?.over == true &&
        room!.endedReason == 'abandon') {
      final who = room.abandonedBy;
      if (who == _localSeat) return ('PARTIDA ABANDONADA', '');
      final marker = who != null && who < _markers.length
          ? _markers[who]
          : 'Un jugador';
      return ('PARTIDA TERMINADA', '$marker abandonó.');
    }
    if (game.finished) {
      final winners = game.winners;
      if (winners.length > 1) {
        return ('EMPATE', _scoreText());
      }
      return (
        winners.first == _localSeat ? 'GANASTE' : 'FIN DE PARTIDA',
        _scoreText(),
      );
    }
    if (_busy) return ('Registrando jugada…', '');
    if (_botThinking && _mode == _MallaMode.cpu)
      return ('La máquina está pensando…', '');
    if (game.currentPlayer == _localSeat)
      return ('TU TURNO', 'Elige una arista.');
    final marker = _markers[game.currentPlayer];
    return (
      'Turno de $marker',
      _mode == _MallaMode.cpu
          ? 'La máquina está pensando…'
          : 'Jugador ${game.currentPlayer + 1}',
    );
  }

  Widget _gameActions(bool focused) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      IbashoButton(
        label: focused ? 'Salir de foco' : 'Enfocar tablero',
        glyph: focused ? Glyph.cross : Glyph.eye,
        onPressed: () => setState(() => _focusBoard = !focused),
      ),
      IbashoButton(
        label: 'Pista',
        glyph: Glyph.bulb,
        tone: ButtonTone.quiet,
        onPressed: !_matchOver && _game?.currentPlayer == _localSeat && !_busy
            ? _showHint
            : null,
      ),
      IbashoButton(
        label: 'Reglas',
        glyph: Glyph.info,
        tone: ButtonTone.quiet,
        onPressed: () => _go(_MallaPage.rules),
      ),
      if (_mode == _MallaMode.cpu)
        IbashoButton(
          label: 'Reiniciar',
          glyph: Glyph.refresh,
          tone: ButtonTone.quiet,
          onPressed: _restartCpu,
        ),
    ],
  );

  Widget _resultCard(BuildContext context) {
    final game = _game!;
    final room = _room;
    if (_mode == _MallaMode.online && room?.endedReason == 'abandon') {
      final who = room!.abandonedBy;
      final mine = who == _localSeat;
      final marker = who != null && who < _markers.length
          ? _markers[who]
          : 'Un jugador';
      return SectionCard(
        child: Column(
          children: [
            Text('⊘', style: Ty.display),
            const SizedBox(height: 4),
            Text(
              mine ? 'Partida abandonada' : '$marker abandonó',
              style: Ty.lead,
            ),
            const SizedBox(height: 10),
            Text(_seriesText(), style: Ty.caption),
            const SizedBox(height: 14),
            IbashoButton(
              label: 'Salir',
              glyph: Glyph.cross,
              onPressed: () => unawaited(_leaveOnline()),
            ),
          ],
        ),
      );
    }
    final winners = game.winners;
    final title = winners.length > 1
        ? 'Empate'
        : '${_markers[winners.first]} ganó';
    final series = _seriesText();
    final requested =
        _mode == _MallaMode.online &&
        room != null &&
        _localSeat < room.rematch.length &&
        room.rematch[_localSeat];
    return SectionCard(
      child: Column(
        children: [
          Text(winners.map((i) => _markers[i]).join(' · '), style: Ty.display),
          const SizedBox(height: 4),
          Text(title, style: Ty.lead),
          const SizedBox(height: 8),
          Text(
            _scoreText(),
            style: Ty.clockSmall(IbashoSkin.of(context).accentDeep),
          ),
          if (series.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(series, style: Ty.caption),
          ],
          if (_mode == _MallaMode.online &&
              room != null &&
              room.rematch.any((v) => v)) ...[
            const SizedBox(height: 8),
            Text(
              '${room.rematch.where((v) => v).length}/${room.playerCount} listos para revancha',
              style: Ty.micro,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_mode == _MallaMode.cpu)
                IbashoButton(
                  label: 'Jugar otra vez',
                  glyph: Glyph.refresh,
                  tone: ButtonTone.accent,
                  onPressed: _nextCpuRound,
                )
              else
                IbashoButton(
                  label: requested ? 'Esperando al grupo…' : 'Pedir revancha',
                  glyph: Glyph.refresh,
                  tone: ButtonTone.accent,
                  onPressed: requested || _busy
                      ? null
                      : () => unawaited(_requestRematch()),
                ),
              IbashoButton(
                label: 'Salir',
                glyph: Glyph.cross,
                onPressed: _mode == _MallaMode.online
                    ? () => unawaited(_leaveOnline())
                    : () => _go(_MallaPage.home),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _scoreText() {
    final game = _game!;
    if (game.playerCount == 2) return '${game.scores[0]} — ${game.scores[1]}';
    return <String>[
      for (var i = 0; i < game.playerCount; i++)
        '${_markers[i]} ${game.scores[i]}',
    ].join(' · ');
  }

  String _seriesText() {
    if (_mode == _MallaMode.online) {
      final room = _room;
      if (room == null) return '';
      var text = room.playerCount == 2
          ? 'Partidas: ${_markers[0]} ${room.series[0]} — ${room.series[1]} ${_markers[1]}'
          : 'Serie: ${<String>[for (var i = 0; i < room.playerCount; i++) '${_markers[i]} ${room.series[i]}'].join(' · ')}';
      if (room.draws > 0)
        text += ' · ${room.draws} empate${room.draws == 1 ? '' : 's'}';
      return text;
    }
    var text = _cpuSeries.length == 2
        ? 'Partidas: ${_markers[0]} ${_cpuSeries[0]} — ${_cpuSeries[1]} ${_markers[1]}'
        : 'Serie: ${<String>[for (var i = 0; i < _cpuSeries.length; i++) '${_markers[i]} ${_cpuSeries[i]}'].join(' · ')}';
    if (_cpuDraws > 0)
      text += ' · $_cpuDraws empate${_cpuDraws == 1 ? '' : 's'}';
    return text;
  }

  Widget _achievementsPage(BuildContext context) {
    final stats = _save.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackRow(title: 'Logros', onBack: () => _go(_MallaPage.home)),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${stats.unlocked.length}/${_achievements.length} desbloqueados · ${stats.games} partidas · ${stats.wins} victorias',
                style: Ty.caption,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final achievement in _achievements)
                    _AchievementCard(
                      achievement: achievement,
                      unlocked: stats.unlocked.contains(achievement.id),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rulesPage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _BackRow(
        title: 'Cómo jugar',
        onBack: () => _go(_game != null ? _MallaPage.game : _MallaPage.home),
      ),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reglas de Malla', style: Ty.lead),
            const SizedBox(height: 10),
            for (final line in const <String>[
              '1. Marca una arista en cada turno.',
              '2. Una arista compartida cuenta para los dos hexágonos que toca.',
              '3. Con Cadena desactivada, los turnos siempre se alternan.',
              '4. Con Cadena activada, conquistar uno o más hexágonos permite volver a jugar.',
              '5. Con 4 de los 6 lados, el hexágono es tuyo.',
              '6. Si se dibuja la sexta arista y nadie llegó a 4, el hexágono es de quien dibujó esa sexta arista.',
              '7. Gana quien conquiste más hexágonos.',
            ]) ...[Text(line, style: Ty.body), const SizedBox(height: 8)],
            const SizedBox(height: 6),
            Text(
              'Compatibilidad online: Ibasho y Malla Web usan el mismo servicio de salas y las mismas claves de arista.',
              style: Ty.caption,
            ),
          ],
        ),
      ),
    ],
  );

  String _presenceLabel(int seat) {
    if (seat >= _presence.length || _presence[seat] == null)
      return 'Sin conexión';
    final age = DateTime.now().millisecondsSinceEpoch - _presence[seat]!;
    if (age < 8500) return 'Conectado';
    if (age < 16000) return 'Reconectando';
    return 'Sin conexión';
  }

  List<String> _cpuMarkers(String user, int count) {
    final used = <String>{user};
    final out = <String>[];
    for (final marker in _botMarkers) {
      if (used.add(marker)) out.add(marker);
      if (out.length == count) break;
    }
    while (out.length < count) out.add('${out.length + 2}');
    return out;
  }

  List<String> _cpuColors(String userColor, int count) {
    final chosen = <String>[userColor.toLowerCase()];
    final out = <String>[];
    while (out.length < count) {
      final candidates = _palette.where((c) => !chosen.contains(c)).toList();
      if (candidates.isEmpty) break;
      candidates.sort(
        (a, b) => _minColorDistance(
          b,
          chosen,
        ).compareTo(_minColorDistance(a, chosen)),
      );
      final pick = candidates.first;
      out.add(pick);
      chosen.add(pick);
    }
    return out;
  }

  double _minColorDistance(String value, List<String> against) =>
      against.map((other) => _colorDistance(value, other)).reduce(math.min);

  double _colorDistance(String a, String b) {
    final x = _rgb(a);
    final y = _rgb(b);
    return math.pow(x.$1 - y.$1, 2).toDouble() +
        math.pow(x.$2 - y.$2, 2).toDouble() +
        math.pow(x.$3 - y.$3, 2).toDouble();
  }

  (int, int, int) _rgb(String value) {
    final n = int.parse(value.substring(1), radix: 16);
    return ((n >> 16) & 255, (n >> 8) & 255, n & 255);
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IbashoButton(
        label: 'Volver',
        glyph: Glyph.arrowLeft,
        tone: ButtonTone.quiet,
        onPressed: onBack,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: Ty.title)),
    ],
  );
}

class _MenuChoice extends StatelessWidget {
  const _MenuChoice({
    required this.glyph,
    required this.title,
    required this.body,
    required this.onPressed,
  });

  final Glyph glyph;
  final String title;
  final String body;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Row(
      children: [
        SizedBox(
          width: 54,
          height: 54,
          child: GlossSurface(
            radius: 18,
            tint: IbashoSkin.of(context).accent,
            child: Center(
              child: GlyphIcon(glyph, size: 28, color: const Color(0xFFFFFFFF)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Ty.lead),
              const SizedBox(height: 3),
              Text(body, style: Ty.caption),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IbashoButton(
          label: 'Abrir',
          glyph: Glyph.arrowRight,
          tone: ButtonTone.accent,
          onPressed: onPressed,
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => GlossSurface(
    radius: 14,
    recessed: true,
    tint: IbashoSkin.of(context).accentWash,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Text(text, textAlign: TextAlign.center, style: Ty.caption),
  );
}

class _LobbyPlayer extends StatelessWidget {
  const _LobbyPlayer({
    required this.marker,
    required this.color,
    required this.label,
    required this.presence,
  });

  final String? marker;
  final Color color;
  final String label;
  final String presence;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 165,
    child: GlossSurface(
      radius: 16,
      recessed: marker == null,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: GlossSurface(
              radius: 12,
              tint: marker == null ? null : color.withValues(alpha: .28),
              borderColor: marker == null
                  ? IbashoSkin.of(context).hairline
                  : color,
              child: Center(child: Text(marker ?? '+', style: Ty.lead)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  marker == null ? 'Esperando…' : label,
                  style: Ty.body,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  marker == null ? label : presence,
                  style: Ty.micro,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlayerScore extends StatelessWidget {
  const _PlayerScore({
    required this.marker,
    required this.color,
    required this.score,
    required this.current,
    required this.mine,
    required this.label,
  });

  final String marker;
  final Color color;
  final int score;
  final bool current;
  final bool mine;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 142,
    child: GlossSurface(
      radius: 16,
      tint: current ? color.withValues(alpha: .20) : null,
      borderColor: current || mine ? color : IbashoSkin.of(context).hairline,
      borderWidth: current ? 2 : 1,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Text(marker, style: Ty.lead.copyWith(color: color)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Ty.micro, overflow: TextOverflow.ellipsis),
                Text(
                  '$score',
                  style: Ty.numeral(24, color: color, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.title,
    required this.body,
    required this.mine,
  });

  final String title;
  final String body;
  final bool mine;

  @override
  Widget build(BuildContext context) => GlossSurface(
    radius: 18,
    tint: mine ? IbashoSkin.of(context).accentWash : null,
    borderColor: mine
        ? IbashoSkin.of(context).accentDeep
        : IbashoSkin.of(context).hairline,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Column(
      children: [
        Text(title, style: Ty.lead, textAlign: TextAlign.center),
        if (body.isNotEmpty)
          Text(body, style: Ty.caption, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _Achievement {
  const _Achievement(
    this.id,
    this.icon,
    this.name,
    this.description,
    this.unlocked,
  );

  final String id;
  final String icon;
  final String name;
  final String description;
  final bool Function(MallaStats stats) unlocked;
}

final List<_Achievement> _achievements = <_Achievement>[
  _Achievement(
    'first_hex',
    '⬡',
    'Primer territorio',
    'Conquista tu primer hexágono.',
    (s) => s.hexes >= 1 || s.unlocked.contains('first_hex'),
  ),
  _Achievement(
    'first_win',
    '✓',
    'Primera victoria',
    'Gana una partida.',
    (s) => s.wins >= 1,
  ),
  _Achievement(
    'online_win',
    '↔',
    'Cara a cara',
    'Gana una partida online.',
    (s) => s.onlineWins >= 1,
  ),
  _Achievement(
    'second_win',
    'Ⅱ',
    'Desde atrás',
    'Gana una partida sin haber empezado.',
    (s) => s.secondWins >= 1,
  ),
  _Achievement(
    'close_win',
    '1',
    'Por un hilo',
    'Gana por un solo hexágono.',
    (s) => s.closeWins >= 1,
  ),
  _Achievement(
    'margin5',
    '5',
    'Dominio',
    'Gana por 5 o más hexágonos.',
    (s) => s.maxMargin >= 5,
  ),
  _Achievement(
    'perfect',
    '○',
    'Impecable',
    'Gana sin ceder ningún hexágono.',
    (s) => s.perfectWins >= 1,
  ),
  _Achievement(
    'big_board',
    '▦',
    'Malla grande',
    'Gana en un tablero de 5×5 o mayor.',
    (s) => s.fiveWins >= 1,
  ),
  _Achievement(
    'streak3',
    '▲',
    'En racha',
    'Consigue 3 victorias seguidas.',
    (s) => s.bestStreak >= 3,
  ),
  _Achievement(
    'games10',
    '10',
    'Habitual',
    'Completa 10 partidas.',
    (s) => s.games >= 10,
  ),
  _Achievement(
    'draw_game',
    '=',
    'Equilibrio',
    'Participa en una partida empatada.',
    (s) => s.draws >= 1,
  ),
  _Achievement(
    'hexes50',
    '50',
    'Cartógrafo',
    'Conquista 50 hexágonos en total.',
    (s) => s.hexes >= 50,
  ),
  _Achievement(
    'full_table',
    '6',
    'Mesa completa',
    'Termina una partida online de 6 jugadores.',
    (s) => s.fullTableGames >= 1,
  ),
  _Achievement(
    'against_all',
    '✦',
    'Contra todos',
    'Gana una partida con 4 o más jugadores.',
    (s) => s.multi4Wins >= 1,
  ),
  _Achievement(
    'last_touch',
    '⑥',
    'Último toque',
    'Conquista con la sexta arista sin llegar a cuatro lados.',
    (s) => s.lastTouchCaptures >= 1,
  ),
  _Achievement(
    'majority',
    '½+',
    'Mayoría absoluta',
    'Conquista más de la mitad del tablero con 3 o más jugadores.',
    (s) => s.majorityWins >= 1,
  ),
];

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement, required this.unlocked});

  final _Achievement achievement;
  final bool unlocked;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Opacity(
      opacity: unlocked ? 1 : .55,
      child: GlossSurface(
        radius: 16,
        tint: unlocked ? IbashoSkin.of(context).accentWash : null,
        borderColor: unlocked
            ? IbashoSkin.of(context).accentDeep
            : IbashoSkin.of(context).hairline,
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(achievement.icon, style: Ty.lead),
            const SizedBox(height: 4),
            Text(
              achievement.name,
              style: Ty.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(achievement.description, style: Ty.micro),
          ],
        ),
      ),
    ),
  );
}

Color _parseColor(String value) {
  final clean = value.toLowerCase();
  if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(clean))
    return const Color(0xFF397D79);
  return Color(0xFF000000 | int.parse(clean.substring(1), radix: 16));
}

String _firstGrapheme(String value, String fallback) {
  final raw = value.trim();
  if (raw.isEmpty) return fallback;
  final runes = raw.runes.toList(growable: false);
  if (runes.isEmpty) return fallback;

  bool isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;
  bool isExtend(int r) =>
      (r >= 0x0300 && r <= 0x036F) ||
      (r >= 0x1AB0 && r <= 0x1AFF) ||
      (r >= 0x1DC0 && r <= 0x1DFF) ||
      (r >= 0x20D0 && r <= 0x20FF) ||
      (r >= 0xFE20 && r <= 0xFE2F) ||
      (r >= 0xFE00 && r <= 0xFE0F) ||
      (r >= 0xE0100 && r <= 0xE01EF) ||
      (r >= 0x1F3FB && r <= 0x1F3FF) ||
      (r >= 0xE0020 && r <= 0xE007F) ||
      r == 0x20E3;

  final out = <int>[runes.first];
  var i = 1;
  if (isRegional(runes.first) && i < runes.length && isRegional(runes[i])) {
    out.add(runes[i++]);
  }
  while (i < runes.length) {
    final r = runes[i];
    if (isExtend(r)) {
      out.add(r);
      i++;
      continue;
    }
    if (r == 0x200D && i + 1 < runes.length) {
      out
        ..add(r)
        ..add(runes[i + 1]);
      i += 2;
      continue;
    }
    break;
  }
  return String.fromCharCodes(out);
}

String _cleanCode(String value) {
  final clean = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return clean.length <= 6 ? clean : clean.substring(0, 6);
}
