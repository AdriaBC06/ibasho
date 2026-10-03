// Ibasho — canal de Tsumiki: bloques que caen, con tu Tama al lado.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
import '../../backend/leaderboards.dart';
import '../../backend/missions.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../game_stage.dart';
import '../game_store.dart';
import 'tsumiki.dart';
import 'tsumiki_board.dart';
import 'tsumiki_input.dart';
import 'tsumiki_store.dart';
import 'tsumiki_widgets.dart';

/// Semilla fija para los recorridos visuales. En la app es siempre `null`.
@visibleForTesting
int? debugTsumikiSeed;

/// Tsumiki a solas (la entrada «solo» del menú del canal).
///
/// Como el buscaminas, una sola escena: a un lado el escenario con uno de tus
/// Tamas (otro en cada partida), que celebra las filas y se agobia cuando la
/// torre llega arriba, los marcadores y los mandos; al otro, el pozo con la
/// pieza guardada y las siguientes. En vertical el pozo manda, con los huecos
/// y el Tama al lado y la cruceta y los botones A y B abajo, como en una DS.
///
/// Se juega con la cruceta y los botones, con gestos sobre el pozo (deslizar
/// para mover, tocar para girar, bajar rapido para soltar y subir para
/// guardar) o con el teclado.
class TsumikiSolo extends ConsumerStatefulWidget {
  const TsumikiSolo({super.key, this.onBack});

  /// Vuelve al menú del canal en vez de cerrarlo.
  final VoidCallback? onBack;

  @override
  ConsumerState<TsumikiSolo> createState() => _TsumikiSoloState();
}

class _TsumikiSoloState extends ConsumerState<TsumikiSolo>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, TsumikiControls<TsumikiSolo> {
  int _startLevel = 1;
  late TsumikiGame _game = TsumikiGame(seed: debugTsumikiSeed, startLevel: _startLevel);

  final math.Random _random = math.Random();
  String? _tamaId;
  final TamaViewController _tama = TamaViewController();
  double _joy = .3;
  String? _bubble;
  Timer? _bubbleTimer;
  bool _greeted = false;
  bool _danger = false;

  String? _banner;
  bool _bannerBig = false;
  Timer? _bannerTimer;

  /// Cuenta atras antes de empezar: momento (en el reloj de efectos) en que
  /// arranco, o `null` si no hay.
  double? _countFrom;

  GameStore? _store;
  TsumikiRecords _records = const TsumikiRecords();
  TsumikiReport? _report;
  bool _showResults = false;
  RewardOutcome? _reward;
  bool _rewardPending = false;
  Timer? _resultsTimer;

