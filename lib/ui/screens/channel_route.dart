// Ibasho — apertura y cierre de un canal.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../canvas.dart';
import '../layout.dart';
import '../widgets/channel_art.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import 'channel_grid.dart';

/// El gesto de la casa: el icono crece desde su sitio hasta llenar la pantalla
/// entera, las esquinas se van a cero y el resto del entorno se desvanece.
///
/// Todo lo que se anima aqui es barato a proposito —un rectangulo, un radio y
/// dos opacidades— para que la transicion no baje de 60 fps.
class ChannelRoute extends PageRoute<void> {
  ChannelRoute({
    required this.origin,
    required this.tint,
    required this.glyph,
    required this.label,
    required this.builder,
    required this.reducedMotion,
    this.art,
  });

  /// Rectangulo del icono en coordenadas del lienzo.
  final Rect origin;

  /// Icono ilustrado del canal, si lo tiene: la baldosa que se abre lo
  /// ensena en vez del glifo.
  final ArtIcon? art;

  final Color tint;
  final Glyph glyph;
  final String label;
  final WidgetBuilder builder;
  final bool reducedMotion;


  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get barrierDismissible => false;

  @override
  Duration get transitionDuration =>
      reducedMotion ? T.reduced : T.channelOpen;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? T.reduced : const Duration(milliseconds: 380);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (reducedMotion) {
      return FadeTransition(
        opacity: animation,
        child: ColoredBox(color: T.shellTop, child: child),
      );
    }

    final grow = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic.flipped,
    );
    final content = CurvedAnimation(
      parent: animation,
      curve: const Interval(.34, 1, curve: Curves.easeOut),
      reverseCurve: const Interval(.5, 1, curve: Curves.easeIn),
    );

    final canvas = CanvasSize.of(context);
    return AnimatedBuilder(
      animation: grow,
      builder: (context, _) {
        final t = grow.value;
        final rect = Rect.lerp(origin, Offset.zero & canvas, t)!;
        final radius = T.tileRadius * (1 - t);

        return Stack(
          children: [
            // El entorno de detras se apaga mientras el canal crece.
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (t * 1.25).clamp(0.0, 1.0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [T.bezelTop, T.bezelBottom],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [T.shellTop, T.shellBottom],
                    ),
                    border: radius > 1
                        ? Border.all(color: T.hairline, width: 1)
                        : null,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // La cara del icono, que se va en cuanto arranca.
                      if (t < .45)
                        Opacity(
                          opacity: (1 - t / .45).clamp(0.0, 1.0),
                          child: _TileFace(tint: tint, glyph: glyph, label: label, art: art),
                        ),
                      // El canal se maqueta una sola vez, a pantalla completa,
                      // y solo se escala. Icono y lienzo comparten proporcion
                      // (1,6), asi que la escala es uniforme y no deforma;
                      // y como no hay relayout por frame, la apertura se queda
                      // en componer una capa.
                      FadeTransition(
                        opacity: content,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox.fromSize(
                            size: canvas,
                            child: RepaintBoundary(child: child),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lo que se ve dentro del rectangulo mientras crece: el icono de partida.
class _TileFace extends StatelessWidget {
  const _TileFace({required this.tint, required this.glyph, required this.label, this.art});

  final Color tint;
  final Glyph glyph;
  final String label;
  final ArtIcon? art;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: art != null
                ? const [T.shellTop, T.shellBottom]
                : [
                    Color.lerp(tint, T.shellTop, .30)!,
                    Color.lerp(tint, T.dusk, .14)!,
                  ],
          ),
        ),
        child: Center(
          child: art != null
              ? ArtIconView(art!, size: 84)
              : GlyphIcon(glyph, size: 46, color: T.onAccent),
        ),
      );
}

/// Abre un canal desde el rectangulo que ocupa su icono.
Future<void> openChannel(
  BuildContext context, {
  required GlobalKey anchor,
  required Color tint,
  required Glyph glyph,
  required String label,
  required WidgetBuilder builder,
  ArtIcon? art,
}) {
  final origin = rectInNavigator(context, anchor) ??
      Rect.fromCenter(
        center: CanvasSize.of(context).center(Offset.zero),
        width: 208,
        height: 130,
      );
  AudioService.instance.play(Sfx.open);
  return Navigator.of(context).push(
    ChannelRoute(
      origin: origin,
      tint: tint,
      glyph: glyph,
      label: label,
      builder: builder,
      reducedMotion: IbashoSkin.of(context).reducedMotion,
      art: art,
    ),
  );
}

/// Pagina dentro de un canal: la habitacion de un Tama, el creador.
///
/// Entra deslizandose desde la derecha con el mismo sobrepaso corto que el
/// cambio de pagina de la rejilla. Lo audaz se queda para abrir canales; esto
/// es discreto a proposito. Con movimiento reducido, un fundido corto.
class ChannelPageRoute<R> extends PageRoute<R> {
  ChannelPageRoute({required this.builder, required this.reducedMotion});

  final WidgetBuilder builder;
  final bool reducedMotion;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => reducedMotion ? T.reduced : T.page;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? T.reduced : const Duration(milliseconds: 300);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [T.shellTop, T.shellBottom],
          ),
        ),
        child: builder(context),
      );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (reducedMotion) return FadeTransition(opacity: animation, child: child);
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: pageSlideCurve,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    );
  }
}

