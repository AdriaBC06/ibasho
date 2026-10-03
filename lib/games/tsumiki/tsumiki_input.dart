// Ibasho — los mandos de Tsumiki: cruceta, botones, teclado y gestos sobre el
// pozo. Los comparten la partida sola y el versus.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/widgets/glyphs.dart';
import 'tsumiki.dart';
import 'tsumiki_board.dart';
import 'tsumiki_widgets.dart';

enum TsumikiAct { left, right, down, drop, rotate, rotateBack, hold }

/// Mover, girar, bajar, soltar y guardar sobre [controlledGame], con la
/// repetición de la cruceta (espera un poco y luego repite rápido) y los
/// gestos sobre el pozo (deslizar para mover, tocar para girar, bajar rápido
/// para soltar y subir para guardar).
mixin TsumikiControls<W extends StatefulWidget> on State<W> {
  TsumikiGame get controlledGame;
  TsumikiFx get controlFx;

  /// El reloj de efectos del canal.
  double get controlNow;

  /// Lo que pasa al asentarse una pieza soltada de golpe (las que caen solas
  /// las avisa el tick del canal).
  void onPieceLocked(LockEvent e);

  /// Se ha guardado una pieza.
  void onPieceHeld() {}

  /// Que el reloj del canal vuelva a andar.
  void kickTicker();

  static const double _das = .17;
  static const double _arr = .05;
  static const double _softRate = .045;
  int _dasDir = 0;
  double _dasT = 0;
  bool _softHeld = false;
  double _softT = 0;
  final Set<TsumikiAct> _keysDown = <TsumikiAct>{};

  double _dragX = 0;
  double _dragY = 0;
  bool _dragged = false;

  /// Lado de una casilla del pozo: los gestos se miden con él.
  double controlCell = 30;

  /// La repetición de la cruceta y de bajar, en cada tick.
  void repeatHeld(double dt) {
    final game = controlledGame;
    if (_dasDir != 0) {
      _dasT += dt;
      while (_dasT >= _das + _arr) {
        _dasT -= _arr;
        if (!game.move(_dasDir)) break;
      }
    }
    if (_softHeld) {
      _softT += dt;
      while (_softT >= _softRate) {
        _softT -= _softRate;
        if (!game.softDrop()) break;
      }
    }
  }

  void releaseAll() {
    _dasDir = 0;
    _softHeld = false;
    _keysDown.clear();
  }

  void press(TsumikiAct act) {
    final game = controlledGame;
    if (game.status != TsumikiStatus.playing) return;
    switch (act) {
      case TsumikiAct.left:
      case TsumikiAct.right:
        final dir = act == TsumikiAct.left ? -1 : 1;
        game.move(dir);
        _dasDir = dir;
        _dasT = 0;
      case TsumikiAct.down:
        game.softDrop();
        _softHeld = true;
        _softT = 0;
      case TsumikiAct.rotate:
      case TsumikiAct.rotateBack:
        if (game.rotate(clockwise: act == TsumikiAct.rotate)) AudioService.instance.play(Sfx.tick);
      case TsumikiAct.drop:
        final p = game.current;
        final res = game.hardDrop();
        if (res != null && p != null) {
          final (d, event) = res;
          final now = controlNow;
          final cols = p.cells.map((c) => c.$1).toSet().toList();
          final ys = p.cells.map((c) => c.$2);
          controlFx.drop = (cols, ys.reduce(math.min), ys.reduce(math.max) + d, pieceColor(p.type), now);
          controlFx.touch(now + TsumikiFx.dropTime);
          if (d > 0) {
            controlFx
              ..shakeAt = now
              ..shakePower = math.min(4, 1.2 + d * .12);
          }
          AudioService.instance.play(Sfx.tick);
          onPieceLocked(event);
        }
      case TsumikiAct.hold:
        if (game.hold()) {
          AudioService.instance.play(Sfx.tick);
          onPieceHeld();
        }
    }
    setState(() {});
    kickTicker();
  }

  void release(TsumikiAct act) {
    switch (act) {
      case TsumikiAct.left:
      case TsumikiAct.right:
        final dir = act == TsumikiAct.left ? -1 : 1;
        if (_dasDir == dir) {
          // Si la otra flecha sigue pulsada, se sigue hacia allí.
          final other = act == TsumikiAct.left ? TsumikiAct.right : TsumikiAct.left;
          _dasDir = _keysDown.contains(other) ? -dir : 0;
          _dasT = 0;
        }
      case TsumikiAct.down:
        _softHeld = false;
      default:
        break;
    }
  }

  static final Map<LogicalKeyboardKey, TsumikiAct> _keys = {
    LogicalKeyboardKey.arrowLeft: TsumikiAct.left,
    LogicalKeyboardKey.keyA: TsumikiAct.left,
    LogicalKeyboardKey.arrowRight: TsumikiAct.right,
    LogicalKeyboardKey.keyD: TsumikiAct.right,
    LogicalKeyboardKey.arrowDown: TsumikiAct.down,
    LogicalKeyboardKey.keyS: TsumikiAct.down,
    LogicalKeyboardKey.arrowUp: TsumikiAct.rotate,
    LogicalKeyboardKey.keyW: TsumikiAct.rotate,
    LogicalKeyboardKey.keyX: TsumikiAct.rotate,
    LogicalKeyboardKey.keyZ: TsumikiAct.rotateBack,
    LogicalKeyboardKey.space: TsumikiAct.drop,
    LogicalKeyboardKey.keyC: TsumikiAct.hold,
    LogicalKeyboardKey.shiftLeft: TsumikiAct.hold,
  };

  /// Las teclas de jugar. La repetición la lleva el canal, no el sistema.
  KeyEventResult handleActKey(KeyEvent event) {
    final act = _keys[event.logicalKey];
    if (act == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _keysDown.add(act);
      press(act);
    } else if (event is KeyUpEvent) {
      _keysDown.remove(act);
      release(act);
    }
    return KeyEventResult.handled;
  }

  /// Envuelve el pozo con los gestos.
  Widget wellGestures({required Key key, required Widget child}) => GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) {
          if (!_dragged) press(TsumikiAct.rotate);
        },
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: child,
      );

  void _onPanStart(DragStartDetails d) {
    _dragX = 0;
    _dragY = 0;
    _dragged = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final game = controlledGame;
    if (game.status != TsumikiStatus.playing) return;
    _dragX += d.delta.dx;
    _dragY += d.delta.dy;
    final step = controlCell * .85;
    while (_dragX.abs() >= step) {
      final dir = _dragX.sign.toInt();
      game.move(dir);
      _dragX -= dir * step;
      _dragged = true;
    }
    // Bajar despacio baja fila a fila; los empujones hacia arriba no cuentan.
    while (_dragY >= controlCell) {
      game.softDrop();
      _dragY -= controlCell;
      _dragged = true;
    }
    setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (v.dy > 1300 && v.dy.abs() > v.dx.abs() * 1.4) {
      press(TsumikiAct.drop);
    } else if (v.dy < -900 && v.dy.abs() > v.dx.abs() * 1.4) {
      press(TsumikiAct.hold);
    }
  }

  /// Los mandos: cruceta a la izquierda, [middle] y guardar en medio, y A y B
  /// en diagonal a la derecha.
  Widget padControls(L l, {required double pad, required double button, required Widget middle, String keyPrefix = 'tsumiki'}) {
    TsumikiAct act(PadDir d) => switch (d) {
          PadDir.left => TsumikiAct.left,
          PadDir.right => TsumikiAct.right,
          PadDir.down => TsumikiAct.down,
          PadDir.up => TsumikiAct.drop,
        };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DPad(
          key: ValueKey<String>('$keyPrefix.dpad'),
          size: pad,
          semanticLabel: l.tsumikiPad,
          onDown: (d) => press(act(d)),
          onUp: (d) => release(act(d)),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              middle,
              const SizedBox(height: 8),
              PadButton(
                key: ValueKey<String>('$keyPrefix.hold'),
                glyph: Glyph.undo,
                size: 48,
                semanticLabel: l.tsumikiHoldAction,
                onDown: () => press(TsumikiAct.hold),
              ),
            ],
          ),
        ),
        SizedBox(
          width: button * 2.1,
          height: button * 1.7,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: PadButton(
                  key: ValueKey<String>('$keyPrefix.b'),
                  letter: 'B',
                  size: button,
                  semanticLabel: l.tsumikiRotateBack,
                  onDown: () => press(TsumikiAct.rotateBack),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: PadButton(
                  key: ValueKey<String>('$keyPrefix.a'),
                  letter: 'A',
                  size: button,
                  semanticLabel: l.tsumikiRotate,
                  onDown: () => press(TsumikiAct.rotate),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
