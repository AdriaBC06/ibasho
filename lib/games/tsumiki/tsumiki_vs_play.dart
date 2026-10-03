// Ibasho — la partida del versus de Tsumiki: tu pozo grande, el del otro
// pequeño con su Tama, las filas grises que llegan y las trabas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/tsumiki_versus.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/tsumiki_versus.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/social/social_widgets.dart' show CardTama;
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../game_stage.dart' show SpeechBubble;
import '../koen/koen_album.dart' show koenFriendName;
import 'tsumiki.dart';
import 'tsumiki_board.dart';
import 'tsumiki_input.dart';
import 'tsumiki_versus.dart';
import 'tsumiki_vs_widgets.dart';
import 'tsumiki_widgets.dart';

/// La partida en curso de [TsumikiVersusController]. Se crea al pasar la
/// sala a juego (una por partida: el canal la separa por su id) y lleva su
/// propio [TsumikiDuel]: publica lo suyo y recibe lo del otro.
class TsumikiVersusPlay extends ConsumerStatefulWidget {
  const TsumikiVersusPlay({super.key, required this.room, required this.onLeave, required this.onExit});

  /// La sala al empezar: de aquí salen la semilla y el lado.
  final TsumikiRoom room;

  /// Rendirse a media partida (el canal pregunta antes).
  final VoidCallback onLeave;

  /// Salir tras el resultado.
  final VoidCallback onExit;

  @override
  ConsumerState<TsumikiVersusPlay> createState() => TsumikiVersusPlayState();
}

