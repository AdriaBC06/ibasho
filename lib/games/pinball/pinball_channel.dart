// Ibasho — canal del pinball: donde se abren las bolas del gacha.
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
import '../../backend/gacha.dart';
import '../../backend/gacha_prizes.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/gacha.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gacha_art.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../game_stage.dart';
import '../game_store.dart';
import '../tsumiki/tsumiki_widgets.dart' show PopBanner;
import 'pinball.dart';
import 'pinball_board.dart';
import 'pinball_catalog.dart';
import 'pinball_widgets.dart';

/// El canal del pinball.
///
/// Una escena, como los demas juegos: a un lado el escenario con uno de tus
/// Tamas (que tambien es el guardian de las bolas UR, ∞ y dirigidas), el
/// marcador y la cola; al otro, la mesa. En vertical la mesa manda y la cola
/// y el Tama van en una columna estrecha al lado.
///
/// Se juega tocando la mitad izquierda o derecha de la pantalla (cada una
/// mueve su flipper) y arrastrando hacia abajo para lanzar; o con Z/M o las
/// flechas y espacio o flecha abajo.
class PinballChannel extends ConsumerStatefulWidget {
  const PinballChannel({super.key});

  @override
  ConsumerState<PinballChannel> createState() => _PinballChannelState();
}

