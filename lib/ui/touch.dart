// Ibasho — zonas tactiles de al menos 48 dp.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lado minimo de una zona tactil, en pixeles logicos de la ventana.
const double minTouchTarget = 48;

/// Punteros que se manejan con el dedo.
///
/// `unknown` entra a proposito: los eventos inyectados por las herramientas de
/// automatizacion (`adb shell input`) llegan sin tipo, y sin esto no se podria
/// probar ni un arrastre en un dispositivo de verdad. Un raton nunca es
/// `unknown`, asi que la rama de escritorio no cambia.
const Set<PointerDeviceKind> fingerKinds = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

bool isFingerLike(PointerDeviceKind kind) => fingerKinds.contains(kind);

/// Algo que el asistente puede activar por un toque que ha caido cerca.
abstract interface class TouchTarget {
  BuildContext get context;

  /// Se puede activar ahora (habilitado y con accion).
  bool get touchLive;

  /// Lo activa como si se hubiera tocado encima.
  void touchFire();
}

/// Asistente de toques para el lienzo horizontal en un movil.
///
/// En horizontal el lienzo de 1280x800 se escala a la mitad en un telefono y
/// un boton de 40 del lienzo mide unos 20 dp. No se puede agrandar sin rehacer
/// la composicion de escritorio, asi que la zona tactil crece sin que se vea:
/// un toque que no cae sobre nada que se pueda tocar se entrega al control mas
/// cercano cuya zona ampliada a 48 dp lo contenga. Si dos compiten, gana el
/// que tenga el borde mas cerca del dedo.
///
/// Solo mira toques (no raton ni lapiz), solo toques cortos y quietos, y
/// nunca roba uno que ya ha caido sobre algo tactil: un campo, un
/// deslizador, un Tama, la barrera de un dialogo.
class TouchAssist extends StatefulWidget {
  const TouchAssist({super.key, required this.child});

  final Widget child;

  static final Set<TouchTarget> _targets = <TouchTarget>{};

  static void register(TouchTarget target) => _targets.add(target);

  static void unregister(TouchTarget target) => _targets.remove(target);

  @override
  State<TouchAssist> createState() => _TouchAssistState();
}

class _Down {
  _Down(this.position, this.at, {required this.claimed});

  final Offset position;
  final Duration at;
  final bool claimed;
  bool moved = false;
}

class _TouchAssistState extends State<TouchAssist> {
  final Map<int, _Down> _downs = <int, _Down>{};

  static const double _slop = 18;
  static const Duration _longest = Duration(milliseconds: 600);

  void _onDown(PointerDownEvent event) {
    if (!isFingerLike(event.kind)) return;
    _downs[event.pointer] = _Down(
      event.position,
      event.timeStamp,
      claimed: _landsOnSomethingTouchable(event.position),
    );
  }

  void _onMove(PointerMoveEvent event) {
    final down = _downs[event.pointer];
    if (down != null && (event.position - down.position).distance > _slop) {
      down.moved = true;
    }
  }

  void _onUp(PointerUpEvent event) {
    final down = _downs.remove(event.pointer);
    if (down == null || down.claimed || down.moved) return;
    if (event.timeStamp - down.at > _longest) return;
    nearestTouchTarget(down.position)?.touchFire();
  }

  bool _landsOnSomethingTouchable(Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, View.of(context).viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is TouchClaim) return true;
      if (target is RenderSemanticsGestureHandler && target.onTap != null) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: (event) => _downs.remove(event.pointer),
        child: widget.child,
      );
}

/// Control al que se entregaria un toque en `position` (coordenadas de la
/// ventana), o `null` si ninguno tiene su zona de 48 dp ahi.
TouchTarget? nearestTouchTarget(Offset position) {
  TouchTarget? best;
  var bestDistance = double.infinity;
  for (final target in TouchAssist._targets) {
    if (!target.touchLive) continue;
    final context = target.context;
    if (!context.mounted) continue;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) continue;
    if (!TickerMode.valuesOf(context).enabled) continue;
    final visible = visibleRectOf(context);
    if (visible == null || visible.isEmpty) continue;
    final zone = Rect.fromCenter(
      center: visible.center,
      width: math.max(visible.width, minTouchTarget),
      height: math.max(visible.height, minTouchTarget),
    );
    if (!zone.contains(position)) continue;
    final dx = math.max(0.0, math.max(visible.left - position.dx, position.dx - visible.right));
    final dy = math.max(0.0, math.max(visible.top - position.dy, position.dy - visible.bottom));
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = target;
    }
  }
  return best;
}

/// Rectangulo de la ventana en el que se ve un widget: el suyo, recortado por
/// cada recorte y cada zona desplazable que tenga por encima. Una ranura de la
/// pagina siguiente o un boton desplazado fuera de la vista no cuentan.
Rect? visibleRectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  var rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
  RenderObject? node = box.parent;
  while (node != null) {
    if (node is RenderBox &&
        node.hasSize &&
        (node is RenderClipRect || node is RenderClipRRect || node is RenderClipPath || node is RenderViewportBase)) {
      final clip = MatrixUtils.transformRect(node.getTransformTo(null), Offset.zero & node.size);
      rect = rect.intersect(clip);
      if (rect.width <= 0 || rect.height <= 0) return Rect.zero;
    }
    node = node.parent;
  }
  return rect;
}

/// Marca que se deja en el arbol para decir "aqui ya hay algo tactil".
class TouchClaim {
  const TouchClaim();
}

/// Envuelve lo que atiende toques por su cuenta (deslizadores, selector de
/// color) para que el asistente no se los quite.
class ClaimTouches extends StatelessWidget {
  const ClaimTouches({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MetaData(
        metaData: const TouchClaim(),
        behavior: HitTestBehavior.translucent,
        child: child,
      );
}

/// Garantiza una caja de al menos `side` por lado sin tocar como se maqueta
/// ni se pinta el hijo: lo centra en la caja, y toda la caja responde al dedo.
class MinTouchSize extends SingleChildRenderObjectWidget {
  const MinTouchSize({super.key, required this.side, super.child});

  final double side;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMinTouchSize(side);

  @override
  void updateRenderObject(BuildContext context, RenderMinTouchSize renderObject) {
    renderObject.side = side;
  }
}

class RenderMinTouchSize extends RenderShiftedBox {
  RenderMinTouchSize(this._side) : super(null);

  double _side;

  set side(double value) {
    if (value == _side) return;
    _side = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size.square(_side));
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(Size(
      math.max(child.size.width, _side),
      math.max(child.size.height, _side),
    ));
    (child.parentData! as BoxParentData).offset = Alignment.center.alongOffset(size - child.size as Offset);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(super.computeMinIntrinsicWidth(height), _side);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(super.computeMaxIntrinsicWidth(height), _side);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width), _side);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width), _side);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child?.getDryLayout(constraints) ?? Size.zero;
    return constraints.constrain(Size(
      math.max(childSize.width, _side),
      math.max(childSize.height, _side),
    ));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final child = this.child;
    if (child != null) {
      final offset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) => child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
