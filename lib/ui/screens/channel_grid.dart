// Ibasho — panel inferior: la rejilla de canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
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
    this.editing = false,
    this.onReorder,
    this.onRequestPrevious,
    this.onRequestNext,
  });

  final List<ChannelSpec> channels;
  final int page;
  final double height;
  final double width;

  /// Modo de arrastrar para cambiar el orden: las baldosas tiemblan y se
  /// pueden soltar en cualquier ranura, en vez de abrir su canal.
  final bool editing;

  /// Se llama con la lista de ids ya en el orden nuevo, al soltar una baldosa
  /// sobre otra ranura. Solo hace falta en modo de edicion.
  final ValueChanged<List<String>>? onReorder;

  /// Al arrastrar una baldosa cerca del borde de la pagina, para pasar a la
  /// anterior o a la siguiente sin soltar.
  final VoidCallback? onRequestPrevious;
  final VoidCallback? onRequestNext;

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

  /// Hacia donde se esta pidiendo pasar de pagina al arrastrar: -1, 0 o 1.
  int _edge = 0;
  Timer? _edgeTimer;

  /// Lo que mide, desde cada borde hacia dentro, la zona que pasa de pagina.
  /// Pasado el borde (el margen, el bisel, fuera de la ventana) tambien
  /// cuenta: arrastrar «a tope» es lo que sale natural.
  static const double _edgeBand = 64;

  /// Al mover una baldosa arrastrada. Se mira la posicion del puntero contra
  /// la rejilla entera en vez de poner zonas `DragTarget` en los bordes: una
  /// zona solo se entera mientras el puntero esta encima, y al llevar la
  /// baldosa a tope el puntero se sale de la rejilla y deja de contar.
  void _onDragMove(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final x = box.globalToLocal(global).dx;
    final edge = x < _edgeBand
        ? -1
        : x > box.size.width - _edgeBand
        ? 1
        : 0;
    if (edge == _edge) return;
    _edge = edge;
    _edgeTimer?.cancel();
    _edgeTimer = edge == 0
        ? null
        : Timer.periodic(const Duration(milliseconds: 550), (_) {
            final turn = _edge < 0 ? widget.onRequestPrevious : widget.onRequestNext;
            turn?.call();
          });
  }

  void _onDragStop() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edge = 0;
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
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

    final grid = ClipRect(
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
                      editing: widget.editing,
                      onReorder: widget.onReorder,
                      onDragMove: _onDragMove,
                      onDragStop: _onDragStop,
                      allIds: widget.editing
                          ? widget.channels.map((c) => c.id).toList(growable: false)
                          : const <String>[],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return grid;
  }
}

/// Zona invisible encima de las flechas del carril: si una baldosa se queda
/// encima mientras se arrastra, al ratito pasa de pagina sin soltarla. (En
/// la rejilla no se usa: ver `_ChannelGridState._onDragMove`.)
class EdgeDropZone extends StatefulWidget {
  const EdgeDropZone({super.key, required this.onHover});

  final VoidCallback? onHover;

  @override
  State<EdgeDropZone> createState() => _EdgeDropZoneState();
}

class _EdgeDropZoneState extends State<EdgeDropZone> {
  Timer? _timer;

  // Se lee `widget.onHover` al disparar, no al armar: entre medias la pagina
  // puede haber cambiado y el borde haberse quedado sin a donde ir. Es
  // periodico para que, quieto encima, siga pasando paginas sin tener que
  // menear el dedo (`onMove` solo llega si el puntero se mueve).
  void _arm() {
    if (widget.onHover == null) return;
    _timer ??= Timer.periodic(const Duration(milliseconds: 550), (_) => widget.onHover?.call());
  }

