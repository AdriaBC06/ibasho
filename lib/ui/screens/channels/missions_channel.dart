// Ibasho — el canal de misiones: diarias y semanales, cobrables en tickets.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/gacha.dart';
import '../../../backend/missions.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/login_bonus.dart' show bonusDay;
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/panel.dart';
import '../channel_route.dart';

String _missionLabel(L l, MissionEvent event) => switch (event) {
      MissionEvent.feed => l.missionFeed,
      MissionEvent.play => l.missionPlay,
      MissionEvent.pull => l.missionPull,
      MissionEvent.buy => l.missionBuy,
    };

Glyph _missionGlyph(MissionEvent event) => switch (event) {
      MissionEvent.feed => Glyph.treat,
      MissionEvent.play => Glyph.play,
      MissionEvent.pull => Glyph.gift,
      MissionEvent.buy => Glyph.yatai,
    };

/// Las misiones diarias y semanales de la cuenta. Una sola columna con dos
/// bloques (`docs/UI.md` §2: formulario/lista, no una coleccion).
class MissionsChannel extends ConsumerWidget {
  const MissionsChannel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final missions = ref.watch(missionsProvider);
    final day = bonusDay();
    final week = gachaWeek();
    final daily = dailyMissionsFor(day);

    return ChannelScaffold(
      title: l.channelMissions,
      glyph: Glyph.flag,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.pick(28, 18), layout.gutter, 44),
        child: Center(
          child: SizedBox(
            width: layout.pick(820, layout.column),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.missionsDailyTitle, style: Ty.title),
                SizedBox(height: layout.pick(14, 10)),
                for (final event in daily) ...[
                  _MissionRow(
                    glyph: _missionGlyph(event),
                    label: _missionLabel(l, event),
                    reward: l.missionsReward(dailyMissionReward, l.gachaTicketGachaken),
                    done: missions.doneToday(event, day),
                    claimed: missions.claimedDaily(event, day),
                    onClaim: () async {
                      final ok = await ref.read(missionsProvider.notifier).claimDaily(event, day);
                      if (ok) {
                        AudioService.instance.play(Sfx.chime);
                      } else if (context.mounted) {
                        AudioService.instance.play(Sfx.error);
                      }
                    },
                  ),
                  SizedBox(height: layout.pick(10, 8)),
                ],
                SizedBox(height: layout.pick(22, 16)),
                Text(l.missionsWeeklyTitle, style: Ty.title),
                SizedBox(height: layout.pick(14, 10)),
                for (final mission in WeeklyMission.values) ...[
                  _MissionRow(
                    glyph: _missionGlyph(mission.event),
                    label: _missionLabel(l, mission.event),
                    reward: l.missionsReward(
                      weeklyMissionReward[mission]!.$2,
                      weeklyMissionReward[mission]!.$1 == TicketKind.kinken
                          ? l.gachaTicketKinken
                          : l.gachaTicketGachaken,
                    ),
                    done: missions.doneThisWeek(mission.event, week),
                    claimed: missions.claimedWeekly(mission, week),
                    onClaim: () async {
                      final ok = await ref.read(missionsProvider.notifier).claimWeekly(mission, week);
                      if (ok) {
                        AudioService.instance.play(Sfx.chime);
                      } else if (context.mounted) {
                        AudioService.instance.play(Sfx.error);
                      }
                    },
                  ),
                  SizedBox(height: layout.pick(10, 8)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({
    required this.glyph,
    required this.label,
    required this.reward,
    required this.done,
    required this.claimed,
    required this.onClaim,
  });

  final Glyph glyph;
  final String label;
  final String reward;
  final bool done;
  final bool claimed;
  final Future<void> Function() onClaim;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          GlyphIcon(glyph, size: 26, color: claimed ? Ty.inkSoft : skin.accentDeep),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Ty.body.copyWith(fontWeight: FontWeight.w600)),
                Text(reward, style: Ty.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (claimed)
            GlyphIcon(Glyph.check, size: 22, color: Ty.inkSoft)
          else
            IbashoButton(
              label: l.missionsClaim,
              glyph: Glyph.gift,
              tone: done ? ButtonTone.accent : ButtonTone.plain,
              height: 40,
              onPressed: done ? () => unawaited(onClaim()) : null,
            ),
        ],
      ),
    );
  }
}
