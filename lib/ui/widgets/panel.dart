// Ibasho — pantallas, tarjetas y desplazamiento.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';

/// Una de las dos pantallas encastradas en el bisel.
class ScreenPanel extends StatelessWidget {
  const ScreenPanel({
    super.key,
    required this.child,
    this.radius = T.panelRadius,
    this.clip = true,
  });

  final Widget child;
  final double radius;
  final bool clip;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ScreenPainter(radius),
        child: clip
            ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
            : child,
      );
}

class _ScreenPainter extends CustomPainter {
  _ScreenPainter(this.radius);

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
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.shellTop, T.shellBottom],
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
          colors: const [T.glintPanel, T.glintNone],
          stops: const [0, .40],
        ).createShader(rect),
    );
    canvas.restore();

    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = T.hairline,
    );
  }

  @override
  bool shouldRepaint(_ScreenPainter old) => old.radius != radius;
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
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [T.onAccent, T.cardBottom],
                ),
                border: Border.all(color: T.hairline),
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
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
                  ),
                ),
                const SizedBox(width: 24),
                control,
              ],
            ),
          ),
          if (divider) const Hairline(),
        ],
      );
}

/// Linea de 1 px. La unica separacion que usa el entorno.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: indent),
        child: const SizedBox(
          height: 1,
          child: DecoratedBox(decoration: BoxDecoration(color: T.hairline)),
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
      };
}