/// Abre una pagina dentro del canal en curso.
Future<R?> pushChannelPage<R>(BuildContext context, WidgetBuilder builder) {
  AudioService.instance.play(Sfx.open);
  return Navigator.of(context).push(
    ChannelPageRoute<R>(
      builder: builder,
      reducedMotion: IbashoSkin.of(context).reducedMotion,
    ),
  );
}

/// Marco comun de todos los canales: cabecera con titulo y vuelta atras.
class ChannelScaffold extends StatelessWidget {
  const ChannelScaffold({
    super.key,
    required this.title,
    required this.glyph,
    required this.child,
    this.trailing,
    this.onClose,
    this.art,
  });

  final String title;
  final Glyph glyph;

  /// Icono ilustrado: sustituye a la pastilla de acento con el glifo.
  final ArtIcon? art;
  final Widget child;
  final Widget? trailing;

  /// Sustituye al cierre normal, por ejemplo para preguntar antes de perder
  /// cambios. Quien lo pasa decide si cierra.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final layout = Layout.of(context);
    final tall = layout.tall;

    void close() {
      if (onClose != null) {
        onClose!();
        return;
      }
      AudioService.instance.play(Sfx.back);
      Navigator.of(context).maybePop();
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            close();
            return null;
          }),
        },
        child: FocusScope(
          autofocus: true,
          child: Column(
            children: [
              SizedBox(
                height: layout.header,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                  child: Row(
                    children: [
                      if (art != null)
                        ArtIconView(art!, size: tall ? 44 : 56)
                      else
                      SizedBox(
                        width: tall ? 40 : 50,
                        height: tall ? 40 : 50,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.lerp(skin.accent, T.shellTop, .28)!,
                                skin.accentDeep,
                              ],
                            ),
                          ),
                          child: Center(
                            child: GlyphIcon(glyph,
                                size: tall ? 22 : 26, color: T.onAccent),
                          ),
                        ),
                      ),
                      SizedBox(width: tall ? 12 : 16),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tall ? Ty.lead.copyWith(fontWeight: FontWeight.w500) : Ty.title,
                        ),
                      ),
                      if (trailing != null) ...[
                        trailing!,
                        SizedBox(width: tall ? 8 : 12),
                      ],
                      IconPill(
                        glyph: Glyph.cross,
                        diameter: tall ? 44 : 46,
                        cue: null,
                        onPressed: close,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(
                height: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: T.hairline)),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
