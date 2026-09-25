// Ibasho — canal de Ohirune: cada Tama busca su sitio para la siesta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
import '../../backend/leaderboards.dart';
import '../../backend/missions.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/login_bonus.dart';
import '../../state/providers.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
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
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/slot_tile.dart';
import '../game_stage.dart';
import '../minesweeper/minesweeper_widgets.dart' show formatDuration;
import 'ohirune.dart';
import 'ohirune_board.dart';
import 'ohirune_store.dart';

/// Semilla fija para los recorridos visuales. En la app es siempre `null`.
@visibleForTesting
int? debugOhiruneSeed;

/// Qué tablero se juega: un nivel o el del día.
@immutable
class OhiruneChoice {
  const OhiruneChoice.level(OhiruneLevel this.level) : daily = false;
  const OhiruneChoice.daily() : level = null, daily = true;

  final OhiruneLevel? level;
  final bool daily;

  OhiruneLevel get effectiveLevel => level ?? ohiruneDailyLevel;

  String get id => daily ? 'daily' : level!.name;

  static const List<OhiruneChoice> all = [
    OhiruneChoice.level(OhiruneLevel.easy),
    OhiruneChoice.level(OhiruneLevel.normal),
    OhiruneChoice.level(OhiruneLevel.hard),
    OhiruneChoice.level(OhiruneLevel.expert),
    OhiruneChoice.level(OhiruneLevel.master),
    OhiruneChoice.daily(),
  ];

  @override
  bool operator ==(Object other) => other is OhiruneChoice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Monedas de una siesta completa. Las reglas solo aceptan subidas de 3, 5
/// u 8 (o lo que falte hasta el tope del día).
int ohiruneRewardFor(OhiruneChoice choice) => choice.daily
    ? 5
    : switch (choice.level!) {
        OhiruneLevel.easy || OhiruneLevel.normal => 3,
        OhiruneLevel.hard || OhiruneLevel.expert => 5,
        OhiruneLevel.master => 8,
      };

/// Lo que cuenta en la clasificación del día: el tiempo más 20 s por vida
/// perdida, en milisegundos.
int ohiruneBoardScore(Duration time, int livesLost) =>
    (time + ohiruneLifePenalty * livesLost).inMilliseconds.clamp(1, LeaderboardGame.ohirune.maxScore);

String ohiruneLevelName(L l, OhiruneLevel level) => switch (level) {
  OhiruneLevel.easy => l.ohiruneEasy,
  OhiruneLevel.normal => l.ohiruneNormal,
  OhiruneLevel.hard => l.ohiruneHard,
  OhiruneLevel.expert => l.ohiruneExpert,
  OhiruneLevel.master => l.ohiruneMaster,
};

/// El canal secreto de Ohirune.
///
/// Una sola escena, como el buscaminas: a un lado el escenario con uno de
/// tus Tamas, las vidas, el tiempo y los tableros; al otro, el tablero. Cada
/// zona de color es de uno de tus Tamas y hay que encontrarle sitio para la
/// siesta: uno por fila, por columna y por zona, sin tocarse ni en diagonal.
/// Dormir a un Tama donde no va cuesta una vida; las X son gratis.
class OhiruneChannel extends ConsumerStatefulWidget {
  const OhiruneChannel({super.key});

  @override
  ConsumerState<OhiruneChannel> createState() => _OhiruneChannelState();
}

class _OhiruneChannelState extends ConsumerState<OhiruneChannel> with SingleTickerProviderStateMixin {
  OhiruneChoice _choice = const OhiruneChoice.level(OhiruneLevel.easy);
  OhiruneGame? _game;

  /// Los Tamas de esta partida, uno por zona.
  List<Tama> _sleepers = const <Tama>[];
  List<Color> _zones = const <Color>[];

  final math.Random _random = math.Random();

  String? _tamaId;
  final TamaViewController _tama = TamaViewController();
  double _joy = .2;
  String? _bubble;
  Timer? _bubbleTimer;
  bool _started = false;

  bool _crossMode = false;

  Stopwatch? _stopwatch;
  Timer? _ticker;

  OhiruneStore? _store;
  OhiruneRecords _records = const OhiruneRecords();

