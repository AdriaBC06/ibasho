// Ibasho — el lienzo: horizontal escalado o vertical a tamaño real.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Todo el entorno se dibuja sobre un lienzo que tiene dos formas, y la forma
/// la decide la proporcion de la ventana, no la plataforma.
///
/// **Horizontal** (la ventana es mas ancha que alta): lienzo virtual de **800
/// de alto** que se escala para llenar la ventana. El ancho se adapta a la
/// forma de la ventana: 1280 en 16:10, 1422 en 16:9, hasta 1920 en
/// ultrapanoramica. Asi las pantallas habituales se llenan sin bandas y la
/// estetica no se rompe, porque la altura —que es lo que fija los tamanos de
/// paneles, iconos y texto— no cambia nunca. Solo por debajo de 16:10 o por
/// encima del tope aparecen bandas. Es el lienzo de escritorio y el del movil
/// girado.
///
/// **Vertical** (mas alta que ancha): no hay lienzo fijo. Cada unidad es un
/// pixel logico de verdad y las pantallas se recolocan para el tamaño que
/// haya, asi que un movil en vertical, una tableta o una ventana estrecha de
/// escritorio usan todos la misma composicion a su medida. Por debajo de
/// 360x640 se escala hacia abajo para que nada se desborde.
///
/// El arbol de widgets es el mismo en las dos formas: girar el movil no
/// desmonta el navegador, ni las rutas abiertas, ni el estado de nadie.
class VirtualCanvas extends StatelessWidget {
  const VirtualCanvas({super.key, required this.child});

  final Widget child;

  static const double minWidth = 1280;
  static const double maxWidth = 1920;

  /// Tamaño minimo del lienzo vertical. Por debajo se escala.
  static const Size minTall = Size(360, 640);

  /// Ancho virtual del lienzo horizontal para una ventana de este tamano.
  static double widthFor(Size window) {
    if (window.isEmpty) return minWidth;
    final width = T.canvas.height * window.width / window.height;
    return width.clamp(minWidth, maxWidth);
  }

  /// La ventana es vertical: se compone a tamaño real.
  static bool isTall(Size window) => !window.isEmpty && window.width < window.height;

