// Ibasho — texto de una linea que, si no cabe, se desliza para leerse entero.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';

/// Una linea de texto. Si cabe, es un [Text] sin mas. Si no, en vez de
/// cortarse con puntos suspensivos, espera un momento, se desliza despacio
/// hasta el final, vuelve a esperar y regresa al principio, en bucle.
///
/// Con el movimiento reducido (o en las pruebas, que esperan a que todo se
/// quede quieto) se corta con puntos suspensivos como siempre.
class ScrollingText extends StatefulWidget {
  const ScrollingText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// `flutter test` define esta variable: alli no se anima nada.
  static final bool _animates = kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  State<ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<ScrollingText> with SingleTickerProviderStateMixin {
  static const _pause = 1.4;
  static const _back = .5;
  static const _pixelsPerSecond = 34.0;

  final _scroll = ScrollController();
  /// Solo se crea si el texto no cabe alguna vez.
  AnimationController? _clock;
  double _extent = 0;

  @override
  void dispose() {
    _clock?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// La vuelta entera: pausa, ida, pausa y regreso rapido.
  void _configure(double extent) {
    if ((extent - _extent).abs() < .5) return;
    _extent = extent;
    if (extent <= 0) {
      _clock?.stop();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    final seconds = _pause + extent / _pixelsPerSecond + _pause + _back;
    (_clock ??= AnimationController(vsync: this)..addListener(_tick))
      ..duration = Duration(milliseconds: (seconds * 1000).round())
      ..repeat();
  }

  void _tick() {
    final clock = _clock;
    if (clock == null || !_scroll.hasClients || _extent <= 0) return;
    final seconds = clock.value * clock.duration!.inMilliseconds / 1000;
    final go = _extent / _pixelsPerSecond;
    final double t;
    if (seconds < _pause) {
      t = 0;
    } else if (seconds < _pause + go) {
      t = Curves.easeInOut.transform((seconds - _pause) / go);
    } else if (seconds < _pause + go + _pause) {
      t = 1;
    } else {
      t = 1 - Curves.easeInOut.transform(((seconds - _pause - go - _pause) / _back).clamp(0.0, 1.0));
    }
    _scroll.jumpTo(t * _extent);
  }

  @override
  Widget build(BuildContext context) {
    if (!ScrollingText._animates || IbashoSkin.of(context).reducedMotion) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: widget.textAlign,
        style: widget.style,
      );
    }
    // Tras cada construccion se mira cuanto sobra; si cambia el tamaño sin
    // reconstruirse, lo avisa la notificacion (que ya llega tras el cuadro).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _configure(_scroll.position.maxScrollExtent);
    });
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        _configure(n.metrics.maxScrollExtent);
        return true;
      },
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          textAlign: widget.textAlign,
          style: widget.style,
        ),
      ),
    );
  }
}