  bool _showResults = false;
  bool _newRecord = false;
  RewardOutcome? _reward;
  bool _rewardPending = false;
  Timer? _resultsTimer;

  final OhiruneFx _fx = OhiruneFx();
  double _fxTime = 0;
  double _fxBase = 0;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _fxTicker;

  double get _now => _fxTime;

  @override
  void initState() {
    super.initState();
    _fxTicker = createTicker(_onFxTick);
    unawaited(_loadStore());
  }

  Future<void> _loadStore() async {
    final store = await OhiruneStore.open();
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
    super.dispose();
  }

  // --- Reloj de efectos -----------------------------------------------------

  bool get _reduced => IbashoSkin.of(context).reducedMotion;

  void _onFxTick(Duration elapsed) {
    _fxTime = _fxBase + elapsed.inMicroseconds / 1e6;
    _clock.value = _fxTime;
    if (_now >= _fx.busyUntil) {
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
    if (!_fxTicker.isActive && _now < _fx.busyUntil) {
      _fxBase = _fxTime;
      _fxTicker.start();
    }
  }

  // --- Tamas ------------------------------------------------------------------

  int get _tamaCount => ref.read(tamasProvider).tamas.length;

  bool _playable(OhiruneChoice c, int tamas) => tamas >= c.effectiveLevel.tamasNeeded;

  bool _dailyDone() => _records.dailyDone(bonusDay());

  Tama? _currentTama(List<Tama> tamas) {
    if (tamas.isEmpty) return null;
    if (_tamaId == null || !tamas.any((t) => t.id == _tamaId)) {
      _tamaId = tamas[_random.nextInt(tamas.length)].id;
    }
    return tamas.firstWhere((t) => t.id == _tamaId);
  }

  void _say(String? text, {Duration hold = const Duration(milliseconds: 2200)}) {
    _bubbleTimer?.cancel();
    _bubble = text;
    if (text == null) return;
    _bubbleTimer = Timer(hold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  // --- Partida ----------------------------------------------------------------

  void _restart([OhiruneChoice? choice]) {
    final l = L.of(context)!;
    final tamas = ref.read(tamasProvider).tamas;
    var next = choice ?? _choice;
    final dailyLocked = next.daily && _dailyDone();
    if (dailyLocked || !_playable(next, tamas.length)) {
      // Se busca el nivel mas alto que se pueda jugar con los Tamas que hay.
      next = OhiruneChoice.all.lastWhere(
        (c) => !c.daily && _playable(c, tamas.length),
        orElse: () => const OhiruneChoice.level(OhiruneLevel.easy),
      );
    }
    _ticker?.cancel();
    _resultsTimer?.cancel();
    _stopwatch = null;
    _fx.clear();
    final level = next.effectiveLevel;
    OhiruneGame? game;
    var sleepers = const <Tama>[];
    if (_playable(next, tamas.length)) {
      final seed = next.daily ? bonusDay() : (debugOhiruneSeed ?? _random.nextInt(1 << 31));
      game = OhiruneGame(next.daily ? OhirunePuzzle.daily(seed) : OhirunePuzzle.generate(level.size, seed: seed));
      // Quien duerme en cada zona: los Tamas de la cuenta, barajados. El del
      // dia baraja siempre igual, para que al volver a entrar no cambie.
      sleepers = (List<Tama>.of(tamas)..shuffle(math.Random(seed))).take(level.size).toList();
    }
    if (_started) AudioService.instance.play(Sfx.tick);
    setState(() {
      _started = true;
      _choice = next;
      _game = game;
      _sleepers = sleepers;
      _zones = ohiruneZoneColors(sleepers);
      _joy = .2;
      _showResults = false;
      _newRecord = false;
      _reward = null;
      _rewardPending = false;
      if (tamas.isNotEmpty) {
        final pool = tamas.length > 1 ? tamas.where((t) => t.id != _tamaId).toList() : tamas;
        _tamaId = pool[_random.nextInt(pool.length)].id;
      }
      _say(
        game == null
            ? l.ohiruneLockedBubble
            : dailyLocked
            ? l.ohiruneBubbleDailyLocked
            : (next.daily ? l.ohiruneBubbleDaily : l.ohiruneBubbleStart),
        hold: const Duration(seconds: 4),
      );
    });
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

  void _place(int x, int y) {
    final game = _game;
    if (game == null || game.isOver) return;
    final l = L.of(context)!;
    _startTimerIfNeeded();
    final i = y * game.size + x;
    // Antes de poner: con que Tamas chocaria, para encender la regla rota.
    final clash = game.clashAt(x, y);
    switch (game.place(x, y)) {
      case OhirunePlace.ignored:
        return;
      case OhirunePlace.placed:
        _fx.placed[i] = _now;
        _fx.touch(_now + OhiruneFx.placeTime);
        if (game.status == OhiruneStatus.won) {
          _onWin();
        } else {
          AudioService.instance.play(Sfx.tick);
          _joy = .6;
          if (_random.nextDouble() < .3) _say(l.ohiruneBubblePlace);
        }
      case OhirunePlace.miss:
        _fx.misses[i] = _now;
        _fx.touch(_now + OhiruneFx.missTime);
        if (clash.any) {
          _fx
            ..clashAt = _now
            ..clashArea = game.clashArea(x, y, clash)
            ..culprits = clash.culprits
            ..touch(_now + OhiruneFx.clashTime);
        }
        AudioService.instance.play(Sfx.error);
        _tama.hop();
        if (game.status == OhiruneStatus.lost) {
          _stopTimer();
          _joy = -1;
          _say(l.ohiruneBubbleLost, hold: const Duration(seconds: 4));
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _tama.speak(ChirpKind.sigh);
            }),
          );
        } else {
          _joy = game.lives == 1 ? -.5 : -.2;
          _say(game.lives == 1 ? l.ohiruneBubbleLastLife : l.ohiruneBubbleMiss, hold: const Duration(seconds: 3));
        }
    }
    setState(() {});
    _kickFx();
  }

  void _cross(int x, int y, bool on) {
    final game = _game;
    if (game == null || game.isOver) return;
    _startTimerIfNeeded();
    game.setCross(x, y, on);
    AudioService.instance.play(Sfx.tick);
    setState(() {});
  }

  void _onWin() {
    final l = L.of(context)!;
    final game = _game!;
    _stopTimer();
    _fx
      ..winAt = _now + .35
      ..touch(_now + .35 + OhiruneFx.winTime);
    AudioService.instance.play(Sfx.chime);
    _joy = 1;
    _say(l.ohiruneBubbleWin, hold: const Duration(seconds: 5));
    _tama
      ..cuddle()
      ..hop();

    final time = _stopwatch?.elapsed ?? Duration.zero;
    final day = _choice.daily ? bonusDay() : null;
    final (records, record) = _records.recordWin(
      level: _choice.effectiveLevel,
      time: time,
      livesLost: game.livesLost,
      day: day,
    );
    _records = records;
    _newRecord = record;
    unawaited(_store?.save(records));
    unawaited(_claimReward());
    // Solo el del dia puntua: es el mismo tablero para todo el mundo.
    if (_choice.daily) {
      unawaited(
        ref
            .read(leaderboardsProvider.notifier)
            .submitScore(LeaderboardGame.ohirune, ohiruneBoardScore(time, game.livesLost)),
      );
    }
    unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.play));
    _resultsTimer = Timer(Duration(milliseconds: _reduced ? 150 : 1600), () {
      if (mounted) setState(() => _showResults = true);
    });
  }

