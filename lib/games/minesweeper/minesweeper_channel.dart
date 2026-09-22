// Ibasho — canal del buscaminas: una sola escena, con tu Tama al lado.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
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
import '../../ui/widgets/overlays.dart';
import 'minesweeper.dart';
import 'minesweeper_board.dart';
import 'minesweeper_store.dart';
import 'minesweeper_widgets.dart';

/// Semilla fija para los recorridos visuales: con ella cada captura enseña
/// la misma partida. En la app es siempre `null`.
@visibleForTesting
int? debugMinesweeperSeed;

/// Monedas de una victoria, por tablero. Las reglas solo aceptan estas
/// cantidades (o lo que falte para llegar al tope del dia).
int rewardFor(BoardChoice choice) => choice.daily
    ? 5
    : switch (choice.level!) {
        MinesweeperLevel.easy => 3,
        MinesweeperLevel.medium => 5,
        MinesweeperLevel.hard => 8,
      };

/// El canal del buscaminas.
///
/// Una sola escena en vez de dos pantallas: a un lado el escenario, con uno
/// de tus Tamas (otro al azar en cada ronda) que reacciona a cada jugada y
/// habla en un bocadillo, los marcadores y los tableros; al otro, el tablero
/// sobre su bandeja de plastico. En vertical el escenario se queda arriba en
/// una franja y los controles abajo, al alcance del pulgar.
///
/// El tablero anima cada casilla que se destapa (en ola desde el toque), cada
/// bandera que se clava, la explosion y el confeti de la victoria. Ganar abre
/// la pantalla de resultados: tiempo, medalla, sellos y las monedas cobradas.
class MinesweeperChannel extends ConsumerStatefulWidget {
  const MinesweeperChannel({super.key});

  @override
  ConsumerState<MinesweeperChannel> createState() => _MinesweeperChannelState();
}

