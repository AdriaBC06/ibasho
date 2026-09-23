// Ibasho — canal de Clasificaciones: tablas diaria y semanal de cada juego,
// con premio en tickets del gacha para el top 3.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../backend/gacha.dart' show TicketKind, gachaWeek;
import '../../../backend/leaderboards.dart';
import '../../../games/minesweeper/minesweeper_widgets.dart' show formatDuration, levelName;
import '../../../games/minesweeper/minesweeper.dart' show MinesweeperLevel;
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/leaderboards.dart';
import '../../../state/login_bonus.dart' show bonusDay;
import '../../../state/people.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../social/social_widgets.dart';
import '../../widgets/channel_art.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../channel_route.dart';

/// La medalla de cada puesto del podio: oro, plata o bronce.
ArtIcon _medalFor(int rank) => switch (rank) {
      1 => ArtIcon.medalGold,
      2 => ArtIcon.medalSilver,
      _ => ArtIcon.medalBronze,
    };

/// El nombre de [game] en el idioma en curso: reutiliza los nombres que ya
/// tiene cada juego (nivel del buscaminas, o el titulo de Tsumiki y Nihongo).
String leaderboardGameName(L l, LeaderboardGame game) => switch (game) {
      LeaderboardGame.minesweeperEasy => levelName(l, MinesweeperLevel.easy),
      LeaderboardGame.minesweeperMedium => levelName(l, MinesweeperLevel.medium),
      LeaderboardGame.minesweeperHard => levelName(l, MinesweeperLevel.hard),
      LeaderboardGame.tsumiki => l.tsumikiTitle,
      LeaderboardGame.nihongo => l.nihongoTitle,
    };

/// El canal de Clasificaciones.
///
/// Colección con dos paneles: arriba el podio oficial del periodo ya cerrado
/// (ayer, o la semana pasada), con el botón para cobrar el premio cuando toca;
/// abajo la clasificación del periodo en curso, con la ficha pública de cada
/// cuenta. Un selector elige el juego (los tres niveles del buscaminas,
/// Tsumiki y Nihongo) y un interruptor la cadencia (diaria o semanal).
class LeaderboardsChannel extends ConsumerStatefulWidget {
  const LeaderboardsChannel({super.key});

  @override
  ConsumerState<LeaderboardsChannel> createState() => _LeaderboardsChannelState();
}

class _LeaderboardsChannelState extends ConsumerState<LeaderboardsChannel> {
  LeaderboardGame _game = LeaderboardGame.minesweeperEasy;
  bool _weekly = false;
  bool _loading = false;
  int _claimingRank = 0;

