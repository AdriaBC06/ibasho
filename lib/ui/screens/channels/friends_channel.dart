// Ibasho — canal de amigos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/social.dart';
import '../../../backend/tama.dart';
import '../../../core/birthday.dart';
import '../../../core/device.dart';
import '../../../core/friend_code.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/friends.dart';
import '../../../state/people.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../social/business_card.dart';
import '../../social/social_widgets.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/pressable.dart';
import '../../layout.dart';
import '../../widgets/slot_tile.dart';
import '../channel_grid.dart';
import '../channel_route.dart';
import '../friends/add_friend_screen.dart';
import '../friends/friend_profile_screen.dart';

/// Ranuras por pagina: rejilla de 6x2, como la de Tamas. En vertical son 3
/// columnas y las filas que quepan.
const int _columns = 6;
const int _perPage = _columns * 2;
const int _tallColumns = 2;

enum FriendsTab { friends, incoming, outgoing }

/// El canal de amigos, montado como el entorno: dos pantallas.
///
/// Arriba, lo tuyo: la tarjeta de visita, el codigo de amigo grande con su
/// boton de copiar y tu estado. Abajo, la rejilla paginada de amigos, con
/// pestañas para las solicitudes recibidas y mandadas.
class FriendsChannel extends ConsumerStatefulWidget {
  const FriendsChannel({super.key, this.initialTab});

  final FriendsTab? initialTab;

  @override
  ConsumerState<FriendsChannel> createState() => _FriendsChannelState();
}

class _FriendsChannelState extends ConsumerState<FriendsChannel> {
  late FriendsTab _tab =
      widget.initialTab ??
      (ref.read(friendsProvider).incoming.isNotEmpty ? FriendsTab.incoming : FriendsTab.friends);
  int _page = 0;