class _MinesweeperChannelState extends ConsumerState<MinesweeperChannel>
    with SingleTickerProviderStateMixin {
  BoardChoice _choice = const BoardChoice.level(MinesweeperLevel.easy);
  late MinesweeperGame _game = _newGame(_choice);

  final math.Random _random = math.Random();

  /// El Tama de esta ronda: uno de los tuyos, al azar.
  String? _tamaId;
  final TamaViewController _tama = TamaViewController();

  /// -1 (KO) a 1 (encantado).
  double _joy = .2;

  String? _bubble;
  Timer? _bubbleTimer;
  bool _greeted = false;

  /// Destapes seguidos sin fallar, para cantar las rachas.
  int _streak = 0;

  Stopwatch? _stopwatch;
  Timer? _ticker;

  MinesweeperStore? _store;
  MinesweeperRecords _records = const MinesweeperRecords();

  WinReport? _report;
  bool _showResults = false;
  RewardOutcome? _reward;
  bool _rewardPending = false;
  Timer? _resultsTimer;

  bool _flagMode = false;

  // --- Efectos ---
  final BoardFx _fx = BoardFx();
  /// El reloj de efectos solo avanza mientras corre el ticker: parado no
  /// hay nada que mover, y al arrancar sigue desde donde se quedo.
  double _fxTime = 0;
  double _fxBase = 0;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  final ValueNotifier<int?> _hover = ValueNotifier<int?>(null);
  late final Ticker _fxTicker;

  /// Solo en dificil sobre un lienzo vertical: el tablero no cabe entero y
  /// se desplaza y amplia con el dedo.
  final TransformationController _viewController = TransformationController();

  double get _now => _fxTime;

  MinesweeperGame _newGame(BoardChoice choice) => choice.daily
      ? MinesweeperGame.daily(DateTime.now())
      : MinesweeperGame(choice.level!, seed: debugMinesweeperSeed);

  @override
  void initState() {
    super.initState();
    _fxTicker = createTicker(_onFxTick);
    unawaited(_loadStore());
  }

  Future<void> _loadStore() async {
    final store = await MinesweeperStore.open();
    final records = await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _records = records;
    });
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _ticker?.cancel();
    _resultsTimer?.cancel();
    _fxTicker.dispose();
    _clock.dispose();
    _hover.dispose();
    _viewController.dispose();
    super.dispose();
  }

  // --- Reloj de efectos -----------------------------------------------------

  bool get _reduced => IbashoSkin.of(context).reducedMotion;

  /// Mientras haga falta: un efecto en curso, la salida del dia latiendo o el
  /// Tama temblando con las ultimas casillas.
  bool get _wantsTicks =>
      _now < _fx.busyUntil ||
      (_game.start != null && _game.status == MinesweeperStatus.ready) ||
      _nervous;

  bool get _nervous =>
      _game.status == MinesweeperStatus.playing && _game.safeLeft > 0 && _game.safeLeft <= 3;

  void _onFxTick(Duration elapsed) {
    _fxTime = _fxBase + elapsed.inMicroseconds / 1e6;
    _clock.value = _fxTime;
    if (!_wantsTicks) {
      _fxTicker.stop();
      _fxBase = _fxTime;
    }
  }

  void _kickFx() {
    if (_reduced) {
      _clock.value = _now + 60;
      return;
    }
    _clock.value = _now;
    if (!_fxTicker.isActive && _wantsTicks) {
      _fxBase = _fxTime;
      _fxTicker.start();
    }
  }

  // --- Tama y bocadillo -----------------------------------------------------

  void _pickTama() {
    final tamas = ref.read(tamasProvider).tamas;
    if (tamas.isEmpty) {
      _tamaId = null;
      return;
    }
    // Otro distinto al de la ronda anterior, si hay donde elegir.
    final pool = tamas.length > 1 ? tamas.where((t) => t.id != _tamaId).toList() : tamas;
    _tamaId = pool[_random.nextInt(pool.length)].id;
  }

  Tama? _currentTama() {
    final tamas = ref.watch(tamasProvider).tamas;
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

  // --- Partida ----------------------------------------------------------------

  void _restart([BoardChoice? choice]) {
    final l = L.of(context)!;
    _ticker?.cancel();
    _resultsTimer?.cancel();
    _stopwatch = null;
    _viewController.value = Matrix4.identity();
    _fx.clear();
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _choice = choice ?? _choice;
      _game = _newGame(_choice);
      _joy = .2;
      _streak = 0;
      _flagMode = false;
      _report = null;
      _showResults = false;
      _reward = null;
      _rewardPending = false;
      _pickTama();
      _say(_choice.daily ? l.minesweeperBubbleDaily : l.minesweeperBubbleStart);
    });
    _kickFx();
    _tama.hop();
  }

  void _startTimerIfNeeded() {
    if (_stopwatch != null) return;
    _stopwatch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch?.stop();
  }

  Set<int> _revealedNow() => {
        for (var y = 0; y < _game.height; y++)
          for (var x = 0; x < _game.width; x++)
            if (_game.cellAt(x, y).revealed) y * _game.width + x,
      };

  void _reveal(int x, int y) {
    if (_game.isOver) return;
    if (_game.cellAt(x, y).flagged) return;
    final l = L.of(context)!;
    final wasReady = _game.status == MinesweeperStatus.ready;
    final before = _revealedNow();
    _game.reveal(x, y);
    final fresh = _revealedNow().difference(before);
    if (wasReady && _game.status != MinesweeperStatus.ready) _startTimerIfNeeded();

    final now = _now;
    for (final i in fresh) {
      final cx = i % _game.width;
      final cy = i ~/ _game.width;
      final dist = math.sqrt(((cx - x) * (cx - x) + (cy - y) * (cy - y)).toDouble());
      final mine = _game.cellAt(cx, cy).mine;
      final start = now + (mine && _game.status == MinesweeperStatus.lost
          ? (cx == x && cy == y ? 0 : .35 + dist * .06)
          : math.min(.9, dist * .028));
      _fx.reveal[i] = start;
      _fx.touch(start + BoardFx.revealTime);
    }

    switch (_game.status) {
      case MinesweeperStatus.won:
        _onWin();
      case MinesweeperStatus.lost:
        _stopTimer();
        _streak = 0;
        _fx
          ..boomAt = now
          ..boomCell = y * _game.width + x
          ..touch(now + BoardFx.boomTime);
        AudioService.instance.play(Sfx.error);
        _joy = -1;
        _say(l.minesweeperBubbleBoom, hold: const Duration(seconds: 4));
        _tama.hop();
        unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _tama.speak(ChirpKind.sigh);
        }));
      case MinesweeperStatus.playing:
        if (fresh.isEmpty) break;
        AudioService.instance.play(Sfx.tick);
        _streak++;
        if (fresh.length >= 12) {
          _joy = .8;
          _say(l.minesweeperBubbleBig);
          _tama.hop();
        } else if (_streak % 10 == 0) {
          _joy = .7;
          _say(l.minesweeperBubbleStreak(_streak));
          _tama.hop();
        } else if (_nervous) {
          _joy = -.2;
          _say(l.minesweeperBubbleAlmost, hold: const Duration(seconds: 3));
        } else {
          _joy = .35;
        }
      case MinesweeperStatus.ready:
        break;
    }
    setState(() {});
    _kickFx();
  }

  void _toggleFlag(int x, int y) {
    if (_game.isOver) return;
    final cell = _game.cellAt(x, y);
    if (cell.revealed) return;
    final l = L.of(context)!;
    final wasReady = _game.status == MinesweeperStatus.ready;
    _game.toggleFlag(x, y);
    if (wasReady && _game.status != MinesweeperStatus.ready) _startTimerIfNeeded();
    final i = y * _game.width + x;
    if (cell.flagged) {
      _fx.flags[i] = _now;
      _fx.touch(_now + BoardFx.flagTime);
      // Solo de vez en cuando: si lo dijera siempre, cansaria.
      if (_random.nextDouble() < .3) _say(l.minesweeperBubbleFlag);
    } else {
      _fx.flags.remove(i);
    }
    AudioService.instance.play(Sfx.tick);
    setState(() {});
    _kickFx();
  }

  void _cellTap(int x, int y) => _flagMode ? _toggleFlag(x, y) : _reveal(x, y);

  void _onWin() {
    final l = L.of(context)!;
    _stopTimer();
    final now = _now;
    _fx
      ..winAt = now + .25
      ..touch(now + .25 + BoardFx.winTime);
    // Las minas sin bandera se marcan solas al ganar: que caigan en ola.
    for (var y = 0; y < _game.height; y++) {
      for (var x = 0; x < _game.width; x++) {
        final i = y * _game.width + x;
        if (_game.cellAt(x, y).flagged && !_fx.flags.containsKey(i)) {
          _fx.flags[i] = now + .1 + (x + y) * .03;
        }
      }
    }
    AudioService.instance.play(Sfx.chime);
    _joy = 1;
    _say(l.minesweeperBubbleWin, hold: const Duration(seconds: 5));
    _tama
      ..cuddle()
      ..hop();

    final time = _stopwatch?.elapsed ?? Duration.zero;
    final (records, report) = _records.recordWin(
      level: _choice.effectiveLevel,
      time: time,
      usedFlags: _game.usedFlags,
      day: _choice.daily ? DateTime.now() : null,
    );
    _records = records;
    _report = report;
    unawaited(_store?.save(records));
    unawaited(_claimReward());
    _resultsTimer = Timer(Duration(milliseconds: _reduced ? 150 : 1300), () {
      if (mounted) setState(() => _showResults = true);
    });
  }

  Future<void> _claimReward() async {
    setState(() => _rewardPending = true);
    final outcome = await ref
        .read(rewardsProvider.notifier)
        .claim(game: 'minesweeper', amount: rewardFor(_choice));
    if (!mounted) return;
    setState(() {
      _reward = outcome;
      _rewardPending = false;
    });
  }

  Future<void> _pickBoard() async {
    final picked = await showIbashoModal<BoardChoice>(
      context,
      (context) => _LevelDialog(current: _choice, records: _records),
    );
    if (picked != null && mounted) _restart(picked);
  }

  // --- Composicion ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tama = _currentTama();
    if (!_greeted) {
      _greeted = true;
      _say(l.minesweeperBubbleStart);
    }
    if (_game.start != null && _game.status == MinesweeperStatus.ready && !_fxTicker.isActive && !_reduced) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kickFx();
      });
    }

    return ChannelScaffold(
      title: l.minesweeperTitle,
      glyph: Glyph.mine,
      art: ArtIcon.minesweeper,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: layout.tall ? _tallLayout(context, tama) : _wideLayout(context, tama),
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
        final t = _clock.value;
        // Con las ultimas casillas tiembla un poco; al perder se agacha.
        final tremble = _nervous && !_reduced ? math.sin(t * 38) * 1.6 : 0.0;
        return Transform.translate(offset: Offset(tremble, 0), child: child);
      },
      child: KeyedSubtree(key: ValueKey<String>('minesweeper.tama.${tama?.id}'), child: face),
    );
  }

  Widget _readouts(L l, {required double height, bool row = true}) {
    final elapsed = _stopwatch?.elapsed ?? Duration.zero;
    final mines = Readout(
      key: const ValueKey<String>('minesweeper.mines'),
      icon: const BombIcon(),
      value: '${_game.minesLeft}',
      label: l.minesweeperMinesLeft,
      height: height,
    );
    final time = Readout(
      icon: GlyphIcon(Glyph.clock, size: height * .5, color: IbashoSkin.of(context).accentDeep, strokeWidth: 2.2),
      value: formatDuration(elapsed),
      label: l.minesweeperTime,
      height: height,
    );
    return Row(
      children: [
        Expanded(child: mines),
        SizedBox(width: row ? 10 : 8),
        Expanded(child: time),
      ],
    );
  }

  Widget _newRoundButton(L l, {double height = 52, bool expand = false}) {
    final over = _game.isOver;
    return IbashoButton(
      key: const ValueKey<String>('minesweeper.restart'),
      label: l.minesweeperNewRound,
      glyph: Glyph.refresh,
      tone: over ? ButtonTone.accent : ButtonTone.plain,
      height: height,
      expand: expand,
      onPressed: () => _restart(),
    );
  }

  Widget _boardArea(BuildContext context, {required bool tall}) {
    final layout = Layout.of(context);
    final skin = IbashoSkin.of(context);
    final report = _report;
    return LayoutBuilder(builder: (context, box) {
      final pad = tall ? 10.0 : 16.0;
      final avail = Size(box.maxWidth - pad * 2, box.maxHeight - pad * 2);
      final natural = math.min(avail.width / _game.width, avail.height / _game.height).clamp(18.0, 68.0);
      // Solo si las casillas quedarian diminutas (el dificil en un movil) se
      // fija un tamaño que se pueda tocar y se deja desplazar y ampliar.
      final needsViewer = tall && natural < 27;
      final cell = needsViewer ? math.max(40.0, layout.touch * .85) : natural.floorToDouble();

      final board = MinesweeperBoard(
        game: _game,
        cellSize: cell,
        fx: _fx,
        clock: _clock,
        hover: _hover,
        accent: skin.accent,
        onCellTap: _cellTap,
        onCellFlag: _toggleFlag,
      );

      final boardW = needsViewer ? avail.width : _game.width * cell;
      final boardH = needsViewer ? avail.height : _game.height * cell;

      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: boardW + pad * 2,
            height: boardH + pad * 2,
            child: GlossSurface(
              radius: tall ? 22 : 30,
              tint: skin.accentWash,
              elevation: 2,
              padding: EdgeInsets.all(pad),
              child: needsViewer
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: InteractiveViewer(
                        transformationController: _viewController,
                        minScale: 1,
                        maxScale: 3,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(24),
                        child: board,
                      ),
                    )
                  : board,
            ),
          ),
          if (report != null && _showResults)
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: ResultsCard(
                      report: report,
                      daily: _choice.daily,
                      reward: _reward,
                      rewardPending: _rewardPending,
                      level: _choice.effectiveLevel,
                      onAgain: () => _restart(),
                      onDismiss: () => setState(() => _showResults = false),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _wideLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 22),
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
                        _stage(tama, 176),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                _readouts(l, height: 58),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, box) {
                  const gap = 10.0;
                  final w = (box.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final c in BoardChoice.all)
                        LevelCard(
                          choice: c,
                          selected: c == _choice,
                          records: _records,
                          width: w,
                          height: 64,
                          onPressed: () {
                            if (c != _choice) _restart(c);
                          },
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 16),
                ModeSwitch(
                  flagMode: _flagMode,
                  onChanged: (v) => setState(() => _flagMode = v),
                  digLabel: l.minesweeperDig,
                  flagLabel: l.minesweeperFlag,
                  height: 50,
                  width: 352,
                ),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: _newRoundButton(l, expand: true)),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(child: _boardArea(context, tall: false)),
        ],
      ),
    );
  }

  Widget _tallLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final small = layout.height < 700;
    // En un movil alto el tablero se queda con el ancho y sobra alto: se lo
    // lleva el escenario del Tama.
    final roomy = layout.height > 840;
    final stageSize = small ? 74.0 : (roomy ? 128.0 : 96.0);
    return Column(
      children: [
        SizedBox(height: small ? 6 : 12),
        SizedBox(
          height: small ? 112 : (roomy ? 196 : 150),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: stageSize + 34,
                child: StageLight(
                  child: Align(alignment: Alignment.bottomCenter, child: _stage(tama, stageSize)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: SpeechBubble(text: _bubble, maxWidth: 200),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _readouts(l, height: small ? 46 : 52, row: false),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: small ? 8 : 14),
        Expanded(child: _boardArea(context, tall: true)),
        SizedBox(height: small ? 8 : 14),
        Row(
          children: [
            ModeSwitch(
              flagMode: _flagMode,
              onChanged: (v) => setState(() => _flagMode = v),
              digLabel: l.minesweeperDig,
              flagLabel: l.minesweeperFlag,
              height: 48,
              showLabels: false,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: IbashoButton(
                key: const ValueKey<String>('minesweeper.levels'),
                label: _choice.daily ? l.minesweeperDaily : levelName(l, _choice.effectiveLevel),
                glyph: Glyph.chevronDown,
                height: 48,
                expand: true,
                onPressed: () => unawaited(_pickBoard()),
              ),
            ),
            const SizedBox(width: 8),
            IconPill(
              key: const ValueKey<String>('minesweeper.restart'),
              glyph: Glyph.refresh,
              tone: _game.isOver ? ButtonTone.accent : ButtonTone.plain,
              semanticLabel: l.minesweeperNewRound,
              diameter: 48,
              onPressed: () => _restart(),
            ),
          ],
        ),
        SizedBox(height: small ? 10 : 16),
      ],
    );
  }
}

/// En vertical los tableros se eligen en un dialogo: las mismas tarjetas que
/// en horizontal, una debajo de otra.
class _LevelDialog extends StatelessWidget {
  const _LevelDialog({required this.current, required this.records});

  final BoardChoice current;
  final MinesweeperRecords records;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.minesweeperChooseLevel,
      width: 360,
      body: LayoutBuilder(
        builder: (context, box) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in BoardChoice.all) ...[
              LevelCard(
                choice: c,
                selected: c == current,
                records: records,
                width: box.maxWidth,
                height: 62,
                onPressed: () => Navigator.of(context).pop(c),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actions: [
        IbashoButton(
          label: l.actionCancel,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
