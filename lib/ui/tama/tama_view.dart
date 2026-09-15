// Ibasho — un Tama vivo en pantalla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
import '../../backend/tama.dart';
import '../../theme/skin.dart';
import 'tama_animator.dart';
import 'tama_painter.dart';

/// Ultima posicion conocida del puntero en toda la ventana.
///
/// La alimenta [TamaPointerTracker] desde la raiz, de modo que un Tama puede
/// seguir el raton aunque este lejos de su caja. No notifica: cada Tama la lee
/// en su propio frame.
class TamaPointer {
  TamaPointer._();

  static Offset? position;
  static PointerDeviceKind kind = PointerDeviceKind.mouse;
  static DateTime at = DateTime.fromMillisecondsSinceEpoch(0);

  static void _record(PointerEvent event) {
    position = event.position;
    kind = event.kind;
    at = DateTime.now();
  }
}

/// Escucha el puntero en toda la app sin quedarse con ningun evento.
class TamaPointerTracker extends StatelessWidget {
  const TamaPointerTracker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: TamaPointer._record,
        onPointerDown: TamaPointer._record,
        onPointerMove: TamaPointer._record,
        child: child,
      );
}

/// Mando a distancia de un [TamaView]: lo usan los botones de cuidados.
class TamaViewController {
  _TamaViewState? _state;

  /// Un mimo desde un boton.
  void cuddle() => _state?._cuddle();

  /// Darle una chuche.
  void feed([TamaFood food = TamaFood.cookie]) => _state?._feed(food);

  /// Que diga algo.
  void speak([ChirpKind kind = ChirpKind.hello]) => _state?._speak(kind);
}

/// Un Tama vivo: respira, parpadea, mira y reacciona.
///
/// Con movimiento reducido no hay ticker: se pinta la pose de reposo, con la
/// cara del humor que tenga, y nada mas se mueve.
class TamaView extends StatefulWidget {
  const TamaView({
    super.key,
    required this.look,
    required this.personality,
    required this.name,
    this.voice = const TamaVoice(),
    this.seed = 0,
    this.joy = .4,
    this.size = 120,
    this.interactive = true,
    this.pettable = false,
    this.shadow = true,
    this.controller,
    this.onTap,
    this.onPetted,
    this.semanticLabel,
  });

  final TamaLook look;
  final TamaPersonality personality;
  final String name;
  final TamaVoice voice;

  /// Semilla del azar de sus gestos. Con el id del Tama, cada uno tiene los
  /// suyos y dos vistas del mismo no van al unisono por casualidad.
  final int seed;

  /// Humor de -1 a 1.
  final double joy;

  final double size;

  /// Reacciona al pasar el raton y al tocarlo.
  final bool interactive;

  /// Se deja mimar frotandolo.
  final bool pettable;

  final bool shadow;
  final TamaViewController? controller;

  /// Toque. Si no hay, tocarlo le hace graznar y dar un salto.
  final VoidCallback? onTap;

  /// Se ha terminado una tanda de mimos frotandolo.
  final VoidCallback? onPetted;

  final String? semanticLabel;

  @override
  State<TamaView> createState() => _TamaViewState();
}

class _TamaViewState extends State<TamaView> with SingleTickerProviderStateMixin {
  late TamaAnimator _animator =
      TamaAnimator(personality: widget.personality, seed: widget.seed);
  final ValueNotifier<TamaPose> _pose = ValueNotifier<TamaPose>(TamaPose.rest);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  bool _reduced = false;
  double _rubbed = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _animator.joy = widget.joy;
    _pose.value = TamaPose(joy: widget.joy);
  }

  @override
  void didUpdateWidget(TamaView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.seed != widget.seed) {
      _animator = TamaAnimator(personality: widget.personality, seed: widget.seed);
    }
    _animator
      ..personality = widget.personality
      ..joy = widget.joy;
    if (_reduced) _pose.value = TamaPose(joy: widget.joy);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final skin = IbashoSkin.of(context);
    // Solo se anima el Tama de la ruta que esta delante: el del panel superior
    // no gasta frames debajo de un canal abierto.
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    _reduced = skin.reducedMotion;
    if (_reduced || !current) {
      if (_ticker.isActive) _ticker.stop();
      if (_reduced) _pose.value = TamaPose(joy: widget.joy);
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _ticker.dispose();
    _pose.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;

    // Un Tama que no se ve (desplazado fuera de la rejilla) no repinta: con
    // 99 Tamas en el canal solo trabajan los que estan en pantalla.
    final view = View.of(context);
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final onScreen = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    if (!screen.overlaps(onScreen)) return;

    final global = TamaPointer.position;
    if (global != null) {
      final local = box.globalToLocal(global);
      // La cara esta un poco por encima del centro de la caja.
      final face = Offset(box.size.width / 2, box.size.height * .56);
      final unit = box.size.shortestSide / 2;
      final mouse = TamaPointer.kind == PointerDeviceKind.mouse;
      final fresh = mouse ||
          DateTime.now().difference(TamaPointer.at) < const Duration(seconds: 3);
      _animator.pointAt(fresh ? (local - face) / unit : null, mouse: mouse);
    }
    _pose.value = _animator.tick(dt);
  }

  Future<void> _speak(ChirpKind kind) async {
    final seconds = await AudioService.instance.chirp(
      name: widget.name,
      voice: widget.voice,
      kind: kind,
    );
    if (mounted && seconds > 0) _animator.speak(seconds);
  }

  void _poke() {
    _animator.poke();
    unawaited(_speak(widget.joy < -.3 ? ChirpKind.sigh : ChirpKind.hello));
  }

  void _cuddle() {
    _animator.cuddle();
    unawaited(_speak(ChirpKind.happy));
  }

  void _feed(TamaFood food) {
    _animator.feed(food);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) unawaited(_speak(ChirpKind.munch));
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child = SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: TamaPainter(
            look: widget.look,
            live: _pose,
            shadow: widget.shadow,
          ),
        ),
      ),
    );

    if (widget.pettable) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _rubbed = 0;
          _animator.pet(active: true);
        },
        onPanUpdate: (d) {
          _rubbed += d.delta.distance;
          _animator.pet(active: true, rub: d.delta.dx);
        },
        onPanEnd: (_) {
          _animator.pet(active: false);
          // Un roce de nada no cuenta como mimo.
          if (_rubbed > widget.size * .6) {
            unawaited(_speak(ChirpKind.happy));
            widget.onPetted?.call();
          }
        },
        child: child,
      );
    }

    if (widget.interactive) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _animator.hovered = true,
        onExit: (_) => _animator.hovered = false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _poke();
            widget.onTap?.call();
          },
          child: child,
        ),
      );
    }

    return Semantics(
      label: widget.semanticLabel ?? widget.name,
      image: true,
      child: child,
    );
  }
}
