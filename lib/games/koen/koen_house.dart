// Ibasho — Tama Kōen: la casita de un dúo, su racha y sus muebles.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/koen.dart' show koenDaylight;
import '../../backend/koen_bonds.dart';
import '../../backend/koen_duo.dart';
import '../../backend/prizes.dart' show prizeItem;
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/login_bonus.dart' show bonusDay;
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/panel.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/prize_view.dart';
import '../../ui/widgets/slot_tile.dart';
import 'koen_album.dart' show koenFriendName;
import 'koen_charm.dart';

/// El color de los dúos: un rosa de farolillo.
const Color koenDuoColor = Color(0xFFFFB7B2);
const Color _duoInk = Color(0xFF8E3B3A);

/// El nivel de amistad con [friend] que se ve fuera del parque.
KoenFriendLevel koenFriendLevelOf(WidgetRef ref, String friend) {
  final park = ref.watch(koenProvider);
  if (park.loaded) return park.friendLevel(friend);
  return ref.watch(koenFriendLevelsProvider).valueOrNull?[friend] ?? KoenFriendLevel.none;
}

/// Apunta la racha del dúo de [tamaId] si con esto ya toca, cobra sus
/// premios y lo dice. Relee antes los Tamas compartidos, que no se siguen en
/// vivo.
Future<void> tickKoenDuoWithToast(BuildContext context, WidgetRef ref, String tamaId) async {
  var duo = koenDuoOfTama(ref.read(koenDuosProvider), tamaId);
  if (duo == null) return;
  final today = bonusDay();
  if (!duo.caredOn(today) && !duo.demo) {
    await ref.read(tamasProvider.notifier).refreshCared();
    if (!context.mounted) return;
    duo = koenDuoOfTama(ref.read(koenDuosProvider), tamaId);
    if (duo == null) return;
  }
  await tickKoenDuo(context, ref, duo);
}

/// Apunta la racha de [duo] y cobra sus premios, con sus avisos.
Future<void> tickKoenDuo(BuildContext context, WidgetRef ref, KoenDuo duo) async {
  final l = L.of(context)!;
  final tick = await ref.read(koenDuosStateProvider.notifier).tick(duo);
  if (tick.isEmpty || !context.mounted) return;
  AudioService.instance.play(Sfx.chime);
  if (tick.streak > 0) showIbashoToast(context, l.koenDuoStreakUp(tick.streak, koenFriendName(ref, duo.friend)));
  for (final prize in tick.prizes) {
    showIbashoToast(context, l.koenDuoPrizeGot(koenStreakPrizeLabel(l, prize)));
  }
}

String koenStreakPrizeLabel(L l, KoenStreakPrize prize) {
  if (prize.coins > 0) return l.koenDuoPrizeCoins(prize.coins);
  if (prize.ticket) return l.koenDuoPrizeTicket;
  return l.koenDuoPrizeFurniture(l.koenFurniture(prize.furniture!.name));
}

/// Los dos Tamas de un dúo en pequeño, juntos: la marca de la lista de amigos
/// y de la sección del parque.
class KoenDuoMark extends StatelessWidget {
  const KoenDuoMark({super.key, required this.duo, this.size = 34});

