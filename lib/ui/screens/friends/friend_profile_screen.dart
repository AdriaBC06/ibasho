// Ibasho — el perfil de un amigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/models.dart';
import '../../../backend/social.dart';
import '../../../backend/tama.dart';
import '../../../core/birthday.dart';
import '../../../core/timezones.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/people.dart';
import '../../../state/profile.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../social/social_widgets.dart';
import '../../tama/tama_widgets.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../channel_route.dart';
import '../channels/friends_channel.dart';
import 'wall_panel.dart';

/// El perfil entero de un amigo: nombre, estado, Tama vivo, color, cumpleaños,
/// su hora local, presencia, insignias y desde cuando sois amigos. Al abrirlo
/// suena su musica en lugar de la de ambiente; el altavoz de la cabecera la
/// calla y se recuerda.
class FriendProfileScreen extends ConsumerStatefulWidget {
  const FriendProfileScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends ConsumerState<FriendProfileScreen> {
  MusicTrack? _playing;

  @override
  void dispose() {
    if (_playing != null) unawaited(AudioService.instance.endProfileTrack());
    super.dispose();
  }

  /// Pone o quita la musica del perfil segun lo que haya elegido el amigo y
  /// el silencio de quien mira.
  void _syncMusic(String? trackId, bool muted) {
    MusicTrack? wanted;
    if (!muted && trackId != null) {
      final track = MusicTrack.byId(trackId);
      if (track.id == trackId) wanted = track;
    }
    if (wanted == _playing) return;
    _playing = wanted;
    unawaited(wanted == null
        ? AudioService.instance.endProfileTrack()
        : AudioService.instance.playProfileTrack(wanted));
  }

  Future<void> _unfriend(String name) async {
    final l = L.of(context)!;
    final yes = await askConfirmation(
      context,
      title: l.friendUnfriendTitle(name),
      body: l.friendUnfriendBody,
      confirmLabel: l.friendUnfriend,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
      width: 560,
    );
    if (!yes || !mounted) return;
    final failure = await ref.read(friendsProvider.notifier).unfriend(widget.accountId);
    if (!mounted) return;
    if (failure == null) {
      AudioService.instance.play(Sfx.back);
      Navigator.of(context).maybePop();
    } else {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, friendFailureText(l, failure), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final account = widget.accountId;
    final muted = ref.watch(preferencesProvider.select((p) => p.profileMusicMuted));
    final music = ref.watch(musicOfProvider(account)).valueOrNull;
    final profile = ref.watch(friendProfileProvider(account));
    final card = ref.watch(cardOfProvider(account)).valueOrNull;
    final friendship = ref.watch(friendsProvider.select((f) => f.friendship(account)));
    final friendsLoaded = ref.watch(friendsProvider.select((f) => f.loaded));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMusic(music?.profileTrack, muted);
    });

    final name = profile.valueOrNull?.displayName ?? card?.displayName ?? '…';

    final mute = IconPill(
      key: const ValueKey<String>('friend.mute'),
      glyph: muted ? Glyph.speakerOff : Glyph.speaker,
      diameter: 46,
      tone: muted ? ButtonTone.plain : ButtonTone.accent,
      semanticLabel: muted ? l.friendMusicUnmute : l.friendMusicMute,
      onPressed: () => unawaited(ref.read(preferencesProvider.notifier).setProfileMusicMuted(!muted)),
    );

    return ChannelScaffold(
      title: name,
      glyph: Glyph.person,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (friendship != null)
            IbashoButton(
              key: const ValueKey<String>('friend.unfriend'),
              label: l.friendUnfriend,
              tone: ButtonTone.quiet,
              height: 40,
              onPressed: () => _unfriend(name),
            ),
          const SizedBox(width: 6),
          mute,
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: friendsLoaded && friendship == null
            ? Center(child: Text(l.friendNotFriends, style: Ty.lead.copyWith(color: T.inkSoft)))
            : profile.when(
                loading: () => Center(child: Text(l.loading, style: Ty.lead)),
                error: (_, _) =>
                    Center(child: Text(l.friendNotFriends, style: Ty.lead.copyWith(color: T.inkSoft))),
                data: (data) => data == null
                    ? Center(child: Text(l.loading, style: Ty.lead))
                    : _Body(
                        accountId: account,
                        profile: data,
                        card: card,
                        friendship: friendship,
                        music: music,
                      ),
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.accountId,
    required this.profile,
    required this.card,
    required this.friendship,
    required this.music,
  });

  final String accountId;
  final UserProfile profile;
  final UserCard? card;
  final Friendship? friendship;
  final MusicOf? music;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(moodClockProvider);
    final party = isBirthdayToday(profile, now);

    return Column(
      children: [
        const SizedBox(height: 14),
        SizedBox(
          height: 330,
          child: ScreenPanel(
            child: Stack(
              children: [
                if (party) const Positioned.fill(child: PartyBackdrop()),
                _Identity(
                  accountId: accountId,
                  profile: profile,
                  card: card,
                  friendship: friendship,
                  music: music,
                  party: party,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ScreenPanel(
            child: WallPanel(accountId: accountId, profile: profile, own: false),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Identity extends ConsumerWidget {
  const _Identity({
    required this.accountId,
    required this.profile,
    required this.card,
    required this.friendship,
    required this.music,
    required this.party,
  });

  final String accountId;
  final UserProfile profile;
  final UserCard? card;
  final Friendship? friendship;
  final MusicOf? music;
  final bool party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final locale = ref.watch(localeProvider).languageCode;
    final now = ref.watch(moodClockProvider);
    final presence = ref.watch(presenceOfProvider(accountId)).valueOrNull ?? Presence.offline;
    final friendCount = ref.watch(friendCountOfProvider(accountId)).valueOrNull ?? 0;
    final tamaId = card?.tamaId;
    final tama = tamaId == null ? null : ref.watch(publicTamaProvider((accountId, tamaId))).valueOrNull;
    final accent = card?.accent ?? profile.accent;
    final badges = badgesFor(
      profile: profile,
      now: now,
      friendsSince: friendship?.since,
      friendCount: friendCount,
      unlockedTracks: music?.unlocked ?? const <String>{},
    );
    final track = music?.profileTrack == null ? null : MusicTrack.byId(music!.profileTrack!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 26, 22),
      child: Row(
        children: [
          SizedBox(
            width: 290,
            child: Center(
              child: tama == null
                  ? SizedBox(
                      width: 190,
                      height: 190,
                      child: GlossSurface(
                        radius: 52,
                        recessed: true,
                        tint: accent,
                        child: Center(
                          child: GlyphIcon(Glyph.tama, size: 90, color: accent, strokeWidth: 2.2),
                        ),
                      ),
                    )
                  : TamaOnStand(
                      key: const ValueKey<String>('friend.tama'),
                      tama: tama,
                      size: 226,
                      joy: party ? 1 : .6,
                      wear: party ? TamaWear.partyHat : TamaWear.none,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (party)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      ageToday(profile, now) == null
                          ? l.friendBirthdayToday
                          : l.friendBirthdayTurns(ageToday(profile, now)!),
                      key: const ValueKey<String>('friend.party'),
                      style: Ty.lead.copyWith(color: T.warn, fontWeight: FontWeight.w700),
                    ),
                  ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.display,
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 46,
                      height: 12,
                      child: GlossSurface(radius: 6, tint: accent, elevation: .6),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  key: const ValueKey<String>('friend.presence'),
                  children: [
                    PresenceLight.of(presence.state, size: 14),
                    const SizedBox(width: 8),
                    Text(presenceLine(l, presence, now), style: Ty.body.copyWith(color: T.inkSoft)),
                  ],
                ),
                if (profile.statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    profile.statusMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.lead.copyWith(color: T.ink, fontWeight: FontWeight.w400),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final badge in badges) BadgeChip(badge: badge)],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    GlyphIcon(Glyph.heart, size: 18, color: skin.accentDeep),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        friendship == null
                            ? ''
                            : l.friendSince(DateFormat.yMMMMd(locale).format(friendship!.since)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.caption.copyWith(color: T.inkSoft),
                      ),
                    ),
                    if (track != null) ...[
                      const SizedBox(width: 18),
                      GlyphIcon(Glyph.note, size: 18, color: skin.accentDeep),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l.friendMusic(track.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.caption.copyWith(color: T.inkSoft),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 290,
            child: _LocalTime(profile: profile, party: party),
          ),
        ],
      ),
    );
  }
}

/// Su hora local, al segundo, con la diferencia respecto a la mia, y su
/// cumpleaños.
class _LocalTime extends ConsumerWidget {
  const _LocalTime({required this.profile, required this.party});

  final UserProfile profile;
  final bool party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final locale = ref.watch(localeProvider).languageCode;
    final now = ref.watch(clockProvider);
    final mine = ref.watch(profileProvider.select((p) => p.profile?.timezone)) ?? '';
    final myZone = mine.isEmpty ? localTimezoneName() : mine;
    final theirZone = profile.timezone.isEmpty ? myZone : profile.timezone;
    final there = wallClockIn(theirZone, now);
    final difference = zoneDifference(theirZone, myZone, now);
    final parts = profile.birthdayParts;
    final zone = zoneById(theirZone);

    return GlossSurface(
      radius: 24,
      elevation: 1.4,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              GlyphIcon(Glyph.clock, size: 18, color: skin.accentDeep),
              const SizedBox(width: 8),
              Text(l.friendLocalTime, style: Ty.label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('HH:mm').format(there),
            key: const ValueKey<String>('friend.localTime'),
            style: Ty.clock(T.ink),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat.MMMEd(locale).format(there),
            style: Ty.caption.copyWith(color: T.inkSoft),
          ),
          const SizedBox(height: 2),
          Text(
            zoneDifferenceLabel(l, difference),
            key: const ValueKey<String>('friend.timeDifference'),
            style: Ty.body.copyWith(color: skin.accentDeep, fontWeight: FontWeight.w500),
          ),
          Text(
            zone?.city ?? theirZone,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ty.micro,
          ),
          const SizedBox(height: 12),
          const Hairline(),
          const SizedBox(height: 12),
          Row(
            children: [
              GlyphIcon(Glyph.cake, size: 18, color: party ? T.warn : skin.accentDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  parts == null
                      ? l.friendNoBirthday
                      : DateFormat.MMMMd(locale).format(DateTime(2000, parts.$2, parts.$3)),
                  style: Ty.body,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// El dia del cumpleaños el panel se viste de fiesta: una guirnalda de
/// banderines arriba y confeti quieto salpicado. Es fondo, no se anima.
class PartyBackdrop extends StatelessWidget {
  const PartyBackdrop({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _PartyPainter()),
      );
}

class _PartyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.partyWash, T.glintNone],
        ).createShader(rect),
    );

    // Guirnalda: un cordel en catenaria con banderines colgando.
    const flags = 17;
    final cord = Path()..moveTo(0, 6);
    for (var i = 1; i <= 40; i++) {
      final t = i / 40;
      cord.lineTo(size.width * t, 6 + math.sin(t * math.pi * 3) .abs() * 12);
    }
    canvas.drawPath(
      cord,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = T.hairline,
    );
    for (var i = 0; i < flags; i++) {
      final t = (i + .5) / flags;
      final x = size.width * t;
      final y = 6 + (math.sin(t * math.pi * 3)).abs() * 12;
      final colour = T.confetti[i % T.confetti.length];
      final flag = Path()
        ..moveTo(x - 9, y)
        ..lineTo(x + 9, y)
        ..lineTo(x, y + 18)
        ..close();
      canvas.drawPath(flag, Paint()..color = colour);
      canvas.drawPath(
        Path()
          ..moveTo(x - 6, y + 2)
          ..lineTo(x - 1, y + 2),
        Paint()
          ..color = T.glintStrong
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Confeti con semilla fija: siempre cae igual.
    final random = math.Random(14);
    for (var i = 0; i < 46; i++) {
      final colour = T.confetti[i % T.confetti.length].withValues(alpha: .7);
      final c = Offset(random.nextDouble() * size.width, 34 + random.nextDouble() * (size.height - 44));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(random.nextDouble() * math.pi);
      if (i.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 8, height: 3.4), const Radius.circular(1.5)),
          Paint()..color = colour,
        );
      } else {
        canvas.drawCircle(Offset.zero, 2.4, Paint()..color = colour);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PartyPainter old) => false;
}
