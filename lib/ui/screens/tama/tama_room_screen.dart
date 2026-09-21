// Ibasho — la habitacion de un Tama: peana, humor y cuidados.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/tama.dart';
import '../../../core/birthday.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/pantry.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../tama/accent_prompt.dart';
import '../../tama/tama_food.dart';
import '../../tama/tama_text.dart';
import '../../tama/tama_view.dart';
import '../../tama/tama_widgets.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../layout.dart';
import '../../widgets/pressable.dart';
import '../channel_route.dart';
import 'tama_creator_screen.dart';

class TamaRoomScreen extends ConsumerStatefulWidget {
  const TamaRoomScreen({super.key, required this.tamaId});

  final String tamaId;

  @override
  ConsumerState<TamaRoomScreen> createState() => _TamaRoomScreenState();
}

class _TamaRoomScreenState extends ConsumerState<TamaRoomScreen> {
  final TamaViewController _view = TamaViewController();
  bool _leaving = false;

  void _cuddle(Tama tama) {
    _view.cuddle();
    unawaited(ref.read(tamasProvider.notifier).pet(tama.id));
  }

  Future<void> _feed(Tama tama, TamaFood food) async {
    final l = L.of(context)!;
    final ok = await ref.read(tamasProvider.notifier).feed(tama.id, food);
    if (!ok) {
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.pantryEmptyToast);
      return;
    }
    _view.feed(food);
  }

  Future<void> _setProfile(Tama tama) async {
    if (await putTamaOnProfile(context, ref, tama)) _view.speak();
  }

  Future<void> _delete(Tama tama) async {
    final l = L.of(context)!;
    final yes = await askConfirmation(
      context,
      title: l.tamaDeleteTitle(tama.name),
      body: l.tamaDeleteBody(tama.name),
      confirmLabel: l.tamaRoomDelete,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
    );
    if (!yes || !mounted) return;
    final wasProfile = ref.read(tamasProvider).profileTamaId == tama.id;
    _leaving = true;
    final ok = await ref.read(tamasProvider.notifier).delete(tama.id);
    if (!mounted) return;
    if (!ok) {
      _leaving = false;
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.tamaDeleteError, isError: true);
      return;
    }
    showIbashoToast(context, l.tamaDeleted);
    AudioService.instance.play(Sfx.back);
    Navigator.of(context).pop();
    final successor = ref.read(tamasProvider).profileTama;
    if (wasProfile && successor != null && successor.look.color != tama.look.color) {
      await reconcileAccentWithTama(context, ref, successor.look.color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tamas = ref.watch(tamasProvider);
    final tama = tamas.byId(widget.tamaId);
    final account = ref.watch(sessionProvider.select((s) => s.accountId));
    final now = ref.watch(moodClockProvider);

    if (tama == null) {
      // Borrado desde otro equipo mientras estaba abierto: no queda nada que
      // ensenar, se vuelve atras.
      if (tamas.loaded && !_leaving) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).maybePop();
          }
        });
      }
      return ChannelScaffold(
        title: l.channelTamas,
        glyph: Glyph.tama,
        child: Center(child: Text(l.loading, style: Ty.lead)),
      );
    }

    final reading = TamaMoodReading.of(tama, now);
    final isProfile = tamas.profileTamaId == tama.id;
    final isCreator = tama.createdBy(account);

    final layout = Layout.of(context);
    final tall = layout.tall;

    // En vertical los botones de la cabecera se quedan en iconos redondos: el
    // titulo es el nombre del Tama y no hay sitio para mas texto.
    final edit = tall
        ? IconPill(
            key: const ValueKey<String>('tama.edit'),
            glyph: Glyph.pencil,
            diameter: 44,
            semanticLabel: l.tamaRoomEdit,
            cue: null,
            onPressed: () => pushChannelPage<void>(
              context,
              (_) => TamaCreatorScreen(tamaId: tama.id),
            ),
          )
        : IbashoButton(
            key: const ValueKey<String>('tama.edit'),
            label: l.tamaRoomEdit,
            glyph: Glyph.pencil,
            height: 44,
            cue: null,
            onPressed: () => pushChannelPage<void>(
              context,
              (_) => TamaCreatorScreen(tamaId: tama.id),
            ),
          );
    final setProfile = tall
        ? IconPill(
            key: const ValueKey<String>('tama.setProfile'),
            glyph: Glyph.portrait,
            diameter: 44,
            semanticLabel: l.tamaRoomSetProfile,
            onPressed: () => _setProfile(tama),
          )
        : IbashoButton(
            key: const ValueKey<String>('tama.setProfile'),
            label: l.tamaRoomSetProfile,
            glyph: Glyph.portrait,
            height: 44,
            onPressed: () => _setProfile(tama),
          );

    final stage = Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isProfile)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlyphIcon(Glyph.portrait, size: 18, color: skin.accentDeep),
                        const SizedBox(width: 8),
                        Text(l.tamaRoomOnProfile, style: Ty.caption.copyWith(color: skin.accentDeep)),
                      ],
                    ),
                  ),
                TamaOnStand(
                  key: const ValueKey<String>('tama.stage'),
                  tama: tama,
                  size: tall ? math.min(layout.width - 80, 260) : 400,
                  joy: reading.joy,
                  controller: _view,
                  pettable: true,
                  onPetted: () => unawaited(ref.read(tamasProvider.notifier).pet(tama.id)),
                  // El dia del cumpleaños de su cuidador, el de perfil va de fiesta.
                  wear: _partyFor(ref, tama) ? TamaWear.partyHat : TamaWear.none,
                ),
                SizedBox(height: tall ? 10 : 18),
                Text(l.tamaRoomPetHint, style: Ty.caption),
              ],
    );

    final cards = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SectionCard(
                    title: l.tamaRoomMood,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(moodLabel(l, reading.mood), style: Ty.title),
                        const SizedBox(height: 6),
                        Text(moodHint(l, reading.mood), style: Ty.caption),
                        const SizedBox(height: 16),
                        TamaMoodMeter(value: reading.value, width: tall ? layout.width : 330),
                        const SizedBox(height: 18),
                        const Hairline(),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            GlyphIcon(Glyph.tama, size: 20, color: skin.accentDeep),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${personalityLabel(l, tama.personality)} · '
                                '${personalityHint(l, tama.personality)}',
                                style: Ty.caption.copyWith(color: T.ink),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SectionCard(
                    title: l.tamaRoomCare,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IbashoButton(
                          key: const ValueKey<String>('tama.pet'),
                          label: l.tamaRoomPet,
                          glyph: Glyph.heart,
                          tone: ButtonTone.accent,
                          height: 52,
                          expand: true,
                          cue: null,
                          onPressed: () => _cuddle(tama),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            l.tamaLastPetted(agoLabel(l, tama.care.lastPetted, DateTime.now())),
                            style: Ty.micro,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Cabecera ligera: que es y cuando comio por ultima vez.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                          child: Row(
                            children: [
                              // En vertical los dos textos se reparten la
                              // linea; en horizontal sobra sitio y cada uno se
                              // queda en su extremo.
                              _Fit(
                                tall: tall,
                                child: Text(
                                  l.tamaRoomFeed,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Ty.body.copyWith(fontWeight: FontWeight.w500),
                                ),
                              ),
                              const Spacer(),
                              _Fit(
                                tall: tall,
                                child: Text(
                                  agoLabel(l, tama.care.lastFed, DateTime.now()),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Ty.micro,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _FoodCarousel(onFeed: (food) => _feed(tama, food)),
                      ],
                    ),
                  ),
                  if (isCreator) ...[
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IbashoButton(
                        key: const ValueKey<String>('tama.delete'),
                        label: l.tamaRoomDelete,
                        glyph: Glyph.trash,
                        tone: ButtonTone.quiet,
                        height: 42,
                        cue: null,
                        onPressed: () => _delete(tama),
                      ),
                    ),
                  ],
                ],
    );

    return ChannelScaffold(
      title: tama.name,
      glyph: Glyph.tama,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCreator) ...[
            edit,
            SizedBox(width: tall ? 8 : 12),
          ],
          if (!isProfile) setProfile,
        ],
      ),
      // En vertical el Tama manda arriba y los cuidados se desplazan debajo;
      // la peana nunca entra en la zona que se arrastra, para que mimarlo no
      // mueva la pantalla.
      child: tall
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: stage,
                ),
                Expanded(
                  child: IbashoScroll(
                    padding: EdgeInsets.fromLTRB(layout.gutter, 14, layout.gutter, 20),
                    child: cards,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: Center(child: stage)),
                SizedBox(
                  width: 430,
                  child: IbashoScroll(
                    padding: const EdgeInsets.fromLTRB(0, 30, 40, 30),
                    child: cards,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Si el Tama es el de perfil y hoy es el cumpleaños de quien lo cuida.
bool _partyFor(WidgetRef ref, Tama tama) {
  final profile = ref.watch(profileProvider.select((p) => p.profile));
  final isProfileTama = ref.watch(tamasProvider.select((t) => t.profileTamaId)) == tama.id;
  return isProfileTama && profile != null && isBirthdayToday(profile, ref.watch(moodClockProvider));
}

/// Un recuadro hundido con el Tama de perfil vivo dentro, o su silueta si aun
/// no hay. Lo usan el panel superior y el perfil.
class TamaWindow extends ConsumerWidget {
  const TamaWindow({super.key, required this.size, this.radius, this.onTap});

  final double size;
  final double? radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = IbashoSkin.of(context);
    final l = L.of(context)!;
    final tama = ref.watch(tamasProvider.select((t) => t.profileTama));
    final now = ref.watch(moodClockProvider);
    final profile = ref.watch(profileProvider.select((p) => p.profile));
    final party = profile != null && isBirthdayToday(profile, now);
    final r = radius ?? size * .28;

    return SizedBox(
      width: size,
      height: size,
      child: GlossSurface(
        radius: r,
        recessed: true,
        child: tama == null
            ? Pressable(
                onPressed: onTap,
                cue: null,
                semanticLabel: l.tamasCreate,
                builder: (context, state) => Center(
                  child: GlyphIcon(
                    Glyph.tama,
                    size: size * .52,
                    color: skin.accent.withValues(alpha: .55 + .3 * state.hover),
                    strokeWidth: 2.2,
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(r),
                child: Transform.translate(
                  offset: Offset(0, size * .04),
                  child: TamaView(
                    look: tama.look,
                    personality: tama.personality,
                    name: tama.name,
                    voice: tama.voice,
                    seed: tama.id.hashCode ^ size.round(),
                    joy: TamaMoodReading.of(tama, now).joy,
                    size: size,
                    wear: party ? TamaWear.partyHat : TamaWear.none,
                    onTap: onTap,
                    semanticLabel: l.tamaOpenRoom(tama.name),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Las chuches, en una tira que se pasa hacia los lados con las flechas, la
/// rueda o arrastrando. Las que aun no se tienen salen hundidas y apagadas, con
/// un candado: se desbloquearan en la tienda.
class _FoodCarousel extends ConsumerStatefulWidget {
  const _FoodCarousel({required this.onFeed});

  final ValueChanged<TamaFood> onFeed;

  @override
  ConsumerState<_FoodCarousel> createState() => _FoodCarouselState();
}

class _FoodCarouselState extends ConsumerState<_FoodCarousel> {
  static const double _item = 66;
  final ScrollController _scroll = ScrollController();
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _canBack => _scroll.hasClients && _scroll.offset > 1;

  bool get _canForward =>
      _scroll.hasClients && _scroll.offset < _scroll.position.maxScrollExtent - 1;

  /// Se desplaza una "pagina" de lo que se ve, encajando en una chuche.
  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final skin = IbashoSkin.of(context);
    final visible = (_scroll.position.viewportDimension / _item).floor().clamp(1, 99);
    final target = ((_scroll.offset / _item).round() + direction * visible) * _item;
    final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
    if ((clamped - _scroll.offset).abs() < 1) return;
    AudioService.instance.play(Sfx.tick);
    if (skin.reducedMotion) {
      _scroll.jumpTo(clamped);
    } else {
      _scroll.animateTo(clamped, duration: T.page, curve: Curves.easeOutCubic);
    }
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheel) < const Duration(milliseconds: 220)) return;
    _lastWheel = now;
    _page((event.scrollDelta.dy + event.scrollDelta.dx) > 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final unlocked = ref.watch(unlockedFoodsProvider);
    final pantry = ref.watch(pantryProvider);
    // Primero las que se tienen.
    final foods = [
      ...TamaFood.values.where(unlocked.contains),
      ...TamaFood.values.where((f) => !unlocked.contains(f)),
    ];

    return Row(
      children: [
        IconPill(
          glyph: Glyph.arrowLeft,
          diameter: 30,
          semanticLabel: l.tamaFoodsPrevious,
          onPressed: _canBack ? () => _page(-1) : null,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Listener(
            onPointerSignal: _onWheel,
            child: ScrollConfiguration(
              behavior: const _DragScrollBehavior(),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Row(
                  children: [
                    for (final food in foods)
                      SizedBox(
                        width: _item,
                        child: _FoodButton(
                          key: ValueKey<String>('tama.feed.${food.name}'),
                          food: food,
                          label: foodLabel(l, food),
                          locked: !unlocked.contains(food),
                          units: unlocked.contains(food) ? pantry[food] ?? 0 : null,
                          onPressed: () {
                            if (unlocked.contains(food)) {
                              widget.onFeed(food);
                            } else {
                              AudioService.instance.play(Sfx.error);
                              showIbashoToast(context, l.tamaFoodLocked(foodLabel(l, food)));
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconPill(
          glyph: Glyph.arrowRight,
          diameter: 30,
          semanticLabel: l.tamaFoodsNext,
          onPressed: _canForward ? () => _page(1) : null,
        ),
      ],
    );
  }
}

/// Arrastrar tambien con el raton, y sin brillo de sobredesplazamiento.
class _DragScrollBehavior extends ScrollBehavior {
  const _DragScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) =>
      child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        // Los eventos inyectados llegan sin tipo (ver fingerKinds).
        PointerDeviceKind.unknown,
      };
}

/// Una chuche: plastico redondo con la comida pintada dentro, o hundido y
/// apagado con un candado si aun no se tiene.
class _FoodButton extends StatelessWidget {
  const _FoodButton({
    super.key,
    required this.food,
    required this.label,
    required this.locked,
    required this.units,
    required this.onPressed,
  });

  final TamaFood food;
  final String label;
  final bool locked;

  /// Unidades en la despensa. `null` cuando esta bloqueada: entonces no hay
  /// nada que contar.
  final int? units;

  final VoidCallback onPressed;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    // Sin unidades se hunde igual que una bloqueada, pero enseñando el "0" en
    // vez de un candado: se sabe que se tuvo, no que falte desbloquearla.
    final empty = !locked && units == 0;
    final recessed = locked || empty;
    return Pressable(
      onPressed: onPressed,
      cue: null,
      semanticLabel: locked ? '$label · ${L.of(context)!.tamaFoodLockedShort}' : label,
      builder: (context, state) {
        final ease = skin.reducedMotion || recessed
            ? 0.0
            : Curves.easeOutBack.transform(state.hover.clamp(0.0, 1.0));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, -4 * ease + (recessed ? 0 : 2 * state.press)),
                child: FocusRing(
                  visible: state.focus,
                  radius: _size / 2,
                  child: SizedBox(
                    width: _size,
                    height: _size,
                    child: GlossSurface(
                      radius: _size / 2,
                      recessed: recessed,
                      elevation: recessed ? 0 : 1 + ease * .8,
                      sink: recessed ? 0 : state.press * 1.5,
                      borderColor: recessed ? T.hairline : Color.lerp(T.hairline, skin.accent, state.hover)!,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Opacity(
                              opacity: recessed ? .38 : 1,
                              child: CustomPaint(painter: TamaFoodPainter(food)),
                            ),
                          ),
                          if (locked)
                            const Positioned(
                              right: 4,
                              bottom: 4,
                              child: GlyphIcon(Glyph.lock, size: 14, color: T.inkSoft),
                            ),
                          if (units != null)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: _UnitsBadge(count: units!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Ty.micro.copyWith(
                  color: recessed ? T.inkSoft.withValues(alpha: .7) : Color.lerp(T.inkSoft, skin.accentDeep, state.hover),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Las unidades que quedan en la despensa, en una esquina de la chuche.
class _UnitsBadge extends StatelessWidget {
  const _UnitsBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 8,
      tint: count == 0 ? null : skin.accent,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: Ty.micro.copyWith(
          color: count == 0 ? T.inkSoft : T.onAccent,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

/// En vertical cede el ancho que haga falta; en horizontal ocupa lo suyo.
class _Fit extends StatelessWidget {
  const _Fit({required this.tall, required this.child});

  final bool tall;
  final Widget child;

  @override
  Widget build(BuildContext context) => tall ? Flexible(child: child) : child;
}