  final TsumikiFx _fx = TsumikiFx();
  double _fxTime = 0;
  double _lastElapsed = 0;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'tsumiki');

  double get _now => _fxTime;
  bool get _reduced => IbashoSkin.of(context).reducedMotion;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadStore());
  }

  Future<void> _loadStore() async {
    final store = await GameStore.open('tsumiki');
    final json = await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _records = TsumikiRecords.fromJson(json);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bubbleTimer?.cancel();
    _bannerTimer?.cancel();
    _resultsTimer?.cancel();
    _ticker.dispose();
    _clock.dispose();
    _focus.dispose();
    super.dispose();
  }

  // --- Reloj -----------------------------------------------------------------

  bool get _wantsTicks =>
      _countFrom != null || _game.status == TsumikiStatus.playing || _now < _fx.busyUntil;

  void _kick() {
    if (!_ticker.isActive && _wantsTicks) {
      _lastElapsed = 0;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final e = elapsed.inMicroseconds / 1e6;
    // Un salto grande (la app estuvo parada) no debe tirar la pieza de golpe.
    final dt = math.min(.1, math.max(0.0, e - _lastElapsed));
    _lastElapsed = e;
    _fxTime += dt;

    final from = _countFrom;
    if (from != null) {
      final left = 3 - (_now - from) / .7;
      final shown = left > 0 ? '${left.ceil()}' : L.of(context)!.tsumikiGo;
      if (shown != _banner) _showBanner(shown, big: true, hold: left > 0 ? null : const Duration(milliseconds: 600));
      if (left <= 0) {
        _countFrom = null;
        _game.start();
        AudioService.instance.play(Sfx.open);
        setState(() {});
      }
    } else if (_game.status == TsumikiStatus.playing) {
      repeatHeld(dt);
      final wasClearing = _game.clearing.isNotEmpty;
      final event = _game.tick(dt);
      if (event != null) _onLock(event);
      if (wasClearing && _game.clearing.isEmpty) {
        _checkDanger();
        setState(() {});
        if (_game.isOver) _onGameOver();
      }
    }
    _clock.value = _fxTime;
    if (!_wantsTicks) _ticker.stop();
  }

  // --- Tama, bocadillo y carteles ---------------------------------------------

  void _pickTama() {
    final tamas = ref.read(tamasProvider).companions;
    if (tamas.isEmpty) {
      _tamaId = null;
      return;
    }
    final pool = tamas.length > 1 ? tamas.where((t) => t.id != _tamaId).toList() : tamas;
    _tamaId = pool[_random.nextInt(pool.length)].id;
  }

  Tama? _currentTama() {
    final tamas = ref.watch(tamasProvider).companions;
    if (tamas.isEmpty) return null;
    if (_tamaId == null || !tamas.any((t) => t.id == _tamaId)) {
      _tamaId = tamas[_random.nextInt(tamas.length)].id;
    }
    return tamas.firstWhere((t) => t.id == _tamaId);
  }

  void _say(String? text, {Duration hold = const Duration(milliseconds: 1800)}) {
    _bubbleTimer?.cancel();
    _bubble = text;
    if (text == null) return;
    _bubbleTimer = Timer(hold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _showBanner(String? text, {bool big = false, Duration? hold = const Duration(milliseconds: 1100)}) {
    _bannerTimer?.cancel();
    setState(() {
      _banner = text;
      _bannerBig = big;
    });
    if (hold != null) {
      _bannerTimer = Timer(hold, () {
        if (mounted) setState(() => _banner = null);
      });
    }
  }

  /// La torre en el tercio de arriba: el Tama se agobia (una vez por
  /// apuro) y respira cuando baja.
  void _checkDanger() {
    final l = L.of(context)!;
    final high = _game.stackTop <= 5;
    if (high && !_danger) {
      _danger = true;
      _joy = -.4;
      _say(l.tsumikiBubbleDanger, hold: const Duration(seconds: 3));
      _tama.hop();
    } else if (!high && _danger && _game.stackTop >= 9) {
      _danger = false;
      _joy = .4;
      _say(l.tsumikiBubbleRelief);
    }
  }

  // --- Partida -----------------------------------------------------------------

  void _newGame({bool countdown = true}) {
    _resultsTimer?.cancel();
    _fx.clear();
    releaseAll();
    setState(() {
      _game = TsumikiGame(seed: debugTsumikiSeed, startLevel: _startLevel);
      _report = null;
      _showResults = false;
      _reward = null;
      _rewardPending = false;
      _danger = false;
      _joy = .3;
      _pickTama();
    });
    if (countdown) _startCountdown();
  }

  void _startCountdown() {
    if (_game.status != TsumikiStatus.ready) return;
    final l = L.of(context)!;
    _focus.requestFocus();
    AudioService.instance.play(Sfx.tick);
    _say(l.tsumikiBubbleStart);
    _tama.hop();
    _countFrom = _now;
    _kick();
    setState(() {});
  }

  void _pause() {
    if (_game.status != TsumikiStatus.playing) return;
    _game.pause();
    releaseAll();
    AudioService.instance.play(Sfx.back);
    _joy = 0;
    _say(L.of(context)!.tsumikiBubblePause, hold: const Duration(seconds: 30));
    setState(() {});
  }

  void _resume() {
    if (_game.status != TsumikiStatus.paused) return;
    _game.resume();
    _focus.requestFocus();
    _say(null);
    _joy = .3;
    AudioService.instance.play(Sfx.tick);
    setState(() {});
    _kick();
  }

  @override
  TsumikiGame get controlledGame => _game;

  @override
  TsumikiFx get controlFx => _fx;

  @override
  double get controlNow => _now;

  @override
  void onPieceLocked(LockEvent e) => _onLock(e);

  @override
  void onPieceHeld() {
    if (_random.nextDouble() < .25) _say(L.of(context)!.tsumikiBubbleHold);
  }

  @override
  void kickTicker() => _kick();

  void _onLock(LockEvent e) {
    final l = L.of(context)!;
    _fx
      ..locked = e.cells
      ..lockedAt = _now
      ..touch(_now + TsumikiFx.lockTime);
    if (e.rows.isNotEmpty) {
      final n = e.rows.length;
      if (n == 4) {
        _fx
          ..shakeAt = _now
          ..shakePower = 6
          ..touch(_now + TsumikiFx.shakeTime);
        AudioService.instance.play(Sfx.chime);
        _showBanner(e.backToBack ? l.tsumikiBannerB2B : l.tsumikiBannerTsumiki, big: false);
        _joy = 1;
        _say(l.tsumikiBubbleTsumiki, hold: const Duration(seconds: 3));
        _tama
          ..cuddle()
          ..hop();
      } else if (n >= 2) {
        AudioService.instance.play(Sfx.chime);
        _showBanner(n == 3 ? l.tsumikiBannerTriple : l.tsumikiBannerDouble);
        _joy = .8;
        _say(n == 3 ? l.tsumikiBubbleTriple : l.tsumikiBubbleDouble);
        _tama.hop();
      } else {
        AudioService.instance.play(Sfx.tick);
        _joy = math.max(_joy, .5);
      }
      if (e.combo >= 2 && n < 4) {
        _showBanner(l.tsumikiBannerCombo(e.combo));
        if (e.combo >= 3) _say(l.tsumikiBubbleCombo);
      }
      if (e.levelUp) {
        Timer(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          _showBanner(l.tsumikiBannerLevel(_game.level));
          setState(() => _say(l.tsumikiBubbleLevel));
          _tama.hop();
        });
      }
    } else {
      _checkDanger();
    }
    if (e.gameOver) _onGameOver();
  }

  void _onGameOver() {
    final l = L.of(context)!;
    releaseAll();
    _fx
      ..overAt = _now + .15
      ..touch(_now + .15 + TsumikiFx.overTime);
    AudioService.instance.play(Sfx.error);
    final good = _game.lines >= 10;
    _joy = good ? .2 : -.8;
    _say(good ? l.tsumikiBubbleOver : l.tsumikiBubbleOverShort, hold: const Duration(seconds: 5));
    _tama.hop();
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _tama.speak(good ? ChirpKind.happy : ChirpKind.sigh);
    }));

    final (records, report) = _records.record(
      score: _game.score,
      lines: _game.lines,
      level: _game.level,
      tsumikis: _game.tsumikis,
      maxCombo: _game.maxCombo,
    );
    _records = records;
    _report = report;
    unawaited(_store?.save(records.toJson()));
    final coins = tsumikiRewardFor(_game.lines);
    if (coins > 0) unawaited(_claim(coins));
    unawaited(ref.read(leaderboardsProvider.notifier).submitScore(LeaderboardGame.tsumiki, _game.score, lines: _game.lines));
    unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.play));
    _resultsTimer = Timer(Duration(milliseconds: _reduced ? 150 : 1400), () {
      if (mounted) setState(() => _showResults = true);
    });
    setState(() {});
    _kick();
  }

  Future<void> _claim(int coins) async {
    setState(() => _rewardPending = true);
    final outcome = await ref.read(rewardsProvider.notifier).claim(game: 'tsumiki', amount: coins);
    if (!mounted) return;
    setState(() {
      _reward = outcome;
      _rewardPending = false;
    });
  }

  // --- Teclado y gestos --------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.enter) {
        switch (_game.status) {
          case TsumikiStatus.playing:
            _pause();
          case TsumikiStatus.paused:
            _resume();
          case TsumikiStatus.ready:
            if (_countFrom == null) _startCountdown();
          case TsumikiStatus.over:
            if (key == LogicalKeyboardKey.enter) _newGame();
        }
        return KeyEventResult.handled;
      }
    }
    return handleActKey(event);
  }

  // --- Composicion ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tama = _currentTama();
    if (!_greeted) {
      _greeted = true;
      _say(l.tsumikiBubbleStart);
    }
    if (_wantsTicks && !_ticker.isActive) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kick();
      });
    }
    return ChannelScaffold(
      title: l.tsumikiTitle,
      glyph: Glyph.blocks,
      art: ArtIcon.tsumiki,
      onClose: widget.onBack == null
          ? null
          : () {
              AudioService.instance.play(Sfx.back);
              widget.onBack!();
            },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: layout.tall ? _tallLayout(context, tama) : _wideLayout(context, tama),
        ),
      ),
    );
  }

  Widget _stage(Tama? tama, double size) {
    final face = tama == null
        ? GlossyFace(joy: _joy, size: size)
        : TamaOnStand(tama: tama, size: size, joy: _joy, controller: _tama);
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, child) {
        // Con la torre arriba tiembla un poco.
        final tremble = _danger && _game.status == TsumikiStatus.playing && !_reduced
            ? math.sin(_clock.value * 38) * 1.6
            : 0.0;
        return Transform.translate(offset: Offset(tremble, 0), child: child);
      },
      child: KeyedSubtree(key: ValueKey<String>('tsumiki.tama.${tama?.id}'), child: face),
    );
  }

  Widget _readouts(L l, {required double height, bool compact = false}) {
    final skin = IbashoSkin.of(context);
    final score = Readout(
      key: const ValueKey<String>('tsumiki.score'),
      icon: const ArtIconView(ArtIcon.coin, size: 30),
      value: '${_game.score}',
      label: l.tsumikiScore,
      height: height,
    );
    final lines = Readout(
      key: const ValueKey<String>('tsumiki.lines'),
      icon: GlyphIcon(Glyph.blocks, size: height * .5, color: skin.accentDeep, strokeWidth: 2.2),
      value: '${_game.lines}',
      label: l.tsumikiLines,
      height: height,
    );
    final level = Readout(
      icon: GlyphIcon(Glyph.star, size: height * .5, color: skin.accentDeep, strokeWidth: 2.2),
      value: '${_game.level}',
      label: l.tsumikiLevel,
      height: height,
    );
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [score, const SizedBox(height: 6), lines, const SizedBox(height: 6), level],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        score,
        const SizedBox(height: 10),
        Row(children: [Expanded(child: lines), const SizedBox(width: 10), Expanded(child: level)]),
      ],
    );
  }

  Widget _holdPocket(L l, double w) =>
      PiecePocket(label: l.tsumikiHold, pieces: [_game.held], width: w, muted: !_game.canHold);

  Widget _nextPocket(L l, double w, {int count = 3}) =>
      PiecePocket(label: l.tsumikiNext, pieces: _game.next.take(count).toList(), width: w);

  /// El pozo con lo que va encima: la tarjeta de salida, la pausa, los
  /// carteles y los resultados.
  Widget _well(BuildContext context, BoxConstraints box, {required bool tall}) {
    final skin = IbashoSkin.of(context);
    final pad = tall ? 8.0 : 12.0;
    final cell = math
        .min((box.maxWidth - pad * 2) / TsumikiGame.width, (box.maxHeight - pad * 2) / TsumikiGame.visibleRows)
        .floorToDouble()
        .clamp(10.0, 40.0);
    controlCell = cell;
    final paused = _game.status == TsumikiStatus.paused;
    return SizedBox(
      width: cell * TsumikiGame.width + pad * 2,
      height: cell * TsumikiGame.visibleRows + pad * 2,
      child: GlossSurface(
        radius: tall ? 18 : 24,
        tint: skin.accentWash,
        elevation: 2,
        padding: EdgeInsets.all(pad),
        child: wellGestures(
          key: const ValueKey<String>('tsumiki.board'),
          child: AnimatedOpacity(
            // En la pausa el pozo se tapa: sin mirar donde ira la siguiente.
            opacity: paused ? .15 : 1,
            duration: skin.motion(const Duration(milliseconds: 200)),
            child: TsumikiBoard(
              game: _game,
              cellSize: cell,
              fx: _fx,
              clock: _clock,
              accent: skin.accent,
              worried: _danger,
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(L l) {
    final report = _report;
    if (report != null && _showResults) {
      return TsumikiResultsCard(
        report: report,
        reward: _reward,
        rewardPending: _rewardPending,
        onAgain: _newGame,
        onDismiss: () => setState(() => _showResults = false),
      );
    }
    if (_game.status == TsumikiStatus.paused) {
      return TsumikiPauseCard(onResume: _resume, onRestart: _newGame);
    }
    if (_game.status == TsumikiStatus.ready && _countFrom == null) {
      return TsumikiReadyCard(
        startLevel: _startLevel,
        records: _records,
        showKeys: !Layout.of(context).tall,
        onLevel: (lv) => setState(() {
          _startLevel = lv;
          _game = TsumikiGame(seed: debugTsumikiSeed, startLevel: lv);
        }),
        onStart: _startCountdown,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _pauseButton(L l, {double diameter = 48}) {
    final over = _game.isOver;
    final playing = _game.status == TsumikiStatus.playing;
    return IconPill(
      key: const ValueKey<String>('tsumiki.pause'),
      glyph: over ? Glyph.refresh : (playing ? Glyph.pause : Glyph.play),
      semanticLabel: over ? l.tsumikiNewGame : (playing ? l.tsumikiPause : l.tsumikiResume),
      diameter: diameter,
      onPressed: () {
        if (over) {
          _newGame();
        } else if (playing) {
          _pause();
        } else if (_game.status == TsumikiStatus.paused) {
          _resume();
        } else if (_countFrom == null) {
          _startCountdown();
        }
      },
    );
  }

  Widget _wideLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 352,
            child: Column(
              children: [
                Expanded(
                  child: StageLight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SpeechBubble(text: _bubble, maxWidth: 260),
                        const SizedBox(height: 6),
                        _stage(tama, 150),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
                _readouts(l, height: 54),
                const SizedBox(height: 14),
                padControls(l, pad: 128, button: 58, middle: _pauseButton(l)),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              // Los huecos van pegados al pozo, no en los bordes.
              const pocket = 96.0;
              const gap = 16.0;
              final well = BoxConstraints(maxWidth: box.maxWidth - (pocket + gap) * 2, maxHeight: box.maxHeight);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 12), child: _holdPocket(l, pocket)),
                      const SizedBox(width: gap),
                      _well(context, well, tall: false),
                      const SizedBox(width: gap),
                      Padding(padding: const EdgeInsets.only(top: 12), child: _nextPocket(l, pocket)),
                    ],
                  ),
                  PopBanner(text: _banner, big: _bannerBig),
                  Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l)))),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _tallLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final small = layout.height < 700;
    final side = small ? 92.0 : 104.0;
    final stageSize = small ? 64.0 : 88.0;
    return Column(
      children: [
        SizedBox(height: small ? 6 : 12),
        Expanded(
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(
                        alignment: Alignment.topCenter,
                        child: _well(context, box, tall: true),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: side,
                    child: Column(
                      children: [
                        _nextPocket(l, side, count: small ? 2 : 3),
                        const SizedBox(height: 8),
                        _holdPocket(l, side),
                        const SizedBox(height: 8),
                        _readouts(l, height: small ? 40 : 46, compact: true),
                        Expanded(
                          child: StageLight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(child: SpeechBubble(text: _bubble, maxWidth: side + 20)),
                                _stage(tama, stageSize),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned.fill(child: Center(child: PopBanner(text: _banner, big: _bannerBig))),
              Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l)))),
            ],
          ),
        ),
        SizedBox(height: small ? 6 : 12),
        padControls(l, pad: small ? 116 : 136, button: small ? 52 : 60, middle: _pauseButton(l)),
        SizedBox(height: small ? 8 : 16),
      ],
    );
  }
}
