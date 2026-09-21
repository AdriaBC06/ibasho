// Ibasho — panel inferior: la rejilla de canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../layout.dart';
import '../widgets/slot_tile.dart';
import 'channel_tile.dart';
import 'channels/channel.dart';

/// Curva del cambio de pagina: llega con un sobrepaso corto, como el carro de
/// una consola que se pasa un poco y vuelve.
const Curve pageSlideCurve = Cubic(.22, .94, .26, 1.05);

/// Rejilla de canales: 4x2 por pagina en horizontal, 3x3 en vertical.
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

  static const double _padH = 28;
  static const double _padV = 26;
  static const double _gapH = 44;
  static const double _gapV = 24;
  static const double _aspect = 1.6;

  /// Medidas de la rejilla vertical. La usa el entorno para repartir el alto
  /// entre las dos pantallas antes de maquetar.
  static const double tallPadH = 20;
  static const double tallPadV = 16;
  static const double tallGapH = 14;
  static const double tallGapV = 14;
  static const double tallAspect = 1.25;

  /// Ancho de baldosa en vertical para un panel de este ancho.
  static double tallTileWidth(double width) =>
      (width - tallPadH * 2 - tallGapH * 2) / 3;

  /// Alto que le gustaria tener a la rejilla vertical, con sus tres filas
  /// enteras.
  static double tallNaturalHeight(double width) =>
      tallTileWidth(width) / tallAspect * 3 + tallGapV * 2 + tallPadV * 2;

  @override
  State<ChannelGrid> createState() => _ChannelGridState();
}

class _ChannelGridState extends State<ChannelGrid>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final tall = Layout.of(context).tall;
    final perPage = channelsPerPage(tall: tall);
    final pageCount = math.max(1, (widget.channels.length / perPage).ceil());
    final compact = widget.height < (tall ? 250 : 200);

    final double tileW;
    final double tileH;
    final int columns;
    if (tall) {
      columns = 3;
      final inner = Size(
        widget.width - ChannelGrid.tallPadH * 2,
        widget.height - ChannelGrid.tallPadV * 2,
      );
      final byWidth = (inner.width - ChannelGrid.tallGapH * 2) / 3;
      final byHeight =
          (inner.height - ChannelGrid.tallGapV * 2) /
          3 *
          ChannelGrid.tallAspect;
      tileW = math.max(56, math.min(byWidth, byHeight));
      tileH = tileW / ChannelGrid.tallAspect;
    } else if (compact) {
      columns = perPage;
      tileH = math.max(34, math.min(72, widget.height - 34));
      tileW = tileH * 1.15;
    } else {
      columns = 4;
      final inner = Size(
        widget.width - ChannelGrid._padH * 2,
        widget.height - ChannelGrid._padV * 2,
      );
      final byWidth = (inner.width - ChannelGrid._gapH * 3) / 4;
      final byHeight =
          (inner.height - ChannelGrid._gapV) / 2 * ChannelGrid._aspect;
      tileW = math.max(90, math.min(byWidth, byHeight));
      tileH = tileW / ChannelGrid._aspect;
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        // Las paginas van una al lado de otra en una fila que es tan ancha
        // como todas juntas, y el `ClipRect` enseña solo la que toca. Sin
        // esto la fila recibe el ancho del panel y se queja de desbordar en
        // cuanto hay mas de una pagina, que es justo lo normal: el recorte
        // es el mecanismo, no un accidente.
        //
        // El desplazamiento va DENTRO del `OverflowBox`: un toque solo llega a
        // un hijo si cae dentro del tamaño de su padre, y con la traslacion
        // fuera la pagina 2 en adelante quedaba fuera del `OverflowBox` y no
        // recibia ni un clic.
        builder: (context, _) => OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: Offset(-_current * widget.width, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var page = 0; page < pageCount; page++)
                  SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: _Page(
                      channels: widget.channels
                          .skip(page * perPage)
                          .take(perPage)
                          .toList(growable: false),
                      perPage: perPage,
                      columns: columns,
                      tileWidth: tileW,
                      tileHeight: tileH,
                      gapH: tall
                          ? ChannelGrid.tallGapH
                          : compact
                          ? 16
                          : ChannelGrid._gapH,
                      gapV: tall ? ChannelGrid.tallGapV : ChannelGrid._gapV,
                      compact: !tall && compact,
                      // Toda pagina se completa con ranuras hundidas: la
                      // rejilla es siempre de 4x2 (3x3 en vertical), como el
                      // HOME de la consola.
                      fill: tall || !compact,
                      glyphOnly: tall && tileH < 58,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.channels,
    required this.perPage,
    required this.columns,
    required this.tileWidth,
    required this.tileHeight,
    required this.gapH,
    required this.gapV,
    required this.compact,
    required this.fill,
    required this.glyphOnly,
  });

  final List<ChannelSpec> channels;
  final int perPage;
  final int columns;
  final double tileWidth;
  final double tileHeight;
  final double gapH;
  final double gapV;
  final bool compact;
  final bool fill;
  final bool glyphOnly;

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
    final rowCount = (perPage / columns).ceil();
    for (var row = 0; row < rowCount; row++) {
      final slice = channels
          .skip(row * columns)
          .take(columns)
          .toList(growable: false);
      if (slice.isEmpty && !fill) continue;
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
                glyphOnly: glyphOnly,
              ),
            ],
            // Relleno para que la fila incompleta no se recentre respecto a la
            // de arriba: los canales tienen que quedar en columna.
            for (var i = slice.length; i < columns; i++) ...[
              if (i > 0) SizedBox(width: gapH),
              fill
                  ? EmptySlot(width: tileWidth, height: tileHeight)
                  : SizedBox(width: tileWidth, height: tileHeight),
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
