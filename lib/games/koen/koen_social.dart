// Ibasho — Tama Kōen fuera del parque: los cuidados a medias, los dúos y su
// racha desde «tus Tamas» y desde amigos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/koen_duo.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/login_bonus.dart' show bonusDay;
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/social/social_widgets.dart' show CountBadge;
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/overlays.dart';
import 'koen_album.dart' show koenFriendName;
import 'koen_care_ui.dart';
import 'koen_house.dart';

/// Lee lo que comparten los dúos y apunta la racha de hoy, con sus avisos.
/// Lo hace el parque al abrirse, y también «tus Tamas» y el perfil de un
/// amigo: la racha no tiene que esperar a que se abra el parque.
Future<void> refreshKoenDuos(BuildContext context, WidgetRef ref) async {
  final duos = ref.read(koenDuosProvider);
  if (duos.every((d) => d.demo)) return;
  await ref.read(koenDuosStateProvider.notifier).load(duos);
  for (final duo in ref.read(koenDuosProvider)) {
    if (!context.mounted) return;
    await tickKoenDuo(context, ref, duo);
  }
}

/// Vuelve a leer los dúos cuando cambia quién forma uno (al llegar los
/// Tamas cuidados a medias, al aceptar una oferta…). Para el `build` de una
/// pantalla, que además llama a [refreshKoenDuos] al abrirse.
void listenKoenDuos(BuildContext context, WidgetRef ref) {
  ref.listen<String>(
    koenDuosProvider.select((duos) => [for (final d in duos) if (!d.demo) d.friend].join(',')),
    (before, now) {
      // Fuera del build: la lectura cambia el estado de los dúos.
      if (now.isNotEmpty && now != before) {
        unawaited(Future<void>.microtask(() => context.mounted ? refreshKoenDuos(context, ref) : null));
      }
    },
  );
}

/// El botón de los cuidados a medias y los dúos, con las ofertas sin
/// contestar encima.
class KoenCareButton extends ConsumerWidget {
  const KoenCareButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final pending = ref.watch(pendingKoenOffersProvider);
    final tall = Layout.of(context).tall;
    void open() => unawaited(showIbashoModal<void>(context, (_) => const KoenCarePanel()));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (tall)
          IconPill(
            key: const ValueKey<String>('koen.care.manage'),
            glyph: Glyph.house,
            diameter: 44,
            semanticLabel: l.koenCareManage,
            onPressed: open,
          )
        else
          IbashoButton(
            key: const ValueKey<String>('koen.care.manage'),
            label: l.koenCareManage,
            glyph: Glyph.house,
            height: 44,
            onPressed: open,
          ),
        if (pending > 0) Positioned(top: -6, right: -6, child: CountBadge(count: pending, size: 22)),
      ],
    );
  }
}

/// Los cuidados a medias (ofertas, Tamas compartidos y ofrecer uno) y los
/// dúos, en un panel.
class KoenCarePanel extends StatelessWidget {
  const KoenCarePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.koenCareManage,
      width: 560,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KoenCareSection(),
              SizedBox(height: 18),
              KoenDuoSection(),
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

/// La racha de [duo] en una línea: «29 días de racha», con la llama si hoy
/// ya cuenta.
class KoenStreakLine extends StatelessWidget {
  const KoenStreakLine({super.key, required this.duo, this.style});

  final KoenDuo duo;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final today = bonusDay();
    final streak = duo.data.streak;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(
          Glyph.flame,
          size: 16,
          color: streak.countedOn(today) ? const Color(0xFFE0663A) : Ty.inkSoft,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            l.koenDuoStreak(streak.current(today)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style ?? Ty.caption.copyWith(color: skin.accentDeep, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// El botón del perfil de un amigo: la casita si tenéis un dúo; si no,
/// ofrecerle cuidar a medias uno de tus Tamas.
class KoenFriendDuoButton extends ConsumerWidget {
  const KoenFriendDuoButton({super.key, required this.friend, this.expand = false, this.height = 40});

  final String friend;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final duo = ref.watch(koenDuoWithProvider(friend));
    final name = koenFriendName(ref, friend);
    if (duo != null) {
      return IbashoButton(
        key: const ValueKey<String>('friend.koenHouse'),
        label: l.koenDuoHouseWith(name),
        glyph: Glyph.house,
        tone: ButtonTone.accent,
        height: height,
        expand: expand,
        onPressed: () => pushChannelPage<void>(context, (_) => KoenHouseScreen(friend: friend)),
      );
    }
    return IbashoButton(
      key: const ValueKey<String>('friend.koenCare'),
      label: l.koenCareOfferTo(name),
      glyph: Glyph.house,
      height: height,
      expand: expand,
      onPressed: () => unawaited(offerKoenCareFromPark(context, ref, friend: friend)),
    );
  }
}
