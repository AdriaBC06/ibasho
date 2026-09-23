// Ibasho — canal de Tamas: todos los de la cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/tama.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../state/tamas.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../tama/accent_prompt.dart';
import '../../tama/tama_text.dart';
import '../../tama/tama_view.dart';
import '../../tama/tama_widgets.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/panel.dart';
import '../../widgets/pressable.dart';
import '../../layout.dart';
import '../../widgets/slot_tile.dart';
import '../channel_grid.dart';
import '../channel_route.dart';
import '../tama/tama_creator_screen.dart';
import '../tama/tama_room_screen.dart';

/// Ranuras por pagina: rejilla de 6x2 en horizontal. En vertical son 3
/// columnas y las filas que quepan.
const int _columns = 6;
const int _perPage = _columns * 2;
const int _tallColumns = 3;

/// El canal de Tamas, montado como el propio entorno: dos pantallas.
///
/// Arriba, el escaparate con el Tama elegido vivo sobre su peana y lo que se
/// puede hacer con el. Abajo, la rejilla manipulable: un Tama por ranura, la
/// ranura de crear y ranuras libres hundidas, paginada con flechas, rueda y
/// teclado. Tocar una ranura la elige; tocar la elegida entra en su habitacion.
class TamasChannel extends ConsumerStatefulWidget {
  const TamasChannel({super.key});

  @override
  ConsumerState<TamasChannel> createState() => _TamasChannelState();
}

class _TamasChannelState extends ConsumerState<TamasChannel> {
  String? _selectedId;
  int _page = 0;
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  /// El elegido, o el de perfil, o el primero.
  /// Ranuras por pagina de la composicion en curso. En vertical depende de
  /// cuantas filas caben, asi que la mide la rejilla y la deja aqui.
  int _slots = _perPage;

  Tama? _selected(TamasState state) =>
      state.byId(_selectedId) ??
      state.profileTama ??
      (state.tamas.isEmpty ? null : state.tamas.first);

  int _pageCount(TamasState state) {
    final slots = state.tamas.length + (state.full ? 0 : 1);
    return math.max(1, (slots / _slots).ceil());
  }

  void _select(Tama tama) {
    if (_selected(ref.read(tamasProvider))?.id == tama.id) {
      _visit(tama);
      return;
    }
    AudioService.instance.play(Sfx.tick);
    setState(() => _selectedId = tama.id);
  }

  void _visit(Tama tama) => pushChannelPage<void>(
        context,
        (_) => TamaRoomScreen(tamaId: tama.id),
      );

  void _create() => pushChannelPage<void>(context, (_) => const TamaCreatorScreen());

