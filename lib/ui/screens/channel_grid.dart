// Ibasho — panel inferior: la rejilla de canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import 'channel_tile.dart';
import 'channels/channel.dart';

/// Curva del cambio de pagina: llega con un sobrepaso corto, como el carro de
/// una consola que se pasa un poco y vuelve.
const Curve pageSlideCurve = Cubic(.22, .94, .26, 1.05);

/// Rejilla de 4x2 por pagina.
class ChannelGrid extends StatefulWidget {
  const ChannelGrid({
    super.key,
    required this.channels,
    required this.page,
    required this.height,
    required this.width,
  });

  final List<ChannelSpec> channels;
  final int page;
  final double height;
  final double width;

  @override
  State<ChannelGrid> createState() => _ChannelGridState();
}

class _ChannelGridState extends State<ChannelGrid>
    with SingleTickerProviderStateMixin {
  static const double _padH = 28;
  static const double _padV = 26;
  static const double _gapH = 44;
  static const double _gapV = 24;
  static const double _aspect = 1.6;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: T.page,
    value: 1,
  );
  late double _from = widget.page.toDouble();
  late double _to = widget.page.toDouble();

  @override
  void didUpdateWidget(ChannelGrid old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) {
      final skin = IbashoSkin.of(context);
      _from = _current;
      _to = widget.page.toDouble();
      _slide
        ..duration = skin.motion(T.page)
        ..forward(from: 0);
    }
  }

  double get _current {
    final t = IbashoSkin.of(context).reducedMotion
        ? 1.0
        : pageSlideCurve.transform(_slide.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  int get _pageCount =>
      math.max(1, (widget.channels.length / channelsPerPage).ceil());

  @override
  Widget build(BuildContext context) {
    final compact = widget.height < 200;
    final inner = Size(
      widget.width - _padH * 2,
      widget.height - _padV * 2,
    );

    final double tileW;
    final double tileH;
    if (compact) {
      tileH = math.max(34, math.min(72, widget.height - 34));
      tileW = tileH * 1.15;
    } else {
      final byWidth = (inner.width - _gapH * 3) / 4;
      final byHeight = (inner.height - _gapV) / 2 * _aspect;
      tileW = math.max(90, math.min(byWidth, byHeight));
      tileH = tileW / _aspect;
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) => Transform.translate(
          offset: Offset(-_current * widget.width, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var page = 0; page < _pageCount; page++)
                SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: _Page(
                    channels: widget.channels
                        .skip(page * channelsPerPage)
                        .take(channelsPerPage)
                        .toList(growable: false),
                    tileWidth: tileW,
                    tileHeight: tileH,
                    gapH: compact ? 16 : _gapH,
                    gapV: _gapV,
                    compact: compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.channels,
    required this.tileWidth,
    required this.tileHeight,
    required this.gapH,
    required this.gapV,
    required this.compact,
  });

  final List<ChannelSpec> channels;
  final double tileWidth;
  final double tileHeight;
  final double gapH;
  final double gapV;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < channels.length; i++) ...[
              if (i > 0) SizedBox(width: gapH),
              ChannelTile(
                key: ValueKey<String>('channel.${channels[i].id}'),
                spec: channels[i],
                width: tileWidth,
                height: tileHeight,
                compact: true,
              ),
            ],
          ],
        ),
      );
    }

    final rows = <Widget>[];
    for (var row = 0; row < 2; row++) {
      final slice = channels.skip(row * 4).take(4).toList(growable: false);
      if (slice.isEmpty) continue;
      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < slice.length; i++) ...[
              if (i > 0) SizedBox(width: gapH),
              ChannelTile(
                key: ValueKey<String>('channel.${slice[i].id}'),
                spec: slice[i],
                width: tileWidth,
                height: tileHeight,
              ),
            ],
            // Relleno para que la fila incompleta no se recentre respecto a la
            // de arriba: los canales tienen que quedar en columna.
            for (var i = slice.length; i < 4; i++) ...[
              SizedBox(width: gapH),
              SizedBox(width: tileWidth, height: tileHeight),
            ],
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: gapV),
            rows[i],
          ],
        ],
      ),
    );
  }
}