  void _disarm() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
        onWillAcceptWithDetails: (_) {
          _arm();
          return false;
        },
        onMove: (_) => _arm(),
        onLeave: (_) => _disarm(),
        builder: (context, candidate, rejected) => const SizedBox.expand(),
      );
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
    this.editing = false,
    this.onReorder,
    this.onDragMove,
    this.onDragStop,
    this.allIds = const <String>[],
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
  final bool editing;
  final ValueChanged<List<String>>? onReorder;
  final ValueChanged<Offset>? onDragMove;
  final VoidCallback? onDragStop;

  /// Ids de todos los canales (todas las paginas), para calcular el orden
  /// nuevo al soltar una baldosa. Solo hace falta en modo de edicion.
  final List<String> allIds;

  Widget _tile(
    ChannelSpec spec, {
    required double width,
    required double height,
    bool compact = false,
    bool glyphOnly = false,
  }) {
    if (!editing) {
      return ChannelTile(
        key: ValueKey<String>('channel.${spec.id}'),
        spec: spec,
        width: width,
        height: height,
        compact: compact,
        glyphOnly: glyphOnly,
      );
    }
    return _ReorderableChannel(
      key: ValueKey<String>('channel.${spec.id}'),
      spec: spec,
      width: width,
      height: height,
      compact: compact,
      glyphOnly: glyphOnly,
      allIds: allIds,
      onReorder: onReorder,
      onDragMove: onDragMove,
      onDragStop: onDragStop,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < channels.length; i++) ...[
              if (i > 0) SizedBox(width: gapH),
              _tile(channels[i], width: tileWidth, height: tileHeight, compact: true),
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
              _tile(slice[i], width: tileWidth, height: tileHeight, glyphOnly: glyphOnly),
            ],
            // Relleno para que la fila incompleta no se recentre respecto a la
            // de arriba: los canales tienen que quedar en columna.
            for (var i = slice.length; i < columns; i++) ...[
              if (i > 0) SizedBox(width: gapH),
              if (editing)
                _EmptyDropSlot(
                  width: tileWidth,
                  height: tileHeight,
                  fill: fill,
                  allIds: allIds,
                  onReorder: onReorder,
                )
              else if (fill)
                EmptySlot(width: tileWidth, height: tileHeight)
              else
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

/// Mueve [draggedId] a la posicion [to] de [ids] (un indice de la lista tal
/// cual esta, antes de moverlo). Un [to] fuera de rango lo lleva al final.
List<String> moveChannelId(List<String> ids, String draggedId, int to) {
  final from = ids.indexOf(draggedId);
  if (from == -1 || from == to) return ids;
  final next = List<String>.from(ids)..removeAt(from);
  next.insert(to < 0 || to > next.length ? next.length : to, draggedId);
  return next;
}

/// Una ranura hundida en modo de edicion: soltar ahi manda el canal al final
/// de todo, para poder llevarlo a la ultima pagina aunque no haya con quien
/// cambiarse.
class _EmptyDropSlot extends StatelessWidget {
  const _EmptyDropSlot({
    required this.width,
    required this.height,
    required this.fill,
    required this.allIds,
    required this.onReorder,
  });

  final double width;
  final double height;
  final bool fill;
  final List<String> allIds;
  final ValueChanged<List<String>>? onReorder;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
        onAcceptWithDetails: (details) {
          final callback = onReorder;
          if (callback != null) callback(moveChannelId(allIds, details.data, allIds.length));
        },
        builder: (context, candidate, rejected) => fill
            ? EmptySlot(width: width, height: height)
            : SizedBox(width: width, height: height),
      );
}

/// Una baldosa arrastrable en modo de edicion: tiembla un poco (como en el
/// HOME de la 3DS, pero mas suave) y acepta que otra se suelte encima, en
/// cuyo caso cambia de sitio con ella (empujando al resto, no intercambiando).
class _ReorderableChannel extends StatelessWidget {
  const _ReorderableChannel({
    super.key,
    required this.spec,
    required this.width,
    required this.height,
    required this.compact,
    required this.glyphOnly,
    required this.allIds,
    required this.onReorder,
    this.onDragMove,
    this.onDragStop,
  });

  final ChannelSpec spec;
  final double width;
  final double height;
  final bool compact;
  final bool glyphOnly;
  final List<String> allIds;
  final ValueChanged<List<String>>? onReorder;

  /// Posicion global del puntero mientras se arrastra, y fin del arrastre
  /// (soltada donde sea o cancelada): la rejilla lo usa para pasar de pagina.
  final ValueChanged<Offset>? onDragMove;
  final VoidCallback? onDragStop;

  /// La baldosa arrastrada se queda con el hueco de [targetId], y las de en
  /// medio corren uno hacia ella. El indice del destino se toma ANTES de
  /// quitar la arrastrada: si se toma despues, al arrastrar hacia delante
  /// todo lo de detras ya ha corrido uno y la baldosa acaba una antes.
  List<String> _moved(String draggedId, String targetId) =>
      moveChannelId(allIds, draggedId, allIds.indexOf(targetId));

  @override
  Widget build(BuildContext context) {
    final tile = ChannelTile(
      spec: spec,
      width: width,
      height: height,
      compact: compact,
      glyphOnly: glyphOnly,
      editing: true,
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != spec.id,
      onAcceptWithDetails: (details) {
        final callback = onReorder;
        if (callback != null) callback(_moved(details.data, spec.id));
      },
      builder: (context, candidate, rejected) => Draggable<String>(
        data: spec.id,
        // La baldosa que se arrastra va centrada bajo el dedo. Con el ancla
        // de siempre queda donde se cogio, y como el destino lo decide el
        // dedo y no la baldosa, al apuntar con su centro caia una ranura
        // antes o despues de donde se veia.
        dragAnchorStrategy: (draggable, context, position) =>
            Offset(width / 2, height / 2),
        onDragUpdate: (details) => onDragMove?.call(details.globalPosition),
        onDragEnd: (_) => onDragStop?.call(),
        feedback: Opacity(
          opacity: .85,
          child: SizedBox(width: width, height: height, child: tile),
        ),
        childWhenDragging: Opacity(
          opacity: .3,
          child: _Wiggle(id: spec.id, child: tile),
        ),
        child: _Wiggle(id: spec.id, child: tile),
      ),
    );
  }
}

/// El temblor sutil de una baldosa en modo de edicion. Cada una lleva una
/// fase distinta segun su id, para que no tiemblen todas a la vez.
class _Wiggle extends StatefulWidget {
  const _Wiggle({required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<_Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<_Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _shiver = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _shiver
      ..value = (widget.id.hashCode.abs() % 100) / 100
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (IbashoSkin.of(context).reducedMotion) return widget.child;
    return AnimatedBuilder(
      animation: _shiver,
      child: widget.child,
      builder: (context, child) => Transform.rotate(
        angle: (_shiver.value * 2 - 1) * (1.6 * math.pi / 180),
        child: child,
      ),
    );
  }
}