class _PinballChannelState extends ConsumerState<PinballChannel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  PinballGame? _game;
  final List<GachaBall> _queue = <GachaBall>[];
  bool _loading = false;
  String? _error;

  /// La partida esta parada (a mano, al salir o al volver a entrar).
  bool _paused = false;

  /// Se esta ensenando la tarjeta de premio o de bola perdida.
  bool _showOutcome = false;
  bool _newRecord = false;

  GameStore? _store;
  int _best = 0;

  final math.Random _random = math.Random();
  String? _tamaId;
  final TamaViewController _tama = TamaViewController();
  final TamaViewController _guard = TamaViewController();

  /// Se estan guardando las bolas jugadas (y si ha fallado la ultima vez).
  bool _syncing = false;
  bool _syncAgain = false;
  bool _syncFailed = false;

  /// Se estan devolviendo las bolas (cancelar desde la pausa).
  bool _cancelling = false;
  String? _cancelError;
  double _joy = .3;
  String? _bubble;
  Timer? _bubbleTimer;
  String? _banner;
  Timer? _bannerTimer;
  Timer? _outcomeTimer;

  // Mandos: que dedo mueve que flipper y cuanto se tira del lanzador.
  final Map<int, bool> _pointers = <int, bool>{};
  int? _plungerPointer;
  double _plungerDrag = 0;
  bool _keyLeft = false;
  bool _keyRight = false;
  bool _charging = false;

  final PinballFx _fx = PinballFx();
  double _fxTime = 0;
  double _lastElapsed = 0;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'pinball');

  double get _now => _fxTime;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadStore());
  }

  Future<void> _loadStore() async {
    final store = await GameStore.open('pinball');
    final json = await store.load();
    if (!mounted) return;
    final saved = PinballGame.fromJson(json['game']);
    setState(() {
      _store = store;
      _best = readInt(json['best']);
      if (saved != null && (!saved.isOver || saved.hasUnsaved)) {
        // Una partida a medias: vuelve en pausa, con la bola en el lanzador.
        // Una acabada con bolas sin guardar vuelve a los resultados.
        _game = saved;
        _paused = !saved.isOver;
      }
    });
    unawaited(_sync());
  }

  void _save() {
    final game = _game;
    unawaited(_store?.save(<String, Object?>{
      'best': _best,
      if (game != null && (!game.isOver || game.hasUnsaved)) 'game': game.toJson(),
    }));
  }

  /// Guarda en el servidor, en orden, las bolas jugadas que falten: baja la
  /// bola de la partida, mete el premio en la coleccion y sube el Catalogo.
  /// Si falla (sin red), se queda para la proxima: al pasar de bola, al
  /// volver a entrar o al acabar.
  Future<bool> _sync() async {
    if (_syncing) {
      _syncAgain = true;
      return false;
    }
    final gacha = ref.read(gachaProvider);
    if (!gacha.loaded) return false;
    _syncing = true;
    var ok = true;
    try {
      do {
        _syncAgain = false;
        final game = _game;
        if (game == null) break;
        for (var i = 0; i < game.outcomes.length; i++) {
          final o = game.outcomes[i];
          if (o.saved) continue;
          final arrived = await ref.read(gachaProvider.notifier).playTurn(index: i, ball: o.ball, prize: o.prize);
          if (!identical(game, _game)) break;
          game.outcomes[i] = o.asSaved;
          _save();
          if (arrived && mounted) {
            AudioService.instance.play(Sfx.pbJackpot);
            _showBanner(L.of(context)!.pinballWishArrived);
          }
        }
      } while (_syncAgain);
    } catch (e) {
      debugPrint('Ibasho: bolas del pinball sin guardar ($e)');
      ok = false;
    } finally {
      _syncing = false;
    }
    if (mounted) setState(() => _syncFailed = !ok);
    return ok;
  }

  /// Sortea el premio de la bola que acaba de entrar: cualquier variante de
  /// su rareza en esa categoria, o una que no se tenga si es la dirigida.
  void _rollPrize(PinballGame game) {
    final i = game.outcomes.length - 1;
    final o = game.outcomes[i];
    final key = rollGachaPrize(
      o.category!,
      o.ball.rarity,
      _random,
      owned: ref.read(gachaProvider).prizes.keys.toSet(),
      fresh: o.ball.isWish,
    );
    game.outcomes[i] = o.withPrize(key);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    // Salir del canal deja la partida guardada tal cual.
    _save();
    WidgetsBinding.instance.removeObserver(this);
    _bubbleTimer?.cancel();
    _bannerTimer?.cancel();
    _outcomeTimer?.cancel();
    _ticker.dispose();
    _clock.dispose();
    _focus.dispose();
    super.dispose();
  }

  // --- Reloj -------------------------------------------------------------------

  bool get _wantsTicks {
    final game = _game;
    return game != null && !_paused && !game.isOver;
  }

  void _kick() {
    if (!_ticker.isActive && _wantsTicks) {
      _lastElapsed = 0;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final e = elapsed.inMicroseconds / 1e6;
    final dt = math.min(.05, math.max(0.0, e - _lastElapsed));
    _lastElapsed = e;
    _fxTime += dt;
    final game = _game;
    if (game != null && !_paused) {
      if (_charging && game.phase == PinballPhase.ready) game.pull = math.min(1, game.pull + dt * 1.1);
      game
        ..setFlipper(left: true, held: _keyLeft || _pointers.containsValue(true))
        ..setFlipper(left: false, held: _keyRight || _pointers.containsValue(false));
      for (final event in game.tick(dt)) {
        _onEvent(event);
      }
      _fx.follow(game, dt);
    }
    _clock.value = _fxTime;
    if (!_wantsTicks) _ticker.stop();
  }

  // --- Tama, bocadillo y carteles -------------------------------------------------

  void _pickTama() {
    final tamas = ref.read(tamasProvider).tamas;
    if (tamas.isEmpty) {
      _tamaId = null;
      return;
    }
    final pool = tamas.length > 1 ? tamas.where((t) => t.id != _tamaId).toList() : tamas;
    _tamaId = pool[_random.nextInt(pool.length)].id;
  }

  Tama? _currentTama(List<Tama> tamas) {
    if (tamas.isEmpty) return null;
    if (_tamaId == null || !tamas.any((t) => t.id == _tamaId)) {
      _tamaId = tamas[_random.nextInt(tamas.length)].id;
    }
    return tamas.firstWhere((t) => t.id == _tamaId);
  }

  void _say(String? text, {Duration hold = const Duration(milliseconds: 1800)}) {
    _bubbleTimer?.cancel();
    setState(() => _bubble = text);
    if (text == null) return;
    _bubbleTimer = Timer(hold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _showBanner(String text) {
    _bannerTimer?.cancel();
    setState(() => _banner = text);
    _bannerTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  // --- Partida -------------------------------------------------------------------

  Future<void> _play() async {
    if (_queue.isEmpty || _loading) return;
    final l = L.of(context)!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(gachaProvider.notifier).loadPinball(List<GachaBall>.of(_queue));
    } catch (e) {
      if (mounted) {
        AudioService.instance.play(Sfx.error);
        setState(() {
          _loading = false;
          _error = l.pinballErrorLoad;
        });
      }
      return;
    }
    if (!mounted) return;
    _fx.clear();
    final game = PinballGame(queue: List<GachaBall>.of(_queue));
    _fx.follow(game, 0, snap: true);
    setState(() {
      _game = game;
      _queue.clear();
      _loading = false;
      _paused = false;
      _showOutcome = false;
      _newRecord = false;
      _joy = .4;
      _pickTama();
    });
    // Las bolas ya no estan en el deposito: desde aqui viven en la partida.
    _save();
    _focus.requestFocus();
    _say(l.pinballBubbleStart);
    _tama.hop();
    _kick();
  }

  void _openCatalog() => unawaited(showIbashoModal<void>(context, (context) => const PinballCatalogDialog()));

  void _pause() {
    final game = _game;
    if (game == null || _paused || game.isOver || _showOutcome) return;
    _releaseAll();
    AudioService.instance.play(Sfx.back);
    setState(() => _paused = true);
    _say(L.of(context)!.pinballBubblePause, hold: const Duration(seconds: 30));
    _save();
  }

  void _resume() {
    if (!_paused || _cancelling) return;
    _cancelError = null;
    AudioService.instance.play(Sfx.tick);
    setState(() => _paused = false);
    _say(null);
    _focus.requestFocus();
    _kick();
  }

  /// Acaba la partida antes de que salga la bola de turno y devuelve al
  /// deposito las que no se han jugado.
  Future<void> _cancel() async {
    final game = _game;
    if (game == null || !game.canCancel || _cancelling) return;
    final l = L.of(context)!;
    setState(() {
      _cancelling = true;
      _cancelError = null;
    });
    try {
      // Lo jugado se guarda antes: si no, cancelar lo devolveria.
      if (game.hasUnsaved && !await _sync()) throw const PullException(PullFailure.network);
      await ref.read(gachaProvider.notifier).cancelPinball(game.unplayed);
    } catch (e) {
      if (mounted) {
        AudioService.instance.play(Sfx.error);
        setState(() {
          _cancelling = false;
          _cancelError = l.pinballErrorCancel;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _cancelling = false;
      _game = null;
      _paused = false;
      _showOutcome = false;
    });
    _fx.clear();
    _save();
    _say(l.pinballBubbleCancel);
    _tama.hop();
  }

  void _releaseAll() {
    _pointers.clear();
    _plungerPointer = null;
    _plungerDrag = 0;
    _keyLeft = _keyRight = _charging = false;
    _game?.pull = 0;
  }

  void _next() {
    final game = _game;
    if (game == null) return;
    final l = L.of(context)!;
    game.nextBall();
    setState(() => _showOutcome = false);
    if (game.isOver) {
      if (game.score > _best) {
        _best = game.score;
        _newRecord = true;
      }
      _joy = .6;
      _tama.hop();
    } else {
      _say(l.pinballBubbleStart);
      _joy = .4;
    }
    _save();
    unawaited(_sync());
    _kick();
  }

  Future<void> _again() async {
    final game = _game;
    // Lo jugado tiene que estar guardado antes de soltar la partida.
    if (game != null && game.hasUnsaved && !await _sync()) {
      AudioService.instance.play(Sfx.error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _game = null;
      _newRecord = false;
    });
    _save();
  }

  void _launch() {
    final game = _game;
    if (game == null || game.phase != PinballPhase.ready) return;
    final event = game.launch();
    if (event != null) AudioService.instance.play(Sfx.pbLaunch);
  }

  /// La primera bola jugada trae el canal del pachinko.
  void _playedOnce() => unawaited(ref.read(preferencesProvider.notifier).playedPinball());

  void _onEvent(PinballEvent e) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final audio = AudioService.instance;
    switch (e.kind) {
      case PinballEventKind.launch:
        break;
      case PinballEventKind.flipper:
        audio.play(Sfx.pbFlipper);
      case PinballEventKind.bumper:
        _fx.bumperAt[e.index!] = _now;
        _fx.spark(e.at, _now, skin.accent);
        audio.play(Sfx.pbBumper);
      case PinballEventKind.sling:
        if (e.at.dx < PinballTable.centerX) {
          _fx.slingLeftAt = _now;
        } else {
          _fx.slingRightAt = _now;
        }
        audio.play(Sfx.pbSling);
      case PinballEventKind.spring:
        _fx.springAt[e.index!] = _now;
        audio.play(Sfx.pbSpring);
      case PinballEventKind.post:
        _fx.postAt[e.index!] = _now;
        audio.play(Sfx.pbPost);
      case PinballEventKind.spinner:
        _fx.spinnerAt[e.index!] = _now;
        audio.play(Sfx.pbSpinner);
      case PinballEventKind.target:
        _fx.targetAt[e.index!] = _now;
        _fx.spark(e.at, _now, categoryColor(e.category!));
        audio.play(Sfx.pbTarget);
      case PinballEventKind.holeOpen:
        _fx.holeAt[e.category!] = _now;
        _fx.spark(e.at, _now, categoryColor(e.category!));
        audio.play(Sfx.pbHoleOpen);
        _showBanner(l.pinballBannerOpen);
        _joy = .8;
        _say(l.pinballBubbleOpen);
        _tama.hop();
      case PinballEventKind.captured:
        _playedOnce();
        _rollPrize(_game!);
        unawaited(_sync());
        final rarity = _game!.outcomes.last.ball.rarity;
        _fx.holeAt[_game!.capturedIn!] = _now;
        _fx.spark(e.at, _now, RarityArt.of(rarity));
        audio.play(Sfx.pbCapture);
        _joy = 1;
        _say(l.pinballBubblePrize, hold: const Duration(seconds: 3));
        _outcomeTimer?.cancel();
        _outcomeTimer = Timer(Duration(milliseconds: skin.reducedMotion ? 100 : 700), () {
          if (!mounted) return;
          setState(() => _showOutcome = true);
          audio.play(rarity.index >= Rarity.ur.index ? Sfx.pbJackpot : Sfx.pbPrize);
          _tama
            ..cuddle()
            ..hop();
        });
        _save();
      case PinballEventKind.kickbackLit:
        audio.play(Sfx.pbKickbackLit);
        _showBanner(l.pinballBannerKickbackLit);
      case PinballEventKind.kickback:
        _fx.kickbackAt = _now;
        _fx.spark(e.at, _now, Art.gold);
        audio.play(Sfx.pbKickback);
        _showBanner(l.pinballBannerKickback);
      case PinballEventKind.saved || PinballEventKind.guarded:
        // El Tama con el que juegas baja al desague, coge la bola y suena el
        // coro: se tiene que entender que la salva el.
        _fx.rescueAt = _now;
        audio.play(Sfx.pbChoir);
        if (e.kind == PinballEventKind.saved) _showBanner(l.pinballBannerSaved);
        _say(e.kind == PinballEventKind.saved ? l.pinballBubbleSaved : l.pinballBubbleGuard);
        _joy = .9;
        _guard.hop();
        _tama.hop();
      case PinballEventKind.thrown:
        _fx.releaseAt = _now;
        _fx.spark(e.at, _now, skin.accent);
        audio.play(Sfx.pbThrown);
        _guard.hop();
      case PinballEventKind.nudge:
        _fx.nudgeAt = _now;
        audio.play(Sfx.pbNudge);
        _showBanner(l.pinballBannerNudge);
      case PinballEventKind.lost:
        _playedOnce();
        unawaited(_sync());
        audio.play(Sfx.pbLost);
        _joy = -.6;
        _say(l.pinballBubbleLost, hold: const Duration(seconds: 3));
        _tama.hop();
        unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _tama.speak(ChirpKind.sigh);
        }));
        _outcomeTimer?.cancel();
        _outcomeTimer = Timer(Duration(milliseconds: skin.reducedMotion ? 100 : 600), () {
          if (mounted) setState(() => _showOutcome = true);
        });
        _save();
      case PinballEventKind.wall:
        break;
    }
    const quiet = <PinballEventKind>{
      PinballEventKind.wall,
      PinballEventKind.flipper,
      PinballEventKind.post,
      PinballEventKind.spinner,
      PinballEventKind.spring,
    };
    if (!quiet.contains(e.kind)) setState(() {});
  }

  // --- Mandos -----------------------------------------------------------------

  bool get _playing {
    final game = _game;
    return game != null && !_paused && !game.isOver && !_showOutcome;
  }

  void _onPointerDown(PointerDownEvent e, double width) {
    if (!_playing) return;
    final game = _game!;
    _pointers[e.pointer] = e.localPosition.dx < width / 2;
    if (game.phase == PinballPhase.ready && _plungerPointer == null) {
      _plungerPointer = e.pointer;
      _plungerDrag = 0;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _plungerPointer) return;
    final game = _game;
    if (game == null || game.phase != PinballPhase.ready) return;
    _plungerDrag = math.max(0, _plungerDrag + e.delta.dy);
    game.pull = (_plungerDrag / 160).clamp(0.0, 1.0);
    // Mientras se tira del lanzador, ese dedo no mueve flippers.
    if (_plungerDrag > 12) _pointers.remove(e.pointer);
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer == _plungerPointer) {
      _plungerPointer = null;
      if (_plungerDrag > 12) _launch();
      _plungerDrag = 0;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    final up = event is KeyUpEvent;
    if (!down && !up) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.escape) {
      if (down) _paused ? _resume() : _pause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.arrowLeft) {
      _keyLeft = down && _playing;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM || key == LogicalKeyboardKey.arrowRight) {
      _keyRight = down && _playing;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.arrowDown) {
      if (down && _playing && _game!.phase == PinballPhase.ready) {
        _charging = true;
      } else if (up && _charging) {
        _charging = false;
        _launch();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Composicion -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tamasState = ref.watch(tamasProvider);
    final tama = _currentTama(tamasState.tamas);
    // Las bolas que quedaron sin guardar esperan a que se lea el gacha.
    ref.listen<bool>(gachaProvider.select((s) => s.loaded), (was, loaded) {
      if (loaded && was != true) unawaited(_sync());
    });
    if (_wantsTicks && !_ticker.isActive) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kick();
      });
    }
    return ChannelScaffold(
      title: l.pinballTitle,
      glyph: Glyph.star,
      art: ArtIcon.pinball,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, box) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) => _onPointerDown(e, box.maxWidth),
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: layout.tall ? _tallLayout(context, tama) : _wideLayout(context, tama),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stage(Tama? tama, double size) {
    final face = tama == null
        ? GlossyFace(joy: _joy, size: size)
        : TamaOnStand(tama: tama, size: size, joy: _joy, controller: _tama);
    return KeyedSubtree(key: ValueKey<String>('pinball.tama.${tama?.id}'), child: face);
  }

  /// La cola de la partida: lo que ya salio (con su premio o tachado), la
  /// que esta en juego y las que esperan.
  Widget _queueStrip({required Axis axis, double ball = 34}) {
    final game = _game;
    if (game == null) return const SizedBox.shrink();
    final skin = IbashoSkin.of(context);
    final items = <Widget>[
      for (var i = 0; i < game.queue.length; i++)
        Padding(
          padding: const EdgeInsets.all(3),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (i == game.ballIndex && !game.isOver)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: skin.accent.withValues(alpha: .6), blurRadius: 10, spreadRadius: 2)],
                    ),
                  ),
                ),
              QueueBall(game.queue[i], size: ball, faded: i < game.outcomes.length && !game.outcomes[i].won),
              if (i < game.outcomes.length && game.outcomes[i].won)
                Positioned(right: -6, bottom: -6, child: CategoryArtView(game.outcomes[i].category!, size: ball * .6)),
            ],
          ),
        ),
    ];
    return GlossSurface(
      radius: 20,
      recessed: true,
      padding: const EdgeInsets.all(5),
      child: axis == Axis.horizontal
          ? Row(mainAxisSize: MainAxisSize.min, children: items)
          : Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _score(L l, double height) => Readout(
        key: const ValueKey<String>('pinball.score'),
        icon: GlyphIcon(Glyph.star, size: height * .5, color: IbashoSkin.of(context).accentDeep, strokeWidth: 2.2),
        value: '${_game?.score ?? 0}',
        label: l.pinballScore,
        height: height,
      );

  Widget _pauseButton(L l) => IconPill(
        key: const ValueKey<String>('pinball.pause'),
        glyph: _paused ? Glyph.play : Glyph.pause,
        semanticLabel: _paused ? l.pinballResume : l.pinballPause,
        diameter: 44,
        onPressed: _paused ? _resume : _pause,
      );

  /// La mesa: todo el ancho y, de alto, lo que quepa (como minimo
  /// [PinballTable.viewHeight]); si no cabe entera, la camara sigue a la
  /// bola. Encima, el Tama cuando baja a salvar una bola.
  Widget _board(BuildContext context, BoxConstraints box, Tama? tama) {
    final skin = IbashoSkin.of(context);
    final game = _game;
    final width = math.min(box.maxWidth, box.maxHeight * PinballTable.width / PinballTable.viewHeight);
    final s = width / PinballTable.width;
    final view = math.min(PinballTable.height, box.maxHeight / s);
    if (_fx.view != view) {
      _fx.view = view;
      _fx.follow(game ?? _idle, 0, snap: true);
    }
    final shown = game ?? _idle;
    return SizedBox(
      width: width,
      height: view * s,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _paused ? .35 : 1,
              duration: skin.motion(const Duration(milliseconds: 200)),
              child: PinballBoard(
                key: const ValueKey<String>('pinball.board'),
                game: shown,
                fx: _fx,
                clock: _clock,
                accent: skin.accent,
                accentDeep: skin.accentDeep,
              ),
            ),
          ),
          if (game != null && tama != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<double>(
                  valueListenable: _clock,
                  builder: (context, now, _) => _rescuer(game, tama, s, now),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// El Tama que salva la bola: aparece en el desague con un halo, la
  /// sostiene encima de la cabeza mientras suena el coro y se va al soltarla.
  Widget _rescuer(PinballGame game, Tama tama, double s, double now) {
    const hold = PinballGame.rescueHold;
    final since = now - _fx.rescueAt;
    final holding = game.rescueUntil != null;
    final after = now - _fx.releaseAt;
    // Entra en 0,25 s, se queda mientras la tiene y sale en 0,4 s.
    double shown;
    if (holding) {
      shown = (since / .25).clamp(0.0, 1.0);
    } else if (since < hold + .6) {
      shown = 1 - ((math.min(after, since - hold)) / .4).clamp(0.0, 1.0);
    } else {
      shown = 0;
    }
    if (shown <= 0) return const SizedBox.shrink();
    final size = 64 * s;
    final center = Offset(PinballTable.guardianAt.dx * s, (PinballTable.height - _fx.camera) * s - size * .5);
    final lift = Curves.easeOutBack.transform(shown);
    final ball = game.current;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // El halo de luz que lo trae.
        Positioned(
          left: center.dx - size,
          top: center.dy - size,
          width: size * 2,
          height: size * 2,
          child: Opacity(
            opacity: shown * .8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Art.gold.withValues(alpha: .55), Art.gold.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: center.dx - size / 2,
          top: center.dy - size / 2 + (1 - lift) * size * .6,
          child: Opacity(
            opacity: shown,
            child: TamaOnStand(tama: tama, size: size, joy: 1, controller: _guard),
          ),
        ),
        if (holding && ball != null)
          Positioned(
            left: center.dx - 10 * s,
            top: center.dy - size * .62 - 10 * s + (1 - lift) * size * .6,
            child: GachaBallView(ball.rarity, size: 20 * s, shadow: false),
          ),
      ],
    );
  }

  /// La mesa de adorno antes de cargar bolas.
  static final PinballGame _idle = PinballGame(queue: const <GachaBall>[GachaBall(Rarity.n)]);

  Widget _overlay(L l, bool hasTama) {
    final game = _game;
    if (!hasTama && game == null) return const PinballNeedTamaCard();
    if (game == null) {
      return PinballLoadCard(
        gacha: ref.watch(gachaProvider),
        queue: _queue,
        best: _best,
        busy: _loading,
        error: _error,
        showKeys: !Layout.of(context).tall,
        onAdd: (b) => setState(() {
          if (_queue.length < pinballQueueMax) _queue.add(b);
        }),
        onRemove: (i) => setState(() => _queue.removeAt(i)),
        onPlay: _play,
        onCatalog: _openCatalog,
      );
    }
    if (game.isOver) {
      return PinballResultsCard(
        outcomes: game.outcomes,
        score: game.score,
        best: _best,
        newRecord: _newRecord,
        unsaved: game.hasUnsaved && _syncFailed,
        onAgain: () => unawaited(_again()),
      );
    }
    if (_showOutcome && game.outcomes.isNotEmpty) {
      final last = game.outcomes.length == game.queue.length;
      final outcome = game.outcomes.last;
      final gacha = ref.watch(gachaProvider);
      final key = outcome.prize;
      return outcome.won
          ? PinballPrizeCard(
              outcome: outcome,
              // Las copias contando esta, este guardada ya o no.
              copies: key == null ? 0 : gacha.copiesOf(key) + (outcome.saved ? 0 : 1),
              last: last,
              onNext: _next,
            )
          : PinballLostCard(ball: outcome.ball, last: last, onNext: _next);
    }
    if (_paused) {
      return PinballPauseCard(
        onResume: _resume,
        returnable: game.canCancel ? game.unplayed.length : 0,
        onCancel: _cancel,
        busy: _cancelling,
        error: _cancelError,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _hint(L l) {
    final game = _game;
    final ready = game != null && game.phase == PinballPhase.ready && _playing;
    return AnimatedOpacity(
      opacity: ready ? 1 : 0,
      duration: IbashoSkin.of(context).motion(const Duration(milliseconds: 200)),
      child: Text(
        Layout.of(context).tall ? l.pinballLaunchHint : l.pinballKeys,
        textAlign: TextAlign.center,
        style: Ty.micro,
      ),
    );
  }

  Widget _wideLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
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
                _score(l, 54),
                const SizedBox(height: 12),
                _queueStrip(axis: Axis.horizontal, ball: 40),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _hint(l)),
                    const SizedBox(width: 10),
                    if (_game != null && !_game!.isOver) _pauseButton(l),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                alignment: Alignment.center,
                children: [
                  _board(context, box, tama),
                  PopBanner(text: _banner),
                  Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l, tama != null)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tallLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final small = layout.height < 700;
    const side = 64.0;
    return Column(
      children: [
        SizedBox(height: small ? 6 : 10),
        Expanded(
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(alignment: Alignment.topCenter, child: _board(context, box, tama)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: side,
                    child: Column(
                      children: [
                        if (_game != null && !_game!.isOver) _pauseButton(l),
                        const SizedBox(height: 8),
                        _queueStrip(axis: Axis.vertical, ball: 40),
                        Expanded(
                          child: StageLight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(child: SpeechBubble(text: _bubble, maxWidth: side + 40)),
                                _stage(tama, small ? 56 : 64),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned.fill(child: Center(child: PopBanner(text: _banner))),
              Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l, tama != null)))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _score(l, small ? 40 : 46)),
            const SizedBox(width: 10),
            Expanded(child: _hint(l)),
          ],
        ),
        SizedBox(height: small ? 8 : 14),
      ],
    );
  }
}
