// Ibasho — Tama Kōen: cuidar un Tama a medias (ofertas, lista y avisos).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/koen.dart';
import '../../backend/koen_care.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/rewards.dart' show RewardsState;
import '../../theme/type.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/screens/tama/tama_room_screen.dart';
import '../../ui/social/social_widgets.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/slot_tile.dart';
import 'koen_album.dart' show koenFriendName;

/// El color de lo que se cuida a medias: un melocotón cálido.
const Color koenCareColor = Color(0xFFFFCF9A);
const Color _careInk = Color(0xFF9A4F16);

/// La marca de un Tama que se cuida a medias: una casita.
class KoenCareMark extends StatelessWidget {
  const KoenCareMark({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: L.of(context)!.koenCareMark,
    child: ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: GlossSurface(
          radius: size / 2,
          tint: koenCareColor,
          elevation: .8,
          child: Center(child: GlyphIcon(Glyph.house, size: size * .6, color: _careInk, strokeWidth: 2.1)),
        ),
      ),
    ),
  );
}

/// Con quién se cuida [tama] a medias: el cuidador si es propio, el creador
/// si no.
String? koenCarePartner(Tama tama, String me) => tama.createdBy(me) ? tama.carer : tama.creator;

/// Ofrece cuidar a medias [tama] (propio): elige el amigo, si no viene ya
/// dado en [friend], y le manda la oferta.
Future<void> offerKoenCare(BuildContext context, WidgetRef ref, Tama tama, {String? friend}) async {
  final l = L.of(context)!;
  friend ??= await showIbashoModal<String>(context, (_) => const _FriendPicker());
  if (friend == null || !context.mounted) return;
  final ok = await ref.read(tamasProvider.notifier).offerCare(tama, friend);
  if (!context.mounted) return;
  if (!ok) {
    AudioService.instance.play(Sfx.error);
    showIbashoToast(context, l.koenCareOfferFailed, isError: true);
    return;
  }
  AudioService.instance.play(Sfx.pop);
  showIbashoToast(context, l.koenCareOfferSent(koenFriendName(ref, friend), tama.name));
}

/// Primero el Tama y luego el amigo, si no viene ya dado en [friend]: desde
/// el parque, los cuidados a medias o el perfil de un amigo.
Future<void> offerKoenCareFromPark(BuildContext context, WidgetRef ref, {String? friend}) async {
  final tama = await showIbashoModal<Tama>(context, (_) => const _TamaPicker());
  if (tama == null || !context.mounted) return;
  await offerKoenCare(context, ref, tama, friend: friend);
}

/// Deja de cuidar [tama] a medias, tras preguntar.
Future<bool> endKoenCare(BuildContext context, WidgetRef ref, Tama tama) async {
  final l = L.of(context)!;
  final me = ref.read(sessionProvider).accountId;
  final partner = koenCarePartner(tama, me);
  final yes = await askConfirmation(
    context,
    title: l.koenCareEndTitle(tama.name),
    body: l.koenCareEndBody(partner == null ? '…' : koenFriendName(ref, partner)),
    confirmLabel: l.koenCareEnd,
    cancelLabel: l.actionCancel,
    tone: ButtonTone.warn,
    width: 480,
  );
  if (!yes || !context.mounted) return false;
  final ok = await ref.read(tamasProvider.notifier).endCare(tama);
  if (!context.mounted) return ok;
  if (!ok) {
    AudioService.instance.play(Sfx.error);
    showIbashoToast(context, l.koenCareFailed, isError: true);
    return false;
  }
  showIbashoToast(context, l.koenCareEnded);
  return true;
}

/// Cobra las monedas del día si toca, y lo dice.
Future<void> claimKoenCareWithToast(BuildContext context, WidgetRef ref, Tama tama) async {
  final l = L.of(context)!;
  final coins = await claimKoenCare(ref, tama);
  if (coins <= 0 || !context.mounted) return;
  AudioService.instance.play(Sfx.chime);
  showIbashoToast(context, l.koenCareCoins(coins));
}

/// La sección del parque: las ofertas que han llegado, los Tamas que se
/// cuidan a medias y el botón de ofrecer uno.
class KoenCareSection extends ConsumerWidget {
  const KoenCareSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final me = ref.watch(sessionProvider.select((s) => s.accountId));
    final offers = ref.watch(koenAllOffersProvider);
    final tamas = ref.watch(tamasProvider);
    final shared = [...tamas.tamas.where((t) => t.shared), ...tamas.cared];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.koenCareTitle, style: Ty.label),
        const SizedBox(height: 4),
        Text(l.koenCareHint(koenCareCoins), style: Ty.micro),
        const SizedBox(height: 8),
        for (final o in offers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _OfferRow(offer: o),
          ),
        if (shared.isEmpty && offers.isEmpty) Text(l.koenCareNone, style: Ty.caption),
        for (final t in shared)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _SharedRow(tama: t, me: me),
          ),
        const SizedBox(height: 4),
        IbashoButton(
          key: const ValueKey<String>('koen.care.offer'),
          label: l.koenCareOffer,
          glyph: Glyph.house,
          tone: ButtonTone.quiet,
          height: 44,
          expand: true,
          onPressed: () => unawaited(offerKoenCareFromPark(context, ref)),
        ),
      ],
    );
  }
}

class _OfferRow extends ConsumerWidget {
  const _OfferRow({required this.offer});

