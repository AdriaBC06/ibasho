// Ibasho — controles del entorno. Ninguno viene de Material.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../layout.dart';
import 'glyphs.dart';
import 'gloss.dart';
import 'pressable.dart';

enum ButtonTone {
  /// Plastico blanco. Lo normal.
  plain,

  /// Tenido de acento. Uno por pantalla, el que continua la tarea.
  accent,

  /// Sin superficie: solo texto. Para acciones secundarias.
  quiet,

  /// Ambar. Para lo que no tiene vuelta atras.
  warn,
}

/// Boton del entorno.
class IbashoButton extends StatelessWidget {
  const IbashoButton({
    super.key,
    required this.label,
    this.onPressed,
    this.glyph,
    this.tone = ButtonTone.plain,
    this.height = 48,
    this.expand = false,
    this.cue = Sfx.tick,
    this.autofocus = false,
    this.minWidth = 0,
  });

  final String label;
  final VoidCallback? onPressed;
  final Glyph? glyph;
  final ButtonTone tone;
  final double height;
  final bool expand;
  final Sfx? cue;
  final bool autofocus;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tint = switch (tone) {
      ButtonTone.accent => skin.accent,
      ButtonTone.warn => T.warn,
      _ => null,
    };
    final quiet = tone == ButtonTone.quiet;
    // En vertical se toca con el dedo: ningun boton baja de 48.
    final height = Layout.of(context).tall ? math.max(this.height, 48.0) : this.height;

