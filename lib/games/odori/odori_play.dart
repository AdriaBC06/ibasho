// Ibasho — Odori: la partida de Taki, con la cancion sonando.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
import '../../backend/leaderboards.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/backdrop_art.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../game_stage.dart';
import 'odori_board.dart';
import 'odori_butai.dart';
import 'odori_catalog.dart';
import 'odori_chart.dart';
import 'odori_engine.dart';
import 'odori_hits.dart';
import 'odori_keys.dart';
import 'odori_lyrics.dart';
import 'odori_song.dart';
import 'odori_store.dart';
import 'odori_widgets.dart';

/// Todo lo que se elige antes de jugar.
@immutable
class OdoriSetup {
  const OdoriSetup({
    required this.song,
    required this.version,
    required this.keys,
    required this.difficulty,
    this.mode = OdoriMode.taki,
    this.butaiMark = ButaiMark.arrows,
    this.butaiTouch = ButaiTouch.targets,
    this.hitVolume = odoriHitDefault,
    this.flow = TakiFlow.down,
    this.look = NoteLook.circle,
    this.approach = 1.2,
    this.offsetMs = 0,
    this.keyMap,
    this.altKeys,
    this.tama,
    this.assist,
  });

  final OdoriSong song;
  final OdoriVersion version;
  final int keys;
  final OdoriDifficulty difficulty;

  /// Taki o Butai. En Butai, [keys] es siempre 4.
  final OdoriMode mode;

  /// Lo que llevan las burbujas en Butai.
  final ButaiMark butaiMark;

  /// Con los dedos: tocar las dianas o los botones.
  final ButaiTouch butaiTouch;

  /// Volumen de los soniditos de cada toque; 0, sin ellos.
  final double hitVolume;
  final TakiFlow flow;
  final NoteLook look;

  /// Segundos que tarda una nota en cruzar el tablero.
  final double approach;

  /// Desfase calibrado: positivo si el sonido llega tarde.
  final int offsetMs;

  /// Teclas de cada carril; sin ellas, las de serie.
  final List<PhysicalKeyboardKey>? keyMap;

  /// Segunda tecla de cada carril (Butai con doble tecla), si hay.
  final List<PhysicalKeyboardKey>? altKeys;

  /// El Tama que acompaña, si hay.
  final Tama? tama;

  /// Su ayuda, si esta puesta: la partida va a los récords con ayuda.
  final OdoriAssist? assist;

  List<PhysicalKeyboardKey> get keyList => keyMap ?? odoriDefaultKeys[keys]!;

  /// El carril de [key], por la tecla principal o por la segunda; -1 si no
  /// es de ninguno.
  int laneOf(PhysicalKeyboardKey key) {
    final lane = keyList.indexOf(key);
    if (lane >= 0) return lane;
    final alt = altKeys;
    return alt == null ? -1 : alt.indexOf(key).clamp(-1, keys - 1);
  }

  bool get butai => mode == OdoriMode.butai;

  /// Las teclas como se leen, para las burbujas de Butai.
  List<String> get caps => [for (final k in keyList) keyCap(k)];

  String get recordKey => odoriRecordKey(song.id, difficulty, keys, assisted: assist != null, mode: mode);
}

/// Reloj de la cancion: un cronometro que se acerca poco a poco a la
/// posicion real del audio y salta si se separa mas de 80 ms.
class SongClock {
  final Stopwatch _watch = Stopwatch();
  double _base = 0;

  double get now => _base + _watch.elapsedMicroseconds / 1e6;
  bool get running => _watch.isRunning;

  void start(double at) {
    _base = at;
    _watch
      ..reset()
      ..start();
  }

  void stop() {
    _base = now;
    _watch
      ..stop()
      ..reset();
  }

  void sync(double? audio) {
    if (audio == null || !running) return;
    final d = audio - now;
    if (d.abs() > .08) {
      _base += d;
    } else {
      _base += d * .05;
    }
  }
}

enum _Phase { loading, playing, paused, results, failed }

class OdoriPlayScreen extends ConsumerStatefulWidget {
  const OdoriPlayScreen({super.key, required this.setup, this.store});

  final OdoriSetup setup;

  /// Donde se apuntan los récords; sin el (depuracion), no se guardan.
  final OdoriStore? store;

  @override
  ConsumerState<OdoriPlayScreen> createState() => _OdoriPlayScreenState();
}