  Future<void> _claimReward() async {
    setState(() => _rewardPending = true);
    final outcome = await ref.read(rewardsProvider.notifier).claim(game: 'ohirune', amount: ohiruneRewardFor(_choice));
    if (!mounted) return;
    setState(() {
      _reward = outcome;
      _rewardPending = false;
    });
  }

  Future<void> _pickBoard() async {
    final picked = await showIbashoModal<OhiruneChoice>(
      context,
      (context) => _LevelDialog(current: _choice, records: _records, tamas: _tamaCount),
    );
    if (picked != null && mounted) _restart(picked);
  }

  // --- Composicion ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tamas = ref.watch(tamasProvider.select((t) => t.tamas));
    if (!_started) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_started) _restart();
      });
    }
    final tama = _currentTama(tamas);
    return ChannelScaffold(
      title: l.channelOhirune,
      glyph: Glyph.moon,
      art: ArtIcon.ohirune,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: layout.tall ? _tallLayout(context, tama, tamas.length) : _wideLayout(context, tama, tamas.length),
      ),
    );
  }

  Widget _stage(Tama? tama, double size) {
    final face = tama == null
        ? GlossyFace(joy: _joy, size: size)
        : TamaOnStand(tama: tama, size: size, joy: _joy, controller: _tama);
    return KeyedSubtree(key: ValueKey<String>('ohirune.tama.${tama?.id}'), child: face);
  }

  Widget _readouts(L l, {required double height}) {
    final elapsed = _stopwatch?.elapsed ?? Duration.zero;
    return Row(
      children: [
        Expanded(
          child: _LivesReadout(lives: _game?.lives ?? ohiruneLives, label: l.ohiruneLives, height: height),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Readout(
            icon: GlyphIcon(Glyph.clock, size: height * .5, color: IbashoSkin.of(context).accentDeep, strokeWidth: 2.2),
            value: formatDuration(elapsed),
            label: l.ohiruneTime,
            height: height,
          ),
        ),
      ],
    );
  }

  Widget _markSwitch(L l, {required double height, required bool labels, double? width}) => _MarkSwitch(
    cross: _crossMode,
    onChanged: (v) => setState(() => _crossMode = v),
    napLabel: l.ohiruneModeNap,
    crossLabel: l.ohiruneModeCross,
    height: height,
    showLabels: labels,
    width: width,
  );

  Widget _boardArea(BuildContext context, {required bool tall, required int tamaCount}) {
    final skin = IbashoSkin.of(context);
    final game = _game;
    return LayoutBuilder(
      builder: (context, box) {
        if (game == null) {
          return Center(child: _LockedCard(missing: math.max(1, ohiruneUnlockTamas - tamaCount)));
        }
        final pad = tall ? 10.0 : 16.0;
        final avail = math.min(box.maxWidth, box.maxHeight) - pad * 2;
        final cell = (avail / game.size).clamp(24.0, 140.0).floorToDouble();
        final side = cell * game.size;
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: side + pad * 2,
              height: side + pad * 2,
              child: GlossSurface(
                radius: tall ? 22 : 30,
                tint: skin.accentWash,
                elevation: 2,
                padding: EdgeInsets.all(pad),
                child: OhiruneBoard(
                  game: game,
                  cellSize: cell,
                  zones: _zones,
                  looks: [for (final t in _sleepers) t.look],
                  fx: _fx,
                  clock: _clock,
                  crossMode: _crossMode,
                  onPlace: _place,
                  onCross: _cross,
                ),
              ),
            ),
            if (_showResults && game.status == OhiruneStatus.won)
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: _ResultsCard(
                        daily: _choice.daily,
                        time: _stopwatch?.elapsed ?? Duration.zero,
                        best: _records.best[_choice.effectiveLevel],
                        livesLost: game.livesLost,
                        newRecord: _newRecord,
                        reward: _reward,
                        rewardPending: _rewardPending,
                        onAgain: () => _restart(),
                        onDismiss: () => setState(() => _showResults = false),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// «Otra siesta» se vuelve el boton de acento al acabar, salvo con los
  /// resultados encima: ahi el acento es el suyo.
  ButtonTone get _restartTone =>
      (_game?.isOver ?? false) && !_showResults ? ButtonTone.accent : ButtonTone.plain;

  Widget _newRoundButton(L l) => IbashoButton(
    key: const ValueKey<String>('ohirune.restart'),
    label: l.ohiruneNewRound,
    glyph: Glyph.refresh,
    tone: _restartTone,
    expand: true,
    onPressed: () => _restart(),
  );

  Widget _wideLayout(BuildContext context, Tama? tama, int tamaCount) {
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
                        Flexible(child: SpeechBubble(text: _bubble, maxWidth: 260)),
                        const SizedBox(height: 6),
                        _stage(tama, 132),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
                _readouts(l, height: 54),
                const SizedBox(height: 10),
                const DailyCoinsMeter(game: 'ohirune', height: 40),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, box) {
                    const gap = 8.0;
                    final w = (box.maxWidth - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final c in OhiruneChoice.all)
                          _LevelCard(
                            choice: c,
                            selected: c == _choice,
                            records: _records,
                            tamas: tamaCount,
                            width: w,
                            height: 54,
                            onPressed: () {
                              if (c != _choice || _game == null) _restart(c);
                            },
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _markSwitch(l, height: 48, labels: true, width: 352),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: _newRoundButton(l)),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(child: _boardArea(context, tall: false, tamaCount: tamaCount)),
        ],
      ),
    );
  }

  Widget _tallLayout(BuildContext context, Tama? tama, int tamaCount) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final small = layout.height < 700;
    final roomy = layout.height > 840;
    final stageSize = small ? 74.0 : (roomy ? 128.0 : 96.0);
    final name = _choice.daily ? l.ohiruneDaily : ohiruneLevelName(l, _choice.effectiveLevel);
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
                    _readouts(l, height: small ? 46 : 52),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: small ? 8 : 14),
        Expanded(child: _boardArea(context, tall: true, tamaCount: tamaCount)),
        SizedBox(height: small ? 8 : 14),
        Row(
          children: [
            _markSwitch(l, height: 48, labels: false),
            const SizedBox(width: 8),
            Expanded(
              child: IbashoButton(
                key: const ValueKey<String>('ohirune.levels'),
                label: name,
                glyph: Glyph.chevronDown,
                height: 48,
                expand: true,
                onPressed: () => unawaited(_pickBoard()),
              ),
            ),
            const SizedBox(width: 8),
            IconPill(
              key: const ValueKey<String>('ohirune.restart'),
              glyph: Glyph.refresh,
              tone: _restartTone,
              semanticLabel: l.ohiruneNewRound,
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

// --- Piezas -------------------------------------------------------------------

/// Las vidas: tres corazones de plastico en un hueco. Uno perdido se queda
/// hundido y vacio.
class _LivesReadout extends StatelessWidget {
  const _LivesReadout({required this.lives, required this.label, required this.height});

  final int lives;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return SizedBox(
      key: const ValueKey<String>('ohirune.lives'),
      height: height,
      child: GlossSurface(
        radius: height / 2,
        recessed: true,
        padding: EdgeInsets.symmetric(horizontal: height * .26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < ohiruneLives; i++)
                    Padding(
                      padding: EdgeInsets.only(right: height * .06),
                      child: AnimatedScale(
                        scale: i < lives ? 1 : .82,
                        duration: skin.motion(const Duration(milliseconds: 320)),
                        curve: skin.curve(Curves.easeOutBack),
                        child: SizedBox.square(
                          dimension: height * .4,
                          child: CustomPaint(
                            painter: _HeartPainter(full: i < lives, hollow: skin.hairline),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(height: 1.1)),
          ],
        ),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter({required this.full, required this.hollow});

  final bool full;
  final Color hollow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24;
    final heart = Path()
      ..moveTo(12 * s, 21 * s)
      ..cubicTo(4 * s, 15.6 * s, 2 * s, 11.6 * s, 2 * s, 8.4 * s)
      ..cubicTo(2 * s, 5.2 * s, 4.6 * s, 3 * s, 7.4 * s, 3 * s)
      ..cubicTo(9.4 * s, 3 * s, 11 * s, 4.2 * s, 12 * s, 6 * s)
      ..cubicTo(13 * s, 4.2 * s, 14.6 * s, 3 * s, 16.6 * s, 3 * s)
      ..cubicTo(19.4 * s, 3 * s, 22 * s, 5.2 * s, 22 * s, 8.4 * s)
      ..cubicTo(22 * s, 11.6 * s, 20 * s, 15.6 * s, 12 * s, 21 * s)
      ..close();
    if (full) {
      paintPlastic(canvas, heart, T.wrong, edge: 1.4 * s);
    } else {
      canvas.drawPath(
        heart,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * s
          ..color = hollow,
      );
    }
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.full != full || old.hollow != hollow;
}

/// Dormir o marcar: dos posiciones en un rail hundido con un pomo que se
/// desliza, como el de cavar y bandera del buscaminas.
class _MarkSwitch extends StatelessWidget {
  const _MarkSwitch({
    required this.cross,
    required this.onChanged,
    required this.napLabel,
    required this.crossLabel,
    required this.height,
    required this.showLabels,
    this.width,
  });

  final bool cross;
  final ValueChanged<bool> onChanged;
  final String napLabel;
  final String crossLabel;
  final double height;
  final bool showLabels;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final knob = height - 8;
    final half = width != null ? (width! - 8) / 2 : (showLabels ? height * 2.3 : height * 1.05);

    Widget option(bool isCross) {
      final active = isCross == cross;
      final label = isCross ? crossLabel : napLabel;
      final color = active ? skin.accentDeep : Ty.inkSoft;
      return Pressable(
        key: ValueKey<String>('ohirune.mode.${isCross ? 'cross' : 'nap'}'),
        cue: null,
        semanticLabel: label,
        onPressed: () {
          if (active) return;
          AudioService.instance.play(Sfx.tick);
          onChanged(isCross);
        },
        builder: (context, state) => SizedBox(
          width: half,
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlyphIcon(isCross ? Glyph.cross : Glyph.moon, size: knob * .56, color: color, strokeWidth: 2.4),
              if (showLabels) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? skin.accentDeep : Color.lerp(Ty.inkSoft, Ty.ink, state.hover)!,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: half * 2 + 8,
      height: height,
      child: GlossSurface(
        radius: height / 2,
        recessed: true,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: skin.motion(const Duration(milliseconds: 260)),
              curve: skin.curve(Curves.easeOutBack),
              alignment: cross ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: half,
                  height: knob,
                  child: GlossSurface(
                    radius: knob / 2,
                    tint: skin.accentWash,
                    borderColor: skin.accentDeep,
                    borderWidth: 1.6,
                    elevation: 1.2,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [option(false), option(true)]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de un tablero: un mini tablero de colores, el nombre, la medida y
/// lo conseguido. Sin Tamas suficientes lleva candado y dice cuántos faltan.
class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.choice,
    required this.selected,
    required this.records,
    required this.tamas,
    required this.onPressed,
    required this.width,
    required this.height,
  });

  final OhiruneChoice choice;
  final bool selected;
  final OhiruneRecords records;
  final int tamas;
  final VoidCallback onPressed;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final level = choice.effectiveLevel;
    final missing = level.tamasNeeded - tamas;
    final today = records.daily[bonusDay()];
    final doneToday = choice.daily && today != null;
    final locked = missing > 0 || doneToday;
    final name = choice.daily ? l.ohiruneDaily : ohiruneLevelName(l, level);
    final sub = missing > 0
        ? l.ohiruneNeedTamas(missing)
        : doneToday
        ? l.ohiruneDailyLocked(formatDuration(today))
        : l.ohiruneLevelSize(level.size);
    final best = choice.daily ? null : records.best[level];
    return SlotTile(
      key: ValueKey<String>('ohirune.level.${choice.id}'),
      width: width,
      height: height,
      selected: selected,
      semanticLabel: name,
      onPressed: locked ? null : onPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: height * .16),
        child: Row(
          children: [
            SizedBox.square(
              dimension: height * .54,
              child: choice.daily
                  ? const ArtIconView(ArtIcon.calendar)
                  : CustomPaint(painter: _MiniBoardPainter(level.size)),
            ),
            SizedBox(width: height * .14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.body.copyWith(fontWeight: FontWeight.w600, height: 1.15),
                  ),
                  Text(
                    best != null && !locked ? '$sub · ${formatDuration(best)}' : sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.micro.copyWith(height: 1.2),
                  ),
                ],
              ),
            ),
            if (locked)
              GlyphIcon(Glyph.lock, size: height * .3, color: Ty.inkSoft, strokeWidth: 2.2)
            else if (!choice.daily && records.flawless.contains(level))
              GlyphIcon(Glyph.heart, size: height * .3, color: T.wrong, strokeWidth: 2.2),
          ],
        ),
      ),
    );
  }
}

/// Un tablero en miniatura con zonas de colores: más casillas cuanto más
/// grande. Los colores son de ilustración, como los de las piezas del Tsumiki.
class _MiniBoardPainter extends CustomPainter {
  const _MiniBoardPainter(this.size);

  final int size;

  static const List<Color> _zones = Art.capsules;

  @override
  void paint(Canvas canvas, Size box) {
    final n = size - 2;
    final u = box.shortestSide / n;
    final rnd = math.Random(size);
    final seeds = [for (var i = 0; i < n; i++) (rnd.nextInt(n), rnd.nextInt(n))];
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        var best = 0;
        var bestD = 1 << 30;
        for (var i = 0; i < seeds.length; i++) {
          final d = (seeds[i].$1 - x).abs() + (seeds[i].$2 - y).abs();
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        final r = Rect.fromLTWH(x * u + u * .06, y * u + u * .06, u * .88, u * .88);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(u * .2)),
          Paint()..color = Art.light(_zones[best % _zones.length], .25),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MiniBoardPainter old) => old.size != size;
}

/// Lo que ocupa el tablero mientras no hay Tamas para la siesta.
class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.missing});

  final int missing;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return ConstrainedBox(
      key: const ValueKey<String>('ohirune.locked'),
      constraints: const BoxConstraints(maxWidth: 360),
      child: GlossSurface(
        radius: 30,
        elevation: 2,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArtIconView(ArtIcon.ohirune, size: 96),
            const SizedBox(height: 10),
            Text(
              l.ohiruneLockedTitle,
              textAlign: TextAlign.center,
              style: Ty.title.copyWith(color: skin.accentDeep),
            ),
            const SizedBox(height: 8),
            Text(l.ohiruneLockedBody(missing, ohiruneUnlockTamas), textAlign: TextAlign.center, style: Ty.body),
          ],
        ),
      ),
    );
  }
}

