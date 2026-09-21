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
/// Un juego recien comprado (`spec.gift`) sale como un regalo envuelto que se
/// balancea solo: tocarlo lo desenvuelve (el lazo se suelta y asoma el icono
/// del juego) en vez de abrir el canal. Una vez desenvuelto es un canal mas.
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
    with TickerProviderStateMixin {
  /// Ancla estable: la animacion de apertura necesita saber exactamente donde
  /// esta el icono, asi que la clave no puede recrearse en cada build.
  late final GlobalKey _anchor = GlobalKey(
    debugLabel: 'channel.${widget.spec.id}',
  );

  /// Balanceo continuo del regalo, mientras no se toca.
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  /// El desenvuelto: de 0 (regalo cerrado) a 1 (icono del juego a la vista).
  late final AnimationController _unwrap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620));

  /// Se pone a `true` en cuanto termina la animacion, para que el tile se
  /// quede en su forma normal aunque el servidor tarde en confirmar.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _unwrap.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _revealed = true);
        _syncWobble();
      }
    });
    _syncWobble();
  }

  @override
  void didUpdateWidget(ChannelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWobble();
  }

  /// Solo se balancea un regalo sin abrir: una animacion infinita en cada
  /// baldosa gastaria fotogramas para nada.
  void _syncWobble() {
    final wobbling = widget.spec.gift && !_revealed;
    if (wobbling && !_wobble.isAnimating) {
      _wobble.repeat();
    } else if (!wobbling && _wobble.isAnimating) {
      _wobble.stop();
    }
  }

  @override
  void dispose() {
    _wobble.dispose();
    _unwrap.dispose();
    super.dispose();
  }

  void _onGiftTap() {
    if (_unwrap.isAnimating || _revealed) return;
    AudioService.instance.play(Sfx.chime);
    unawaited(_unwrap.forward());
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
    final tint = spec.empty ? null : skin.accent;
    final badge = spec.badge == null ? 0 : ref.watch(spec.badge!);
    final showingGift = spec.gift && !_revealed;

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
        var tilt = (2 * math.pi / 180) * ease * (1 - state.press);

        Widget glyphFor(double unwrapT) {
          if (!spec.gift) {
            return GlyphIcon(
              spec.glyph,
              size: height * (compact || widget.glyphOnly ? .5 : .38),
              color: spec.empty ? T.inkSoft : T.onAccent,
            );
          }
          // Se funde del lazo al icono del juego a mitad de la animacion.
          final size = height * (compact || widget.glyphOnly ? .5 : .38);
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - unwrapT * 1.6).clamp(0.0, 1.0),
                child: GlyphIcon(Glyph.gift, size: size, color: T.onAccent),
              ),
              Opacity(
                opacity: ((unwrapT - .35) / .65).clamp(0.0, 1.0),
                child: GlyphIcon(spec.glyph, size: size, color: T.onAccent),
              ),
            ],
          );
        }

        Widget tile(double unwrapT, double wobbleT) {
          // Balanceo suave mientras esta envuelto; al tocarlo, un pequeño
          // rebote de "pop" cuando se abre.
          if (showingGift && !skin.reducedMotion) {
            tilt += (6 * math.pi / 180) * math.sin(wobbleT * 2 * math.pi) * (1 - unwrapT);
          }
          final pop = showingGift ? 1 + math.sin(unwrapT * math.pi) * .16 : 1.0;

          return Transform.translate(
            offset: Offset(0, -lift),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0011)
                ..rotateX(tilt)
                ..scaleByDouble(pop, pop, pop, 1),
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
                        ? Center(child: glyphFor(unwrapT))
                        : Padding(
                            padding: EdgeInsets.all(height * .12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                glyphFor(unwrapT),
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
                          ),
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            showingGift || _unwrap.isAnimating
                ? AnimatedBuilder(
                    animation: Listenable.merge([_wobble, _unwrap]),
                    builder: (context, _) => tile(_unwrap.value, _wobble.value),
                  )
                : tile(1, 0),
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
