// Ibasho — el entorno de dos paneles.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/card.dart';
import '../../state/channel_order.dart';
import '../../state/login_bonus.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../canvas.dart';
import '../layout.dart';
import '../widgets/backdrop_art.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import '../widgets/panel.dart';
import 'channel_grid.dart';
import 'channel_route.dart';
import '../../games/ohirune/ohirune.dart';
import 'channels/channel.dart';
import 'login_bonus_panel.dart';
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
  double get bottomHeight => T.panelBalanced * 2 - topHeight;

  /// Alto del panel superior con este estado.
  ///
  /// En horizontal son las tres alturas de siempre. En vertical se reparte lo
  /// que haya: equilibrado le da a la rejilla justo lo que necesitan sus tres
  /// filas y el resto al panel de arriba, y los otros dos estados encogen uno
  /// de los dos al minimo.
  double topFor({required double available, required double gridNatural}) =>
      switch (this) {
        PanelBalance.balanced => math.max(
          _tallMinTop,
          available - math.min(gridNatural, available - _tallMinTop),
        ),
        PanelBalance.topLarge => available - _tallMinGrid,
        PanelBalance.bottomLarge => _tallMinTop,
      };

  /// Alto minimo del panel de arriba en vertical: el reloj, el saludo y el
  /// Tama en una tira.
  static const double _tallMinTop = 120;

  /// Alto minimo de la rejilla en vertical: tres filas de iconos sin etiqueta,
  /// nunca por debajo de lo que se puede tocar.
  static const double _tallMinGrid = 212;

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
  // Presupuesto vertical del lienzo horizontal (800):
  // 12 + panel 340 + carril 42 + panel 340 + aire 14 + barra 40 + 12.
  static const double _railHeight = 42;
  static const double _barGap = 14;
  static const double _barHeight = 40;

  // En vertical el carril y la barra crecen hasta lo que se toca con el dedo,
  // y el reparto de los dos paneles sale del alto que haya.
  static const double _tallRailHeight = 56;
  static const double _tallBarHeight = 48;

  // Se crea en initState y no de forma perezosa: si nadie pulsa ampliar, un
  // `late final` se crearia por primera vez en dispose(), con el arbol ya
  // desmontado.
  late final AnimationController _magnify;
  late Animation<double> _topHeight = AlwaysStoppedAnimation<double>(
    PanelBalance.balanced.topHeight,
  );

  @override
  void initState() {
    super.initState();
    _magnify = AnimationController(vsync: this, duration: T.magnify, value: 1);
    // El bono diario se ofrece solo al entrar, una vez por sesion, en cuanto
    // se sabe que el de hoy esta sin cobrar.
    ref.listenManual(
      loginBonusProvider,
      (_, bonus) => _offerBonus(bonus),
      fireImmediately: true,
    );
  }

  bool _bonusOffered = false;

  void _offerBonus(LoginBonusState bonus) {
    if (_bonusOffered ||
        !loginBonusAutoOpen ||
        !bonus.loaded ||
        bonus.claimedToday) {
      return;
    }
    _bonusOffered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showLoginBonus(context));
    });
  }

  PanelBalance _balance = PanelBalance.balanced;
  int _page = 0;

  /// Modo de arrastrar los canales para cambiarlos de sitio.
  bool _editingOrder = false;

  void _toggleEditingOrder() {
    AudioService.instance.play(Sfx.tick);
    setState(() => _editingOrder = !_editingOrder);
  }

  void _reorderChannels(List<String> order) =>
      unawaited(ref.read(channelOrderProvider.notifier).setOrder(order));

  /// Alto del panel de arriba cuando empezo la animacion de ampliar. Se guarda
  /// en vez de calcularlo porque al girar el movil las alturas cambian.
  double _fromTop = PanelBalance.balanced.topHeight;
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  final GlobalKey _settingsAnchor = GlobalKey(debugLabel: 'shortcut.settings');
  final GlobalKey _profileAnchor = GlobalKey(debugLabel: 'shortcut.profile');

  @override
  void dispose() {
    _magnify.dispose();
    super.dispose();
  }

  List<ChannelSpec> get _channels {
    // El gachapon se desbloquea con el primer ticket (o con lo que ya haya
    // caido en el deposito) y llega envuelto hasta que se abre.
    final gacha = ref.watch(gachaProvider);
    final unlocked =
        gacha.tickets.values.any((n) => n > 0) ||
        gacha.totalBalls > 0 ||
        gacha.wish != null;
    // El pinball, con la primera bola. Una cuenta que ya ha tirado alguna
    // vez lo conserva aunque se quede sin bolas.
    final pinball = gacha.pulledOnce || gacha.totalBalls > 0;
    final prefs = ref.watch(preferencesProvider);
    // El pachinko, tras la primera bola jugada en el pinball (o si ya se ha
    // jugado alguna tanda, desde otro dispositivo).
    final pachinko = prefs.pinballPlayed || gacha.pachinkoPlayed;
    // Tamakoro, con el primer Tama. Quien ya lo abrio lo conserva.
    final koro =
        ref.watch(tamasProvider.select((t) => t.tamas.isNotEmpty)) ||
        prefs.koroOpened;
    // Ohirune, el canal secreto, con los Tamas del tablero facil.
    final ohirune =
        ref.watch(tamasProvider.select((t) => t.tamas.length >= ohiruneUnlockTamas)) ||
        prefs.ohiruneOpened;
    final channels = channelsFor(
      isAdmin: ref.read(sessionProvider).isAdmin,
      installedGames: ref.watch(installedGamesProvider),
      gachaUnlocked: unlocked,
      gachaGift: unlocked && !prefs.gachaOpened,
      pinballUnlocked: pinball,
      pinballGift: pinball && !prefs.pinballOpened,
      pachinkoUnlocked: pachinko,
      pachinkoGift: pachinko && !prefs.pachinkoOpened,
      koroUnlocked: koro,
      koroGift: koro && !prefs.koroOpened,
      odoriGift: !prefs.odoriOpened,
      ohiruneUnlocked: ohirune,
      ohiruneGift: ohirune && !prefs.ohiruneOpened,
    );
    // El orden que haya elegido la cuenta manda; lo nuevo va al final y lo que
    // ya no existe se ignora (ver `applyChannelOrder`).
    final order = ref.watch(channelOrderProvider.select((s) => s.order));
    return applyChannelOrder(channels, order);
  }

  int _pageCount(bool tall) =>
      math.max(1, (_channels.length / channelsPerPage(tall: tall)).ceil());

  void _cycleBalance() {
    final skin = IbashoSkin.of(context);
    final next = _balance.next;
    setState(() {
      _fromTop = _topHeight.value;
      _balance = next;
    });
    _magnify
      ..duration = skin.motion(T.magnify)
      ..forward(from: 0);
  }

  /// La animacion de ampliar, resuelta con las alturas de la composicion en
  /// curso: asi girar el movil a mitad de animacion no la deja a medias en
  /// unidades de la otra.
  void _retune(Layout layout, double available, double gridNatural) {
    final skin = IbashoSkin.of(context);
    final target = layout.tall
        ? _balance.topFor(available: available, gridNatural: gridNatural)
        : _balance.topHeight;
    _topHeight = Tween<double>(begin: _fromTop, end: target).animate(
      CurvedAnimation(
        parent: _magnify,
        curve: skin.curve(Curves.easeInOutCubic),
      ),
    );
  }

  void _goToPage(int page) {
    final target = page.clamp(0, _pageCount(CanvasSize.tallOf(context)) - 1);
    if (target == _page) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _page = target);
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheel) < const Duration(milliseconds: 260)) return;
    if (event.scrollDelta.dy.abs() < 2 && event.scrollDelta.dx.abs() < 2) {
      return;
    }
    _lastWheel = now;
    final forward = (event.scrollDelta.dy + event.scrollDelta.dx) > 0;
    _goToPage(_page + (forward ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final channels = _channels;
    final pageCount = _pageCount(layout.tall);
    if (_page >= pageCount) _page = pageCount - 1;
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
    // El fondo puesto en Ajustes: detras de los paneles, se ve por el aire
    // que dejan (el carril, la barra y los margenes).
    final backdropId = ref.watch(backdropIdProvider);

    return Bezel(
      child: Stack(
        children: [
          // Detras de todo y de lado a lado: solo se ve por el aire que dejan
          // los paneles (los margenes, el carril y la barra). No ocupa sitio
          // ni cambia ningun tamano.
          Positioned.fill(
            child: RepaintBoundary(child: BackdropView(id: backdropId)),
          ),
          FocusScope(
            autofocus: true,
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.pageDown): _PageIntent(1),
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
                  padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final panelWidth = box.maxWidth;
                      final railHeight = layout.pick(
                        _railHeight,
                        _tallRailHeight,
                      );
                      final barHeight = layout.pick(_barHeight, _tallBarHeight);
                      final barGap = layout.pick(_barGap, 10.0);
                      final available =
                          box.maxHeight - 24 - railHeight - barGap - barHeight;
                      final gridNatural = ChannelGrid.tallNaturalHeight(
                        panelWidth,
                      );
                      _retune(layout, available, gridNatural);

                      return AnimatedBuilder(
                        animation: _topHeight,
                        builder: (context, _) {
                          final topHeight = _topHeight.value;
                          final bottomHeight = layout.tall
                              ? available - topHeight
                              : T.panelBalanced * 2 - topHeight;

                          return Stack(
                            children: [
                              Column(
                                children: [
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: topHeight,
                                    child: ScreenPanel(
                                      glass: true,
                                      child: TopPanel(height: topHeight),
                                    ),
                                  ),
                                  SizedBox(
                                    height: railHeight,
                                    child: _ControlRail(
                                      page: _page,
                                      pageCount: pageCount,
                                      diameter: layout.pill,
                                      editingOrder: _editingOrder,
                                      onPrevious: () => _goToPage(_page - 1),
                                      onNext: () => _goToPage(_page + 1),
                                      onMagnify: _cycleBalance,
                                      onToggleEditingOrder: _toggleEditingOrder,
                                    ),
                                  ),
                                  SizedBox(
                                    height: bottomHeight,
                                    child: Listener(
                                      onPointerSignal: _editingOrder
                                          ? null
                                          : _onWheel,
                                      child: _editingOrder
                                          ? ScreenPanel(
                                            glass: true,
                                              child: ChannelGrid(
                                                channels: channels,
                                                page: _page,
                                                height: bottomHeight,
                                                width: panelWidth,
                                                editing: true,
                                                onReorder: _reorderChannels,
                                                onRequestPrevious: _page > 0
                                                    ? () => _goToPage(_page - 1)
                                                    : null,
                                                onRequestNext:
                                                    _page < pageCount - 1
                                                    ? () => _goToPage(_page + 1)
                                                    : null,
                                              ),
                                            )
                                          : PageSwipe(
                                              onPrevious: () =>
                                                  _goToPage(_page - 1),
                                              onNext: () =>
                                                  _goToPage(_page + 1),
                                              child: ScreenPanel(
                                                glass: true,
                                                child: ChannelGrid(
                                                  channels: channels,
                                                  page: _page,
                                                  height: bottomHeight,
                                                  width: panelWidth,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  SizedBox(height: barGap),
                                  SizedBox(
                                    height: barHeight,
                                    child: _BottomBar(
                                      page: _page,
                                      pageCount: pageCount,
                                      settingsAnchor: _settingsAnchor,
                                      profileAnchor: _profileAnchor,
                                      channels: channels,
                                      label: l,
                                      height: barHeight,
                                      width: panelWidth,
                                      editingOrder: _editingOrder,
                                      onDoneEditingOrder: _toggleEditingOrder,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
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
    required this.diameter,
    required this.editingOrder,
    required this.onPrevious,
    required this.onNext,
    required this.onMagnify,
    required this.onToggleEditingOrder,
  });

  final int page;
  final int pageCount;
  final double diameter;

  /// En modo de ordenar canales, las flechas tambien pasan de pagina si una
  /// baldosa se queda arrastrada encima un ratito.
  final bool editingOrder;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onMagnify;
  final VoidCallback onToggleEditingOrder;

  Widget _arrow(
    String key,
    Glyph glyph,
    double diameter,
    VoidCallback? onPressed,
    VoidCallback? onHover,
  ) {
    final pill = IconPill(
      key: ValueKey<String>(key),
      glyph: glyph,
      diameter: diameter,
      onPressed: onPressed,
    );
    if (!editingOrder) return pill;
    return Stack(
      children: [
        pill,
        Positioned.fill(child: EdgeDropZone(onHover: onHover)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // Las flechas en los extremos, simetricas; ordenar y ampliar hacia
      // dentro, a la derecha.
      _arrow(
        'grid.previous',
        Glyph.arrowLeft,
        diameter,
        page > 0 ? onPrevious : null,
        page > 0 ? onPrevious : null,
      ),
      const Spacer(),
      IconPill(
        key: const ValueKey<String>('reorder-channels'),
        glyph: Glyph.pencil,
        diameter: diameter,
        tone: editingOrder ? ButtonTone.accent : ButtonTone.plain,
        semanticLabel: L.of(context)!.reorderChannelsStart,
        onPressed: onToggleEditingOrder,
      ),
      const SizedBox(width: 14),
      IconPill(
        key: const ValueKey<String>('magnify'),
        glyph: Glyph.magnify,
        diameter: diameter,
        tone: ButtonTone.accent,
        onPressed: editingOrder ? null : onMagnify,
      ),
      const SizedBox(width: 14),
      _arrow(
        'grid.next',
        Glyph.arrowRight,
        diameter,
        page < pageCount - 1 ? onNext : null,
        page < pageCount - 1 ? onNext : null,
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
    required this.height,
    required this.width,
    required this.editingOrder,
    required this.onDoneEditingOrder,
  });

  final int page;
  final int pageCount;
  final double height;
  final double width;
  final GlobalKey settingsAnchor;
  final GlobalKey profileAnchor;
  final List<ChannelSpec> channels;
  final L label;

  /// En modo de ordenar canales, los puntos de pagina dejan sitio al boton de
  /// «Hecho», la otra forma de salir del modo (la primera es volver a pulsar
  /// el lapiz del carril).
  final bool editingOrder;
  final VoidCallback onDoneEditingOrder;

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
      art: spec.art,
    );

    final settings = _spec('settings');
    final profile = _spec('profile');

    // En vertical los dos atajos se reparten el ancho que dejan los puntos de
    // pagina, para no desbordar en una pantalla estrecha. En horizontal el
    // lienzo siempre mide 1280: cada boton ocupa lo suyo, como siempre.
    final shortcut = Layout.of(context).tall
        ? BoxConstraints.loose(Size(math.max(120, (width - 90) / 2), height))
        : null;
    Widget fit(Widget child) => shortcut == null
        ? child
        : ConstrainedBox(constraints: shortcut, child: child);

    return Row(
      children: [
        fit(
          KeyedSubtree(
            key: settingsAnchor,
            child: IbashoButton(
              label: settings.label(label),
              glyph: settings.glyph,
              height: height,
              cue: null,
              onPressed: () => open(settingsAnchor, settings),
            ),
          ),
        ),
        const Spacer(),
        editingOrder
            ? IbashoButton(
                key: const ValueKey<String>('reorder-channels.done'),
                label: label.reorderChannelsDone,
                tone: ButtonTone.accent,
                height: height,
                cue: null,
                onPressed: onDoneEditingOrder,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < pageCount; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    _PageDot(active: i == page, accent: skin.accent),
                  ],
                ],
              ),
        const Spacer(),
        fit(
          KeyedSubtree(
            key: profileAnchor,
            child: IbashoButton(
              label: profile.label(label),
              glyph: profile.glyph,
              height: height,
              cue: null,
              onPressed: () => open(profileAnchor, profile),
            ),
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
        color: active ? accent : skin.hairline,
        border: Border.all(
          color: active ? Color.lerp(accent, T.dusk, .4)! : skin.hairline,
        ),
      ),
    );
  }
}