class _OdoriPlayScreenState extends ConsumerState<OdoriPlayScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  OdoriSetup get setup => widget.setup;

  _Phase _phase = _Phase.loading;
  OdoriScore? _score;
  OdoriEngine? _engine;

  /// La letra, si la version la tiene, y las dianas de Butai.
  OdoriLyrics? _lyrics;
  List<ButaiSpot>? _spots;
  double? _audioLength;
  bool _audioStarted = false;

  final SongClock _clock = SongClock();
  final ValueNotifier<double> _time = ValueNotifier<double>(-1);
  final TakiFx _fx = TakiFx();
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'odori');

  Judgment? _lastJudgment;
  double _lastJudgedAt = -99;

  // Resultados: el récord de antes y si esta partida lo bate.
  OdoriResult? _result;
  OdoriBest? _oldBest;
  bool _newRecord = false;
  RewardOutcome? _reward;
  bool _rewardPending = false;

  // El Tama: su humor, lo que dice y los fallos seguidos que lleva.
  final TamaViewController _tamaCtl = TamaViewController();
  double _joy = .4;
  String? _bubble;
  Timer? _bubbleTimer;
  int _missRun = 0;

  /// Dedos sobre el tablero: puntero → carril.
  final Map<int, int> _pointers = <int, int>{};
  final Set<PhysicalKeyboardKey> _held = <PhysicalKeyboardKey>{};

  double get _offset => setup.offsetMs / 1000;

  /// Tiempo de la partida: el reloj menos el desfase calibrado.
  double get _now => _clock.now - _offset;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    unawaited(AudioService.instance.hushMusic());
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _bubbleTimer?.cancel();
    _time.dispose();
    _focus.dispose();
    unawaited(AudioService.instance.stopOdori());
    unawaited(AudioService.instance.unhushMusic());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  Future<void> _load() async {
    try {
      // Sin cache: se lee una vez por partida y no hace falta guardarla.
      final raw = await rootBundle.loadString(setup.version.scoreAsset, cache: false);
      final score = OdoriScore.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      final lyrics = await loadOdoriLyrics(setup.version, score);
      if (!mounted) return;
      _score = score;
      _lyrics = lyrics;
      await _begin();
    } catch (e) {
      debugPrint('Ibasho: Odori no ha podido cargar ${setup.version.id} ($e)');
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  /// Monta el chart, deja la cancion en pausa al principio y arranca el
  /// reloj en negativo: las primeras notas tienen tiempo de llegar.
  Future<void> _begin() async {
    final score = _score!;
    final chart = buildChart(score, keys: setup.keys, difficulty: setup.difficulty, butai: setup.butai);
    _audioLength = await AudioService.instance.loadOdori(setup.version.audioAsset);
    if (setup.hitVolume > 0) {
      await AudioService.instance.loadOdoriHits([
        for (final h in OdoriHit.values) h.name,
      ], (key) => synthesizeHit(OdoriHit.values.byName(key)));
    }
    if (!mounted) return;
    _engine = OdoriEngine(chart, assist: setup.assist);
    _spots = setup.butai ? butaiLayout(chart, seed: score.id) : null;
    _fx.clear();
    _lastJudgment = null;
    _result = null;
    _missRun = 0;
    _joy = .4;
    if (setup.tama != null) {
      final l = L.of(context)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _say(l.odoriSayStart, hop: true));
    }
    _audioStarted = false;
    final first = chart.notes.isEmpty ? 0.0 : chart.notes.first.time;
    _clock.start(math.min(-1.0, first - setup.approach - 1.2));
    _time.value = _now;
    setState(() => _phase = _Phase.playing);
    _focus.requestFocus();
    if (!_ticker.isActive) _ticker.start();
  }

  /// Cuando acaba la partida: tras la ultima nota, sin esperar al final del
  /// audio (que sigue sonando debajo de los resultados).
  double get _endAt {
    final chart = _engine!.chart;
    final last = chart.notes.fold<double>(0, (a, n) => math.max(a, n.end));
    final len = _audioLength ?? _score!.length;
    return math.max(last + 1.2, math.min(len, last + 3));
  }

  void _onTick(Duration _) {
    final engine = _engine;
    if (engine == null || _phase != _Phase.playing) return;
    final raw = _clock.now;
    if (!_audioStarted && raw >= 0) {
      _audioStarted = true;
      AudioService.instance.setOdoriPaused(false, at: raw);
    } else if (_audioStarted) {
      _clock.sync(AudioService.instance.odoriPosition);
    }
    final t = _now;
    engine.advance(t);
    _collect(engine);
    _time.value = t;
    if (t >= _endAt || engine.finished && t >= _endAt - 1) _finish();
  }

  /// Recoge los juicios nuevos. Con [press], viene de un toque: si no ha
  /// juzgado nada, suena el toque vacio.
  void _collect(OdoriEngine engine, {bool press = false}) {
    OdoriHit? sound = press ? OdoriHit.tap : null;
    for (final e in engine.events) {
      if (!e.tail || e.judgment == Judgment.miss) {
        _lastJudgment = e.judgment;
        _lastJudgedAt = e.at;
      }
      _fx.bursts.add((e.lane, e.at, e.judgment));
      final hit = OdoriHit.of(e.judgment);
      // Suena el mejor de lo que haya pasado a la vez.
      if (sound == null || hit.index > sound.index) sound = hit;
      _react(e, engine.combo);
    }
    engine.events.clear();
    if (sound != null) _sound(sound);
    final now = _time.value;
    _fx.bursts.removeWhere((b) => now - b.$2 > .7);
  }

  void _sound(OdoriHit hit) => AudioService.instance.playOdoriHit(hit.name, setup.hitVolume * hit.level);

  void _finish() {
    _ticker.stop();
    _releaseAll();
    AudioService.instance.play(Sfx.chime);
    final result = _engine!.result();
    final store = widget.store;
    if (store != null) {
      final (fresh, old) = store.data.record(setup.recordKey, result);
      _newRecord = fresh;
      _oldBest = old;
      unawaited(store.save());
      final board = odoriBoardScore(
        result.score,
        setup.difficulty,
        keys: setup.keys,
        assisted: setup.assist != null,
      );
      if (board != null) {
        final game = setup.butai ? LeaderboardGame.odoriButai : LeaderboardGame.odori;
        unawaited(ref.read(leaderboardsProvider.notifier).submitScore(game, board));
      }
    }
    _result = result;
    _reward = null;
    if (result.rank.index >= OdoriRank.c.index) unawaited(_claimReward());
    if (setup.tama != null) {
      final l = L.of(context)!;
      final r = result.rank;
      final great = r.index >= OdoriRank.s.index;
      _joy = great ? 1 : (r.index >= OdoriRank.b.index ? .6 : -.1);
      _say(great ? l.odoriSayGreat : (r.index >= OdoriRank.b.index ? l.odoriSayGood : l.odoriSayMeh), hop: true);
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _tamaCtl.speak(great || r.index >= OdoriRank.b.index ? ChirpKind.happy : ChirpKind.sigh);
      });
    }
    setState(() => _phase = _Phase.results);
  }

  // --- El Tama -------------------------------------------------------------

  void _say(String text, {bool hop = false, Duration hold = const Duration(milliseconds: 1600)}) {
    if (setup.tama == null || !mounted) return;
    if (hop) _tamaCtl.hop();
    _bubbleTimer?.cancel();
    setState(() => _bubble = text);
    _bubbleTimer = Timer(hold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  /// Lo que hace el Tama con cada juicio: salta con los combos redondos,
  /// avisa cuando su ayuda salva algo y anima tras una racha de fallos.
  void _react(JudgeEvent e, int combo) {
    if (setup.tama == null) return;
    final l = L.of(context)!;
    if (e.helped) {
      _say(l.odoriSayHelp, hop: true);
      _tamaCtl.speak(ChirpKind.hello);
    }
    if (e.judgment == Judgment.miss) {
      _missRun++;
      _joy = math.max(-.4, _joy - .12);
      if (_missRun == 4) _say(l.odoriSayMisses);
    } else {
      _missRun = 0;
      _joy = math.min(1, _joy + .01);
      if (combo > 0 && combo % 50 == 0) _say('$combo ♪', hop: true);
    }
  }

  // --- Pausa --------------------------------------------------------------

  void _pause() {
    if (_phase != _Phase.playing) return;
    _clock.stop();
    AudioService.instance.setOdoriPaused(true);
    _releaseAll();
    AudioService.instance.play(Sfx.back);
    setState(() => _phase = _Phase.paused);
  }

  /// Se vuelve un poco atras para cogerle el ritmo otra vez.
  void _resume() {
    if (_phase != _Phase.paused) return;
    final at = _clock.now - 1.5;
    _clock.start(at);
    if (at >= 0) {
      _audioStarted = true;
      AudioService.instance.setOdoriPaused(false, at: at);
    } else {
      _audioStarted = false;
    }
    AudioService.instance.play(Sfx.tick);
    setState(() => _phase = _Phase.playing);
    _focus.requestFocus();
    if (!_ticker.isActive) _ticker.start();
  }

  Future<void> _claimReward() async {
    setState(() => _rewardPending = true);
    final outcome = await ref
        .read(rewardsProvider.notifier)
        .claim(game: 'odori', amount: odoriRewardFor(setup.difficulty));
    if (!mounted) return;
    setState(() {
      _reward = outcome;
      _rewardPending = false;
    });
  }

  void _restart() {
    _ticker.stop();
    _releaseAll();
    setState(() => _phase = _Phase.loading);
    unawaited(_begin());
  }

  void _leave() => Navigator.of(context).maybePop();

  // --- Toques --------------------------------------------------------------

  void _press(int lane) {
    final engine = _engine;
    if (engine == null || _phase != _Phase.playing || lane >= setup.keys) return;
    final t = _now;
    _fx.pressedAt[lane] = t;
    _fx.down[lane] = true;
    engine.press(lane, t);
    _collect(engine, press: true);
  }

  void _release(int lane) {
    final engine = _engine;
    if (engine == null || lane >= setup.keys) return;
    _fx.down[lane] = false;
    if (_phase != _Phase.playing) return;
    engine.release(lane, _now);
    _collect(engine);
  }

  void _releaseAll() {
    for (var j = 0; j < setup.keys; j++) {
      if (_fx.down[j]) _release(j);
      _fx.down[j] = false;
    }
    _pointers.clear();
    _held.clear();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.physicalKey;
    final logical = event.logicalKey;
    if (event is KeyDownEvent &&
        (logical == LogicalKeyboardKey.escape ||
            logical == LogicalKeyboardKey.keyP ||
            logical == LogicalKeyboardKey.enter)) {
      switch (_phase) {
        case _Phase.playing:
          _pause();
        case _Phase.paused:
          if (logical == LogicalKeyboardKey.escape) {
            _leave();
          } else {
            _resume();
          }
        case _Phase.results:
          if (logical == LogicalKeyboardKey.enter) _restart();
          if (logical == LogicalKeyboardKey.escape) _leave();
        default:
          break;
      }
      return KeyEventResult.handled;
    }
    final lane = setup.laneOf(key);
    if (lane < 0) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      // Con doble tecla, cada una pulsa: se alternan en las rafagas.
      if (_held.add(key)) _press(lane);
    } else if (event is KeyUpEvent) {
      _held.remove(key);
      // El carril se suelta cuando no queda ninguna de sus teclas pulsada.
      if (!_held.any((k) => setup.laneOf(k) == lane)) _release(lane);
    }
    return KeyEventResult.handled;
  }

  int _laneAt(Offset p, Size size) {
    final across = setup.flow.vertical ? p.dx / size.width : p.dy / size.height;
    return (across * setup.keys).floor().clamp(0, setup.keys - 1);
  }

  // --- Composicion ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final backdrop = ref.watch(backdropIdProvider);
    // Butai ocupa toda la pantalla; lo demas va por encima.
    if (setup.butai && _engine != null && _phase != _Phase.loading && _phase != _Phase.failed) {
      return _butai(context, layout);
    }
    return Stack(
      children: [
        if (backdrop.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(child: BackdropView(id: backdrop)),
          ),
        _scaffold(context, l, layout),
      ],
    );
  }

  Widget _scaffold(BuildContext context, L l, Layout layout) {
    return ChannelScaffold(
      title: setup.song.title,
      glyph: Glyph.note,
      art: ArtIcon.odori,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, layout.pick(12, 8), layout.gutter, layout.pick(16, 10)),
          child: switch (_phase) {
            _Phase.loading => Center(child: Text(l.odoriLoading, style: Ty.lead)),
            _Phase.failed => Center(
              child: Text(l.odoriLoadFailed, style: Ty.lead, textAlign: TextAlign.center),
            ),
            _ => _game(context, layout),
          },
        ),
      ),
    );
  }

  Widget _game(BuildContext context, Layout layout) {
    final engine = _engine!;
    final wide = !layout.tall && setup.flow.vertical;
    final hud = _hud(context, compact: !wide);
    final lyrics = _lyrics;
    // La letra va debajo del tablero, nunca encima de las notas.
    final play = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _board(context)),
        if (lyrics != null)
          KaraokeStrip(
            lyrics: lyrics,
            time: _time,
            lit: IbashoSkin.of(context).accentDeep,
            compact: !wide,
            onDark: IbashoSkin.of(context).dark,
          ),
      ],
    );
    return Stack(
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: Align(alignment: Alignment.topCenter, child: hud),
              ),
              const SizedBox(width: 24),
              Expanded(child: play),
              const SizedBox(width: 24),
              SizedBox(width: 260, child: _tamaStage(context)),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hud,
              const SizedBox(height: 8),
              Expanded(child: play),
            ],
          ),
        ..._overlays(context, engine),
      ],
    );
  }

  /// La pausa, los resultados y el aviso de que no hay audio, encima de
  /// todo.
  List<Widget> _overlays(BuildContext context, OdoriEngine engine) {
    final l = L.of(context)!;
    return [
      if (_phase == _Phase.paused)
        Positioned.fill(
          child: Center(
            child: SingleChildScrollView(
              child: OdoriPauseCard(onResume: _resume, onRestart: _restart, onLeave: _leave),
            ),
          ),
        ),
      if (_phase == _Phase.results)
        Positioned.fill(
          child: Center(
            child: SingleChildScrollView(
              child: OdoriResultsCard(
                result: _result ?? engine.result(),
                title: setup.song.title,
                difficulty: setup.difficulty,
                keys: setup.keys,
                best: _oldBest?.score,
                newRecord: _newRecord,
                assisted: setup.assist != null,
                coins: _reward != null || _rewardPending ? rewardText(l, _reward, _rewardPending) : null,
                coinsGranted: _reward?.status == RewardStatus.granted,
                onAgain: _restart,
                onLeave: _leave,
              ),
            ),
          ),
        ),
      if (_phase == _Phase.playing && _audioLength == null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Text(l.odoriNoAudio, style: Ty.caption, textAlign: TextAlign.center),
        ),
    ];
  }

  Widget _board(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final engine = _engine!;
    final vertical = setup.flow.vertical;
    return LayoutBuilder(
      builder: (context, box) {
        // Carriles de hasta 84 px: con pocas teclas no se estira de lado a lado.
        final lanes = setup.keys.toDouble();
        final w = vertical ? math.min(box.maxWidth, lanes * 84 + 24) : box.maxWidth;
        final h = vertical ? box.maxHeight : math.min(box.maxHeight, lanes * 72 + 24);
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: GlossSurface(
              radius: 24,
              recessed: true,
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, inner) {
                  final size = Size(inner.maxWidth, inner.maxHeight);
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      final lane = _laneAt(e.localPosition, size);
                      _pointers[e.pointer] = lane;
                      _press(lane);
                    },
                    onPointerMove: (e) {
                      // Deslizar a otro carril suelta el anterior y pulsa el nuevo.
                      final lane = _laneAt(e.localPosition, size);
                      final was = _pointers[e.pointer];
                      if (was == null || was == lane) return;
                      _pointers[e.pointer] = lane;
                      if (!_pointers.values.contains(was)) _release(was);
                      _press(lane);
                    },
                    onPointerUp: (e) => _lift(e.pointer),
                    onPointerCancel: (e) => _lift(e.pointer),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: TakiBoard(
                            engine: engine,
                            time: _time,
                            fx: _fx,
                            accent: skin.accent,
                            accentDeep: skin.accentDeep,
                            flow: setup.flow,
                            look: setup.look,
                            approach: setup.approach,
                            keyLabels: Layout.of(context).tall ? const [] : [for (final k in setup.keyList) keyCap(k)],
                            dark: skin.surfaces.dark,
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Align(
                              alignment: vertical
                                  ? Alignment(0, setup.flow == TakiFlow.down ? .25 : -.25)
                                  : Alignment(setup.flow == TakiFlow.right ? .25 : -.25, 0),
                              child: ValueListenableBuilder<double>(
                                valueListenable: _time,
                                builder: (context, t, _) =>
                                    JudgmentPop(judgment: _lastJudgment, age: t - _lastJudgedAt, combo: engine.combo),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Butai: el escenario llena la pantalla y el marcador, la letra, el Tama
  /// y los botones van por encima. Las dianas se quedan en lo que dejan
  /// libre. Con los dedos se toca la diana donde cae cada nota.
  Widget _butai(BuildContext context, Layout layout) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final engine = _engine!;
    final tall = layout.tall;
    final lyrics = _lyrics;
    final pad = tall && setup.butaiTouch == ButaiTouch.pad;
    final tama = tall ? null : setup.tama;
    final gutter = layout.gutter;
    final padH = pad ? 96.0 : 0.0;
    final lyricsH = lyrics == null ? 0.0 : (tall ? 64.0 : 80.0);
    final inset = EdgeInsets.fromLTRB(gutter + (tama != null ? 150 : 0), tall ? 112 : 104, gutter, 12 + padH + lyricsH);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          final area = inset.deflateRect(Offset.zero & box.biggest);
          return Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _touchStage(e.pointer, e.localPosition, area),
                  onPointerUp: (e) => _lift(e.pointer),
                  onPointerCancel: (e) => _lift(e.pointer),
                  child: ButaiStage(
                    key: const ValueKey<String>('odori.butai'),
                    engine: engine,
                    spots: _spots!,
                    time: _time,
                    fx: _fx,
                    accent: skin.accent,
                    approach: setup.approach,
                    mark: setup.butaiMark,
                    caps: setup.caps,
                    labels: [for (final j in Judgment.values) judgmentText(l, j)],
                    inset: inset,
                    radius: 0,
                  ),
                ),
              ),
              Positioned(
                left: gutter,
                right: gutter,
                top: 10,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: _butaiBar(context, tall: tall),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: inset.top - 12,
                child: IgnorePointer(
                  child: Center(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _time,
                      builder: (context, t, _) =>
                          JudgmentPop(judgment: _lastJudgment, age: t - _lastJudgedAt, combo: engine.combo),
                    ),
                  ),
                ),
              ),
              if (lyrics != null)
                Positioned(
                  left: gutter,
                  right: gutter,
                  bottom: 8 + padH,
                  child: IgnorePointer(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: KaraokeStrip(
                          lyrics: lyrics,
                          time: _time,
                          lit: Color.lerp(skin.accent, const Color(0xFFFFFFFF), .35)!,
                          compact: tall,
                          onDark: true,
                        ),
                      ),
                    ),
                  ),
                ),
              if (pad)
                Positioned(
                  left: gutter,
                  right: gutter,
                  bottom: 8,
                  child: ButaiPad(onPress: _press, onRelease: _release, mark: setup.butaiMark, caps: setup.caps),
                ),
              if (tama != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  width: 160,
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SpeechBubble(text: _bubble),
                        const SizedBox(height: 4),
                        KeyedSubtree(
                          key: ValueKey<String>('odori.tama.${tama.id}'),
                          child: TamaOnStand(tama: tama, size: 120, joy: _joy, controller: _tamaCtl),
                        ),
                      ],
                    ),
                  ),
                ),
              ..._overlays(context, engine),
            ],
          );
        },
      ),
    );
  }

  /// Un dedo en el escenario: toca la tecla de la diana mas cercana. Si no
  /// hay ninguna cerca, solo suena el toque vacio.
  void _touchStage(int pointer, Offset at, Rect area) {
    final engine = _engine;
    if (engine == null || _phase != _Phase.playing) return;
    final lane = butaiPick(engine, _spots!, at, area, _now, setup.approach);
    if (lane == null) {
      _sound(OdoriHit.tap);
      return;
    }
    _pointers[pointer] = lane;
    _press(lane);
  }

  /// El marcador de Butai, una barra de cristal arriba.
  Widget _butaiBar(BuildContext context, {required bool tall}) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final engine = _engine!;
    final length = _endAt;
    final pause = IconPill(
      key: const ValueKey<String>('odori.pause'),
      glyph: _phase == _Phase.playing ? Glyph.pause : Glyph.play,
      semanticLabel: l.odoriPause,
      diameter: tall ? 40 : 44,
      onPressed: () => _phase == _Phase.playing ? _pause() : _resume(),
    );
    return GlossSurface(
      radius: 20,
      elevation: 2,
      padding: EdgeInsets.fromLTRB(tall ? 12 : 16, 8, tall ? 8 : 10, 10),
      child: ValueListenableBuilder<double>(
        valueListenable: _time,
        builder: (context, t, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                DifficultyTag(difficulty: setup.difficulty, small: true),
                const SizedBox(width: 10),
                if (!tall) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(setup.song.title, style: Ty.lead, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          setup.song.authorOf(setup.version),
                          style: Ty.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Que figura va con cada tecla.
                  for (var j = 0; j < butaiKeys; j++) ...[
                    ButaiSymbol(lane: j, size: 26, mark: setup.butaiMark, caps: setup.caps),
                    const SizedBox(width: 4),
                  ],
                  const SizedBox(width: 12),
                ],
                Text(
                  '${engine.score}',
                  style: Ty.numeral(tall ? 22 : 26, color: Ty.ink, weight: FontWeight.w700),
                ),
                if (tall) const Spacer() else const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(engine.accuracy * 100).toStringAsFixed(2)} %',
                      style: Ty.numeral(14, color: skin.accentDeep, weight: FontWeight.w700),
                    ),
                    Text(
                      '${l.odoriCombo} ${engine.combo}',
                      style: Ty.numeral(13, color: Ty.inkSoft, weight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                pause,
              ],
            ),
            const SizedBox(height: 6),
            SongProgress(value: t / length),
          ],
        ),
      ),
    );
  }

  /// El Tama al lado del tablero, sobre su peana con el foco y su bocadillo.
  Widget _tamaStage(BuildContext context) {
    final tama = setup.tama;
    if (tama == null) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 64,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SpeechBubble(text: _bubble),
          ),
        ),
        const SizedBox(height: 6),
        StageLight(
          child: SizedBox(
            width: 220,
            height: 220,
            child: Center(
              child: KeyedSubtree(
                key: ValueKey<String>('odori.tama.${tama.id}'),
                child: TamaOnStand(tama: tama, size: 170, joy: _joy, controller: _tamaCtl),
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  void _lift(int pointer) {
    final lane = _pointers.remove(pointer);
    if (lane != null && !_pointers.values.contains(lane)) _release(lane);
  }

  Widget _hud(BuildContext context, {required bool compact}) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final engine = _engine!;
    final length = _endAt;
    final pause = IconPill(
      key: const ValueKey<String>('odori.pause'),
      glyph: _phase == _Phase.playing ? Glyph.pause : Glyph.play,
      semanticLabel: l.odoriPause,
      diameter: compact ? 40 : 48,
      onPressed: () => _phase == _Phase.playing ? _pause() : _resume(),
    );
    return ValueListenableBuilder<double>(
      valueListenable: _time,
      builder: (context, t, _) {
        final score = Text(
          '${engine.score}',
          style: Ty.numeral(compact ? 24 : 34, color: Ty.ink, weight: FontWeight.w700),
        );
        final acc = Text(
          '${(engine.accuracy * 100).toStringAsFixed(2)} %',
          style: Ty.numeral(compact ? 14 : 18, color: skin.accentDeep, weight: FontWeight.w700),
        );
        final combo = Text(
          '${l.odoriCombo} ${engine.combo}',
          style: Ty.numeral(compact ? 14 : 18, color: Ty.inkSoft, weight: FontWeight.w700),
        );
        final progress = SongProgress(value: t / length);
        if (compact) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  DifficultyTag(difficulty: setup.difficulty, small: true),
                  const SizedBox(width: 10),
                  Expanded(child: score),
                  acc,
                  const SizedBox(width: 10),
                  pause,
                ],
              ),
              const SizedBox(height: 6),
              progress,
            ],
          );
        }
        return GlossSurface(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(setup.song.title, style: Ty.lead, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(setup.song.authorOf(setup.version), style: Ty.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
                children: [
                  DifficultyTag(difficulty: setup.difficulty, small: true),
                  const SizedBox(width: 8),
                  Text(l.odoriKeysCount(setup.keys), style: Ty.caption),
                ],
              ),
              const SizedBox(height: 12),
              score,
              acc,
              const SizedBox(height: 4),
              combo,
              const SizedBox(height: 12),
              progress,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: pause),
            ],
          ),
        );
      },
    );
  }
}