  final KoenOffer offer;

  Future<void> _answer(BuildContext context, WidgetRef ref, bool yes) async {
    final l = L.of(context)!;
    final tamas = ref.read(tamasProvider.notifier);
    // Las del parque de prueba se responden en local.
    if (offer.from.startsWith('demo-')) {
      ref.read(koenDemoOffersProvider.notifier).update((o) => [...o.where((x) => x.from != offer.from)]);
      if (yes) {
        final me = ref.read(sessionProvider).accountId;
        final t = offer.card.toTama();
        tamas.debugCare(Tama(
          id: t.id,
          creator: offer.from,
          keeper: offer.from,
          carer: me,
          name: t.name,
          personality: t.personality,
          voice: t.voice,
          look: t.look,
          createdAt: t.createdAt,
          updatedAt: t.updatedAt,
        ));
        AudioService.instance.play(Sfx.chime);
        showIbashoToast(context, l.koenCareAccepted(offer.card.name));
      }
      return;
    }
    final ok = yes ? await tamas.acceptCare(offer.from, offer.tamaId) : await tamas.declineCare(offer.from);
    if (!context.mounted) return;
    if (!ok) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.koenCareFailed, isError: true);
      return;
    }
    if (yes) {
      AudioService.instance.play(Sfx.chime);
      showIbashoToast(context, l.koenCareAccepted(offer.card.name));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final c = offer.card;
    return GlossSurface(
      radius: 14,
      elevation: .8,
      tint: koenCareColor,
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: TamaView(
              look: c.look,
              personality: c.personality,
              name: c.name,
              voice: c.voice,
              seed: koenHash(c.tamaId),
              size: 46,
              interactive: false,
              shadow: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.koenCareOfferFrom(koenFriendName(ref, offer.from), c.name), style: Ty.caption.copyWith(color: Ty.ink)),
          ),
          const SizedBox(width: 6),
          IconPill(
            key: ValueKey<String>('koen.care.accept.${offer.from}'),
            glyph: Glyph.check,
            diameter: 36,
            tone: ButtonTone.accent,
            semanticLabel: l.koenCareAccept,
            cue: null,
            onPressed: () => unawaited(_answer(context, ref, true)),
          ),
          const SizedBox(width: 6),
          IconPill(
            key: ValueKey<String>('koen.care.decline.${offer.from}'),
            glyph: Glyph.cross,
            diameter: 36,
            semanticLabel: l.koenCareDecline,
            onPressed: () => unawaited(_answer(context, ref, false)),
          ),
        ],
      ),
    );
  }
}

/// Un Tama que se cuida a medias: tocarlo abre su habitación.
class _SharedRow extends ConsumerWidget {
  const _SharedRow({required this.tama, required this.me});

  final Tama tama;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final partner = koenCarePartner(tama, me);
    final reading = TamaMoodReading.of(tama, ref.watch(moodClockProvider));
    return SlotTile(
      key: ValueKey<String>('koen.care.${tama.id}'),
      width: double.infinity,
      height: 58,
      semanticLabel: tama.name,
      onPressed: () => pushChannelPage<void>(context, (_) => TamaRoomScreen(tamaId: tama.id)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: TamaView(
                look: tama.look,
                personality: tama.personality,
                name: tama.name,
                voice: tama.voice,
                seed: tama.id.hashCode,
                joy: reading.joy,
                size: 48,
                interactive: false,
                shadow: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tama.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.body),
                  Text(
                    l.koenCareWith(partner == null ? '…' : koenFriendName(ref, partner)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.micro,
                  ),
                ],
              ),
            ),
            if (koenCareDone(tama, RewardsState.today())) const GlyphIcon(Glyph.check, size: 18, color: _careInk),
            const SizedBox(width: 6),
            const KoenCareMark(size: 22),
          ],
        ),
      ),
    );
  }
}

/// Elige qué Tama propio se ofrece: los que aún no se cuidan a medias.
class _TamaPicker extends ConsumerWidget {
  const _TamaPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final tamas = ref.watch(tamasProvider.select((t) => t.tamas)).where((t) => !t.shared).toList();
    return IbashoDialog(
      title: l.koenCareOfferPickTama,
      width: 460,
      body: tamas.isEmpty
          ? Text(l.koenCareOfferNoTamas, style: Ty.body)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tamas)
                      SlotTile(
                        key: ValueKey<String>('koen.care.pick.${t.id}'),
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
              ),
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

/// Elige el amigo con quien cuidarlo.
class _FriendPicker extends ConsumerWidget {
  const _FriendPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final friends = ref.watch(friendsProvider.select((f) => f.friends));
    return IbashoDialog(
      title: l.koenCareOfferPickFriend,
      width: 460,
      body: friends.isEmpty
          ? Text(l.koenCareOfferNoFriends, style: Ty.body)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in friends)
                      SlotTile(
                        key: ValueKey<String>('koen.care.friend.${f.accountId}'),
                        width: 96,
                        height: 112,
                        semanticLabel: koenFriendName(ref, f.accountId),
                        onPressed: () => Navigator.of(context).pop(f.accountId),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                          child: Column(
                            children: [
                              Expanded(child: IgnorePointer(child: CardTama(accountId: f.accountId, size: 70))),
                              Text(
                                koenFriendName(ref, f.accountId),
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