/// Los resultados de una siesta completa, sobre el tablero con un rebote.
class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.daily,
    required this.time,
    required this.best,
    required this.livesLost,
    required this.newRecord,
    required this.reward,
    required this.rewardPending,
    required this.onAgain,
    required this.onDismiss,
  });

  final bool daily;
  final Duration time;
  final Duration? best;
  final int livesLost;
  final bool newRecord;
  final RewardOutcome? reward;
  final bool rewardPending;
  final VoidCallback onAgain;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlossSurface(
          key: const ValueKey<String>('ohirune.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                daily ? l.ohiruneDailyTitle : l.ohiruneWinTitle,
                style: Ty.title.copyWith(color: skin.accentDeep),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                formatDuration(time),
                style: Ty.numeral(40, color: Ty.ink, weight: FontWeight.w700),
              ),
              if (daily && livesLost > 0)
                Text(l.ohiruneDailyScore(formatDuration(time + ohiruneLifePenalty * livesLost)), style: Ty.caption)
              else if (best != null)
                Text('${l.gameBest} ${formatDuration(best!)}', style: Ty.caption),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (newRecord && !daily) ResultChip(text: l.gameNewRecord, accent: true),
                  if (livesLost == 0)
                    ResultChip(
                      text: l.ohiruneFlawless,
                      icon: GlyphIcon(Glyph.heart, size: 16, color: T.wrong, strokeWidth: 2.2),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              CoinLine(text: rewardText(l, reward, rewardPending), granted: reward?.status == RewardStatus.granted),
              const SizedBox(height: 18),
              IbashoButton(
                key: const ValueKey<String>('ohirune.again'),
                label: l.ohiruneNewRound,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onAgain,
              ),
              const SizedBox(height: 4),
              IbashoButton(
                label: l.ohiruneSeeBoard,
                tone: ButtonTone.quiet,
                height: 40,
                cue: Sfx.back,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// En vertical los tableros se eligen en un dialogo.
class _LevelDialog extends StatelessWidget {
  const _LevelDialog({required this.current, required this.records, required this.tamas});

  final OhiruneChoice current;
  final OhiruneRecords records;
  final int tamas;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.ohiruneChooseLevel,
      width: 360,
      body: LayoutBuilder(
        builder: (context, box) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DailyCoinsMeter(game: 'ohirune', height: 40),
            const SizedBox(height: 10),
            for (final c in OhiruneChoice.all) ...[
              _LevelCard(
                choice: c,
                selected: c == current,
                records: records,
                tamas: tamas,
                width: box.maxWidth,
                height: 54,
                onPressed: () => Navigator.of(context).pop(c),
              ),
              const SizedBox(height: 8),
            ],
            Text(l.ohiruneRules, textAlign: TextAlign.center, style: Ty.caption),
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
