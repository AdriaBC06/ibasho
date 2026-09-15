// Ibasho — el entorno de dos paneles.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/card.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../canvas.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import '../widgets/panel.dart';
import 'channel_grid.dart';
import 'channel_route.dart';
import 'channels/channel.dart';
import 'top_panel.dart';

/// Los tres estados del boton de ampliar.
enum PanelBalance {
  /// Los dos paneles a la misma altura.
  balanced,

  /// Manda el de arriba.
  topLarge,

  /// Manda el de abajo.
  bottomLarge;

  double get topHeight => switch (this) {
        PanelBalance.balanced => T.panelBalanced,
        PanelBalance.topLarge => T.panelLarge,
        PanelBalance.bottomLarge => T.panelSmall,
      };

  /// La suma es constante, asi el entorno no se mueve de sitio.
  double get bottomHeight =>
      T.panelBalanced * 2 - topHeight;

  PanelBalance get next => switch (this) {
        PanelBalance.balanced => PanelBalance.topLarge,
        PanelBalance.topLarge => PanelBalance.bottomLarge,
        PanelBalance.bottomLarge => PanelBalance.balanced,
      };
}

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen>
    with SingleTickerProviderStateMixin {
  static const double _margin = 40;
  // Presupuesto vertical del lienzo (800):
  // 12 + panel 340 + carril 42 + panel 340 + aire 14 + barra 40 + 12.
  static const double _railHeight = 42;
  static const double _barGap = 14;
  static const double _barHeight = 40;

  // Se crea en initState y no de forma perezosa: si nadie pulsa ampliar, un
  // `late final` se crearia por primera vez en dispose(), con el arbol ya
  // desmontado.
  late final AnimationController _magnify;
  late Animation<double> _topHeight =
      AlwaysStoppedAnimation<double>(PanelBalance.balanced.topHeight);

  @override
  void initState() {
    super.initState();
    _magnify = AnimationController(vsync: this, duration: T.magnify, value: 1);
  }

  PanelBalance _balance = PanelBalance.balanced;
  int _page = 0;
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  final GlobalKey _settingsAnchor = GlobalKey(debugLabel: 'shortcut.settings');
  final GlobalKey _profileAnchor = GlobalKey(debugLabel: 'shortcut.profile');

  @override
  void dispose() {
    _magnify.dispose();
    super.dispose();
  }

  List<ChannelSpec> get _channels =>
      channelsFor(isAdmin: ref.read(sessionProvider).isAdmin);

  int get _pageCount =>
      math.max(1, (_channels.length / channelsPerPage).ceil());

  void _cycleBalance() {
    final skin = IbashoSkin.of(context);
    final next = _balance.next;
    setState(() {
      _topHeight = Tween<double>(
        begin: _topHeight.value,
        end: next.topHeight,
      ).animate(CurvedAnimation(
        parent: _magnify,
        curve: skin.curve(Curves.easeInOutCubic),
      ));
      _balance = next;
    });
    _magnify
      ..duration = skin.motion(T.magnify)
      ..forward(from: 0);
  }

  void _goToPage(int page) {
    final target = page.clamp(0, _pageCount - 1);
    if (target == _page) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _page = target);
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheel) < const Duration(milliseconds: 260)) return;
    if (event.scrollDelta.dy.abs() < 2 && event.scrollDelta.dx.abs() < 2) return;
    _lastWheel = now;
    final forward = (event.scrollDelta.dy + event.scrollDelta.dx) > 0;
    _goToPage(_page + (forward ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final channels = _channels;
    // Carga la musica de la cuenta en cuanto se entra, sin esperar a Ajustes.
    ref.watch(musicLibraryProvider.select((m) => m.loaded));
    // Presencia, amigos (la insignia de solicitudes) y la ficha publica viven
    // mientras se esta dentro, no solo con su canal abierto.
    ref.watch(presenceProvider.select((p) => p.connected));
    ref.watch(friendsProvider.select((f) => f.loaded));
    ref.watch(cardKeeperProvider);
    // El panel de administracion reparte los codigos de amigo que falten.
    if (ref.watch(sessionProvider.select((s) => s.isAdmin))) {
      ref.watch(adminProvider.select((a) => a.loading));
    }

    return Bezel(
      child: FocusScope(
        autofocus: true,
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.pageDown):
                _PageIntent(1),
            SingleActivator(LogicalKeyboardKey.pageUp): _PageIntent(-1),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _PageIntent: CallbackAction<_PageIntent>(
                onInvoke: (intent) {
                  _goToPage(_page + intent.delta);
                  return null;
                },
              ),
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _margin),
              child: AnimatedBuilder(
                animation: _topHeight,
                builder: (context, _) {
                  final topHeight = _topHeight.value;
                  final bottomHeight = T.panelBalanced * 2 - topHeight;
                  final panelWidth = CanvasSize.of(context).width - _margin * 2;

                  return Column(
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(
                        height: topHeight,
                        child: ScreenPanel(child: TopPanel(height: topHeight)),
                      ),
                      SizedBox(
                        height: _railHeight,
                        child: _ControlRail(
                          page: _page,
                          pageCount: _pageCount,
                          onPrevious: () => _goToPage(_page - 1),
                          onNext: () => _goToPage(_page + 1),
                          onMagnify: _cycleBalance,
                        ),
                      ),
                      SizedBox(
                        height: bottomHeight,
                        child: Listener(
                          onPointerSignal: _onWheel,
                          child: ScreenPanel(
                            child: ChannelGrid(
                              channels: channels,
                              page: _page,
                              height: bottomHeight,
                              width: panelWidth,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _barGap),
                      SizedBox(
                        height: _barHeight,
                        child: _BottomBar(
                          page: _page,
                          pageCount: _pageCount,
                          settingsAnchor: _settingsAnchor,
                          profileAnchor: _profileAnchor,
                          channels: channels,
                          label: l,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIntent extends Intent {
  const _PageIntent(this.delta);

  final int delta;
}

/// Flechas de paginacion y boton de ampliar, entre las dos pantallas.
class _ControlRail extends StatelessWidget {
  const _ControlRail({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
    required this.onMagnify,
  });

  final int page;
  final int pageCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onMagnify;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          // Las flechas en los extremos, simetricas; ampliar al lado de la
          // derecha, hacia dentro.
          IconPill(
            glyph: Glyph.arrowLeft,
            diameter: 36,
            onPressed: page > 0 ? onPrevious : null,
          ),
          const Spacer(),
          IconPill(
            key: const ValueKey<String>('magnify'),
            glyph: Glyph.magnify,
            diameter: 36,
            tone: ButtonTone.accent,
            onPressed: onMagnify,
          ),
          const SizedBox(width: 14),
          IconPill(
            glyph: Glyph.arrowRight,
            diameter: 36,
            onPressed: page < pageCount - 1 ? onNext : null,
          ),
        ],
      );
}

/// Atajos, puntos de pagina y acceso al perfil.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.pageCount,
    required this.settingsAnchor,
    required this.profileAnchor,
    required this.channels,
    required this.label,
  });

  final int page;
  final int pageCount;
  final GlobalKey settingsAnchor;
  final GlobalKey profileAnchor;
  final List<ChannelSpec> channels;
  final L label;

  ChannelSpec _spec(String id) => channels.firstWhere((c) => c.id == id);

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);

    void open(GlobalKey anchor, ChannelSpec spec) => openChannel(
          context,
          anchor: anchor,
          tint: skin.accent,
          glyph: spec.glyph,
          label: spec.label(label),
          builder: spec.builder,
        );

    final settings = _spec('settings');
    final profile = _spec('profile');

    return Row(
      children: [
        KeyedSubtree(
          key: settingsAnchor,
          child: IbashoButton(
            label: settings.label(label),
            glyph: settings.glyph,
            height: 40,
            cue: null,
            onPressed: () => open(settingsAnchor, settings),
          ),
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < pageCount; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _PageDot(active: i == page, accent: skin.accent),
            ],
          ],
        ),
        const Spacer(),
        KeyedSubtree(
          key: profileAnchor,
          child: IbashoButton(
            label: profile.label(label),
            glyph: profile.glyph,
            height: 40,
            cue: null,
            onPressed: () => open(profileAnchor, profile),
          ),
        ),
      ],
    );
  }
}

class _PageDot extends StatelessWidget {
  const _PageDot({required this.active, required this.accent});

  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return AnimatedContainer(
      duration: skin.motion(const Duration(milliseconds: 240)),
      curve: skin.curve(Curves.easeOut),
      width: active ? 12 : 9,
      height: active ? 12 : 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? accent : T.hairline,
        border: Border.all(
          color: active ? Color.lerp(accent, T.dusk, .4)! : T.hairline,
        ),
      ),
    );
  }
}
