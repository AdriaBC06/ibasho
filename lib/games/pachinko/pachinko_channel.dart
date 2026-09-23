// Ibasho — canal del pachinko: donde se arriesgan bolas para subirlas.
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
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
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
import '../game_stage.dart';
import '../game_store.dart';
import 'pachinko.dart';
import 'pachinko_board.dart';
import 'pachinko_widgets.dart';

/// El canal del pachinko.
///
/// Una escena, como los demas juegos: a un lado el escenario con uno de tus
/// Tamas y la bandeja con las bolas que quedan; al otro, el tablero entero.
/// Se toca el tablero para soltar una bola de la rareza elegida en esa x (y
/// manteniendo, salen seguidas); o con las flechas y espacio.
///
/// Las bolas salen del deposito al empezar (recibo `gacha/pachinko`) y
/// vuelven al acabar con lo que haya salido (`gacha/settle`). Entre medias
/// la tanda vive en el dispositivo, como la partida del pinball.
class PachinkoChannel extends ConsumerStatefulWidget {
  const PachinkoChannel({super.key});

  @override
  ConsumerState<PachinkoChannel> createState() => _PachinkoChannelState();
}

class _PachinkoChannelState extends ConsumerState<PachinkoChannel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  PachinkoGame? _game;
  final Map<Rarity, int> _picked = <Rarity, int>{};
  bool _loading = false;
  String? _error;

  /// La tanda esta parada (a mano, al salir o al volver a entrar).
  bool _paused = false;

  /// La tanda acabada ya esta cobrada en el servidor.
  bool _settled = false;
  bool _settling = false;
  String? _settleError;

  /// La rareza que sale al tocar.
  Rarity? _selected;

  GameStore? _store;
  final math.Random _random = math.Random();
  String? _tamaId;
  final TamaViewController _tama = TamaViewController();
  double _joy = .3;
  String? _bubble;
  Timer? _bubbleTimer;

  // Mandos: donde se apunta y si se esta soltando.
  int? _holdPointer;
  bool _keyDrop = false;
  bool _keyLeft = false;
  bool _keyRight = false;

  final PachinkoFx _fx = PachinkoFx()..aimX = PachinkoTable.width / 2;
  double _fxTime = 0;
  double _lastElapsed = 0;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'pachinko');

  double get _now => _fxTime;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadStore());
  }

  Future<void> _loadStore() async {
    final store = await GameStore.open('pachinko');
    final json = await store.load();
    if (!mounted) return;
    final saved = PachinkoGame.fromJson(json['game']);
    setState(() {
      _store = store;
      if (saved != null) {
        _game = saved;
        _pickRarity();
        // Una tanda a medias vuelve en pausa; una acabada sin cobrar, a
        // cobrarse.
        _paused = !saved.isOver;
      }
    });
    if (saved != null && saved.isOver) unawaited(_settle());
  }

  void _save() {
    final game = _game;
    unawaited(_store?.save(<String, Object?>{
      if (game != null && !_settled) 'game': game.toJson(),
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    // Salir del canal deja la tanda guardada tal cual.
    _save();
    WidgetsBinding.instance.removeObserver(this);
    _bubbleTimer?.cancel();
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
      if (_keyLeft != _keyRight) {
        _fx.aimX = ((_fx.aimX ?? PachinkoTable.width / 2) + (_keyLeft ? -1 : 1) * 160 * dt)
            .clamp(PachinkoTable.dropMinX, PachinkoTable.dropMaxX);
      }
      if (_holdPointer != null || _keyDrop) _drop();
      for (final event in game.tick(dt)) {
        _onEvent(event);
      }
      if (game.isOver) _finished();
    }
    _clock.value = _fxTime;
    if (!_wantsTicks) _ticker.stop();
  }

  // --- Tama y bocadillo ------------------------------------------------------------

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

  // --- Tanda -------------------------------------------------------------------

  /// Si la rareza elegida se ha acabado, pasa a la siguiente que quede.
  void _pickRarity() {
    final game = _game;
    if (game == null) return;
    if (_selected != null && game.stockOf(_selected!) > 0) return;
    _selected = null;
    for (final r in pachinkoRarities) {
      if (game.stockOf(r) > 0) {
        _selected = r;
        return;
      }
    }
  }

  Future<void> _play() async {
    final total = _picked.values.fold(0, (a, b) => a + b);
    if (total == 0 || _loading) return;
    final l = L.of(context)!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(gachaProvider.notifier).loadPachinko(Map<Rarity, int>.of(_picked));
    } catch (e) {
      if (mounted) {
        AudioService.instance.play(Sfx.error);
        setState(() {
          _loading = false;
          _error = l.pachinkoErrorLoad;
        });
      }
      return;
    }
    if (!mounted) return;
    _fx.clear();
    final game = PachinkoGame(stock: Map<Rarity, int>.of(_picked));
    setState(() {
      _game = game;
      _picked.clear();
      _loading = false;
      _paused = false;
      _settled = false;
      _settleError = null;
      _selected = null;
      _joy = .4;
      _pickRarity();
    });
    // Las bolas ya no estan en el deposito: desde aqui viven en la tanda.
    _save();
    _focus.requestFocus();
    _say(l.pachinkoBubbleStart);
    _tama.hop();
    _kick();
  }

  void _pause() {
    final game = _game;
    if (game == null || _paused || game.isOver) return;
    _releaseAll();
    AudioService.instance.play(Sfx.back);
    setState(() => _paused = true);
    _say(L.of(context)!.pachinkoBubblePause, hold: const Duration(seconds: 30));
    _save();
  }

  void _resume() {
    if (!_paused || _settling) return;
    _settleError = null;
    AudioService.instance.play(Sfx.tick);
    setState(() => _paused = false);
    _say(null);
    _focus.requestFocus();
    _kick();
  }

  /// Termina antes de soltarlas todas: las que quedan vuelven tal cual.
  Future<void> _finishEarly() async {
    final game = _game;
    if (game == null || game.flying.isNotEmpty || _settling) return;
    game.end();
    setState(() => _paused = false);
    _finished();
  }

  void _releaseAll() {
    _holdPointer = null;
    _keyDrop = _keyLeft = _keyRight = false;
  }

  bool _finishing = false;

  /// La tanda se ha acabado: se guarda y se cobra.
  void _finished() {
    if (_finishing) return;
    _finishing = true;
    _releaseAll();
    _say(null);
    _save();
    unawaited(_settle());
  }

  Future<void> _settle() async {
    final game = _game;
    if (game == null || _settling || _settled) return;
    final l = L.of(context)!;
    setState(() {
      _settling = true;
      _settleError = null;
    });
    try {
      await ref.read(gachaProvider.notifier).settlePachinko(game.payout);
    } catch (e) {
      if (mounted) {
        AudioService.instance.play(Sfx.error);
        setState(() {
          _settling = false;
          _settleError = l.pachinkoErrorSettle;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _settling = false;
      _settled = true;
      _joy = .7;
    });
    _save();
    AudioService.instance.play(Sfx.pkPayout);
    _tama
      ..cuddle()
      ..hop();
  }

  void _again() {
    setState(() {
      _game = null;
      _settled = false;
      _finishing = false;
      _settleError = null;
    });
    _fx.clear();
    _save();
  }

  void _drop() {
    final game = _game;
    final rarity = _selected;
    if (game == null || rarity == null || !_playing) return;
    final event = game.drop(_fx.aimX ?? PachinkoTable.width / 2, rarity);
    if (event == null) return;
    _onEvent(event);
    if (game.stockOf(rarity) == 0) setState(_pickRarity);
  }

  void _onEvent(PachinkoEvent e) {
    final l = L.of(context)!;
    final audio = AudioService.instance;
    switch (e.kind) {
      case PachinkoEventKind.drop:
        audio.play(Sfx.pkDrop);
        setState(() {});
      case PachinkoEventKind.pin:
        _fx.pinAt[e.index!] = _now;
        audio.play(Sfx.pkPin);
      case PachinkoEventKind.ball:
        audio.play(Sfx.pkPin);
      case PachinkoEventKind.windmill:
        audio.play(Sfx.pkWindmill);
      case PachinkoEventKind.tulip:
        audio.play(Sfx.pkTulip);
      case PachinkoEventKind.pocket:
        final rarity = e.rarity!;
        final kind = e.pocket!;
        final prize = pachinkoPrize(rarity, kind)!;
        _fx.pocketAt[e.index!] = _now;
        _fx.popup(e.at, _now, rarity, kind);
        _fx.spark(e.at, _now, RarityArt.of(prize));
        final big = kind == PocketKind.up2 || (kind == PocketKind.up1 && prize == Rarity.ur);
        audio.play(switch (kind) {
          PocketKind.same => Sfx.pkSame,
          _ => big ? Sfx.pkUp2 : Sfx.pkUp1,
        });
        if (big) {
          _joy = 1;
          _say(kind == PocketKind.up2 ? l.pachinkoBubbleTulip : l.pachinkoBubbleUp);
          _tama
            ..cuddle()
            ..hop();
        } else if (kind == PocketKind.up1) {
          _joy = math.min(1, _joy + .2);
          _tama.hop();
        }
        setState(() {});
      case PachinkoEventKind.out:
        _fx.outAt = _now;
        audio.play(Sfx.pkOut);
        _joy = math.max(-.3, _joy - .06);
        // Perder una rara duele; las N se van sin drama.
        if (e.rarity!.index >= Rarity.sr.index) {
          _say(l.pachinkoBubbleLost);
          _tama.speak(ChirpKind.sigh);
        }
        setState(() {});
      case PachinkoEventKind.wall || PachinkoEventKind.nudge:
        break;
    }
  }

  // --- Mandos -----------------------------------------------------------------

  bool get _playing {
    final game = _game;
    return game != null && !_paused && !game.isOver;
  }

  double _worldX(Offset local, double scale) => local.dx / scale;

  void _onPointerDown(PointerDownEvent e, double scale) {
    if (!_playing) return;
    _fx.aimX = _worldX(e.localPosition, scale);
    _holdPointer = e.pointer;
    _drop();
  }

  void _onPointerMove(PointerMoveEvent e, double scale) {
    if (e.pointer != _holdPointer) return;
    _fx.aimX = _worldX(e.localPosition, scale);
  }

  void _onPointerUp(PointerEvent e) {
    if (e.pointer == _holdPointer) _holdPointer = null;
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
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _keyLeft = down && _playing;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      _keyRight = down && _playing;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.arrowDown) {
      _keyDrop = down && _playing;
      if (_keyDrop) _drop();
      return KeyEventResult.handled;
    }
    final digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];
    final i = digits.indexOf(key);
    if (i >= 0) {
      final rarity = pachinkoRarities[i];
      if (down && _playing && _game!.stockOf(rarity) > 0) {
        AudioService.instance.play(Sfx.tick);
        setState(() => _selected = rarity);
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
    final tama = _currentTama(ref.watch(tamasProvider).tamas);
    if (_wantsTicks && !_ticker.isActive) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kick();
      });
    }
    return ChannelScaffold(
      title: l.pachinkoTitle,
      glyph: Glyph.star,
      art: ArtIcon.pachinko,
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
    return KeyedSubtree(key: ValueKey<String>('pachinko.tama.${tama?.id}'), child: face);
  }

  Widget _tray({Axis axis = Axis.horizontal, double ball = 34}) {
    final game = _game;
    if (game == null || game.isOver) return const SizedBox.shrink();
    return PachinkoTray(
      game: game,
      selected: _selected,
      axis: axis,
      ball: ball,
      onSelect: (r) => setState(() => _selected = r),
    );
  }

  Widget _pauseButton(L l) => IconPill(
        key: const ValueKey<String>('pachinko.pause'),
        glyph: _paused ? Glyph.play : Glyph.pause,
        semanticLabel: _paused ? l.pachinkoResume : l.pachinkoPause,
        diameter: 44,
        onPressed: _paused ? _resume : _pause,
      );

  /// El tablero entero, tan grande como quepa.
  Widget _board(BuildContext context, BoxConstraints box) {
    final skin = IbashoSkin.of(context);
    final width = math.min(box.maxWidth, box.maxHeight * PachinkoTable.width / PachinkoTable.height);
    final s = width / PachinkoTable.width;
    final shown = _game ?? _idle;
    return SizedBox(
      width: width,
      height: PachinkoTable.height * s,
      child: MouseRegion(
        onHover: (e) {
          if (_playing) _fx.aimX = _worldX(e.localPosition, s);
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onPointerDown(e, s),
          onPointerMove: (e) => _onPointerMove(e, s),
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: AnimatedOpacity(
            opacity: _paused ? .35 : 1,
            duration: skin.motion(const Duration(milliseconds: 200)),
            child: PachinkoBoard(
              key: const ValueKey<String>('pachinko.board'),
              game: shown,
              fx: _fx,
              clock: _clock,
              accent: skin.accent,
              accentDeep: skin.accentDeep,
            ),
          ),
        ),
      ),
    );
  }

  /// El tablero de hoy, de adorno antes de cargar bolas.
  final PachinkoGame _idle = PachinkoGame(stock: const <Rarity, int>{});

  Widget _overlay(L l) {
    final game = _game;
    if (game == null) {
      return PachinkoLoadCard(
        gacha: ref.watch(gachaProvider),
        picked: _picked,
        busy: _loading,
        error: _error,
        showKeys: !Layout.of(context).tall,
        onChange: (r, n) => setState(() => _picked[r] = n),
        onPlay: _play,
      );
    }
    if (game.isOver) {
      return PachinkoResultsCard(
        game: game,
        settled: _settled,
        busy: _settling,
        error: _settleError,
        onRetry: () => unawaited(_settle()),
        onAgain: _again,
      );
    }
    if (_paused) {
      return PachinkoPauseCard(
        onResume: _resume,
        left: game.left,
        falling: game.flying.isNotEmpty,
        onFinish: () => unawaited(_finishEarly()),
        busy: _settling,
        error: _settleError,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _hint(L l) {
    final layout = Layout.of(context);
    return AnimatedOpacity(
      opacity: _playing ? 1 : 0,
      duration: IbashoSkin.of(context).motion(const Duration(milliseconds: 200)),
      child: Text(
        layout.tall ? l.pachinkoDropHint : l.pachinkoKeys,
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
                _tray(ball: 40),
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
                  _board(context, box),
                  Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l)))),
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
                      builder: (context, box) => Align(alignment: Alignment.topCenter, child: _board(context, box)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: side,
                    child: Column(
                      children: [
                        if (_game != null && !_game!.isOver) _pauseButton(l),
                        const SizedBox(height: 8),
                        _tray(axis: Axis.vertical, ball: 36),
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
              Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l)))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _hint(l),
        SizedBox(height: small ? 8 : 14),
      ],
    );
  }
}
