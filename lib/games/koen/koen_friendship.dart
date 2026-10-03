// Ibasho — Tama Kōen: la ficha de amistad con un amigo (nivel, puntos, cómo
// sube y qué trae cada nivel).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/koen.dart' show koenDragsPerPair;
import '../../backend/koen_bonds.dart';
import '../../backend/koen_duo.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/type.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/hint_bubble.dart';
import '../../ui/widgets/overlays.dart';
import 'koen_album.dart' show koenFriendName;
import 'koen_badge.dart';

/// Abre la ficha de amistad del parque con [friend].
Future<void> showKoenFriendship(BuildContext context, String friend) =>
    showIbashoModal<void>(context, (_) => KoenFriendshipDialog(friend: friend));

/// Hasta qué nivel deja subir la casita de un dúo la amistad [level] (con
/// racha de sobra).
int koenHouseCap(KoenFriendLevel level) {
  var cap = 1;
  for (final (_, need) in koenHouseSteps) {
    if (level.index < need.index) break;
    cap++;
  }
  return cap;
}

/// La píldora del perfil de un amigo: al pasar el ratón explica qué es y al
/// tocarla abre la ficha de amistad.
class KoenFriendChipButton extends StatelessWidget {
  const KoenFriendChipButton({super.key, required this.friend, required this.level});

  final String friend;
  final KoenFriendLevel level;

  @override
  Widget build(BuildContext context) => HintBubble(
    message: L.of(context)!.koenFriendChipHint,
    onPressed: () {
      AudioService.instance.play(Sfx.tick);
      showKoenFriendship(context, friend);
    },
    child: KoenFriendChip(level: level),
  );
}

class KoenFriendshipDialog extends ConsumerWidget {
  const KoenFriendshipDialog({super.key, required this.friend});

  final String friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final name = koenFriendName(ref, friend);
    final points = ref.watch(koenFriendPointsProvider(friend)).valueOrNull ?? 0;
    final level = KoenFriendLevel.of(points);
    final next = level.index + 1 < KoenFriendLevel.values.length ? KoenFriendLevel.values[level.index + 1] : null;
    final from = level.points;
    final progress = next == null ? 1.0 : ((points - from) / (next.points - from)).clamp(0.0, 1.0);

    String gives(KoenFriendLevel lv) => [
      if (lv == KoenFriendLevel.acquainted) l.koenFriendshipFirst,
      if (lv.coins > 0) l.koenFriendshipCoins(lv.coins),
      if (lv == koenCharmLevel) l.koenFriendshipCharm,
      l.koenFriendshipHouse(koenHouseCap(lv)),
    ].join(' · ');

    return IbashoDialog(
      title: l.koenFriendshipTitle(name),
      width: 560,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  KoenFriendBadge(level: level, size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          level == KoenFriendLevel.none ? '—' : l.koenFriendLevel(level.name),
                          style: Ty.title.copyWith(color: KoenFriendBadgePainter.deep(level)),
                        ),
                        const SizedBox(height: 4),
                        Text(l.koenFriendshipPoints(points), style: Ty.caption),
                        const SizedBox(height: 10),
                        _Bar(value: progress, color: koenFriendColor(next ?? level)),
                        const SizedBox(height: 6),
                        Text(
                          next == null
                              ? l.koenFriendshipMax
                              : l.koenFriendshipToNext(next.points - points, l.koenFriendLevel(next.name)),
                          style: Ty.micro,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(l.koenFriendshipHow(name, koenDragsPerPair), style: Ty.body),
              const SizedBox(height: 18),
              Text(l.koenFriendshipLevels, style: Ty.label),
              const SizedBox(height: 8),
              for (final lv in KoenFriendLevel.values.skip(1))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GlossSurface(
                    radius: 14,
                    recessed: lv.index > level.index,
                    elevation: .8,
                    tint: lv.index <= level.index ? koenFriendColor(lv) : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Opacity(
                          opacity: lv.index <= level.index ? 1 : .45,
                          child: KoenFriendBadge(level: lv, size: 30),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${l.koenFriendLevel(lv.name)} · ${l.koenFriendshipAt(lv.points)}',
                                style: Ty.body.copyWith(color: Ty.ink, fontWeight: FontWeight.w600),
                              ),
                              Text(gives(lv), style: Ty.micro),
                            ],
                          ),
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

/// La barra de lo que llevan hacia el siguiente nivel.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 14,
    child: GlossSurface(
      radius: 7,
      recessed: true,
      padding: const EdgeInsets.all(2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value <= 0 ? .001 : value,
          child: value <= 0 ? const SizedBox() : GlossSurface(radius: 5, tint: color, elevation: .6),
        ),
      ),
    ),
  );
}
