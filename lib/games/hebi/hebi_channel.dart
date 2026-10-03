// Ibasho — canal de Hebi: la serpiente clasica, con tu Tama al lado.
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
import '../tsumiki/tsumiki_widgets.dart' show DPad, PadButton, PadDir, PopBanner;
import 'hebi.dart';
import 'hebi_board.dart';
import 'hebi_store.dart';
import 'hebi_widgets.dart';

/// Semilla fija para los recorridos visuales. En la app es siempre `null`.
@visibleForTesting
int? debugHebiSeed;

/// El canal de Hebi.
///
/// Como Tsumiki: a un lado el escenario con uno de tus Tamas (otro en cada
/// partida), que celebra lo que come la serpiente y se agobia cuando va
/// directa a una pared o a su cola, los marcadores y los mandos; al otro, el
/// tablero. En vertical el tablero manda, con el Tama y los marcadores al
/// lado y la cruceta y el boton A abajo, como en una DS.
///
/// Se juega con la cruceta, deslizando sobre el tablero o con el teclado. El
/// boton A (o espacio) acelera mientras se mantiene.
class HebiChannel extends ConsumerStatefulWidget {
  const HebiChannel({super.key});

  @override
  ConsumerState<HebiChannel> createState() => _HebiChannelState();
}

class _HebiChannelState extends ConsumerState<HebiChannel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late HebiGame _game = HebiGame(seed: debugHebiSeed);

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
  HebiRecords _records = const HebiRecords();
  HebiReport? _report;
  bool _showResults = false;
  RewardOutcome? _reward;
  bool _rewardPending = false;
  Timer? _resultsTimer;

  // Deslizar sobre el tablero.
  Offset _drag = Offset.zero;
  double _cell = 24;

  final HebiFx _fx = HebiFx();
  double _fxTime = 0;
  double _lastElapsed = 0;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'hebi');

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
    final store = await GameStore.open('hebi');
    final json = await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _records = HebiRecords.fromJson(json);
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

  bool get _wantsTicks => _countFrom != null || _game.status == HebiStatus.playing || _now < _fx.busyUntil;

  void _kick() {
    if (!_ticker.isActive && _wantsTicks) {
      _lastElapsed = 0;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final e = elapsed.inMicroseconds / 1e6;
    // Un salto grande (la app estuvo parada) no debe estrellar la serpiente.
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
    } else if (_game.status == HebiStatus.playing) {
      final step = _game.tick(dt);
      if (step != null) _onStep(step);
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

  /// Va directa a una pared o a su cola: el Tama se agobia (una vez por
  /// apuro) y respira cuando gira a tiempo.
  void _checkDanger() {
    final high = _game.danger;
    if (high && !_danger) {
      _danger = true;
      _joy = -.3;
      if (_random.nextDouble() < .35) _say(L.of(context)!.hebiBubbleDanger);
    } else if (!high && _danger) {
      _danger = false;
      _joy = math.max(_joy, .3);
    }
  }

  // --- Partida -----------------------------------------------------------------

  void _newGame({bool countdown = true}) {
    _resultsTimer?.cancel();
    _fx.clear();
    setState(() {
      _game = HebiGame(seed: debugHebiSeed);
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
    if (_game.status != HebiStatus.ready) return;
    final l = L.of(context)!;
    _focus.requestFocus();
    AudioService.instance.play(Sfx.tick);
    _say(l.hebiBubbleStart);
    _tama.hop();
    _countFrom = _now;
    _kick();
    setState(() {});
  }

  void _pause() {
    if (_game.status != HebiStatus.playing) return;
    _game
      ..pause()
      ..boost = false;
    AudioService.instance.play(Sfx.back);
    _joy = 0;
    _say(L.of(context)!.hebiBubblePause, hold: const Duration(seconds: 30));
    setState(() {});
  }

  void _resume() {
    if (_game.status != HebiStatus.paused) return;
    _game.resume();
    _focus.requestFocus();
    _say(null);
    _joy = .3;
    AudioService.instance.play(Sfx.tick);
    setState(() {});
    _kick();
  }

  void _turn(HebiDir d) {
    if (_game.turn(d)) _kick();
  }

  void _setBoost(bool on) {
    if (_game.boost == on) return;
    _game.boost = on && _game.status == HebiStatus.playing;
  }

  void _onStep(HebiStep step) {
    final l = L.of(context)!;
    final ate = step.ate;
    if (ate != null) {
      _fx
        ..eatAt = _game.head
        ..eatenAt = _now
        ..touch(_now + HebiFx.eatTime);
      AudioService.instance.play(Sfx.tick);
      _joy = math.min(1, _joy + .2);
      _tama.hop();
      final len = _game.length;
      if (len % 10 == 0) {
        AudioService.instance.play(Sfx.chime);
        _showBanner(l.hebiBannerLength(len));
        _say(l.hebiBubbleLength, hold: const Duration(seconds: 2));
        _tama.cuddle();
      } else if (_random.nextDouble() < .2) {
        _say(_eatLine(l));
      }
      if (step.speedUp) {
        Timer(const Duration(milliseconds: 500), () {
          if (!mounted || _game.isOver) return;
          _showBanner(l.hebiBannerSpeed(_game.speed));
        });
      }
    }
    if (step.over) {
      _onGameOver(won: step.won);
    } else {
      _checkDanger();
    }
    setState(() {});
  }

  String _eatLine(L l) => switch (_random.nextInt(3)) {
        0 => l.hebiBubbleYum,
        1 => l.hebiBubbleMore,
        _ => l.hebiBubbleGrow,
      };

  void _onGameOver({required bool won}) {
    final l = L.of(context)!;
    _game.boost = false;
    _fx
      ..overAt = _now + .1
      ..touch(_now + .1 + HebiFx.overTime);
    AudioService.instance.play(won ? Sfx.chime : Sfx.error);
    final good = hebiRewardFor(_game.length) > 0;
    _joy = won ? 1 : (good ? .2 : -.8);
    _say(won ? l.hebiBubbleWon : (good ? l.hebiBubbleOver : l.hebiBubbleOverShort), hold: const Duration(seconds: 5));
    _tama.hop();
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _tama.speak(good || won ? ChirpKind.happy : ChirpKind.sigh);
    }));

    final (records, report) = _records.record(
      length: _game.length,
      eaten: _game.eaten,
      speed: _game.speed,
      seconds: _game.time,
      won: won,
    );
    _records = records;
    _report = report;
    unawaited(_store?.save(records.toJson()));
    final coins = hebiRewardFor(_game.length);
    if (coins > 0) unawaited(_claim(coins));
    unawaited(ref.read(leaderboardsProvider.notifier).submitScore(LeaderboardGame.hebi, _game.length));
    unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.play));
    _resultsTimer = Timer(Duration(milliseconds: _reduced ? 150 : 1300), () {
      if (mounted) setState(() => _showResults = true);
    });
    _kick();
  }

  Future<void> _claim(int coins) async {
    setState(() => _rewardPending = true);
    final outcome = await ref.read(rewardsProvider.notifier).claim(game: 'hebi', amount: coins);
    if (!mounted) return;
    setState(() {
      _reward = outcome;
      _rewardPending = false;
    });
  }

  // --- Teclado y gestos --------------------------------------------------------

  static final Map<LogicalKeyboardKey, HebiDir> _keys = {
    LogicalKeyboardKey.arrowUp: HebiDir.up,
    LogicalKeyboardKey.keyW: HebiDir.up,
    LogicalKeyboardKey.arrowDown: HebiDir.down,
    LogicalKeyboardKey.keyS: HebiDir.down,
    LogicalKeyboardKey.arrowLeft: HebiDir.left,
    LogicalKeyboardKey.keyA: HebiDir.left,
    LogicalKeyboardKey.arrowRight: HebiDir.right,
    LogicalKeyboardKey.keyD: HebiDir.right,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) _setBoost(true);
      if (event is KeyUpEvent) _setBoost(false);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.enter)) {
      switch (_game.status) {
        case HebiStatus.playing:
          _pause();
        case HebiStatus.paused:
          _resume();
        case HebiStatus.ready:
          if (_countFrom == null) _startCountdown();
        case HebiStatus.over:
          if (key == LogicalKeyboardKey.enter) _newGame();
      }
      return KeyEventResult.handled;
    }
    final dir = _keys[key];
    if (dir == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _turn(dir);
    return KeyEventResult.handled;
  }

  void _onPanStart(DragStartDetails d) => _drag = Offset.zero;

  /// Deslizar gira en cuanto el dedo se ha movido algo mas de media casilla
  /// en una direccion clara; sin levantarlo se puede encadenar otro giro.
  void _onPanUpdate(DragUpdateDetails d) {
    if (_game.status != HebiStatus.playing) return;
    _drag += d.delta;
    final step = math.max(14.0, _cell * .6);
    if (_drag.distance < step) return;
    final horizontal = _drag.dx.abs() > _drag.dy.abs();
    final dir = horizontal
        ? (_drag.dx > 0 ? HebiDir.right : HebiDir.left)
        : (_drag.dy > 0 ? HebiDir.down : HebiDir.up);
    _turn(dir);
    _drag = Offset.zero;
  }

  // --- Composicion ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tama = _currentTama();
    if (!_greeted) {
      _greeted = true;
      _say(l.hebiBubbleStart);
    }
    if (_wantsTicks && !_ticker.isActive) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kick();
      });
    }
    return ChannelScaffold(
      title: l.hebiTitle,
      glyph: Glyph.snake,
      art: ArtIcon.hebi,
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
        // Si va directa a chocar, tiembla un poco.
        final tremble = _danger && _game.status == HebiStatus.playing && !_reduced
            ? math.sin(_clock.value * 38) * 1.6
            : 0.0;
        return Transform.translate(offset: Offset(tremble, 0), child: child);
      },
      child: KeyedSubtree(key: ValueKey<String>('hebi.tama.${tama?.id}'), child: face),
    );
  }

  Widget _readouts(L l, {required double height, bool compact = false}) {
    final skin = IbashoSkin.of(context);
    final length = Readout(
      key: const ValueKey<String>('hebi.length'),
      icon: GlyphIcon(Glyph.snake, size: height * .5, color: skin.accentDeep, strokeWidth: 2.2),
      value: '${_game.length}',
      label: l.hebiLength,
      height: height,
    );
    final speed = Readout(
      key: const ValueKey<String>('hebi.speed'),
      icon: GlyphIcon(Glyph.star, size: height * .5, color: skin.accentDeep, strokeWidth: 2.2),
      value: '${_game.speed}',
      label: l.hebiSpeed,
      height: height,
    );
    final best = Readout(
      icon: GlyphIcon(Glyph.trophy, size: height * .5, color: skin.accentDeep, strokeWidth: 2.2),
      value: '${math.max(_records.bestLength, _game.length)}',
      label: l.gameBest,
      height: height,
    );
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [length, const SizedBox(height: 6), speed, const SizedBox(height: 6), best],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        length,
        const SizedBox(height: 10),
        Row(children: [Expanded(child: speed), const SizedBox(width: 10), Expanded(child: best)]),
      ],
    );
  }

  /// El tablero con lo que va encima: la tarjeta de salida, la pausa, los
  /// carteles y los resultados.
  Widget _field(BuildContext context, BoxConstraints box, {required bool tall}) {
    final skin = IbashoSkin.of(context);
    final pad = tall ? 8.0 : 12.0;
    final cell = math
        .min((box.maxWidth - pad * 2) / HebiGame.width, (box.maxHeight - pad * 2) / HebiGame.height)
        .floorToDouble()
        .clamp(10.0, 44.0);
    _cell = cell;
    final paused = _game.status == HebiStatus.paused;
    return SizedBox(
      width: cell * HebiGame.width + pad * 2,
      height: cell * HebiGame.height + pad * 2,
      child: GlossSurface(
        radius: tall ? 18 : 24,
        tint: skin.accentWash,
        elevation: 2,
        padding: EdgeInsets.all(pad),
        child: GestureDetector(
          key: const ValueKey<String>('hebi.board'),
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          child: AnimatedOpacity(
            opacity: paused ? .15 : 1,
            duration: skin.motion(const Duration(milliseconds: 200)),
            child: HebiBoard(
              game: _game,
              cellSize: cell,
              fx: _fx,
              clock: _clock,
              accent: skin.accent,
              reducedMotion: _reduced,
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(L l) {
    final report = _report;
    if (report != null && _showResults) {
      return HebiResultsCard(
        report: report,
        reward: _reward,
        rewardPending: _rewardPending,
        onAgain: _newGame,
        onDismiss: () => setState(() => _showResults = false),
      );
    }
    if (_game.status == HebiStatus.paused) {
      return HebiPauseCard(onResume: _resume, onRestart: _newGame);
    }
    if (_game.status == HebiStatus.ready && _countFrom == null) {
      return HebiReadyCard(
        records: _records,
        showKeys: !Layout.of(context).tall,
        onStart: _startCountdown,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _pauseButton(L l, {double diameter = 48}) {
    final over = _game.isOver;
    final playing = _game.status == HebiStatus.playing;
    return IconPill(
      key: const ValueKey<String>('hebi.pause'),
      glyph: over ? Glyph.refresh : (playing ? Glyph.pause : Glyph.play),
      semanticLabel: over ? l.tsumikiNewGame : (playing ? l.tsumikiPause : l.tsumikiResume),
      diameter: diameter,
      onPressed: () {
        if (over) {
          _newGame();
        } else if (playing) {
          _pause();
        } else if (_game.status == HebiStatus.paused) {
          _resume();
        } else if (_countFrom == null) {
          _startCountdown();
        }
      },
    );
  }

  /// Los mandos: cruceta a la izquierda, pausa en medio y A (acelerar) a la
  /// derecha.
  Widget _controls(L l, {required double pad, required double button}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DPad(
          key: const ValueKey<String>('hebi.dpad'),
          size: pad,
          semanticLabel: l.hebiPad,
          onDown: (d) => _turn(switch (d) {
            PadDir.left => HebiDir.left,
            PadDir.right => HebiDir.right,
            PadDir.down => HebiDir.down,
            PadDir.up => HebiDir.up,
          }),
          onUp: (_) {},
        ),
        Expanded(child: Center(child: _pauseButton(l))),
        PadButton(
          key: const ValueKey<String>('hebi.a'),
          letter: 'A',
          size: button,
          semanticLabel: l.hebiBoost,
          onDown: () => _setBoost(true),
          onUp: () => _setBoost(false),
        ),
      ],
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
                _controls(l, pad: 128, button: 64),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  _field(context, box, tall: false),
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
    final stageSize = small ? 64.0 : 88.0;
    return Column(
      children: [
        SizedBox(height: small ? 6 : 12),
        // Arriba, el Tama con su bocadillo y los marcadores en fila.
        SizedBox(
          height: small ? 120 : 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: StageLight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(child: SpeechBubble(text: _bubble, maxWidth: 200)),
                      _stage(tama, stageSize),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: small ? 120 : 136, child: _readouts(l, height: small ? 34 : 42, compact: true)),
            ],
          ),
        ),
        SizedBox(height: small ? 6 : 10),
        Expanded(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, box) => Align(
                  alignment: Alignment.topCenter,
                  child: _field(context, box, tall: true),
                ),
              ),
              Positioned.fill(child: Center(child: PopBanner(text: _banner, big: _bannerBig))),
              Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l)))),
            ],
          ),
        ),
        SizedBox(height: small ? 6 : 12),
        _controls(l, pad: small ? 116 : 136, button: small ? 56 : 64),
        SizedBox(height: small ? 8 : 16),
      ],
    );
  }
}
