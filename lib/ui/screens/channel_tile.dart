// Ibasho — el icono de un canal.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../social/social_widgets.dart';
import '../widgets/glyphs.dart';
import '../widgets/gift_face.dart';
import '../widgets/gloss.dart';
import '../widgets/pressable.dart';
import 'channel_route.dart';
import 'channels/channel.dart';

/// Icono de canal.
///
/// Al pasar el raton se inclina dos grados y se eleva cuatro pixeles con
/// curva elastica; al pulsar se hunde dos. Nada mas: lo espectacular se guarda
/// para la apertura.
///
/// Un juego recien comprado (`spec.gift`) sale como un regalo envuelto que
/// ocupa todo el icono, como en el HOME de la 3DS: quieto, sin etiqueta. Tocarlo
/// lo desenvuelve (el regalo se abre y asoma el icono del juego) en vez de
/// abrir el canal. Una vez desenvuelto es un canal mas.
class ChannelTile extends ConsumerStatefulWidget {
  const ChannelTile({
    super.key,
    required this.spec,
    required this.width,
    required this.height,
    this.compact = false,
    this.glyphOnly = false,
  });

  final ChannelSpec spec;
  final double width;
  final double height;

  /// Version reducida para cuando el panel inferior esta encogido.
  final bool compact;

  /// Sin etiqueta: en vertical, cuando la baldosa se queda pequeña.
  final bool glyphOnly;

  @override
  ConsumerState<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends ConsumerState<ChannelTile>
    with SingleTickerProviderStateMixin {
  /// Ancla estable: la animacion de apertura necesita saber exactamente donde
  /// esta el icono, asi que la clave no puede recrearse en cada build.
  late final GlobalKey _anchor = GlobalKey(
    debugLabel: 'channel.${widget.spec.id}',
  );

  /// El desenvuelto: de 0 (regalo cerrado) a 1 (icono del juego a la vista).
  late final AnimationController _unwrap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  /// Se pone a `true` en cuanto termina la animacion, para que el tile se
  /// quede en su forma normal aunque el servidor tarde en confirmar.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _unwrap.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _revealed = true);
      }
    });
  }

  @override
  void dispose() {
    _unwrap.dispose();
    super.dispose();
  }

  void _onGiftTap() {
    if (_unwrap.isAnimating || _revealed) return;
    AudioService.instance.play(Sfx.chime);
    if (IbashoSkin.of(context).reducedMotion) {
      _unwrap.value = 1;
      setState(() => _revealed = true);
    } else {
      unawaited(_unwrap.forward());
    }
    final gameId = widget.spec.gameId;
    if (gameId == null) return;
    unawaited(ref.read(shopProvider.notifier).unwrap(gameId));
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final compact = widget.compact;
    final width = widget.width;
    final height = widget.height;
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final anchor = _anchor;
    final showingGift = spec.gift && !_revealed;
    // El regalo cerrado es una baldosa clara, sin el acento del entorno.
    final wrapped = showingGift && _unwrap.value < .5;
    final tint = spec.empty || wrapped ? null : skin.accent;
    final badge = spec.badge == null ? 0 : ref.watch(spec.badge!);

    return Pressable(
      cue: null,
      semanticLabel: spec.label(l),
      onPressed: showingGift
          ? _onGiftTap
          : () => openChannel(
              context,
              anchor: anchor,
              tint: tint ?? skin.accent,
              glyph: spec.glyph,
              label: spec.label(l),
              builder: spec.builder,
            ),
      builder: (context, state) {
        // Curva elastica en la elevacion: es lo que hace que el icono parezca
        // una pieza fisica y no una capa que se mueve.
        final ease = skin.reducedMotion
            ? state.hover
            : Curves.easeOutBack.transform(state.hover.clamp(0.0, 1.0));
        final lift = 4 * ease - 2 * state.press;
        final tilt = (2 * math.pi / 180) * ease * (1 - state.press);

        Widget content() {
          final size = height * (compact || widget.glyphOnly ? .5 : .38);
          final glyph = GlyphIcon(
            spec.glyph,
            size: size,
            color: spec.empty ? T.inkSoft : T.onAccent,
          );
          if (compact || widget.glyphOnly) return Center(child: glyph);
          return Padding(
            padding: EdgeInsets.all(height * .12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                glyph,
                SizedBox(height: height * .09),
                Text(
                  spec.label(l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body.copyWith(
                    fontSize: math.max(11, height * .115),
                    fontWeight: FontWeight.w500,
                    color: spec.empty ? T.inkSoft : T.onAccent,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          );
        }

        Widget face(double unwrapT) {
          if (!spec.gift || (_revealed && !_unwrap.isAnimating)) {
            return content();
          }
          // El icono del juego asoma a medida que el regalo se abre: el
          // regalo crece un poco y se desvanece.
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: ((unwrapT - .3) / .7).clamp(0.0, 1.0),
                child: content(),
              ),
              if (unwrapT < 1)
                Opacity(
                  opacity: (1 - unwrapT * 1.4).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1 + unwrapT * .35,
                    child: const GiftFace(),
                  ),
                ),
            ],
          );
        }

        Widget tile(double unwrapT) {
          return Transform.translate(
            offset: Offset(0, -lift),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0011)
                ..rotateX(tilt),
              child: FocusRing(
                visible: state.focus,
                radius: T.tileRadius,
                child: SizedBox(
                  key: anchor,
                  width: width,
                  height: height,
                  child: GlossSurface(
                    radius: T.tileRadius,
                    tint: tint,
                    recessed: spec.empty,
                    elevation: spec.empty ? 0 : 1 + ease * 1.1,
                    specular: spec.empty ? 0 : 1 - state.press * .35,
                    borderColor: spec.empty || wrapped
                        ? T.hairline
                        : Color.lerp(skin.accent, T.dusk, .36)!,
                    sink: state.press * 1.5,
                    child: face(unwrapT),
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            spec.gift && !_revealed
                ? AnimatedBuilder(
                    animation: _unwrap,
                    builder: (context, _) => tile(_unwrap.value),
                  )
                : tile(1),
            // La insignia va fuera de la inclinacion: se lee siempre recta,
            // pegada a la esquina, y sube con el icono.
            if (badge > 0)
              Positioned(
                top: -8 - lift,
                right: -8,
                child: CountBadge(
                  key: ValueKey<String>('channel.${spec.id}.badge'),
                  count: badge,
                  size: compact ? 20 : 28,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Sonido al recorrer la rejilla con el teclado o la rueda.
void playGridTick() => AudioService.instance.play(Sfx.tick);
