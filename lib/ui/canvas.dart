// Ibasho — lienzo virtual de 800 de alto y ancho adaptable.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Todo el entorno se dibuja sobre un lienzo virtual de **800 de alto** que se
/// escala para llenar la ventana.
///
/// El ancho se adapta a la forma de la ventana: 1280 en 16:10, 1422 en 16:9,
/// hasta 1920 en ultrapanoramica. Asi las pantallas habituales se llenan sin
/// bandas y la estetica no se rompe, porque la altura —que es lo que fija los
/// tamanos de paneles, iconos y texto— no cambia nunca. Solo por debajo de
/// 16:10 o por encima del tope aparecen bandas.
class VirtualCanvas extends StatelessWidget {
  const VirtualCanvas({super.key, required this.child});

  final Widget child;

  static const double minWidth = 1280;
  static const double maxWidth = 1920;

  /// Ancho virtual del lienzo para una ventana de este tamano.
  static double widthFor(Size window) {
    if (window.isEmpty) return minWidth;
    final width = T.canvas.height * window.width / window.height;
    return width.clamp(minWidth, maxWidth);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: T.letterbox,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(
              widthFor(constraints.biggest),
              T.canvas.height,
            );
            // SizedBox.expand y no Center: con restricciones sueltas
            // FittedBox se queda al tamano del hijo y solo escala hacia abajo.
            return SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox.fromSize(
                  size: size,
                  child: CanvasSize(size: size, child: child),
                ),
              ),
            );
          },
        ),
      );
}

/// Tamano del lienzo virtual en curso, para quien lo necesite: el entorno para
/// ensanchar sus paneles y la apertura de canal para saber a donde crecer.
class CanvasSize extends InheritedWidget {
  const CanvasSize({super.key, required this.size, required super.child});

  final Size size;

  static Size of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasSize>()?.size ?? T.canvas;

  @override
  bool updateShouldNotify(CanvasSize old) => old.size != size;
}

/// Rectangulo que ocupa un widget, en coordenadas del overlay del Navigator
/// que lo contiene.
///
/// Es el sistema en el que se pinta una ruta, asi que es justo lo que necesita
/// la animacion de apertura para saber desde donde tiene que crecer. Como el
/// Navigator vive dentro del lienzo virtual, estas coordenadas ya son las del
/// lienzo de 1280x800, sin importar el tamano de la ventana.
Rect? rectInNavigator(BuildContext context, GlobalKey key) {
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  final target = key.currentContext?.findRenderObject();
  if (overlay is! RenderBox || target is! RenderBox) return null;
  if (!overlay.hasSize || !target.hasSize) return null;
  return target.localToGlobal(Offset.zero, ancestor: overlay) & target.size;
}