    return Pressable(
      onPressed: onPressed,
      cue: cue,
      autofocus: autofocus,
      semanticLabel: label,
      builder: (context, state) {
        final enabled = state.enabled;
        final lift = quiet ? 0.0 : 2.0 * state.hover - 2.0 * state.press;
        final ink = quiet
            ? Color.lerp(T.inkSoft, skin.accentDeep, state.hover)!
            : (tint == null ? T.ink : T.onAccent);

        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (glyph != null) ...[
              GlyphIcon(glyph!, size: height * .42, color: enabled ? ink : T.inkSoft),
              SizedBox(width: label.isEmpty ? 0 : height * .18),
            ],
            if (label.isNotEmpty)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body.copyWith(
                    fontSize: height * .32,
                    fontWeight: FontWeight.w500,
                    color: enabled ? ink : T.inkSoft,
                    height: 1.1,
                  ),
                ),
              ),
          ],
        );

        return Transform.translate(
          offset: Offset(0, -lift),
          child: FocusRing(
            visible: state.focus,
            radius: T.buttonRadius,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: expand ? 0 : minWidth,
                minHeight: height,
                maxHeight: height,
              ),
              child: quiet
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: height * .34),
                      child: Center(child: content),
                    )
                  : GlossSurface(
                      radius: T.buttonRadius,
                      tint: enabled ? tint : null,
                      elevation: enabled ? 1 + state.hover * .7 : .35,
                      specular: enabled ? 1 - state.press * .45 : .3,
                      borderColor: tint == null
                          ? T.hairline
                          : Color.lerp(tint, T.dusk, .34)!,
                      sink: state.press * 1.6,
                      padding: EdgeInsets.symmetric(horizontal: height * .46),
                      child: Center(child: content),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Boton circular de icono: flechas de paginacion, ampliar, cerrar.
class IconPill extends StatelessWidget {
  const IconPill({
    super.key,
    required this.glyph,
    this.onPressed,
    this.diameter = 42,
    this.tone = ButtonTone.plain,
    this.cue = Sfx.tick,
    this.semanticLabel,
  });

  final Glyph glyph;
  final VoidCallback? onPressed;
  final double diameter;
  final ButtonTone tone;
  final Sfx? cue;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tint = tone == ButtonTone.accent ? skin.accent : null;
    final diameter = Layout.of(context).tall ? math.max(this.diameter, 44.0) : this.diameter;

    return Pressable(
      onPressed: onPressed,
      cue: cue,
      semanticLabel: semanticLabel,
      // Los botones redondos del carril no se elevan al pasar el raton: solo
      // cambian de color y se hunden un poco al pulsarlos.
      builder: (context, state) => Transform.translate(
        offset: Offset(0, 1.5 * state.press),
        child: FocusRing(
          visible: state.focus,
          radius: diameter / 2,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: GlossSurface(
              radius: diameter / 2,
              tint: state.enabled ? tint : null,
              elevation: state.enabled ? 1 - state.press * .5 : .3,
              specular: state.enabled ? 1 - state.press * .4 : .25,
              sink: state.press * 1.4,
              child: Center(
                child: GlyphIcon(
                  glyph,
                  size: diameter * .48,
                  color: !state.enabled
                      ? T.inkSoft.withValues(alpha: .45)
                      : tint != null
                          ? T.onAccent
                          : Color.lerp(T.ink, skin.accentDeep, state.hover)!,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interruptor de pastilla.
class IbashoToggle extends StatelessWidget {
  const IbashoToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 62,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final height = width * .52;
    final knob = height - 8;

    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: null,
      builder: (context, state) => FocusRing(
        visible: state.focus,
        radius: height / 2,
        child: SizedBox(
          width: width,
          height: height,
          child: GlossSurface(
            radius: height / 2,
            recessed: true,
            tint: value ? skin.accent : null,
            child: AnimatedAlign(
              duration: skin.motion(const Duration(milliseconds: 220)),
              curve: skin.curve(Curves.easeOutBack),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: knob,
                  height: knob,
                  child: GlossSurface(
                    radius: knob / 2,
                    elevation: 1.1,
                    borderColor: value ? skin.accentDeep : T.hairline,
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

/// Deslizador del entorno: raíl de cristal hundido y pomo de plastico con su
/// brillo.
///
/// Suena un tick corto al tocarlo, al soltarlo y, si tiene `ticks`, cada vez
/// que el valor cruza uno de esos pasos mientras se arrastra.
class IbashoSlider extends StatefulWidget {
  const IbashoSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 280,
    this.ticks = 0,
    this.onChangeStart,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double width;

  /// Pasos audibles a lo largo del recorrido. 0: solo al tocar y al soltar.
  final int ticks;

  /// Empieza un gesto: sirve para apuntar un paso de deshacer por arrastre y
  /// no uno por pixel.
  final VoidCallback? onChangeStart;

  final String? semanticLabel;

  @override
  State<IbashoSlider> createState() => _IbashoSliderState();
}

class _IbashoSliderState extends State<IbashoSlider> {
  static const double _track = 16;
  static const double _knob = 28;

  /// Ancho de verdad: `double.infinity` lo resuelve la caja que lo contiene.
  double _width = 0;

  double _fractionFor(double dx) =>
      ((dx - _knob / 2) / (_width - _knob)).clamp(0.0, 1.0);

  int _bucket(double v) => widget.ticks <= 0 ? 0 : (v * widget.ticks).round();

  void _emit(double fraction, {bool tick = true}) {
    if ((fraction - widget.value).abs() < .001) return;
    final crossed = widget.ticks > 0 && _bucket(fraction) != _bucket(widget.value);
    if (tick || crossed) AudioService.instance.play(Sfx.tick);
    widget.onChanged(fraction);
  }

  @override
  Widget build(BuildContext context) => widget.width.isFinite
      ? _build(context, widget.width)
      : LayoutBuilder(builder: (context, box) => _build(context, box.maxWidth));

  Widget _build(BuildContext context, double width) {
    final skin = IbashoSkin.of(context);
    final value = widget.value.clamp(0.0, 1.0);
    final grip = Layout.of(context).tall ? 10.0 : 0.0;
    _width = width;

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: '${(value * 100).round()}',
      child: Focus(
        canRequestFocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onChangeStart?.call();
            _emit((value - .05).clamp(0.0, 1.0));
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onChangeStart?.call();
            _emit((value + .05).clamp(0.0, 1.0));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              // Con el dedo la zona de agarre es mas alta que el raíl, sin que
              // el deslizador se vea distinto.
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: grip),
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  Focus.of(context).requestFocus();
                  widget.onChangeStart?.call();
                  _emit(_fractionFor(d.localPosition.dx));
                },
                onHorizontalDragStart: (_) => widget.onChangeStart?.call(),
                onHorizontalDragUpdate: (d) =>
                    _emit(_fractionFor(d.localPosition.dx), tick: false),
                onHorizontalDragEnd: (_) => AudioService.instance.play(Sfx.tick),
                child: FocusRing(
                  visible: focused,
                  radius: _knob / 2,
                  inset: -2,
                  child: SizedBox(
                    width: width,
                    height: _knob,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: SizedBox(
                            height: _track,
                            child: GlossSurface(
                              radius: _track / 2,
                              recessed: true,
                              // El cristal: un reflejo fino en la mitad de abajo
                              // del raíl hundido.
                              child: Align(
                                alignment: const Alignment(0, .55),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 9),
                                  child: SizedBox(
                                    height: 2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: T.glintStrong,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3.5),
                          child: SizedBox(
                            height: _track - 5,
                            width: math.max(
                              _track - 5,
                              (width - 7) * value,
                            ),
                            child: GlossSurface(
                              radius: (_track - 5) / 2,
                              tint: skin.accent,
                              elevation: 0,
                              borderColor: skin.accentDeep,
                              specular: .7,
                            ),
                          ),
                        ),
                        Positioned(
                          left: (width - _knob) * value,
                          child: SizedBox(
                            width: _knob,
                            height: _knob,
                            child: GlossSurface(
                              radius: _knob / 2,
                              elevation: 1.2,
                              borderColor: skin.accentDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Selector segmentado: idioma, color de acento, pares de opciones.
class IbashoSegmented<V> extends StatelessWidget {
  const IbashoSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.height = 44,
  });

  final List<(V value, String label)> options;
  final V value;
  final ValueChanged<V> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => _build(context, box.maxWidth),
      );

  Widget _build(BuildContext context, double maxWidth) {
    final skin = IbashoSkin.of(context);
    // En vertical las opciones se reparten el ancho disponible; si quien lo
    // contiene no acota el ancho (una fila, por ejemplo), se queda a su
    // tamaño natural.
    final tall = Layout.of(context).tall && maxWidth.isFinite;
    final height = tall ? math.max(this.height, 56.0) : this.height;

    return SizedBox(
      height: height,
      width: tall ? maxWidth : null,
      child: GlossSurface(
        radius: height / 2,
        recessed: true,
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final (optionValue, label) in options)
              _segment(
                tall,
                Pressable(
                onPressed: optionValue == value ? null : () => onChanged(optionValue),
                builder: (context, state) {
                  final selected = optionValue == value;
                  final text = FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Ty.body.copyWith(
                        color: selected
                            ? T.onAccent
                            : Color.lerp(T.inkSoft, skin.accentDeep, state.hover)!,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  );
                  return AnimatedContainer(
                    duration: skin.motion(T.hover),
                    curve: skin.curve(Curves.easeOut),
                    constraints: BoxConstraints(minWidth: tall ? 0 : height * 2.1),
                    height: height - 8,
                    child: selected
                        ? GlossSurface(
                            radius: (height - 8) / 2,
                            tint: skin.accent,
                            elevation: .9,
                            borderColor: skin.accentDeep,
                            padding: EdgeInsets.symmetric(horizontal: tall ? 8 : 14),
                            child: Center(child: text),
                          )
                        : Padding(
                            padding: EdgeInsets.symmetric(horizontal: tall ? 8 : 14),
                            child: Center(child: text),
                          ),
                  );
                },
              ),
              ),
          ],
        ),
      ),
    );
  }

  /// En vertical las opciones se reparten el ancho por igual; en horizontal
  /// cada una ocupa lo suyo.
  Widget _segment(bool tall, Widget child) => tall ? Expanded(child: child) : child;
}

/// Muestra de color, para elegir el acento.
class ColorChip extends StatelessWidget {
  const ColorChip({
    super.key,
    required this.color,
    required this.selected,
    required this.onPressed,
    this.diameter = 38,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final diameter = Layout.of(context).tall ? math.max(this.diameter, 44.0) : this.diameter;
    return Pressable(
        onPressed: onPressed,
        builder: (context, state) => FocusRing(
          visible: state.focus,
          radius: diameter / 2,
          child: Transform.translate(
            offset: Offset(0, -2 * state.hover + 1.5 * state.press),
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: GlossSurface(
                radius: diameter / 2,
                tint: color,
                elevation: selected ? 1.6 : .8,
                borderWidth: selected ? 2.5 : 1,
                borderColor: selected
                    ? Color.lerp(color, T.dusk, .45)!
                    : T.hairline,
                child: selected
                    ? Center(
                        child: GlyphIcon(
                          Glyph.check,
                          size: diameter * .5,
                          color: T.onAccent,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
  }
}