  final KoenDuo duo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (left, right) = duo.pair;
    Widget tama(Tama t) => SizedBox(
      width: size * .62,
      height: size * .62,
      child: TamaView(
        look: t.look,
        personality: t.personality,
        name: t.name,
        voice: t.voice,
        seed: t.id.hashCode,
        size: size * .62,
        interactive: false,
        shadow: false,
      ),
    );
    return Semantics(
      label: L.of(context)!.koenDuoMark,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size * 1.3,
          height: size * .8,
          child: GlossSurface(
            radius: size * .4,
            tint: koenDuoColor,
            elevation: .8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(left: size * .06, bottom: size * .04, child: tama(left)),
                Positioned(right: size * .06, bottom: size * .04, child: tama(right)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La sección de los dúos en el panel del parque.
class KoenDuoSection extends ConsumerWidget {
  const KoenDuoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final duos = ref.watch(koenDuosProvider);
    final today = bonusDay();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.koenDuoTitle, style: Ty.label),
        const SizedBox(height: 4),
        Text(duos.isEmpty ? l.koenDuoNone : l.koenDuoHint, style: Ty.micro),
        const SizedBox(height: 8),
        for (final duo in duos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SlotTile(
              key: ValueKey<String>('koen.duo.${duo.friend}'),
              width: double.infinity,
              height: 58,
              semanticLabel: l.koenDuoWith(koenFriendName(ref, duo.friend)),
              onPressed: () => pushChannelPage<void>(context, (_) => KoenHouseScreen(friend: duo.friend)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                child: Row(
                  children: [
                    KoenDuoMark(duo: duo, size: 40),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.koenDuoWith(koenFriendName(ref, duo.friend)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.caption.copyWith(color: Ty.ink, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${l.koenDuoStreak(duo.data.streak.current(today))} · '
                            '${l.koenDuoLevel(duo.level(koenFriendLevelOf(ref, duo.friend)))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.micro,
                          ),
                        ],
                      ),
                    ),
                    if (duo.data.streak.countedOn(today)) const GlyphIcon(Glyph.flame, size: 20, color: _duoInk),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// --- La pantalla ---------------------------------------------------------------

class KoenHouseScreen extends ConsumerStatefulWidget {
  const KoenHouseScreen({super.key, required this.friend});

  final String friend;

  @override
  ConsumerState<KoenHouseScreen> createState() => _KoenHouseScreenState();
}

class _KoenHouseScreenState extends ConsumerState<KoenHouseScreen> {
  @override
  void initState() {
    super.initState();
    // Al entrar se releen los Tamas compartidos y lo del dúo, y se apunta el
    // día si ya toca.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(tamasProvider.notifier).refreshCared();
      if (!mounted) return;
      final duo = ref.read(koenDuoWithProvider(widget.friend));
      if (duo == null) return;
      await ref.read(koenDuosStateProvider.notifier).load([duo]);
      if (!mounted) return;
      final fresh = ref.read(koenDuoWithProvider(widget.friend));
      if (fresh != null) await tickKoenDuo(context, ref, fresh);
    });
  }

  Future<void> _saved(Future<bool> work) async {
    final ok = await work;
    if (!mounted) return;
    if (!ok) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, L.of(context)!.koenDuoFailed, isError: true);
    } else {
      AudioService.instance.play(Sfx.pop);
    }
  }

  void _swap(KoenDuo duo) {
    final (left, right) = duo.pair;
    unawaited(_saved(ref.read(koenDuosStateProvider.notifier).setPair(duo, right.id, left.id)));
  }

  /// Elige otro Tama para el lado de [current], entre los del mismo creador.
  Future<void> _pickTama(KoenDuo duo, Tama current) async {
    final options = [...duo.mine, ...duo.theirs].where((t) => t.creator == current.creator).toList();
    if (options.length < 2) return;
    final picked = await showIbashoModal<Tama>(context, (_) => _TamaChoice(options: options));
    if (picked == null || picked.id == current.id || !mounted) return;
    final (left, right) = duo.pair;
    final l = left.id == current.id ? picked.id : left.id;
    final r = right.id == current.id ? picked.id : right.id;
    unawaited(_saved(ref.read(koenDuosStateProvider.notifier).setPair(duo, l, r)));
  }

  Future<void> _pickFurniture(KoenDuo duo, int spot, List<KoenFurniture> have) async {
    final current = duo.data.decor[spot];
    final picked = await showIbashoModal<_Choice>(
      context,
      (_) => _FurnitureChoice(have: have, current: current, spot: spot),
    );
    if (picked == null || picked.furniture == current || !mounted) return;
    unawaited(_saved(ref.read(koenDuosStateProvider.notifier).place(duo, spot, picked.furniture)));
  }

  Future<void> _chooseCharm(KoenDuo duo) async {
    final picked = await showIbashoModal<KoenCharm>(
      context,
      (_) => _CharmChoice(code: duo.charmCode, current: duo.data.charm?.shape),
    );
    if (picked == null || picked == duo.data.charm?.shape || !mounted) return;
    final ctrl = ref.read(koenDuosStateProvider.notifier);
    final ok = await ctrl.chooseCharm(duo, picked);
    if (!mounted) return;
    // Si ya llevaba la mitad de otra forma, se cambia por la nueva.
    final fresh = ref.read(koenDuoWithProvider(widget.friend));
    if (ok && fresh != null && koenCharmWorn(ref, fresh).$1) {
      await _wearCharm(fresh, true);
    } else {
      await _saved(Future.value(ok));
    }
  }

  /// Le pone (o le quita) al Tama propio de la casita su mitad del
  /// accesorio: primero la cobra, si aún no la tiene, y luego la guarda en
  /// su aspecto, en lugar de otra mitad que llevara.
  Future<void> _wearCharm(KoenDuo duo, bool wear) async {
    final l = L.of(context)!;
    final ctrl = ref.read(koenDuosStateProvider.notifier);
    final charm = duo.data.charm;
    if (charm == null) return;
    if (duo.demo) {
      ctrl.demoWear(wear);
      AudioService.instance.play(wear ? Sfx.chime : Sfx.pop);
      if (wear) showIbashoToast(context, l.koenCharmGot(duo.myHalf.$1.name, l.koenCharmName(charm.shape.name)));
      return;
    }
    final (tama, _) = duo.myHalf;
    TamaLook? look;
    if (wear) {
      final key = await ctrl.claimCharm(duo);
      if (!mounted) return;
      if (key == null) return _saved(Future.value(false));
      look = koenWithCharm(tama.look, key);
      if (look == null) {
        AudioService.instance.play(Sfx.error);
        showIbashoToast(context, l.tamaAccessoriesFull, isError: true);
        return;
      }
    } else {
      look = koenWithoutCharm(tama.look);
    }
    final ok = await ref.read(tamasProvider.notifier).saveIdentity(tama.copyWith(look: look));
    if (!mounted) return;
    if (!ok) return _saved(Future.value(false));
    AudioService.instance.play(wear ? Sfx.chime : Sfx.pop);
    if (wear) showIbashoToast(context, l.koenCharmGot(tama.name, l.koenCharmName(charm.shape.name)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final duo = ref.watch(koenDuoWithProvider(widget.friend));
    final name = koenFriendName(ref, widget.friend);
    if (duo == null) {
      return ChannelScaffold(
        title: l.koenDuoHouseTitle(name),
        glyph: Glyph.house,
        child: Center(child: Text(l.koenDuoNone, style: Ty.lead, textAlign: TextAlign.center)),
      );
    }
    final friendLevel = koenFriendLevelOf(ref, widget.friend);
    final level = duo.level(friendLevel);
    final have = koenFurnitureFor(level, duo.data.streak.best);
    final layout = Layout.of(context);
    final house = KoenHouseView(
      duo: duo,
      level: level,
      demoWorn: ref.watch(koenDuosStateProvider.select((s) => s.demoWorn)),
      onTama: (t) => unawaited(_pickTama(duo, t)),
      onSpot: (spot) => unawaited(_pickFurniture(duo, spot, have)),
    );
    final cards = _HouseCards(
      duo: duo,
      level: level,
      friendLevel: friendLevel,
      have: have,
      onSwap: () => _swap(duo),
      onCharmPick: () => unawaited(_chooseCharm(duo)),
      onCharmWear: (wear) => unawaited(_wearCharm(duo, wear)),
    );
    return ChannelScaffold(
      title: l.koenDuoHouseTitle(name),
      glyph: Glyph.house,
      child: layout.tall
          ? Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(layout.gutter, 6, layout.gutter, 0),
                  child: house,
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
                Expanded(
                  child: Center(
                    child: Padding(padding: const EdgeInsets.fromLTRB(40, 20, 30, 20), child: house),
                  ),
                ),
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

class _HouseCards extends ConsumerWidget {
  const _HouseCards({
    required this.duo,
    required this.level,
    required this.friendLevel,
    required this.have,
    required this.onSwap,
    required this.onCharmPick,
    required this.onCharmWear,
  });

  final KoenDuo duo;
  final int level;
  final KoenFriendLevel friendLevel;
  final List<KoenFurniture> have;
  final VoidCallback onSwap;
  final VoidCallback onCharmPick;
  final ValueChanged<bool> onCharmWear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final today = bonusDay();
    final streak = duo.data.streak;
    final needs = <String>[
      for (final t in [duo.left, duo.right]) ...[
        if (!_on(t.care.lastFed, today)) l.koenDuoNeedFeed(t.name),
        if (!_on(t.care.lastPetted, today)) l.koenDuoNeedPet(t.name),
      ],
    ];
    final next = level < koenHouseMaxLevel ? koenHouseSteps[level - 1] : null;
    final claimed = ref.watch(koenDuosStateProvider.select((s) => s.claimed[duo.key])) ?? const <int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: l.koenDuoStreak(streak.current(today)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GlyphIcon(Glyph.flame, size: 26, color: streak.countedOn(today) ? _duoInk : Ty.inkSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      streak.countedOn(today) ? l.koenDuoTodayDone : l.koenDuoTodayNeeds(needs.join(', ')),
                      style: Ty.body,
                    ),
                  ),
                ],
              ),
              if (streak.best > 0) ...[
                const SizedBox(height: 6),
                Text(l.koenDuoBest(streak.best), style: Ty.micro),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionCard(
          title: l.koenDuoLevel(level),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                next == null
                    ? l.koenDuoMax
                    : next.$2 == KoenFriendLevel.none
                    ? l.koenDuoNextStreak(next.$1)
                    : l.koenDuoNextBoth(next.$1, l.koenFriendLevel(next.$2.name)),
                style: Ty.caption.copyWith(color: Ty.ink),
              ),
              const SizedBox(height: 6),
              Text(l.koenDuoFurniture(have.length, KoenFurniture.values.length), style: Ty.micro),
              const SizedBox(height: 12),
              IbashoButton(
                key: const ValueKey<String>('koen.house.swap'),
                label: l.koenDuoSwap,
                glyph: Glyph.refresh,
                tone: ButtonTone.quiet,
                height: 44,
                expand: true,
                onPressed: onSwap,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionCard(
          title: l.koenDuoPrizes,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final prize in koenStreakPrizes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(l.koenDuoPrizeDays(prize.days), style: Ty.caption.copyWith(color: Ty.ink)),
                      ),
                      Expanded(child: Text(koenStreakPrizeLabel(l, prize), style: Ty.caption)),
                      if (claimed.contains(prize.days))
                        GlyphIcon(Glyph.check, size: 20, color: skin.accentDeep)
                      else
                        GlyphIcon(Glyph.lock, size: 18, color: Ty.inkSoft),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _CharmCard(duo: duo, friendLevel: friendLevel, onPick: onCharmPick, onWear: onCharmWear),
      ],
    );
  }

  static bool _on(DateTime? at, int day) => at != null && at.millisecondsSinceEpoch >= day * 86400000;
}

// --- La casita pintada -----------------------------------------------------------

/// Dónde va cada hueco de los muebles: el punto de abajo en el centro (en
/// fracciones de la casita), lo grande que es (en fracciones del alto) y si
/// va delante de los Tamas. Se abren por orden con el nivel.
const List<(Offset, double, bool)> koenHouseSpots = [
  (Offset(.14, .67), .25, false),
  (Offset(.87, .96), .31, true),
  (Offset(.13, .96), .31, true),
  (Offset(.86, .67), .25, false),
  (Offset(.5, .99), .2, true),
  (Offset(.5, .645), .2, false),
];

/// Los Tamas de la casita: el centro de abajo y el tamaño, en fracciones.
const Offset _leftTama = Offset(.33, .9);
const Offset _rightTama = Offset(.67, .9);
const double _tamaSize = .38;

/// La casita de un dúo: la habitación con sus muebles y los dos Tamas.
/// [onTama] y [onSpot] la hacen tocable.
class KoenHouseView extends StatelessWidget {
  const KoenHouseView({
    super.key,
    required this.duo,
    required this.level,
    this.demoWorn = false,
    this.onTama,
    this.onSpot,
  });

  final KoenDuo duo;
  final int level;

  /// En el dúo de prueba: los dos llevan su mitad del accesorio, sin
  /// haberlo guardado.
  final bool demoWorn;
  final ValueChanged<Tama>? onTama;
  final ValueChanged<int>? onSpot;

  @override
  Widget build(BuildContext context) {
    final (left, right) = duo.pair;
    final spots = koenDecorSpots(level);
    final daylight = koenDaylight(DateTime.now());
    final charm = duo.data.charm;
    TamaLook lookOf(Tama t, bool isLeft) => duo.demo && demoWorn && charm != null
        ? koenWithCharm(t.look, charm.keyFor(left: isLeft)) ?? t.look
        : t.look;
    final leftLook = lookOf(left, true);
    final rightLook = lookOf(right, false);
    final link = koenCharmLink(leftLook, rightLook);
    return AspectRatio(
      aspectRatio: 16 / 11,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final size = h * _tamaSize;
          Offset topLeft(Offset at) => Offset(at.dx * w - size / 2, at.dy * h - size);
          Widget tama(Tama t, TamaLook look, Offset at) {
            final many = [...duo.mine, ...duo.theirs].where((x) => x.creator == t.creator).length > 1;
            return Positioned(
              left: at.dx * w - size / 2,
              top: at.dy * h - size,
              width: size,
              height: size,
              child: TamaView(
                key: ValueKey<String>('koen.house.tama.${t.id}'),
                look: look,
                personality: t.personality,
                name: t.name,
                voice: t.voice,
                seed: t.id.hashCode,
                joy: TamaMoodReading.of(t, DateTime.now()).joy,
                size: size,
                onTap: many && onTama != null ? () => onTama!(t) : null,
                semanticLabel: t.name,
              ),
            );
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _HousePainter(decor: duo.data.decor, spots: spots, front: false, daylight: daylight, level: level),
                  ),
                ),
                tama(left, leftLook, _leftTama),
                tama(right, rightLook, _rightTama),
                if (link != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey<String>('koen.house.charm'),
                        painter: KoenCharmLinkPainter(
                          charm: link,
                          from: koenCharmAnchor(leftLook, topLeft(_leftTama), size, towardRight: true),
                          to: koenCharmAnchor(rightLook, topLeft(_rightTama), size, towardRight: false),
                          scale: size,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _HousePainter(decor: duo.data.decor, spots: spots, front: true, daylight: daylight, level: level),
                    ),
                  ),
                ),
                if (onSpot != null)
                  for (var i = 0; i < spots; i++)
                    _spotButton(L.of(context)!, i, w, h, duo.data.decor[i] == null),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _spotButton(L l, int i, double w, double h, bool empty) {
    final (at, size, _) = koenHouseSpots[i];
    final s = math.max(40.0, size * h);
    return Positioned(
      left: at.dx * w - s / 2,
      top: at.dy * h - s,
      width: s,
      height: s,
      child: Pressable(
        key: ValueKey<String>('koen.house.spot.$i'),
        semanticLabel: l.koenDuoSpot(i + 1),
        onPressed: () => onSpot!(i),
        builder: (context, state) => empty
            ? Center(
                child: Container(
                  width: s * .5,
                  height: s * .5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFFFFF).withValues(alpha: .25 + .25 * state.hover),
                    border: Border.all(color: _duoInk.withValues(alpha: .5), width: 1.6),
                  ),
                  child: Center(child: GlyphIcon(Glyph.plus, size: s * .26, color: _duoInk)),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

class _HousePainter extends CustomPainter {
  _HousePainter({
    required this.decor,
    required this.spots,
    required this.front,
    required this.daylight,
    required this.level,
  });

  final Map<int, KoenFurniture> decor;
  final int spots;

  /// Pinta solo lo de delante de los Tamas; si no, la habitación y lo de
  /// detrás.
  final bool front;
  final double daylight;
  final int level;

  @override
  void paint(Canvas canvas, Size size) {
    if (!front) _room(canvas, size);
    for (var i = 0; i < spots; i++) {
      final f = decor[i];
      final (at, s, isFront) = koenHouseSpots[i];
      if (f == null || isFront != front) continue;
      final h = s * size.height;
      paintKoenFurniture(canvas, f, Offset(at.dx * size.width, at.dy * size.height), h);
    }
  }

  void _room(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final floorY = h * .62;
    // La pared, más cálida de noche con la luz encendida.
    final wall = Color.lerp(const Color(0xFFE9C9A0), const Color(0xFFF6E8D0), daylight)!;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, floorY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(wall, const Color(0xFF000000), .08)!, wall],
        ).createShader(Rect.fromLTWH(0, 0, w, floorY)),
    );
    final wood = Paint()..color = const Color(0xFFA9774B);
    final woodDark = Paint()..color = const Color(0xFF7E5332);
    // La viga de arriba y los pilares.
    canvas.drawRect(Rect.fromLTWH(0, h * .1, w, h * .035), wood);
    canvas.drawRect(Rect.fromLTWH(0, h * .132, w, h * .008), woodDark);
    for (final x in [0.0, w - w * .035]) {
      canvas.drawRect(Rect.fromLTWH(x, 0, w * .035, floorY), wood);
    }
    // La ventana de papel, con la luz de fuera (de noche, la de dentro).
    final win = Rect.fromLTRB(w * .38, h * .17, w * .62, h * .42);
    final paper = Color.lerp(const Color(0xFFFFD79A), const Color(0xFFFFFBF0), daylight)!;
    canvas.drawRect(win.inflate(w * .012), woodDark);
    canvas.drawRect(win, Paint()..color = paper);
    final lattice = Paint()
      ..color = const Color(0xFF8C5F3A)
      ..strokeWidth = math.max(1, w * .004);
    for (var i = 1; i < 3; i++) {
      final x = win.left + win.width * i / 3;
      canvas.drawLine(Offset(x, win.top), Offset(x, win.bottom), lattice);
    }
    for (var i = 1; i < 4; i++) {
      final y = win.top + win.height * i / 4;
      canvas.drawLine(Offset(win.left, y), Offset(win.right, y), lattice);
    }
    // Un pergamino colgado, desde el nivel 3.
    if (level >= 3) {
      final scroll = Rect.fromLTWH(w * .2, h * .18, w * .07, h * .3);
      canvas.drawRect(scroll, Paint()..color = const Color(0xFF6E8B74));
      canvas.drawRect(scroll.deflate(w * .01), Paint()..color = const Color(0xFFF7F0DD));
      final ink = Paint()
        ..color = const Color(0xFF3A3A3A)
        ..strokeWidth = math.max(1.2, w * .006)
        ..strokeCap = StrokeCap.round;
      final c = scroll.center;
      canvas.drawLine(c + Offset(0, -h * .07), c + Offset(0, h * .07), ink);
      canvas.drawLine(c + Offset(-w * .012, -h * .03), c + Offset(w * .012, -h * .03), ink);
      canvas.drawCircle(c + Offset(0, h * .1), w * .006, Paint()..color = const Color(0xFFC0392B));
    }
    // El suelo de tatami, con sus bordes.
    final floor = Rect.fromLTWH(0, floorY, w, h - floorY);
    canvas.drawRect(
      floor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC9C98A), Color(0xFFDCDB9E)],
        ).createShader(floor),
    );
    final weave = Paint()
      ..color = const Color(0xFFB5B577)
      ..strokeWidth = 1;
    for (var y = floorY + h * .02; y < h; y += h * .025) {
      canvas.drawLine(Offset(0, y), Offset(w, y), weave);
    }
    final heri = Paint()
      ..color = const Color(0xFF3F5B37)
      ..strokeWidth = math.max(2, h * .012);
    canvas.drawLine(Offset(0, floorY + h * .2), Offset(w, floorY + h * .2), heri);
    canvas.drawLine(Offset(w * .5, floorY), Offset(w * .5, floorY + h * .2), heri);
    canvas.drawLine(Offset(w * .25, floorY + h * .2), Offset(w * .25, h), heri);
    canvas.drawLine(Offset(w * .75, floorY + h * .2), Offset(w * .75, h), heri);
    // El zócalo.
    canvas.drawRect(Rect.fromLTWH(0, floorY - h * .015, w, h * .02), woodDark);
    // De noche, un poco de penumbra.
    if (daylight < 1) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF1E1840).withValues(alpha: (1 - daylight) * .18),
      );
    }
  }