  /// Ranuras por pagina de la composicion en curso, que en vertical depende
  /// del alto.
  int _slots = _perPage;
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);
  final GlobalKey _cardKey = GlobalKey(debugLabel: 'friends.businessCard');
  bool _exporting = false;

  int _itemCount(FriendsState state) => switch (_tab) {
    FriendsTab.friends => state.friends.length + (state.full ? 0 : 1),
    FriendsTab.incoming => state.incoming.length,
    FriendsTab.outgoing => state.outgoing.length,
  };

  int _pageCount(FriendsState state) => math.max(1, (_itemCount(state) / _slots).ceil());

  void _goToPage(int page) {
    final target = page.clamp(0, _pageCount(ref.read(friendsProvider)) - 1);
    if (target == _page) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _page = target);
  }

  void _setTab(FriendsTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _page = 0;
    });
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheel) < const Duration(milliseconds: 260)) return;
    if (event.scrollDelta.dy.abs() < 2 && event.scrollDelta.dx.abs() < 2) return;
    _lastWheel = now;
    _goToPage(_page + ((event.scrollDelta.dy + event.scrollDelta.dx) > 0 ? 1 : -1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageDown) {
      _goToPage(_page + 1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _goToPage(_page - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _addFriend() => pushChannelPage<void>(context, (_) => const AddFriendScreen());

  void _openFriend(String account) =>
      pushChannelPage<void>(context, (_) => FriendProfileScreen(accountId: account));

  Future<void> _copyCode(String code) async {
    final l = L.of(context)!;
    await Clipboard.setData(ClipboardData(text: FriendCode.format(code)));
    if (!mounted) return;
    showIbashoToast(context, l.friendsCodeCopied);
  }

  Future<void> _exportCard() async {
    if (_exporting) return;
    final l = L.of(context)!;
    final username = ref.read(sessionProvider).username;
    setState(() => _exporting = true);
    try {
      final png = await renderBusinessCard(_cardKey);
      if (Device.isAndroid) {
        // En el movil no hay dialogo de guardar: se comparte.
        final code = ref.read(friendsProvider).code;
        await shareBusinessCard(png, username, l.friendsCardShareText(code == null ? '' : FriendCode.format(code)));
        return;
      }
      final path = await saveBusinessCard(png, username);
      if (!mounted) return;
      AudioService.instance.play(Sfx.chime);
      showIbashoToast(context, l.friendsCardSaved(path));
    } catch (e) {
      debugPrint('Ibasho: no se ha podido exportar la tarjeta ($e)');
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.friendsCardError, isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _run(Future<FriendFailure?> action, {String? success}) async {
    final l = L.of(context)!;
    final failure = await action;
    if (!mounted) return;
    if (failure == null) {
      if (success != null) {
        AudioService.instance.play(Sfx.open);
        showIbashoToast(context, success);
      }
      return;
    }
    AudioService.instance.play(Sfx.error);
    showIbashoToast(context, friendFailureText(l, failure), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final state = ref.watch(friendsProvider);
    final pages = _pageCount(state);
    if (_page >= pages) _page = pages - 1;

    final layout = Layout.of(context);
    final tall = layout.tall;
    final dots = [
      for (var i = 0; i < pages; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        _PageDot(active: i == _page),
      ],
    ];

    return ChannelScaffold(
      title: l.friendsTitle,
      glyph: Glyph.friends,
      trailing: state.friends.isEmpty
          ? null
          : Text(
              l.friendsCount(state.friends.length, maxFriendsPerAccount),
              style: Ty.numeral(layout.pick(19, 16), color: Ty.inkSoft),
            ),
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: LayoutBuilder(builder: (context, box) {
          final top = tall ? math.max(286.0, math.min(360.0, box.maxHeight * .45)) : 300.0;
          return Column(
            children: [
              const SizedBox(height: 14),
              SizedBox(
                height: top,
                child: ScreenPanel(
                  child: _MyCard(
                    cardKey: _cardKey,
                    code: state.code,
                    exporting: _exporting,
                    onCopy: state.code == null ? null : () => _copyCode(state.code!),
                    onExport: _exportCard,
                    onAdd: _addFriend,
                  ),
                ),
              ),
              // En vertical las pestañas se llevan su propia fila: con las
              // flechas al lado no cabrian.
              if (tall) ...[
                const SizedBox(height: 10),
                _Tabs(tab: _tab, state: state, onChanged: _setTab),
              ],
              SizedBox(
                height: layout.pick(54, 56),
                child: Row(
                  children: [
                    IconPill(
                      glyph: Glyph.arrowLeft,
                      diameter: layout.pill,
                      onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
                    ),
                    const Spacer(),
                    if (!tall) ...[
                      _Tabs(tab: _tab, state: state, onChanged: _setTab),
                      const SizedBox(width: 18),
                    ],
                    ...dots,
                    const Spacer(),
                    IconPill(
                      glyph: Glyph.arrowRight,
                      diameter: layout.pill,
                      onPressed: _page < pages - 1 ? () => _goToPage(_page + 1) : null,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Listener(
                  onPointerSignal: _onWheel,
                  child: PageSwipe(
                    onPrevious: () => _goToPage(_page - 1),
                    onNext: () => _goToPage(_page + 1),
                    child: ScreenPanel(
                    child: LayoutBuilder(
                      builder: (context, box) => _PagedSlots(
                        size: box.biggest,
                        page: _page,
                        pages: pages,
                        tall: tall,
                        // Las ranuras de amigos llevan cosas dentro (el
                        // piloto, y dos botones en las solicitudes): en
                        // vertical van de dos en dos para que todo eso se
                        // pueda tocar.
                        columns: tall ? (_tab == FriendsTab.friends ? _tallColumns : 1) : _columns,
                        // Una solicitud lleva dos botones dentro: en vertical
                        // ocupa una tira ancha, no una baldosa.
                        rowHeight: tall && _tab != FriendsTab.friends ? 78.0 : null,
                        count: _itemCount(state),
                        onSlots: (slots) {
                          if (slots == _slots) return;
                          final first = _page * _slots;
                          _slots = slots;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _page = first ~/ slots);
                          });
                        },
                        empty: switch (_tab) {
                          FriendsTab.friends => null,
                          FriendsTab.incoming => l.friendsIncomingEmpty,
                          FriendsTab.outgoing => l.friendsOutgoingEmpty,
                        },
                        builder: (index, width, height) => switch (_tab) {
                          FriendsTab.friends =>
                            index == 0 && !state.full
                                ? _AddTile(width: width, height: height, onPressed: _addFriend)
                                : _FriendTile(
                                    friendship: state.friends[index - (state.full ? 0 : 1)],
                                    width: width,
                                    height: height,
                                    onPressed: () => _openFriend(
                                      state.friends[index - (state.full ? 0 : 1)].accountId,
                                    ),
                                  ),
                          FriendsTab.incoming => _RequestTile(
                            request: state.incoming[index],
                            incoming: true,
                            width: width,
                            height: height,
                            onAccept: () => _run(
                              ref
                                  .read(friendsProvider.notifier)
                                  .accept(state.incoming[index].accountId),
                              success: l.friendsAccepted,
                            ),
                            onDismiss: () => _run(
                              ref
                                  .read(friendsProvider.notifier)
                                  .reject(state.incoming[index].accountId),
                            ),
                          ),
                          FriendsTab.outgoing => _RequestTile(
                            request: state.outgoing[index],
                            incoming: false,
                            width: width,
                            height: height,
                            onDismiss: () => _run(
                              ref
                                  .read(friendsProvider.notifier)
                                  .cancel(state.outgoing[index].accountId),
                            ),
                          ),
                        },
                      ),
                    ),
                  ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
          }),
        ),
      ),
    );
  }
}

String friendFailureText(L l, FriendFailure failure) => switch (failure) {
  FriendFailure.yourListFull => l.friendsErrorYourListFull(maxFriendsPerAccount),
  FriendFailure.theirListFull => l.friendsErrorTheirListFull(maxFriendsPerAccount),
  FriendFailure.network => l.loginErrorNetwork,
  FriendFailure.rejected => l.friendsErrorRejected,
};

// --- Pantalla de arriba -------------------------------------------------------

class _MyCard extends ConsumerWidget {
  const _MyCard({
    required this.cardKey,
    required this.code,
    required this.exporting,
    required this.onCopy,
    required this.onExport,
    required this.onAdd,
  });

  final GlobalKey cardKey;
  final String? code;
  final bool exporting;
  final VoidCallback? onCopy;
  final VoidCallback onExport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final profile = ref.watch(profileProvider.select((p) => p.profile));
    final username = ref.watch(sessionProvider.select((s) => s.username));
    final tama = ref.watch(tamasProvider.select((t) => t.profileTama));
    final now = ref.watch(moodClockProvider);
    final party = profile != null && isBirthdayToday(profile, now);

    final layout = Layout.of(context);
    final tall = layout.tall;
    final cardWidth = tall ? math.min(layout.width - 180, 150.0) : 438.0;

    final code = this.code;
    final codeRow = Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              code == null ? l.friendsCodePending : FriendCode.format(code),
              key: const ValueKey<String>('friends.code'),
              style: code == null
                  ? Ty.lead.copyWith(color: Ty.inkSoft)
                  : Ty.numeral(tall ? 26 : 44, weight: FontWeight.w700)
                      .copyWith(letterSpacing: 1),
            ),
          ),
        ),
        SizedBox(width: tall ? 8 : 16),
        IconPill(
          key: const ValueKey<String>('friends.copy'),
          glyph: Glyph.copy,
          diameter: 44,
          semanticLabel: l.friendsCopyCode,
          onPressed: onCopy,
        ),
      ],
    );

    // En vertical: la tarjeta pequeña con el codigo al lado, las acciones
    // debajo y el estado al pie.
    if (tall) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: cardWidth,
                  height: cardWidth * businessCardSize.height / businessCardSize.width,
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: cardKey,
                      child: BusinessCard(
                        displayName: profile?.displayName ?? username,
                        accent: skin.accent,
                        code: code ?? '',
                        caption: l.friendsYourCode,
                        tama: tama,
                        wear: party ? TamaWear.partyHat : TamaWear.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.friendsYourCode, style: Ty.label),
                      const SizedBox(height: 4),
                      codeRow,
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: IbashoButton(
                    key: const ValueKey<String>('friends.add'),
                    label: l.friendsAdd,
                    glyph: Glyph.personPlus,
                    tone: ButtonTone.accent,
                    height: 48,
                    expand: true,
                    cue: null,
                    onPressed: onAdd,
                  ),
                ),
                const SizedBox(width: 12),
                IconPill(
                  key: const ValueKey<String>('friends.export'),
                  glyph: Glyph.download,
                  diameter: 48,
                  semanticLabel: l.friendsExportCard,
                  cue: null,
                  onPressed: exporting ? null : onExport,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _PresencePicker(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 26, 32, 26),
      child: _Split(
        tall: tall,
        children: [
          // La tarjeta se maqueta a su tamaño de diseño y se escala: el PNG
          // sale de este mismo RepaintBoundary a mas resolucion.
          SizedBox(
            width: cardWidth,
            height: cardWidth * businessCardSize.height / businessCardSize.width,
            child: FittedBox(
              child: RepaintBoundary(
                key: cardKey,
                child: BusinessCard(
                  displayName: profile?.displayName ?? username,
                  accent: skin.accent,
                  code: code ?? '',
                  caption: l.friendsYourCode,
                  tama: tama,
                  wear: party ? TamaWear.partyHat : TamaWear.none,
                ),
              ),
            ),
          ),
          SizedBox(width: tall ? 14 : 38),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!tall) ...[
                  Text(l.friendsYourCode, style: Ty.label),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          code == null ? l.friendsCodePending : FriendCode.format(code),
                          key: const ValueKey<String>('friends.code'),
                          style: code == null
                              ? Ty.lead.copyWith(color: Ty.inkSoft)
                              : Ty.numeral(tall ? 24 : 44, weight: FontWeight.w700)
                                  .copyWith(letterSpacing: 1),
                        ),
                      ),
                    ),
                    SizedBox(width: tall ? 8 : 16),
                    IconPill(
                      key: const ValueKey<String>('friends.copy'),
                      glyph: Glyph.copy,
                      diameter: 44,
                      semanticLabel: l.friendsCopyCode,
                      onPressed: onCopy,
                    ),
                  ],
                ),
                SizedBox(height: tall ? 12 : 18),
                Row(
                  children: [
                    Flexible(
                      child: IbashoButton(
                        key: const ValueKey<String>('friends.add'),
                        label: l.friendsAdd,
                        glyph: Glyph.personPlus,
                        tone: ButtonTone.accent,
                        height: 46,
                        minWidth: tall ? 0 : 190,
                        cue: null,
                        onPressed: onAdd,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (tall)
                      IconPill(
                        key: const ValueKey<String>('friends.export'),
                        glyph: Glyph.download,
                        diameter: 46,
                        semanticLabel: l.friendsExportCard,
                        cue: null,
                        onPressed: exporting ? null : onExport,
                      )
                    else
                      Flexible(
                        child: IbashoButton(
                          key: const ValueKey<String>('friends.export'),
                          label: exporting ? l.friendsExporting : l.friendsExportCard,
                          glyph: Glyph.download,
                          height: 46,
                          cue: null,
                          onPressed: exporting ? null : onExport,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: tall ? 12 : 20),
                if (!tall) ...[
                  Text(l.presenceTitle, style: Ty.label),
                  const SizedBox(height: 8),
                ],
                const _PresencePicker(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Los cuatro estados que se pueden elegir, como pastillas con su piloto.
class _PresencePicker extends ConsumerWidget {
  const _PresencePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final status = ref.watch(presenceProvider);

    final tall = Layout.of(context).tall;

    Widget pill(PresenceMode mode) => Pressable(
              key: ValueKey<String>('presence.${mode.name}'),
              semanticLabel: presenceModeLabel(l, mode),
              onPressed: mode == status.mode
                  ? null
                  : () => unawaited(ref.read(presenceProvider.notifier).setMode(mode)),
              builder: (context, state) {
                final selected = mode == status.mode;
                return FocusRing(
                  visible: state.focus,
                  radius: 18,
                  child: Transform.translate(
                    offset: Offset(0, -1.5 * state.hover + 1.5 * state.press),
                    child: SizedBox(
                      height: 36,
                      child: GlossSurface(
                        radius: 18,
                        recessed: !selected,
                        tint: selected ? skin.accentWash : null,
                        elevation: selected ? 1.2 : 0,
                        borderWidth: selected ? 2 : 1,
                        borderColor: selected
                            ? skin.accentDeep
                            : Color.lerp(skin.hairline, skin.accent, state.hover)!,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PresenceLight(
                              color: presenceModeColor(mode),
                              lit: mode != PresenceMode.invisible,
                              size: 12,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                presenceModeLabel(l, mode),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Ty.caption.copyWith(
                                  color: selected ? skin.accentDeep : Ty.ink,
                                  fontWeight: FontWeight.w500,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );

    // Los cuatro estados: en fila cuando hay ancho; en dos filas de dos en
    // vertical, para que se lea el nombre entero de cada uno.
    if (tall) {
      return Column(
        children: [
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: pill(PresenceMode.values[row * 2 + i])),
                ],
              ],
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (final mode in PresenceMode.values) ...[
          if (mode.index > 0) const SizedBox(width: 8),
          Flexible(child: pill(mode)),
        ],
      ],
    );
  }
}

// --- Carril ---------------------------------------------------------------------

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.state, required this.onChanged});

  final FriendsTab tab;
  final FriendsState state;
  final ValueChanged<FriendsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoSegmented<FriendsTab>(
      key: const ValueKey<String>('friends.tabs'),
      height: 40,
      options: [
        (FriendsTab.friends, l.friendsTabFriends(state.friends.length)),
        (FriendsTab.incoming, l.friendsTabIncoming(state.incoming.length)),
        (FriendsTab.outgoing, l.friendsTabOutgoing(state.outgoing.length)),
      ],
      value: tab,
      onChanged: onChanged,
    );
  }
}

class _PageDot extends StatelessWidget {
  const _PageDot({required this.active});

  final bool active;

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
        color: active ? skin.accent : skin.hairline,
        border: Border.all(color: active ? skin.accentDeep : skin.hairline),
      ),
    );
  }
}

// --- Pantalla de abajo ------------------------------------------------------------

typedef _SlotBuilder = Widget Function(int index, double width, double height);

/// Paginas de ranuras que se desplazan con el sobrepaso corto de la rejilla de
/// canales. Las ranuras sin nada se ven hundidas.
class _PagedSlots extends StatefulWidget {
  const _PagedSlots({
    required this.size,
    required this.page,
    required this.pages,
    required this.tall,
    required this.columns,
    required this.rowHeight,
    required this.count,
    required this.builder,
    required this.onSlots,
    this.empty,
  });

  final Size size;
  final int page;
  final int pages;
  final bool tall;
  final int columns;
  final double? rowHeight;
  final int count;
  final ValueChanged<int> onSlots;
  final _SlotBuilder builder;

  /// Mensaje cuando no hay nada que ensenar.
  final String? empty;

  @override
  State<_PagedSlots> createState() => _PagedSlotsState();
}

class _PagedSlotsState extends State<_PagedSlots> with SingleTickerProviderStateMixin {
  static const double _padH = 28;
  static const double _padV = 22;
  static const double _gapH = 22;
  static const double _gapV = 18;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: T.page,
    value: 1,
  );
  late double _from = widget.page.toDouble();
  late double _to = widget.page.toDouble();

  @override
  void didUpdateWidget(_PagedSlots old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) {
      _from = _current;
      _to = widget.page.toDouble();
      _slide
        ..duration = IbashoSkin.of(context).motion(T.page)
        ..forward(from: 0);
    }
  }

  double get _current {
    final t = IbashoSkin.of(context).reducedMotion ? 1.0 : pageSlideCurve.transform(_slide.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.size.width;
    final height = widget.size.height;
    final columns = widget.columns;
    final padH = widget.tall ? 16.0 : _padH;
    final gapH = widget.tall ? 12.0 : _gapH;
    final available = (width - padH * 2 - gapH * (columns - 1)) / columns;
    final rowHeight = widget.rowHeight;
    final rows = widget.tall
        ? math.max(
            rowHeight == null ? 2 : 1,
            ((height - _padV * 2 + _gapV) / ((rowHeight ?? available / 1.18) + _gapV)).floor(),
          )
        : 2;
    final tileH = rowHeight ??
        (widget.tall
            ? math.min(available / 1.18, (height - _padV * 2 - _gapV * (rows - 1)) / rows)
            : (height - _padV * 2 - _gapV) / 2);
    final tileW = rowHeight == null ? math.min(available, tileH * 1.18) : available;
    final perPage = columns * rows;
    widget.onSlots(perPage);

    Widget slot(int index) => index < widget.count
        ? widget.builder(index, tileW, tileH)
        : EmptySlot(width: tileW, height: tileH);

    return Stack(
      children: [
        ClipRect(
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, _) => Transform.translate(
              offset: Offset(-_current * width, 0),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: width * widget.pages,
                child: Row(
                  children: [
                    for (var page = 0; page < widget.pages; page++)
                      SizedBox(
                        width: width,
                        height: height,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var row = 0; row < rows; row++) ...[
                                if (row > 0) const SizedBox(height: _gapV),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var col = 0; col < columns; col++) ...[
                                      if (col > 0) SizedBox(width: gapH),
                                      slot(page * perPage + row * columns + col),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.count == 0 && widget.empty != null)
          Center(
            child: GlossSurface(
              radius: 22,
              elevation: 1.2,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              child: Text(widget.empty!, style: Ty.body.copyWith(color: Ty.inkSoft)),
            ),
          ),
      ],
    );
  }
}

/// Un amigo en su ranura: su Tama, su nombre y el piloto de su presencia.
class _FriendTile extends ConsumerWidget {
  const _FriendTile({
    required this.friendship,
    required this.width,
    required this.height,
    required this.onPressed,
  });

  final Friendship friendship;
  final double width;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final account = friendship.accountId;
    final card = ref.watch(cardOfProvider(account)).valueOrNull;
    final presence = ref.watch(presenceOfProvider(account)).valueOrNull ?? Presence.offline;
    final profile = ref.watch(friendProfileProvider(account)).valueOrNull;
    final now = ref.watch(moodClockProvider);
    final party = profile != null && isBirthdayToday(profile, now);
    final name = card?.displayName ?? '…';

    return SlotTile(
      key: ValueKey<String>('friends.friend.$account'),
      width: width,
      height: height,
      tint: card == null ? null : Color.lerp(card.accent, T.shellTop, .9),
      onPressed: onPressed,
      semanticLabel: '$name · ${presenceLabel(l, presence.state)}',
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: IgnorePointer(
                  child: OverflowBox(
                    alignment: const Alignment(0, .35),
                    maxHeight: height,
                    maxWidth: height,
                    child: CardTama(
                      accountId: account,
                      card: card,
                      size: height * .98,
                      wear: party ? TamaWear.partyHat : TamaWear.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.caption.copyWith(
                    color: Ty.ink,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          Positioned(top: 9, right: 10, child: PresenceLight.of(presence.state, size: 15)),
          if (party)
            const Positioned(
              top: 8,
              left: 10,
              child: GlyphIcon(Glyph.cake, size: 17, color: T.warn),
            ),
        ],
      ),
    );
  }
}

/// Una solicitud: el Tama y el nombre de la persona, con aceptar y rechazar
/// (recibidas) o retirar (mandadas).
class _RequestTile extends ConsumerWidget {
  const _RequestTile({
    required this.request,
    required this.incoming,
    required this.width,
    required this.height,
    required this.onDismiss,
    this.onAccept,
  });

  final FriendRequest request;
  final bool incoming;
  final double width;
  final double height;
  final VoidCallback? onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final account = request.accountId;
    final card = ref.watch(cardOfProvider(account)).valueOrNull;
    final name = card?.displayName ?? '…';

    final accept = onAccept == null
        ? null
        : IconPill(
            key: ValueKey<String>('friends.accept.$account'),
            glyph: Glyph.check,
            diameter: 34,
            tone: ButtonTone.accent,
            semanticLabel: l.friendsAccept,
            cue: null,
            onPressed: onAccept,
          );
    final dismiss = IconPill(
      key: ValueKey<String>('friends.dismiss.$account'),
      glyph: Glyph.cross,
      diameter: 34,
      semanticLabel: incoming ? l.friendsReject : l.friendsCancel,
      onPressed: onDismiss,
    );

    // Ranura ancha (vertical): el Tama a la izquierda, el nombre al centro y
    // los botones a la derecha, todos del tamaño que se toca.
    if (width > height * 1.5) {
      return SlotTile(
        key: ValueKey<String>('friends.request.$account'),
        width: width,
        height: height,
        tint: card == null ? null : Color.lerp(card.accent, T.shellTop, .9),
        semanticLabel: name,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              IgnorePointer(
                child: SizedBox(
                  width: height - 16,
                  height: height - 12,
                  child: CardTama(accountId: account, card: card, size: height - 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.body.copyWith(color: Ty.ink, fontWeight: FontWeight.w500),
                    ),
                    if (!incoming) Text(l.friendsPending, style: Ty.micro),
                  ],
                ),
              ),
              if (accept != null) ...[accept, const SizedBox(width: 8)],
              dismiss,
            ],
          ),
        ),
      );
    }

    return SlotTile(
      key: ValueKey<String>('friends.request.$account'),
      width: width,
      height: height,
      tint: card == null ? null : Color.lerp(card.accent, T.shellTop, .9),
      semanticLabel: name,
      child: Column(
        children: [
          Expanded(
            child: IgnorePointer(
              child: OverflowBox(
                alignment: const Alignment(0, .5),
                maxHeight: height * .8,
                maxWidth: height * .8,
                child: CardTama(accountId: account, card: card, size: height * .7),
              ),
            ),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ty.caption.copyWith(color: Ty.ink, fontWeight: FontWeight.w500, height: 1.1),
          ),
          if (!incoming) Text(l.friendsPending, style: Ty.micro.copyWith(height: 1.2)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (accept != null) ...[accept, const SizedBox(width: 10)],
                dismiss,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La ranura de añadir: hundida como un canal libre, con la persona y el mas.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.width, required this.height, required this.onPressed});

  final double width;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    return Pressable(
      key: const ValueKey<String>('friends.addTile'),
      cue: null,
      onPressed: onPressed,
      semanticLabel: l.friendsAdd,
      builder: (context, state) => Transform.translate(
        offset: Offset(0, 1.5 * state.press),
        child: FocusRing(
          visible: state.focus,
          radius: T.tileRadius,
          child: SizedBox(
            width: width,
            height: height,
            child: GlossSurface(
              radius: T.tileRadius,
              recessed: true,
              borderColor: Color.lerp(skin.hairline, skin.accent, state.hover)!,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlyphIcon(
                    Glyph.personPlus,
                    size: height * (tall ? .28 : .3),
                    color: Color.lerp(Ty.inkSoft, skin.accentDeep, state.hover)!,
                    strokeWidth: 2.2,
                  ),
                  SizedBox(height: height * (tall ? .05 : .06)),
                  Flexible(
                    child: Text(
                    l.friendsAdd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.caption.copyWith(
                      color: Color.lerp(Ty.inkSoft, skin.accentDeep, state.hover),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Los dos bloques de la pantalla de arriba: en fila si hay ancho, en columna
/// si no.
class _Split extends StatelessWidget {
  const _Split({required this.tall, required this.children});

  final bool tall;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => tall
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: children.first),
          const SizedBox(height: 10),
          Expanded(child: children.last),
        ])
      : Row(children: children);
}
