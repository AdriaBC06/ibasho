// Ibasho — base de todo lo que se puede pulsar.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../canvas.dart';
import '../touch.dart';

/// Estado continuo de un control pulsable.
///
/// Los valores van de 0 a 1 y estan animados: los pintores los usan para
/// interpolar elevacion, inclinacion y brillo sin saltos.
class PressState {
  const PressState(this.hover, this.press, this.focus, this.enabled);

  final double hover;
  final double press;
  final bool focus;
  final bool enabled;
}

/// Gestion de puntero, foco y teclado para un control propio.
///
/// No hay ni ripple ni highlight de Material: el aspecto entero lo decide el
/// `builder`.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onSecondaryPressed,
    this.enabled = true,
    this.cue = Sfx.tick,
    this.focusNode,
    this.autofocus = false,
    this.cursor = SystemMouseCursors.click,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, PressState state) builder;
  final VoidCallback? onPressed;
  final VoidCallback? onSecondaryPressed;
  final bool enabled;

  /// Sonido que suena al activarlo. `null` lo deja mudo.
  final Sfx? cue;

  final FocusNode? focusNode;
  final bool autofocus;
  final MouseCursor cursor;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with TickerProviderStateMixin
    implements TouchTarget {
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: T.hover,
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: T.press,
    reverseDuration: const Duration(milliseconds: 160),
  );
  bool _focused = false;

  bool get _live => widget.enabled && widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    TouchAssist.register(this);
  }

  @override
  bool get touchLive => _live;

  @override
  void touchFire() {
    _press.forward(from: 1).then((_) => _press.reverse());
    _fire();
  }

  @override
  void dispose() {
    TouchAssist.unregister(this);
    _hover.dispose();
    _press.dispose();
    super.dispose();
  }

  void _fire() {
    if (!_live) return;
    if (widget.cue != null) AudioService.instance.play(widget.cue!);
    widget.onPressed!.call();
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    _hover.duration = skin.motion(T.hover);
    _press.duration = skin.motion(T.press);
    // En vertical se compone a tamaño real y toda zona tactil mide al menos
    // 48 dp. En horizontal no se toca la maqueta: ver TouchAssist.
    final tall = CanvasSize.tallOf(context);
    final minSide = tall ? minTouchTarget / CanvasSize.scaleOf(context) : 0.0;

    return Semantics(
      button: true,
      enabled: _live,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _live,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _live ? widget.cursor : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => v && _live ? _hover.forward() : _hover.reverse(),
        onFocusChange: (v) => setState(() => _focused = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _press.forward().then((_) => _press.reverse());
            _fire();
            return null;
          }),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (!_live) return;
            if (e.buttons == kSecondaryMouseButton) return;
            // Con el dedo no hay paso por encima que avise: se hunde al
            // instante, y lo que abra se anima al soltar.
            if (isFingerLike(e.kind)) {
              _press.value = 1;
            } else {
              _press.forward();
            }
          },
          onPointerUp: (_) => _press.reverse(),
          onPointerCancel: (_) => _press.reverse(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _fire,
            onSecondaryTap: widget.onSecondaryPressed,
            child: MinTouchSize(
              side: minSide,
              child: AnimatedBuilder(
                animation: Listenable.merge([_hover, _press]),
                builder: (context, _) => widget.builder(
                  context,
                  PressState(
                    skin.reducedMotion ? (_hover.value > 0 ? 1 : 0) : _hover.value,
                    _press.value,
                    _focused,
                    _live,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anillo de foco. Es la unica pista de foco del entorno y siempre es cian.
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.visible,
    required this.radius,
    required this.child,
    this.inset = -4,
  });

  final bool visible;
  final double radius;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return CustomPaint(
      foregroundPainter: visible
          ? _RingPainter(radius: radius, inset: inset, color: skin.accent)
          : null,
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.radius, required this.inset, required this.color});

  final double radius;
  final double inset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(inset);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius - inset));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color.withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius || old.inset != inset || old.color != color;
}