class TsumikiVersusPlayState extends ConsumerState<TsumikiVersusPlay>
    with SingleTickerProviderStateMixin, TsumikiControls<TsumikiVersusPlay> {
  late final String _me = ref.read(sessionProvider).accountId;
  late final String _friend = widget.room.other(_me);
  late final TsumikiDuel _duel = TsumikiDuel(seed: widget.room.seed, side: widget.room.side(_me));
  late final TsumikiVersusController _vs = ref.read(tsumikiVersusProvider.notifier);
  StreamSubscription<TsumikiVsEvent>? _incoming;

  final TsumikiFx _fx = TsumikiFx();
  double _fxTime = 0;
  double _lastElapsed = 0;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'tsumiki.vs');

  double? _countFrom;
  String? _banner;
  bool _bannerBig = false;
  Timer? _bannerTimer;

  bool _publishing = false;
  bool _dirty = false;
  bool _lost = false;
  bool _ended = false;
  bool _rematchBusy = false;

  // El final, tal como quedó: con la revancha del otro la sala ya es otra.
  bool _won = false;
  TsumikiEnd? _end;
  TsumikiSeat _finalSeat = const TsumikiSeat();
  Set<TsumikiSabotage> _shownFx = const <TsumikiSabotage>{};

  // Lo que dice el Tama del otro y lo contento que está.
  String? _rivalSay;
  double _rivalJoy = .5;
  double _rivalSaidAt = -10;
  int _rivalWeight = 0;
  Timer? _rivalTimer;
  bool _rivalHigh = false;

  TsumikiGame get _game => _duel.game;
  double get _now => _fxTime;

  /// Lo que lleva el duelo, para rendirse o cerrar sin perderlo.
  int get lines => _game.lines;
  int get sent => _duel.sent;

  @override
  TsumikiGame get controlledGame => _game;

  @override
  TsumikiFx get controlFx => _fx;

  @override
  double get controlNow => _now;

  @override
  void onPieceLocked(LockEvent e) => _onLock(e);

  @override
  void kickTicker() => _kick();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _incoming = _vs.incoming.listen(_onIncoming);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Lo que el otro ya hubiera mandado antes de abrirse esta pantalla.
      for (final (_, e) in widget.room.events[_friend] ?? const <(String, TsumikiVsEvent)>[]) {
        _onIncoming(e);
      }
      _startCountdown();
    });
  }

  @override
  void dispose() {
    unawaited(_incoming?.cancel());
    _bannerTimer?.cancel();
    _rivalTimer?.cancel();
    _ticker.dispose();
    _clock.dispose();
    _focus.dispose();
    super.dispose();
  }

  // --- Reloj -----------------------------------------------------------------

  bool get _wantsTicks =>
      _countFrom != null || _game.status == TsumikiStatus.playing || _now < _fx.busyUntil || _duel.active.isNotEmpty;

  void _kick() {
    if (!_ticker.isActive && _wantsTicks) {
      _lastElapsed = 0;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final e = elapsed.inMicroseconds / 1e6;
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
        _publish();
        setState(() {});
      }
    } else if (_game.status == TsumikiStatus.playing) {
      repeatHeld(dt);
      final wasClearing = _game.clearing.isNotEmpty;
      final event = _game.tick(dt);
      if (event != null) _onLock(event);
      if (wasClearing && _game.clearing.isEmpty) {
        setState(() {});
        if (_game.isOver) _onTopOut();
      }
    }
    if (_duel.active.isNotEmpty) {
      _duel.tick(dt);
      final now = _duel.active.keys.toSet();
      if (now.length != _shownFx.length || !now.containsAll(_shownFx)) {
        _shownFx = now;
        _publish();
        setState(() {});
      }
    }
    _clock.value = _fxTime;
    if (!_wantsTicks) _ticker.stop();
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

  /// El Tama del otro reacciona. Si acaba de decir algo, solo lo pisa lo que
  /// pesa al menos lo mismo ([weight]: 1 las filas, 2 las trabas y los
  /// sustos, 3 el final).
  void _rival(String text, {required double joy, int weight = 1, Duration hold = const Duration(milliseconds: 2200)}) {
    if (_now - _rivalSaidAt < .9 && weight < _rivalWeight) return;
    _rivalSaidAt = _now;
    _rivalWeight = weight;
    _rivalTimer?.cancel();
    setState(() {
      _rivalSay = text;
      _rivalJoy = joy;
    });
    _rivalTimer = Timer(hold, () {
      if (mounted) setState(() => _rivalSay = null);
    });
  }

  void _startCountdown() {
    if (_game.status != TsumikiStatus.ready) return;
    _focus.requestFocus();
    AudioService.instance.play(Sfx.tick);
    _countFrom = _now;
    _kick();
    setState(() {});
    _rival(L.of(context)!.tsumikiRivalStart, joy: .8);
  }

  // --- Partida -----------------------------------------------------------------

  void _onLock(LockEvent e) {
    final l = L.of(context)!;
    _fx
      ..locked = e.cells
      ..lockedAt = _now
      ..touch(_now + TsumikiFx.lockTime);
    if (e.garbageIn > 0) {
      _fx
        ..shakeAt = _now
        ..shakePower = math.min(5, 1.5 + e.garbageIn * .5)
        ..touch(_now + TsumikiFx.shakeTime);
      AudioService.instance.play(Sfx.back);
    }
    final attack = _duel.onLock(e);
    if (e.rows.isNotEmpty) {
      final n = e.rows.length;
      AudioService.instance.play(n >= 2 ? Sfx.chime : Sfx.tick);
      if (n == 4) {
        _fx
          ..shakeAt = _now
          ..shakePower = 6
          ..touch(_now + TsumikiFx.shakeTime);
        _showBanner(e.backToBack ? l.tsumikiBannerB2B : l.tsumikiBannerTsumiki);
      } else if (n >= 2) {
        _showBanner(n == 3 ? l.tsumikiBannerTriple : l.tsumikiBannerDouble);
      }
      if (e.combo >= 2 && n < 4 && attack == null) _showBanner(l.tsumikiBannerCombo(e.combo));
    }
    if (attack != null) {
      unawaited(_vs.send(TsumikiVsEvent.attack(attack)));
      _showBanner(l.tsumikiVsAttack(attack.rows));
      _rival(l.tsumikiRivalHit, joy: .2);
    }
    _publish();
    if (e.gameOver) _onTopOut();
  }

  void _onIncoming(TsumikiVsEvent e) {
    if (!mounted || _ended) return;
    final l = L.of(context)!;
    if (e.attack case final a?) {
      _duel.receive(a);
      AudioService.instance.play(Sfx.tick);
      if (a.rows >= 2) _rival(l.tsumikiRivalAttack, joy: .95);
    } else if (e.sabotage case final s?) {
      _duel.suffer(s);
      _shownFx = _duel.active.keys.toSet();
      AudioService.instance.play(Sfx.error);
      _showBanner(l.tsumikiSabGot(sabotageName(l, s)));
      _rival(l.tsumikiRivalTrick, joy: 1, weight: 2);
      _publish();
      _kick();
    }
    setState(() {});
  }

  void _throw(TsumikiSabotage s) {
    if (_game.status != TsumikiStatus.playing || !_duel.use(s)) return;
    final l = L.of(context)!;
    AudioService.instance.play(Sfx.chime);
    unawaited(_vs.send(TsumikiVsEvent.sabotage(s)));
    _showBanner(l.tsumikiSabThrown(sabotageName(l, s), koenFriendName(ref, _friend)));
    _rival(l.tsumikiRivalTricked, joy: .15, weight: 2);
    _publish();
    setState(() {});
  }

  /// Publica el tablero; si ya hay una publicación en camino, vuelve a
  /// publicar al acabar con lo último.
  void _publish() {
    if (_ended) return;
    if (_publishing) {
      _dirty = true;
      return;
    }
    _publishing = true;
    _dirty = false;
    unawaited(_vs
        .publish(
          board: _game.encodeBoard(),
          lines: _game.lines,
          sent: _duel.sent,
          meter: _duel.meter,
          fx: _duel.active.keys.toSet(),
        )
        .whenComplete(() {
      _publishing = false;
      if (_dirty && mounted) _publish();
    }));
  }

  void _onTopOut() {
    if (_lost) return;
    _lost = true;
    releaseAll();
    _fx
      ..overAt = _now + .15
      ..touch(_now + .15 + TsumikiFx.overTime);
    AudioService.instance.play(Sfx.error);
    unawaited(_vs.lose(lines: _game.lines, sent: _duel.sent));
    setState(() {});
    _kick();
  }

  /// La sala dice que se ha acabado (por mí o por el otro): se para todo.
  void _onEnded() {
    if (_ended) return;
    _ended = true;
    releaseAll();
    _countFrom = null;
    _banner = null;
    _game.pause();
    _duel.active.clear();
    ref.invalidate(tsumikiScoreProvider(_friend));
    final vs = ref.read(tsumikiVersusProvider);
    _won = vs.winner == _me;
    _end = vs.room?.end;
    _finalSeat = vs.room?.seat(_friend) ?? const TsumikiSeat();
    AudioService.instance.play(_won ? Sfx.chime : Sfx.back);
    setState(() {});
    final l = L.of(context)!;
    _rival(_won ? l.tsumikiRivalLost : l.tsumikiRivalWon, joy: _won ? .3 : 1, weight: 3, hold: const Duration(seconds: 6));
  }

  Future<void> _rematch() async {
    setState(() => _rematchBusy = true);
    await _vs.rematch();
    if (mounted) setState(() => _rematchBusy = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      const digits = [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4];
      final i = digits.indexOf(event.logicalKey);
      if (i >= 0) {
        _throw(TsumikiSabotage.values[i]);
        return KeyEventResult.handled;
      }
    }
    return handleActKey(event);
  }

  // --- Composición -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final vs = ref.watch(tsumikiVersusProvider);
    final room = vs.room;
    final seat = _ended ? _finalSeat : (room?.id == widget.room.id ? room!.seat(_friend) : const TsumikiSeat());
    _duel.opponentHeight = seat.height;
    // Su Tama se asusta una vez cada vez que su montón se acerca arriba.
    final high = !_ended && seat.height >= TsumikiGame.visibleRows - 5;
    if (high != _rivalHigh) {
      _rivalHigh = high;
      if (high) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rival(L.of(context)!.tsumikiRivalDanger, joy: .1, weight: 2);
        });
      }
    }
    if (vs.phase == TsumikiVsPhase.done && room?.id == widget.room.id) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onEnded();
      });
    }
    if (_wantsTicks && !_ticker.isActive) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kick();
      });
    }
    final layout = Layout.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: layout.tall ? _tallLayout(context, seat, vs) : _wideLayout(context, seat, vs),
      ),
    );
  }

  Widget _overlay(L l, TsumikiVsState vs, TsumikiSeat seat) {
    if (!_ended) return const SizedBox.shrink();
    return TsumikiVsResultCard(
      won: _won,
      end: _end,
      friendName: koenFriendName(ref, _friend),
      myLines: _game.lines,
      mySent: _duel.sent,
      theirLines: seat.lines,
      theirSent: seat.sent,
      score: ref.watch(tsumikiScoreProvider(_friend)).valueOrNull,
      rematchOffered: vs.rematchOffered,
      rematchBusy: _rematchBusy,
      onRematch: () => unawaited(_rematch()),
      onExit: widget.onExit,
    );
  }

  Widget _well(BuildContext context, BoxConstraints box, {required bool tall}) {
    final skin = IbashoSkin.of(context);
    final pad = tall ? 8.0 : 12.0;
    const gauge = 10.0;
    final cell = math
        .min((box.maxWidth - pad * 2 - gauge - 6) / TsumikiGame.width, (box.maxHeight - pad * 2) / TsumikiGame.visibleRows)
        .floorToDouble()
        .clamp(10.0, 40.0);
    controlCell = cell;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: pad),
          child: GarbageGauge(rows: _game.pendingGarbage, cell: cell, width: gauge),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: cell * TsumikiGame.width + pad * 2,
          height: cell * TsumikiGame.visibleRows + pad * 2,
          child: GlossSurface(
            radius: tall ? 18 : 24,
            tint: skin.accentWash,
            elevation: 2,
            padding: EdgeInsets.all(pad),
            child: wellGestures(
              key: const ValueKey<String>('tsumiki.vs.board'),
              child: Stack(
                children: [
                  TsumikiBoard(game: _game, cellSize: cell, fx: _fx, clock: _clock, accent: skin.accent),
                  Positioned(left: 0, right: 0, top: 0, child: TsumikiFog(cell: cell, on: _duel.foggy)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _holdPocket(L l, double w) => PiecePocket(
        label: l.tsumikiHold,
        pieces: [_game.held],
        width: w,
        muted: !_game.canHold || _game.holdLocked,
      );

  Widget _nextPocket(L l, double w, {int count = 3}) => PiecePocket(
        label: l.tsumikiNext,
        pieces: _duel.previewHidden ? List<TsumikiPiece?>.filled(count, null) : _game.next.take(count).toList(),
        width: w,
        muted: _duel.previewHidden,
      );

  /// El otro: su nombre y su Tama, su tablero pequeño y sus números.
  Widget _opponent(L l, TsumikiSeat seat, {required double cell, required double tama, bool compact = false}) {
    final skin = IbashoSkin.of(context);
    final name = koenFriendName(ref, _friend);
    final head = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: tama,
          height: tama,
          child: IgnorePointer(child: CardTama(key: const ValueKey<String>('tsumiki.vs.rivalTama'), accountId: _friend, size: tama, joy: _rivalJoy)),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(color: Ty.ink, fontWeight: FontWeight.w600)),
        ),
      ],
    );
    final bubble = SpeechBubble(key: const ValueKey<String>('tsumiki.vs.rivalSay'), text: _rivalSay, maxWidth: compact ? 150 : 260);
    return Column(
      key: const ValueKey<String>('tsumiki.vs.opponent'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          // En vertical no hay hueco: el globo flota sobre los bolsillos.
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              head,
              Positioned(
                left: -60,
                right: 0,
                top: 0,
                child: FractionalTranslation(translation: const Offset(0, -1), child: Align(alignment: Alignment.bottomRight, child: bubble)),
              ),
            ],
          )
        else ...[
          SizedBox(height: 66, child: Align(alignment: Alignment.bottomCenter, child: bubble)),
          const SizedBox(height: 4),
          head,
        ],
        const SizedBox(height: 4),
        TsumikiMiniBoard(board: seat.board, cell: cell, over: _ended && _won),
        const SizedBox(height: 4),
        Text(
          compact ? '${seat.lines} · ${seat.sent}' : '${seat.lines} ${l.tsumikiLines} · ${seat.sent} ${l.tsumikiVsSent}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Ty.micro.copyWith(color: skin.accentDeep),
        ),
        if (seat.fx.isNotEmpty) ...[
          const SizedBox(height: 4),
          SufferedTricks(active: seat.fx, size: compact ? 20 : 24),
        ],
      ],
    );
  }

  Widget _leaveButton(L l) => IconPill(
        key: const ValueKey<String>('tsumiki.vs.leave'),
        glyph: Glyph.flag,
        semanticLabel: l.tsumikiVsLeave,
        diameter: 48,
        onPressed: _ended ? widget.onExit : widget.onLeave,
      );

  Widget _sabotages({double button = 46, bool vertical = false}) => SabotageBar(
        meter: _duel.meter / TsumikiDuel.meterFull,
        ready: _duel.hasCharge && _game.status == TsumikiStatus.playing,
        onThrow: _throw,
        button: button,
        vertical: vertical,
      );

  Widget _wideLayout(BuildContext context, TsumikiSeat seat, TsumikiVsState vs) {
    final l = L.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 330,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    final cell = math.min(9.0, ((box.maxHeight - 190) / TsumikiGame.visibleRows).floorToDouble()).clamp(4.0, 9.0);
                    return Center(child: _opponent(l, seat, cell: cell, tama: 64));
                  }),
                ),
                if (_duel.active.isNotEmpty) ...[
                  SufferedTricks(active: _duel.active.keys),
                  const SizedBox(height: 8),
                ],
                _sabotages(),
                const SizedBox(height: 12),
                padControls(l, pad: 124, button: 56, middle: _leaveButton(l), keyPrefix: 'tsumiki.vs'),
                const SizedBox(height: 6),
                Text(l.tsumikiVsKeys, textAlign: TextAlign.center, style: Ty.micro),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
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
                  Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l, vs, seat)))),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _tallLayout(BuildContext context, TsumikiSeat seat, TsumikiVsState vs) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final small = layout.height < 700;
    final side = small ? 88.0 : 100.0;
    return Column(
      children: [
        SizedBox(height: small ? 4 : 10),
        Expanded(
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(alignment: Alignment.topCenter, child: _well(context, box, tall: true)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: side,
                    child: Column(
                      children: [
                        _nextPocket(l, side, count: 2),
                        const SizedBox(height: 6),
                        _holdPocket(l, side),
                        const SizedBox(height: 6),
                        Expanded(
                          child: LayoutBuilder(builder: (context, box) {
                            final cell = math.min(side / TsumikiGame.width, (box.maxHeight - 56) / TsumikiGame.visibleRows).floorToDouble().clamp(3.0, 9.0);
                            return Align(alignment: Alignment.topCenter, child: _opponent(l, seat, cell: cell, tama: 26, compact: true));
                          }),
                        ),
                        if (_duel.active.isNotEmpty) SufferedTricks(active: _duel.active.keys, size: 22),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned.fill(child: Center(child: PopBanner(text: _banner, big: _bannerBig))),
              Positioned.fill(child: Center(child: SingleChildScrollView(child: _overlay(l, vs, seat)))),
            ],
          ),
        ),
        SizedBox(height: small ? 4 : 8),
        _sabotages(button: small ? 38 : 42),
        SizedBox(height: small ? 4 : 8),
        padControls(l, pad: small ? 108 : 128, button: small ? 50 : 56, middle: _leaveButton(l), keyPrefix: 'tsumiki.vs'),
        SizedBox(height: small ? 6 : 12),
      ],
    );
  }
}