  @override
  bool shouldRepaint(_HousePainter old) =>
      old.decor != decor || old.spots != spots || old.front != front || old.daylight != daylight || old.level != level;
}

/// Pinta [f] con su base en [base] (abajo en el centro) y [h] de alto.
void paintKoenFurniture(Canvas canvas, KoenFurniture f, Offset base, double h) {
  canvas.save();
  canvas.translate(base.dx, base.dy);
  canvas.scale(h / 100);
  // A partir de aquí, la caja va de (-50, -100) a (50, 0).
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0x55000000);
  Paint fill(int c) => Paint()..color = Color(c);
  final shadow = Paint()..color = const Color(0x33000000);
  canvas.drawOval(Rect.fromCenter(center: const Offset(0, -2), width: 92, height: 12), shadow);
  switch (f) {
    case KoenFurniture.zabuton:
      for (final (dx, dy, c) in [(-16.0, -6.0, 0xFFC0504D), (14.0, -22.0, 0xFF3E5C8A)]) {
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(dx, dy), width: 62, height: 22), const Radius.circular(10));
        canvas.drawRRect(r, fill(c));
        canvas.drawRRect(r, line);
        canvas.drawCircle(Offset(dx, dy), 3, fill(0xFFF2D16B));
      }
    case KoenFurniture.andon:
      canvas.drawRect(const Rect.fromLTRB(-20, -96, 20, -14), fill(0xFFFFE6A8));
      canvas.drawRect(
        const Rect.fromLTRB(-20, -96, 20, -14),
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xAAFFC250), Color(0x00FFC250)]).createShader(const Rect.fromLTRB(-30, -96, 30, -14)),
      );
      final frame = fill(0xFF6B4226);
      for (final x in [-22.0, 18.0]) {
        canvas.drawRect(Rect.fromLTWH(x, -100, 4, 100), frame);
      }
      canvas.drawRect(const Rect.fromLTRB(-22, -100, 22, -96), frame);
      canvas.drawRect(const Rect.fromLTRB(-22, -16, 22, -12), frame);
      canvas.drawLine(const Offset(-20, -55), const Offset(20, -55), line);
    case KoenFurniture.kotatsu:
      final quilt = Path()
        ..moveTo(-46, -30)
        ..lineTo(46, -30)
        ..quadraticBezierTo(52, -10, 48, 0)
        ..lineTo(-48, 0)
        ..quadraticBezierTo(-52, -10, -46, -30)
        ..close();
      canvas.drawPath(quilt, fill(0xFFE07B3C));
      for (var x = -36.0; x <= 36; x += 18) {
        canvas.drawCircle(Offset(x, -14), 4, fill(0xFFF6C177));
      }
      canvas.drawPath(quilt, line);
      final top = RRect.fromRectAndRadius(const Rect.fromLTRB(-50, -40, 50, -30), const Radius.circular(3));
      canvas.drawRRect(top, fill(0xFF8B5A33));
      canvas.drawRRect(top, line);
      canvas.drawCircle(const Offset(10, -48), 9, fill(0xFFF39C2B));
      canvas.drawCircle(const Offset(-8, -46), 7, fill(0xFFF5A742));
      canvas.drawCircle(const Offset(12, -56), 2, fill(0xFF4E7A33));
    case KoenFurniture.bonsai:
      final pot = Path()
        ..moveTo(-28, -22)
        ..lineTo(28, -22)
        ..lineTo(22, 0)
        ..lineTo(-22, 0)
        ..close();
      canvas.drawPath(pot, fill(0xFF4F6D8C));
      canvas.drawPath(pot, line);
      final trunk = Paint()
        ..color = const Color(0xFF6B4A2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(0, -22)
          ..cubicTo(-14, -40, 14, -52, -2, -70),
        trunk,
      );
      for (final (dx, dy, r) in [(-22.0, -66.0, 16.0), (16.0, -60.0, 15.0), (-2.0, -84.0, 17.0)]) {
        canvas.drawCircle(Offset(dx, dy), r, fill(0xFF4E8A4A));
        canvas.drawCircle(Offset(dx - r * .3, dy - r * .3), r * .45, fill(0xFF6FAE5F));
      }
    case KoenFurniture.tansu:
      final body = const Rect.fromLTRB(-40, -90, 40, -4);
      canvas.drawRect(body, fill(0xFF9B6A3F));
      canvas.drawRect(body, line);
      for (var i = 1; i < 4; i++) {
        final y = -90 + 86 * i / 4;
        canvas.drawLine(Offset(-40, y), Offset(40, y), line);
      }
      for (var i = 0; i < 4; i++) {
        final y = -90 + 86 * (i + .5) / 4;
        canvas.drawCircle(Offset(-16, y), 3.4, fill(0xFF2E2E2E));
        canvas.drawCircle(Offset(16, y), 3.4, fill(0xFF2E2E2E));
      }
      canvas.drawRect(const Rect.fromLTRB(-36, -4, -28, 0), fill(0xFF6B4226));
      canvas.drawRect(const Rect.fromLTRB(28, -4, 36, 0), fill(0xFF6B4226));
    case KoenFurniture.byobu:
      for (var i = 0; i < 4; i++) {
        final x0 = -48 + 24.0 * i;
        final skew = i.isEven ? 6.0 : -6.0;
        final panel = Path()
          ..moveTo(x0, -92 + skew)
          ..lineTo(x0 + 24, -92 - skew)
          ..lineTo(x0 + 24, -2 - skew)
          ..lineTo(x0, -2 + skew)
          ..close();
        canvas.drawPath(panel, fill(i.isEven ? 0xFFE8C766 : 0xFFDDB955));
        canvas.drawPath(panel, line);
      }
      final hills = Path()
        ..moveTo(-46, -30)
        ..quadraticBezierTo(-24, -62, 0, -36)
        ..quadraticBezierTo(22, -70, 46, -34)
        ..lineTo(46, -24)
        ..lineTo(-46, -20)
        ..close();
      canvas.drawPath(hills, fill(0xFF5F8F6B));
      canvas.drawCircle(const Offset(22, -72), 7, fill(0xFFD9534F));
    case KoenFurniture.maneki:
      canvas.drawOval(const Rect.fromLTRB(-26, -54, 26, 0), fill(0xFFFFFCF5));
      canvas.drawOval(const Rect.fromLTRB(-26, -54, 26, 0), line);
      canvas.drawCircle(const Offset(0, -64), 22, fill(0xFFFFFCF5));
      canvas.drawCircle(const Offset(0, -64), 22, line);
      for (final s in [-1.0, 1.0]) {
        final ear = Path()
          ..moveTo(s * 18, -76)
          ..lineTo(s * 16, -94)
          ..lineTo(s * 4, -84)
          ..close();
        canvas.drawPath(ear, fill(0xFFFFFCF5));
        canvas.drawPath(ear, line);
      }
      canvas.drawCircle(const Offset(-8, -66), 2.4, fill(0xFF2E2E2E));
      canvas.drawCircle(const Offset(8, -66), 2.4, fill(0xFF2E2E2E));
      canvas.drawOval(const Rect.fromLTRB(-12, -58, -4, -54), fill(0x55E57373));
      canvas.drawOval(const Rect.fromLTRB(4, -58, 12, -54), fill(0x55E57373));
      // La pata que llama.
      final paw = RRect.fromRectAndRadius(const Rect.fromLTRB(16, -92, 32, -60), const Radius.circular(8));
      canvas.drawRRect(paw, fill(0xFFFFFCF5));
      canvas.drawRRect(paw, line);
      canvas.drawRect(const Rect.fromLTRB(-18, -46, 18, -41), fill(0xFFC0392B));
      canvas.drawCircle(const Offset(0, -38), 5, fill(0xFFF2C14E));
      canvas.drawCircle(const Offset(-14, -22), 7, fill(0xFFF2C14E));
  }
  canvas.restore();
}