  void _goToPage(int page) {
    final target = page.clamp(0, _pageCount(ref.read(tamasProvider)) - 1);
    if (target == _page) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _page = target);
  }

  /// Mueve la eleccion con el teclado, pasando de pagina si hace falta.
  void _step(int delta) {
    final state = ref.read(tamasProvider);
    if (state.tamas.isEmpty) return;
    final current = _selected(state);
    final index = current == null ? 0 : state.tamas.indexWhere((t) => t.id == current.id);
    final next = (index + delta).clamp(0, state.tamas.length - 1);
    if (next == index) return;
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _selectedId = state.tamas[next].id;
      _page = next ~/ _slots;
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
    if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _step(_slots ~/ 2);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _step(-(_slots ~/ 2));
    } else if (key == LogicalKeyboardKey.pageDown) {
      _goToPage(_page + 1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _goToPage(_page - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final state = ref.watch(tamasProvider);
    final selected = _selected(state);
    final pages = _pageCount(state);
    if (_page >= pages) _page = pages - 1;

    final layout = Layout.of(context);

    return ChannelScaffold(
      title: l.tamasTitle,
      glyph: Glyph.tama,
      trailing: state.tamas.isEmpty
          ? null
          : Text(
              l.tamasCount(state.tamas.length, maxTamasPerAccount),
              style: Ty.numeral(layout.pick(19, 16), color: Ty.inkSoft),
            ),
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: LayoutBuilder(builder: (context, box) {
          final showcase = layout.tall
              ? math.max(210.0, math.min(330.0, box.maxHeight * .40))
              : 290.0;
          return Column(
            children: [
              const SizedBox(height: 14),
              SizedBox(
                height: showcase,
                child: ScreenPanel(
                  child: !state.loaded
                      ? Center(child: Text(l.loading, style: Ty.lead))
                      : _Showcase(
                          tama: selected,
                          isProfile: selected != null && selected.id == state.profileTamaId,
                          onVisit: selected == null ? null : () => _visit(selected),
                          onCreate: _create,
                        ),
                ),
              ),
              SizedBox(
                height: layout.pick(42, 56),
                child: Row(
                  children: [
                    IconPill(
                      glyph: Glyph.arrowLeft,
                      diameter: layout.pill,
                      onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
                    ),
                    const Spacer(),
                    for (var i = 0; i < pages; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      _PageDot(active: i == _page),
                    ],
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
                          tall: layout.tall,
                          tamas: state.tamas,
                          showCreate: state.loaded && !state.full,
                          selectedId: selected?.id,
                          profileId: state.profileTamaId,
                          onSelect: _select,
                          onCreate: _create,
                          onSlots: (slots) {
                            if (slots == _slots) return;
                            // Al girar el movil cambian las ranuras por
                            // pagina: se conserva la que se estaba mirando.
                            final first = _page * _slots;
                            _slots = slots;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _page = first ~/ slots);
                            });
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

// --- Pantalla de arriba -------------------------------------------------------

class _Showcase extends ConsumerWidget {
  const _Showcase({
    required this.tama,
    required this.isProfile,
    required this.onVisit,
    required this.onCreate,
  });

  final Tama? tama;
  final bool isProfile;
  final VoidCallback? onVisit;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = IbashoSkin.of(context);
    // El escaparate cambia con un fundido corto: lo audaz se queda para abrir
    // canales.
    return AnimatedSwitcher(
      duration: skin.motion(const Duration(milliseconds: 200)),
      switchInCurve: skin.curve(Curves.easeOut),
      switchOutCurve: skin.curve(Curves.easeIn),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey<String?>(tama?.id),
        child: tama == null
            ? _EmptyShowcase(onCreate: onCreate)
            : _TamaShowcase(tama: tama!, isProfile: isProfile, onVisit: onVisit!),
      ),
    );
  }
}

class _TamaShowcase extends ConsumerWidget {
  const _TamaShowcase({required this.tama, required this.isProfile, required this.onVisit});

  final Tama tama;
  final bool isProfile;
  final VoidCallback onVisit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final reading = TamaMoodReading.of(tama, ref.watch(moodClockProvider));
    final isCreator = tama.createdBy(ref.watch(sessionProvider.select((s) => s.accountId)));

    final layout = Layout.of(context);
    final tall = layout.tall;

    return LayoutBuilder(builder: (context, box) {
      // El escaparate aprovecha el alto que le toque: en un movil grande el
      // Tama se ve casi como en su habitacion.
      final stage = tall
          ? math.min(box.maxHeight * .54, math.min(box.maxWidth * .36, 180.0))
          : 236.0;

      final actions = Row(
        children: [
          _Fill(
            tall: tall,
            child: IbashoButton(
              key: const ValueKey<String>('tamas.visit'),
              label: l.tamaVisit,
              glyph: Glyph.arrowRight,
              tone: ButtonTone.accent,
              height: 48,
              expand: tall,
              minWidth: tall ? 0 : 170,
              cue: null,
              onPressed: onVisit,
            ),
          ),
          if (!isProfile) ...[
            const SizedBox(width: 12),
            if (tall)
              IconPill(
                key: const ValueKey<String>('tamas.setProfile'),
                glyph: Glyph.portrait,
                diameter: 48,
                semanticLabel: l.tamaRoomSetProfile,
                onPressed: () => unawaited(putTamaOnProfile(context, ref, tama)),
              )
            else
              IbashoButton(
                key: const ValueKey<String>('tamas.setProfile'),
                label: l.tamaRoomSetProfile,
                glyph: Glyph.portrait,
                height: 48,
                onPressed: () => unawaited(putTamaOnProfile(context, ref, tama)),
              ),
          ],
          if (isCreator) ...[
            const SizedBox(width: 12),
            if (tall)
              IconPill(
                key: const ValueKey<String>('tamas.edit'),
                glyph: Glyph.pencil,
                diameter: 48,
                semanticLabel: l.tamaRoomEdit,
                cue: null,
                onPressed: () => pushChannelPage<void>(
                  context,
                  (_) => TamaCreatorScreen(tamaId: tama.id),
                ),
              )
            else
              IbashoButton(
                key: const ValueKey<String>('tamas.edit'),
                label: l.tamaRoomEdit,
                glyph: Glyph.pencil,
                height: 48,
                cue: null,
                onPressed: () => pushChannelPage<void>(
                  context,
                  (_) => TamaCreatorScreen(tamaId: tama.id),
                ),
              ),
          ],
        ],
      );

      final identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  tama.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tall ? Ty.title : Ty.display,
                ),
              ),
              if (isProfile) ...[
                SizedBox(width: tall ? 8 : 16),
                Flexible(child: _ProfileBadge(label: l.tamaProfileBadge)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tall
                ? personalityLabel(l, tama.personality)
                : '${personalityLabel(l, tama.personality)} · ${personalityHint(l, tama.personality)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ty.caption.copyWith(fontSize: 15),
          ),
          SizedBox(height: tall ? 12 : 18),
          Row(
            children: [
              Flexible(child: TamaMoodMeter(value: reading.value, width: tall ? 120 : 200)),
              SizedBox(width: tall ? 10 : 14),
              Flexible(
                child: Text(
                  moodLabel(l, reading.mood),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body.copyWith(color: skin.accentDeep),
                ),
              ),
            ],
          ),
          if (!tall) ...[
            SizedBox(height: tall ? 14 : 26),
            actions,
            const SizedBox(height: 10),
            Text(l.tamasSelectHint, style: Ty.micro),
          ],
        ],
      );

      final showcase = Row(
        children: [
          SizedBox(
            width: tall ? stage + 14 : 400,
            child: Center(
              child: TamaOnStand(
                key: const ValueKey<String>('tamas.showcase'),
                tama: tama,
                size: stage,
                joy: reading.joy,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, tall ? 6 : 30, tall ? 16 : 36, tall ? 6 : 30),
              child: identity,
            ),
          ),
        ],
      );

      // En vertical los botones se bajan a su propia fila, a todo lo ancho:
      // en la columna del nombre no les quedaria ni un dedo de sitio.
      if (!tall) return showcase;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          children: [
            Expanded(child: showcase),
            actions,
          ],
        ),
      );
    });
  }
}

class _EmptyShowcase extends StatelessWidget {
  const _EmptyShowcase({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return Row(
      children: [
        SizedBox(
          width: 400,
          child: Center(
            child: SizedBox(
              width: 170,
              height: 170,
              child: GlossSurface(
                radius: 46,
                recessed: true,
                child: Center(
                  child: GlyphIcon(
                    Glyph.tama,
                    size: 88,
                    color: skin.accent.withValues(alpha: .6),
                    strokeWidth: 2.2,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(l.tamasEmptyTitle, style: Ty.title),
                const SizedBox(height: 10),
                Text(l.tamasEmptyBody, style: Ty.body.copyWith(color: Ty.inkSoft)),
                const SizedBox(height: 26),
                Row(
                  children: [
                    IbashoButton(
                      key: const ValueKey<String>('tamas.createEmpty'),
                      label: l.tamasCreate,
                      glyph: Glyph.plus,
                      tone: ButtonTone.accent,
                      height: 50,
                      minWidth: 210,
                      cue: null,
                      onPressed: onCreate,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    // En vertical el nombre manda: la insignia se queda en su icono, con el
    // texto en la etiqueta de accesibilidad.
    if (tall) {
      return Semantics(
        label: label,
        child: SizedBox(
          width: 30,
          height: 30,
          child: GlossSurface(
            radius: 15,
            recessed: true,
            tint: skin.accent,
            child: Center(
              child: GlyphIcon(Glyph.portrait, size: 16, color: skin.accentDeep),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 30,
      child: GlossSurface(
        radius: 15,
        recessed: true,
        tint: skin.accent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(Glyph.portrait, size: 15, color: skin.accentDeep),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ty.caption.copyWith(color: skin.accentDeep, height: 1.1),
              ),
            ),
          ],
        ),
      ),
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

// --- Pantalla de abajo ----------------------------------------------------------

/// Las paginas de ranuras, desplazandose con el sobrepaso corto de la rejilla
/// de canales.
class _PagedSlots extends StatefulWidget {
  const _PagedSlots({
    required this.size,
    required this.page,
    required this.pages,
    required this.tall,
    required this.tamas,
    required this.showCreate,
    required this.selectedId,
    required this.profileId,
    required this.onSelect,
    required this.onCreate,
    required this.onSlots,
  });

  final Size size;
  final int page;
  final int pages;
  final bool tall;
  final ValueChanged<int> onSlots;
  final List<Tama> tamas;
  final bool showCreate;
  final String? selectedId;
  final String? profileId;
  final ValueChanged<Tama> onSelect;
  final VoidCallback onCreate;

  @override
  State<_PagedSlots> createState() => _PagedSlotsState();
}

class _PagedSlotsState extends State<_PagedSlots> with SingleTickerProviderStateMixin {
  static const double _padH = 28;
  static const double _padV = 22;
  static const double _gapH = 22;
  static const double _gapV = 18;

  late final AnimationController _slide =
      AnimationController(vsync: this, duration: T.page, value: 1);
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
    final columns = widget.tall ? _tallColumns : _columns;
    final padH = widget.tall ? 16.0 : _padH;
    final gapH = widget.tall ? 12.0 : _gapH;
    final tileW = (width - padH * 2 - gapH * (columns - 1)) / columns;
    // En vertical caben las filas que quepan, nunca menos de dos.
    final rows = widget.tall
        ? math.max(2, ((height - _padV * 2 + _gapV) / (tileW / 1.18 + _gapV)).floor())
        : 2;
    final tileH = widget.tall
        ? math.min(tileW / 1.18, (height - _padV * 2 - _gapV * (rows - 1)) / rows)
        : (height - _padV * 2 - _gapV) / 2;
    final perPage = columns * rows;
    widget.onSlots(perPage);

    final tileWidth = math.min(tileW, tileH * 1.18);

    Widget slot(int index) {
      if (index < widget.tamas.length) {
        final tama = widget.tamas[index];
        return _TamaTile(
          key: ValueKey<String>('tamas.card.${tama.id}'),
          tama: tama,
          width: tileWidth,
          height: tileH,
          selected: tama.id == widget.selectedId,
          onProfile: tama.id == widget.profileId,
          onPressed: () => widget.onSelect(tama),
        );
      }
      if (index == widget.tamas.length && widget.showCreate) {
        return _CreateTile(width: tileWidth, height: tileH, onPressed: widget.onCreate);
      }
      return EmptySlot(width: tileWidth, height: tileH);
    }

    return ClipRect(
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
    );
  }
}

/// Un Tama en su ranura: plastico blanco con el brillo de la casa. Al pasar el
/// raton se inclina dos grados y sube cuatro pixeles con curva elastica, igual
/// que un canal; la elegida lleva el filo y el lavado de acento.
class _TamaTile extends ConsumerWidget {
  const _TamaTile({
    super.key,
    required this.tama,
    required this.width,
    required this.height,
    required this.selected,
    required this.onProfile,
    required this.onPressed,
  });

  final Tama tama;
  final double width;
  final double height;
  final bool selected;
  final bool onProfile;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final reading = TamaMoodReading.of(tama, ref.watch(moodClockProvider));

    return SlotTile(
      width: width,
      height: height,
      selected: selected,
      onPressed: onPressed,
      semanticLabel: selected ? l.tamaOpenRoom(tama.name) : tama.name,
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
                    child: TamaView(
                      look: tama.look,
                      personality: tama.personality,
                      name: tama.name,
                      voice: tama.voice,
                      seed: tama.id.hashCode,
                      joy: reading.joy,
                      size: height * .98,
                      interactive: false,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
                child: Text(
                  tama.name,
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
          if (onProfile)
            Positioned(
              top: 9,
              right: 10,
              child: GlyphIcon(Glyph.portrait, size: 17, color: skin.accentDeep),
            ),
        ],
      ),
    );
  }
}

/// La ranura de crear: hundida como un canal libre, con un mas.
class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.width, required this.height, required this.onPressed});

  final double width;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    return Pressable(
      key: const ValueKey<String>('tamas.create'),
      cue: null,
      onPressed: onPressed,
      semanticLabel: l.tamasCreate,
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
                mainAxisSize: tall ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  GlyphIcon(
                    Glyph.plus,
                    size: height * (tall ? .28 : .3),
                    color: Color.lerp(Ty.inkSoft, skin.accentDeep, state.hover)!,
                    strokeWidth: 2.2,
                  ),
                  SizedBox(height: height * (tall ? .05 : .06)),
                  _Fit(
                    tall: tall,
                    child: Text(
                      l.tamasCreate,
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

/// En vertical cede el alto que haga falta; en horizontal ocupa lo suyo.
class _Fit extends StatelessWidget {
  const _Fit({required this.tall, required this.child});

  final bool tall;
  final Widget child;

  @override
  Widget build(BuildContext context) => tall ? Flexible(child: child) : child;
}

/// En vertical ocupa el ancho que sobra; en horizontal, lo suyo.
class _Fill extends StatelessWidget {
  const _Fill({required this.tall, required this.child});

  final bool tall;
  final Widget child;

  @override
  Widget build(BuildContext context) => tall ? Expanded(child: child) : child;
}
