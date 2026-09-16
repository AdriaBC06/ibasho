// Ibasho — el icono de un canal.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../social/social_widgets.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import '../widgets/pressable.dart';
import 'channel_route.dart';
import 'channels/channel.dart';

/// Icono de canal.
///
/// Al pasar el raton se inclina dos grados y se eleva cuatro pixeles con
/// curva elastica; al pulsar se hunde dos. Nada mas: lo espectacular se guarda
/// para la apertura.
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

class _ChannelTileState extends ConsumerState<ChannelTile> {
  /// Ancla estable: la animacion de apertura necesita saber exactamente donde
  /// esta el icono, asi que la clave no puede recrearse en cada build.
  late final GlobalKey _anchor = GlobalKey(
    debugLabel: 'channel.${widget.spec.id}',
  );

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final compact = widget.compact;
    final width = widget.width;
    final height = widget.height;
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final anchor = _anchor;
    final tint = spec.empty ? null : skin.accent;
    final badge = spec.badge == null ? 0 : ref.watch(spec.badge!);

    return Pressable(
      cue: null,
      semanticLabel: spec.label(l),
      onPressed: () => openChannel(
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

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
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
                      borderColor: spec.empty
                          ? T.hairline
                          : Color.lerp(skin.accent, T.dusk, .36)!,
                      sink: state.press * 1.5,
                      child: compact || widget.glyphOnly
                          ? Center(
                              child: GlyphIcon(
                                spec.glyph,
                                size: height * .5,
                                color: spec.empty ? T.inkSoft : T.onAccent,
                              ),
                            )
                          : Padding(
                              padding: EdgeInsets.all(height * .12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GlyphIcon(
                                    spec.glyph,
                                    size: height * .38,
                                    color: spec.empty
                                        ? T.inkSoft.withValues(alpha: .75)
                                        : T.onAccent,
                                  ),
                                  SizedBox(height: height * .09),
                                  Text(
                                    spec.label(l),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Ty.body.copyWith(
                                      fontSize: math.max(11, height * .115),
                                      fontWeight: FontWeight.w500,
                                      color: spec.empty
                                          ? T.inkSoft
                                          : T.onAccent,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
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