/// Un mueble en pequeño, para elegirlo.
class KoenFurnitureView extends StatelessWidget {
  const KoenFurnitureView(this.furniture, {super.key, this.size = 56});

  final KoenFurniture furniture;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _FurniturePainter(furniture)),
  );
}

class _FurniturePainter extends CustomPainter {
  _FurniturePainter(this.furniture);

  final KoenFurniture furniture;

  @override
  void paint(Canvas canvas, Size size) =>
      paintKoenFurniture(canvas, furniture, Offset(size.width / 2, size.height * .96), size.height * .9);

  @override
  bool shouldRepaint(_FurniturePainter old) => old.furniture != furniture;
}

// --- Elegir ---------------------------------------------------------------------

class _Choice {
  const _Choice(this.furniture);

  final KoenFurniture? furniture;
}

class _FurnitureChoice extends StatelessWidget {
  const _FurnitureChoice({required this.have, required this.current, required this.spot});

  final List<KoenFurniture> have;
  final KoenFurniture? current;
  final int spot;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.koenDuoPickFurniture,
      width: 480,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in have)
                SlotTile(
                  key: ValueKey<String>('koen.house.furniture.${f.name}'),
                  width: 100,
                  height: 112,
                  selected: f == current,
                  semanticLabel: l.koenFurniture(f.name),
                  onPressed: () => Navigator.of(context).pop(_Choice(f)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: Column(
                      children: [
                        Expanded(child: Center(child: KoenFurnitureView(f, size: 64))),
                        Text(
                          l.koenFurniture(f.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.micro.copyWith(color: Ty.ink),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (current != null)
          IbashoButton(
            key: const ValueKey<String>('koen.house.furniture.none'),
            label: l.koenDuoRemove,
            tone: ButtonTone.quiet,
            onPressed: () => Navigator.of(context).pop(const _Choice(null)),
          ),
        IbashoButton(
          label: l.actionClose,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _TamaChoice extends StatelessWidget {
  const _TamaChoice({required this.options});

  final List<Tama> options;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.koenDuoPickTama,
      width: 460,
      body: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in options)
            SlotTile(
              key: ValueKey<String>('koen.house.pick.${t.id}'),
              width: 96,
              height: 112,
              semanticLabel: t.name,
              onPressed: () => Navigator.of(context).pop(t),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                child: Column(
                  children: [
                    Expanded(
                      child: TamaView(
                        look: t.look,
                        personality: t.personality,
                        name: t.name,
                        voice: t.voice,
                        seed: t.id.hashCode,
                        size: 70,
                        interactive: false,
                        shadow: false,
                      ),
                    ),
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(color: Ty.ink)),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionClose,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// --- El accesorio de pareja ------------------------------------------------------

/// Si el Tama propio de la casita y el del amigo llevan ya su mitad.
(bool, bool) koenCharmWorn(WidgetRef ref, KoenDuo duo) {
  final charm = duo.data.charm;
  if (charm == null) return (false, false);
  if (duo.demo) {
    final worn = ref.read(koenDuosStateProvider).demoWorn;
    return (worn, worn);
  }
  final (mine, left) = duo.myHalf;
  final theirs = left ? duo.right : duo.left;
  return (
    koenWornKeys(mine.look).contains(charm.keyFor(left: left)),
    koenWornKeys(theirs.look).contains(charm.keyFor(left: !left)),
  );
}

class _CharmCard extends ConsumerWidget {
  const _CharmCard({required this.duo, required this.friendLevel, required this.onPick, required this.onWear});

  final KoenDuo duo;
  final KoenFriendLevel friendLevel;
  final VoidCallback onPick;
  final ValueChanged<bool> onWear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    ref.watch(koenDuosStateProvider.select((s) => s.demoWorn));
    final charm = duo.data.charm;
    final unlocked = duo.demo || friendLevel.index >= koenCharmLevel.index;
    final (mine, theirs) = koenCharmWorn(ref, duo);
    final me = duo.myHalf.$1;
    final children = <Widget>[
      Text(l.koenCharmHint, style: Ty.caption.copyWith(color: Ty.ink)),
      const SizedBox(height: 12),
    ];
    if (!unlocked) {
      children.add(Row(
        children: [
          GlyphIcon(Glyph.lock, size: 18, color: Ty.inkSoft),
          const SizedBox(width: 8),
          Expanded(child: Text(l.koenCharmLocked(l.koenFriendLevel(koenCharmLevel.name)), style: Ty.caption)),
        ],
      ));
    } else if (charm == null) {
      children.addAll([
        Text(l.koenCharmPick, style: Ty.micro),
        const SizedBox(height: 10),
        IbashoButton(
          key: const ValueKey<String>('koen.house.charm.pick'),
          label: l.koenCharmTitle,
          glyph: Glyph.heart,
          height: 44,
          expand: true,
          onPressed: onPick,
        ),
      ]);
    } else {
      children.addAll([
        Row(
          children: [
            KoenCharmPairView(charm: charm, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.koenCharmName(charm.shape.name), style: Ty.body.copyWith(color: Ty.ink)),
                  const SizedBox(height: 2),
                  if (mine && theirs)
                    Text(l.koenCharmFits, style: Ty.caption.copyWith(color: skin.accentDeep))
                  else if (mine)
                    Text(l.koenCharmWaiting(koenFriendName(ref, duo.friend)), style: Ty.micro),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        IbashoButton(
          key: const ValueKey<String>('koen.house.charm.wear'),
          label: mine ? l.koenCharmTakeOff(me.name) : l.koenCharmWear(me.name),
          glyph: mine ? null : Glyph.heart,
          tone: mine ? ButtonTone.quiet : ButtonTone.accent,
          height: 44,
          expand: true,
          onPressed: () => onWear(!mine),
        ),
        const SizedBox(height: 8),
        IbashoButton(
          key: const ValueKey<String>('koen.house.charm.change'),
          label: l.koenCharmChange,
          tone: ButtonTone.quiet,
          height: 44,
          expand: true,
          onPressed: onPick,
        ),
      ]);
    }
    return SectionCard(
      title: l.koenCharmTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// Las dos mitades del accesorio, una junto a otra.
class KoenCharmPairView extends StatelessWidget {
  const KoenCharmPairView({super.key, required this.charm, this.size = 48});

  final KoenCharmChoice charm;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Semantics(
      label: l?.koenCharmName(charm.shape.name),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final left in const [true, false])
            if (prizeItem(charm.keyFor(left: left)) case final item?) PrizeView(item, size: size),
        ],
      ),
    );
  }
}

class _CharmChoice extends StatelessWidget {
  const _CharmChoice({required this.code, required this.current});

  final String code;
  final KoenCharm? current;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.koenCharmPick,
      width: 480,
      body: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final shape in KoenCharm.values)
            SlotTile(
              key: ValueKey<String>('koen.house.charm.${shape.name}'),
              width: 136,
              height: 120,
              selected: shape == current,
              semanticLabel: l.koenCharmName(shape.name),
              onPressed: () => Navigator.of(context).pop(shape),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                child: Column(
                  children: [
                    Expanded(child: Center(child: KoenCharmPairView(charm: KoenCharmChoice(shape, code), size: 56))),
                    Text(
                      l.koenCharmName(shape.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.micro.copyWith(color: Ty.ink),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionClose,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
