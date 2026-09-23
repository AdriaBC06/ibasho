// Ibasho — pantallas, tarjetas y desplazamiento.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/menu_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../layout.dart';
import 'theme_ornament.dart' show StarRim;

/// Una de las dos pantallas encastradas en el bisel.
class ScreenPanel extends StatelessWidget {
  const ScreenPanel({
    super.key,
    required this.child,
    this.radius = T.panelRadius,
    this.clip = true,
    this.glass = false,
  });

  final Widget child;
  final double radius;
  final bool clip;

  /// Las pantallas del menu de inicio: con un tema puesto son de cristal
  /// esmerilado ([Surfaces.glass]) y dejan ver el fondo, desenfocado.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final surfaces = IbashoSkin.of(context).surfaces;
    final opacity = glass ? surfaces.glass : 1.0;
    final panel = CustomPaint(
      painter: _ScreenPainter(radius, surfaces, opacity),
      child: clip
          ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
          : child,
    );
    if (opacity >= 1) return panel;
    final blur = ((opacity - .06) * 28).clamp(0.0, 14.0);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              // Cuanto mas transparente, menos esmerilado: al fondo del
              // deslizador el cristal es limpio, no traslucido.
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        panel,
        // La ∞ ademas lleva un cometa de luz dando la vuelta al marco.
        if (surfaces.ornament == Ornament.stars)
          Positioned.fill(child: StarRim(radius: radius)),
      ],
    );
  }
}

class _ScreenPainter extends CustomPainter {
  _ScreenPainter(this.radius, this.surfaces, this.opacity);

  final Surfaces surfaces;

  /// Opacidad del cuerpo: 1 es plastico, menos es cristal.
  final double opacity;

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // El rebaje del bisel alrededor de la pantalla.
    canvas.drawRRect(
      rrect.inflate(3),
      Paint()
        ..color = T.bezelRecess
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      rrect.inflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = T.glintRim,
    );

    // Cuerpo del panel.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surfaces.shellTop.withValues(alpha: opacity),
            surfaces.shellBottom.withValues(alpha: opacity),
          ],
        ).createShader(rect),
    );

    // Brillo especular. En una superficie tan ancha se queda en una banda muy
    // tenue, si no parece un boton gigante.
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (surfaces.dark ? T.glintSoft : T.glintPanel).withValues(
              alpha: (surfaces.dark ? T.glintSoft : T.glintPanel).a *
                  (opacity * 2).clamp(0.0, 1.0),
            ),
            T.glintNone,
          ],
          stops: const [0, .40],
        ).createShader(rect),
    );
    canvas.restore();

    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = surfaces.hairline,
    );
  }

  @override
  bool shouldRepaint(_ScreenPainter old) =>
      old.radius != radius || old.surfaces != surfaces || old.opacity != opacity;
}

/// Bloque de contenido dentro de un canal.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(26, 22, 26, 24),
    this.width,
  });

  final String? title;
  final Widget child;
  final EdgeInsets padding;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 10),
                child: Text(title!, style: Ty.label.copyWith(fontSize: 14)),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [IbashoSkin.of(context).shellTop, IbashoSkin.of(context).cardBottom],
                ),
                border: Border.all(color: IbashoSkin.of(context).hairline),
                boxShadow: const [
                  BoxShadow(color: T.shadow, blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      );
}

/// Una fila de ajuste: etiqueta a la izquierda, control a la derecha.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.hint,
    required this.control,
    this.divider = true,
  });

  final String label;
  final String? hint;
  final Widget control;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final tall = Layout.of(context).tall;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Ty.body),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint!, style: Ty.caption),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          // En un lienzo estrecho la etiqueta no comparte fila con el control:
          // se pone encima y el control ocupa el ancho entero.
          child: tall
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    text,
                    const SizedBox(height: 10),
                    control,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 24),
                    control,
                  ],
                ),
        ),
        if (divider) const Hairline(),
      ],
    );
  }
}

/// Linea de 1 px. La unica separacion que usa el entorno.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: indent),
        child: SizedBox(
          height: 1,
          child: DecoratedBox(decoration: BoxDecoration(color: IbashoSkin.of(context).hairline)),
        ),
      );
}

/// Desplazamiento vertical con barra propia.
class IbashoScroll extends StatefulWidget {
  const IbashoScroll({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.controller,
  });

  final Widget child;
  final EdgeInsets padding;
  final ScrollController? controller;

  @override
  State<IbashoScroll> createState() => _IbashoScrollState();
}

class _IbashoScrollState extends State<IbashoScroll> {
  ScrollController? _owned;

  ScrollController get _controller =>
      widget.controller ?? (_owned ??= ScrollController());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return ScrollConfiguration(
      behavior: const _NoChromeScrollBehavior(),
      child: RawScrollbar(
        controller: _controller,
        thumbColor: skin.accent.withValues(alpha: .75),
        radius: const Radius.circular(5),
        thickness: 7,
        thumbVisibility: false,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          controller: _controller,
          padding: widget.padding,
          physics: const ClampingScrollPhysics(),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Ni destello de sobredesplazamiento ni barra de Material.
class _NoChromeScrollBehavior extends ScrollBehavior {
  const _NoChromeScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, _) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, _) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        // Los eventos inyectados llegan sin tipo (ver fingerKinds).
        PointerDeviceKind.unknown,
      };
}