  /// Tamaño del lienzo para una ventana (ya descontadas las zonas seguras).
  static Size sizeFor(Size window) {
    if (!isTall(window)) return Size(widthFor(window), T.canvas.height);
    final shrink = [
      1.0,
      window.width / minTall.width,
      window.height / minTall.height,
    ].reduce((a, b) => a < b ? a : b);
    return window / shrink;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Muescas, esquinas y barra de gestos: el lienzo se queda dentro. En
    // escritorio son cero.
    final safe = media.padding;

    return ColoredBox(
      color: T.letterbox,
      child: _SafeBezel(
        insets: safe,
        child: Padding(
          padding: safe,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final window = constraints.biggest;
              final tall = isTall(window);
              final size = sizeFor(window);
              final scale = window.isEmpty
                  ? 1.0
                  : [window.width / size.width, window.height / size.height]
                      .reduce((a, b) => a < b ? a : b);

              return _KeyboardLift(
                keyboard: (media.viewInsets.bottom - safe.bottom).clamp(0.0, double.infinity),
                // SizedBox.expand y no Center: con restricciones sueltas
                // FittedBox se queda al tamano del hijo y solo escala hacia
                // abajo.
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox.fromSize(
                      size: size,
                      child: MediaQuery(
                        // Dentro del lienzo no hay zonas seguras ni teclado
                        // (ya se han resuelto fuera) y la escala de texto del
                        // sistema no se aplica: el lienzo tiene medidas fijas y
                        // un texto al 200 % lo reventaria. Ver README.
                        data: media.copyWith(
                          size: size,
                          padding: EdgeInsets.zero,
                          viewPadding: EdgeInsets.zero,
                          viewInsets: EdgeInsets.zero,
                          textScaler: TextScaler.noScaling,
                        ),
                        child: CanvasSize(size: size, tall: tall, scale: scale, child: child),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Tamaño y forma del lienzo en curso, para quien lo necesite: el entorno para
/// ensanchar sus paneles, las pantallas para recolocarse en vertical y la
/// apertura de canal para saber a donde crecer.
class CanvasSize extends InheritedWidget {
  const CanvasSize({
    super.key,
    required this.size,
    this.tall = false,
    this.scale = 1,
    required super.child,
  });

  final Size size;

  /// Composicion vertical, a tamaño real.
  final bool tall;

  /// Pixeles logicos de la ventana por unidad del lienzo. En horizontal, en
  /// un movil, ronda 0,5: un boton de 48 del lienzo mide 24 dp de verdad.
  final double scale;

  static Size of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasSize>()?.size ?? T.canvas;

  static bool tallOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasSize>()?.tall ?? false;

  static double scaleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasSize>()?.scale ?? 1;

  @override
  bool updateShouldNotify(CanvasSize old) =>
      old.size != size || old.tall != tall || old.scale != scale;
}

/// Rectangulo que ocupa un widget, en coordenadas del overlay del Navigator
/// que lo contiene.
///
/// Es el sistema en el que se pinta una ruta, asi que es justo lo que necesita
/// la animacion de apertura para saber desde donde tiene que crecer. Como el
/// Navigator vive dentro del lienzo virtual, estas coordenadas ya son las del
/// lienzo, sin importar el tamano de la ventana.
Rect? rectInNavigator(BuildContext context, GlobalKey key) {
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  final target = key.currentContext?.findRenderObject();
  if (overlay is! RenderBox || target is! RenderBox) return null;
  if (!overlay.hasSize || !target.hasSize) return null;
  return target.localToGlobal(Offset.zero, ancestor: overlay) & target.size;
}

/// Lo que queda fuera del lienzo por las zonas seguras se pinta con el mismo
/// metal del bisel, para que la muesca y la barra de gestos parezcan el marco
/// de la consola y no una banda negra. Sin zonas seguras no pinta nada.
class _SafeBezel extends StatelessWidget {
  const _SafeBezel({required this.insets, required this.child});

  final EdgeInsets insets;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: insets == EdgeInsets.zero
            ? const BoxDecoration()
            : const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [T.bezelTop, T.bezelBottom],
                  stops: [0, .92],
                ),
              ),
        child: child,
      );
}

/// Sube el lienzo entero lo justo para que el campo de texto con foco no
/// quede debajo del teclado en pantalla.
///
/// No encoge nada ni recoloca: el lienzo tiene medidas fijas, asi que se
/// desplaza como una pieza y vuelve a su sitio al cerrarse el teclado. En
/// escritorio no hay teclado en pantalla y esto no hace nada.
class _KeyboardLift extends StatefulWidget {
  const _KeyboardLift({required this.keyboard, required this.child});

  /// Alto del teclado en pantalla que tapa el lienzo, en pixeles de ventana.
  final double keyboard;

  final Widget child;

  @override
  State<_KeyboardLift> createState() => _KeyboardLiftState();
}

class _KeyboardLiftState extends State<_KeyboardLift> {
  final GlobalKey _content = GlobalKey(debugLabel: 'canvas.content');
  double _lift = 0;
  bool _scheduled = false;

  static const double _margin = 16;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_schedule);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_schedule);
    super.dispose();
  }

  @override
  void didUpdateWidget(_KeyboardLift old) {
    super.didUpdateWidget(old);
    if (old.keyboard != widget.keyboard) _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    if (widget.keyboard <= 0 && _lift == 0) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final next = _measure();
      if ((next - _lift).abs() > .5) setState(() => _lift = next);
    });
  }

  double _measure() {
    if (widget.keyboard <= 0) return 0;
    final content = _content.currentContext?.findRenderObject();
    final focus = FocusManager.instance.primaryFocus?.context;
    if (content is! RenderBox || !content.hasSize || focus == null) return 0;
    // Solo los campos de texto abren teclado.
    if (focus.findAncestorStateOfType<EditableTextState>() == null) return 0;
    final field = focus.findRenderObject();
    if (field is! RenderBox || !field.attached || !field.hasSize) return 0;

    final rect = MatrixUtils.transformRect(
      field.getTransformTo(content),
      Offset.zero & field.size,
    );
    final visibleBottom = content.size.height - widget.keyboard;
    final overlap = rect.bottom + _margin * 2 - visibleBottom;
    if (overlap <= 0) return 0;
    // Nunca tanto que el campo se salga por arriba.
    return overlap.clamp(0.0, (rect.top - _margin).clamp(0.0, double.infinity));
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _lift),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, lift, child) => Transform.translate(
          offset: Offset(0, -lift),
          child: child,
        ),
        child: KeyedSubtree(key: _content, child: widget.child),
      );
}