  int get _key => _weekly ? gachaWeek() : bonusDay();
  int get _prevKey => _key - 1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final notifier = ref.read(leaderboardsProvider.notifier);
    final game = _game;
    final weekly = _weekly;
    final key = _key;
    final prevKey = _prevKey;
    await Future.wait([
      notifier.loadPeriod(game, weekly: weekly, key: key),
      notifier.loadPeriod(game, weekly: weekly, key: prevKey),
    ]);
    await notifier.loadClaims(game, weekly: weekly, key: prevKey);
    if (mounted && game == _game && weekly == _weekly) setState(() => _loading = false);
  }

  void _selectGame(LeaderboardGame game) {
    if (game == _game) return;
    setState(() => _game = game);
    unawaited(_load());
  }

  void _setWeekly(bool weekly) {
    if (weekly == _weekly) return;
    setState(() => _weekly = weekly);
    unawaited(_load());
  }

  String _scoreText(int score) =>
      _game.lowerIsBetter ? formatDuration(Duration(milliseconds: score)) : '$score';

  Future<void> _claim(L l, int rank, TicketKind kind) async {
    setState(() => _claimingRank = rank);
    final ok = await ref.read(leaderboardsProvider.notifier).claim(
          game: _game,
          weekly: _weekly,
          key: _prevKey,
          rank: rank,
          kind: kind,
        );
    if (!mounted) return;
    setState(() => _claimingRank = 0);
    showIbashoToast(context, ok ? l.leaderboardsClaimed : l.leaderboardsClaimFailed, isError: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final me = ref.watch(sessionProvider.select((s) => s.accountId));
    final state = ref.watch(leaderboardsProvider);
    final current = state.periodOf(_game, _weekly, _key);
    final previous = state.periodOf(_game, _weekly, _prevKey);

    return ChannelScaffold(
      title: l.leaderboardsTitle,
      glyph: Glyph.trophy,
      art: ArtIcon.leaderboards,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: LayoutBuilder(
          builder: (context, box) {
            final officialHeight = layout.tall
                ? (box.maxHeight * .34).clamp(190.0, 260.0)
                : (box.maxHeight * .42).clamp(220.0, 300.0);
            return Column(
              children: [
                const SizedBox(height: 14),
                IbashoSegmented<LeaderboardGame>(
                  options: [for (final g in LeaderboardGame.values) (g, leaderboardGameName(l, g))],
                  value: _game,
                  onChanged: _selectGame,
                ),
                const SizedBox(height: 10),
                IbashoSegmented<bool>(
                  options: [(false, l.leaderboardsDaily), (true, l.leaderboardsWeekly)],
                  value: _weekly,
                  onChanged: _setWeekly,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: officialHeight,
                  child: ScreenPanel(
                    child: _OfficialPanel(
                      loading: _loading,
                      weekly: _weekly,
                      period: previous,
                      me: me,
                      claimingRank: _claimingRank,
                      claimedOf: (rank, kind) => state.claimed(_game, _weekly, _prevKey, kind),
                      onClaim: (rank, kind) => unawaited(_claim(l, rank, kind)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ScreenPanel(
                    child: _StandingsPanel(
                      loading: _loading,
                      weekly: _weekly,
                      game: _game,
                      period: current,
                      me: me,
                      scoreText: _scoreText,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

// --- Panel de arriba: el podio oficial y el cobro --------------------------

class _OfficialPanel extends StatelessWidget {
  const _OfficialPanel({
    required this.loading,
    required this.weekly,
    required this.period,
    required this.me,
    required this.claimingRank,
    required this.claimedOf,
    required this.onClaim,
  });

  final bool loading;
  final bool weekly;
  final LeaderboardPeriod period;
  final String me;
  final int claimingRank;
  final bool Function(int rank, TicketKind kind) claimedOf;
  final void Function(int rank, TicketKind kind) onClaim;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final results = period.results;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            weekly ? l.leaderboardsOfficialWeekly : l.leaderboardsOfficialDaily,
            style: Ty.lead,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const SizedBox()
                : (results == null || results.isEmpty)
                    ? Center(
                        child: Text(
                          l.leaderboardsOfficialEmpty,
                          textAlign: TextAlign.center,
                          style: Ty.body.copyWith(color: Ty.inkSoft),
                        ),
                      )
                    : IbashoScroll(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < results.length; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(
                                child: _PodiumTile(
                                  rank: i + 1,
                                  weekly: weekly,
                                  accountId: results[i],
                                  mine: results[i] == me,
                                  claiming: claimingRank == i + 1,
                                  claimedOf: (kind) => claimedOf(i + 1, kind),
                                  onClaim: (kind) => onClaim(i + 1, kind),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PodiumTile extends ConsumerWidget {
  const _PodiumTile({
    required this.rank,
    required this.weekly,
    required this.accountId,
    required this.mine,
    required this.claiming,
    required this.claimedOf,
    required this.onClaim,
  });

  final int rank;
  final bool weekly;
  final String accountId;
  final bool mine;
  final bool claiming;
  final bool Function(TicketKind kind) claimedOf;
  final void Function(TicketKind kind) onClaim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final card = ref.watch(cardOfProvider(accountId)).valueOrNull;
    final reward = leaderboardReward(weekly: weekly, rank: rank);
    return GlossSurface(
      radius: 18,
      tint: mine ? skin.accentWash : null,
      borderColor: mine ? skin.accentDeep : null,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtIconView(_medalFor(rank), size: 34),
          const SizedBox(height: 8),
          CardTama(accountId: accountId, size: 56, card: card),
          const SizedBox(height: 8),
          Text(
            card?.displayName ?? '···',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Ty.caption.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(l.leaderboardsRank(rank), style: Ty.micro.copyWith(color: Ty.inkSoft)),
          if (mine && reward != null) ...[
            const SizedBox(height: 8),
            for (final entry in reward.entries)
              _ClaimButton(
                kind: entry.key,
                amount: entry.value,
                claimed: claimedOf(entry.key),
                claiming: claiming,
                onPressed: () => onClaim(entry.key),
              ),
          ],
        ],
      ),
    );
  }
}

class _ClaimButton extends StatelessWidget {
  const _ClaimButton({
    required this.kind,
    required this.amount,
    required this.claimed,
    required this.claiming,
    required this.onPressed,
  });

  final TicketKind kind;
  final int amount;
  final bool claimed;
  final bool claiming;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final art = kind == TicketKind.kinken ? ArtIcon.ticketKinken : ArtIcon.ticketGachaken;
    if (claimed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(Glyph.check, size: 15, color: T.correct),
            const SizedBox(width: 4),
            Text(l.leaderboardsClaimed, style: Ty.micro.copyWith(color: T.correct)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtIconView(art, size: 22),
          const SizedBox(width: 6),
          Flexible(
            child: IbashoButton(
              label: claiming ? l.leaderboardsClaiming : '${l.leaderboardsClaim} ${l.leaderboardsReward(amount)}',
              tone: ButtonTone.accent,
              height: 36,
              expand: true,
              cue: null,
              onPressed: claiming ? null : onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Panel de abajo: la clasificación en curso -----------------------------

class _StandingsPanel extends StatelessWidget {
  const _StandingsPanel({
    required this.loading,
    required this.weekly,
    required this.game,
    required this.period,
    required this.me,
    required this.scoreText,
  });

  final bool loading;
  final bool weekly;
  final LeaderboardGame game;
  final LeaderboardPeriod period;
  final String me;
  final String Function(int score) scoreText;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final ranked = period.ranked(game);
    final myRank = period.rankOf(game, me);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  weekly ? l.leaderboardsStandingsWeekly : l.leaderboardsStandingsDaily,
                  style: Ty.lead,
                ),
              ),
              if (myRank != null)
                _RankChip(text: l.leaderboardsYourRank(myRank))
              else
                Text(l.leaderboardsNoScore, style: Ty.caption.copyWith(color: Ty.inkSoft)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const SizedBox()
                : ranked.isEmpty
                    ? Center(
                        child: Text(
                          l.leaderboardsStandingsEmpty,
                          style: Ty.body.copyWith(color: Ty.inkSoft),
                        ),
                      )
                    : IbashoScroll(
                        child: Column(
                          children: [
                            for (var i = 0; i < ranked.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _StandingRow(
                                rank: i + 1,
                                accountId: ranked[i].accountId,
                                mine: ranked[i].accountId == me,
                                scoreText: scoreText(ranked[i].score),
                              ),
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 14,
      tint: skin.accent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, style: Ty.caption.copyWith(color: T.onAccent, fontWeight: FontWeight.w600)),
    );
  }
}

class _StandingRow extends ConsumerWidget {
  const _StandingRow({
    required this.rank,
    required this.accountId,
    required this.mine,
    required this.scoreText,
  });

  final int rank;
  final String accountId;
  final bool mine;
  final String scoreText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = IbashoSkin.of(context);
    final card = ref.watch(cardOfProvider(accountId)).valueOrNull;
    return GlossSurface(
      radius: 16,
      recessed: !mine,
      tint: mine ? skin.accentWash : null,
      borderColor: mine ? skin.accentDeep : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: Ty.numeral(18, color: rank <= 3 ? skin.accentDeep : Ty.inkSoft, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          CardTama(accountId: accountId, size: 40, card: card),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              card?.displayName ?? '···',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ty.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(scoreText, style: Ty.numeral(18, color: Ty.ink, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
