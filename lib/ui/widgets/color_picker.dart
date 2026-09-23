// Ibasho — selector de color completo, sin limites.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import 'gloss.dart';
import 'pressable.dart';

/// Cuadro de saturacion y brillo con un rail de tono debajo.
///
/// No recorta nada: se puede llegar a cualquier color, tambien a un marron
/// apagado o a un gris. El estado se lleva en HSV para que el tono no se
/// pierda al pasar por el blanco o el negro.
class HsvColorPicker extends StatefulWidget {
  const HsvColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.width = 420,
    this.height = 190,
  });

  final Color value;
  final ValueChanged<Color> onChanged;
  final VoidCallback? onChangeStart;
  final double width;
  final double height;

  @override
  State<HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends State<HsvColorPicker> {
  static const double _rail = 26;
  static const double _knob = 26;

  late HSVColor _hsv = HSVColor.fromColor(widget.value);
  Color _sent = T.glintNone;

  @override
  void didUpdateWidget(HsvColorPicker old) {
    super.didUpdateWidget(old);
    // Solo se resincroniza si el color viene de fuera (el campo HEX, barajar,
    // deshacer). Lo que sale de aqui mismo no debe mover el tono.
    if (widget.value != _sent && widget.value != _hsv.toColor()) {
      _hsv = HSVColor.fromColor(widget.value);
    }
  }

  void _emit(HSVColor next) {
    setState(() => _hsv = next);
    _sent = next.toColor();
    widget.onChanged(_sent);
  }

  void _pickSv(Offset local) {
    final s = (local.dx / widget.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / widget.height).clamp(0.0, 1.0);
    _emit(_hsv.withSaturation(s).withValue(v));
  }

  void _pickHue(double dx) {
    final h = ((dx - _knob / 2) / (widget.width - _knob)).clamp(0.0, 1.0) * 360;
    _emit(_hsv.withHue(h.clamp(0, 359.9)));
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) {
              widget.onChangeStart?.call();
              AudioService.instance.play(Sfx.tick);
              _pickSv(d.localPosition);
            },
            onPanUpdate: (d) => _pickSv(d.localPosition),
            onPanEnd: (_) => AudioService.instance.play(Sfx.tick),
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: CustomPaint(painter: _SvPainter(hueColor)),
                    ),
                  ),
                  // Filo y sombra interior del hueco, sin tapar el color.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: skin.hairline),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [T.shadow, T.glintNone],
                            stops: [0, .08],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _hsv.saturation * widget.width - _knob / 2,
                    top: (1 - _hsv.value) * widget.height - _knob / 2,
                    child: _Knob(color: _hsv.toColor(), size: _knob),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final step = switch (event.logicalKey) {
              LogicalKeyboardKey.arrowLeft => -6.0,
              LogicalKeyboardKey.arrowRight => 6.0,
              _ => 0.0,
            };
            if (step == 0) return KeyEventResult.ignored;
            widget.onChangeStart?.call();
            AudioService.instance.play(Sfx.tick);
            _emit(_hsv.withHue((_hsv.hue + step) % 360));
            return KeyEventResult.handled;
          },
          child: Builder(
            builder: (context) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragDown: (d) {
                  Focus.of(context).requestFocus();
                  widget.onChangeStart?.call();
                  AudioService.instance.play(Sfx.tick);
                  _pickHue(d.localPosition.dx);
                },
                onHorizontalDragUpdate: (d) => _pickHue(d.localPosition.dx),
                onHorizontalDragEnd: (_) => AudioService.instance.play(Sfx.tick),
                child: FocusRing(
                  visible: Focus.of(context).hasFocus,
                  radius: _rail / 2,
                  child: SizedBox(
                    width: widget.width,
                    height: _knob,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned.fill(
                          top: (_knob - _rail) / 2 + 3,
                          bottom: (_knob - _rail) / 2 + 3,
                          left: 2,
                          right: 2,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(_rail / 2),
                            child: const CustomPaint(painter: _HuePainter()),
                          ),
                        ),
                        Positioned(
                          left: _hsv.hue / 360 * (widget.width - _knob),
                          child: _Knob(color: hueColor, size: _knob, ring: skin.accentDeep),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({required this.color, required this.size, this.ring});

  final Color color;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: SizedBox(
          width: size,
          height: size,
          child: GlossSurface(
            radius: size / 2,
            tint: color,
            elevation: 1.4,
            borderWidth: 2.5,
            borderColor: ring ?? T.shellTop,
          ),
        ),
      );
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hue);

  final Color hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [T.shellTop, hue]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.pigmentBlack.withValues(alpha: 0), T.pigmentBlack],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hue != hue;
}

class _HuePainter extends CustomPainter {
  const _HuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h % 360.0, .78, 1).toColor(),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => false;
}
