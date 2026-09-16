// Ibasho — medidas que cambian entre el lienzo horizontal y el vertical.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'canvas.dart';
import 'touch.dart';

/// Las medidas de la composicion en curso.
///
/// No hay dos arboles de widgets: cada pantalla se maqueta una sola vez y pide
/// aqui los numeros que cambian. En horizontal son los de siempre —el lienzo
/// de 1280x800 no se mueve ni un pixel— y en vertical son los de una pantalla
/// estrecha que se toca con el dedo.
class Layout {
  Layout._(this.size, this.tall, this.scale);

  factory Layout.of(BuildContext context) => Layout._(
        CanvasSize.of(context),
        CanvasSize.tallOf(context),
        CanvasSize.scaleOf(context),
      );

  final Size size;

  /// Composicion vertical, en pixeles logicos de verdad.
  final bool tall;

  /// Pixeles de la ventana por unidad del lienzo.
  final double scale;

  double get width => size.width;

  double get height => size.height;

  /// Margen lateral de una pantalla. En vertical hay poco ancho, pero el aire
  /// de los lados es parte de la estetica: no se sacrifica.
  double get gutter => tall ? 22 : 40;

  /// Separacion entre bloques.
  double get gap => tall ? 16 : 22;

  /// Lado de un boton redondo de carril.
  double get pill => tall ? 48 : 36;

  /// Alto de un boton con texto.
  double get button => tall ? 48 : 46;

  /// Alto de la cabecera de un canal.
  double get header => tall ? 68 : 92;

  /// Ancho maximo de una columna de contenido: en una tableta en vertical el
  /// texto no debe cruzar la pantalla entera.
  double get column => tall ? (width < 620 ? width - gutter * 2 : 600) : width;

  /// Lo que mide en unidades del lienzo algo que debe tener 48 dp de verdad.
  double get touch => minTouchTarget / scale;

  /// `a` en horizontal, `b` en vertical.
  T pick<T>(T a, T b) => tall ? b : a;
}

/// Arrastre horizontal para pasar de pagina, solo con el dedo.
///
/// Se suma a las flechas, que siguen estando. Con raton no hace nada: en
/// escritorio la rueda y el teclado ya cambian de pagina.
class PageSwipe extends StatelessWidget {
  const PageSwipe({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.child,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget child;

  /// Lo que hay que arrastrar para que cuente como pasar de pagina.
  static const double _distance = 60;

  /// O soltarlo a esta velocidad, en pixeles por segundo.
  static const double _velocity = 380;

  @override
  Widget build(BuildContext context) {
    var travelled = 0.0;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(supportedDevices: fingerKinds),
          (recognizer) => recognizer
            ..onStart = ((_) => travelled = 0)
            ..onUpdate = ((details) => travelled += details.primaryDelta ?? 0)
            ..onEnd = (details) {
              final velocity = details.primaryVelocity ?? 0;
              final forward = travelled < 0 || velocity < 0;
              if (travelled.abs() < _distance && velocity.abs() < _velocity) return;
              forward ? onNext() : onPrevious();
            },
        ),
      },
      child: child,
    );
  }
}
