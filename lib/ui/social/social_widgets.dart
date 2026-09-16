// Ibasho — piezas de interfaz de amigos: presencia, avatar e insignias.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/models.dart';
import '../../backend/social.dart';
import '../../backend/tama.dart';
import '../../core/birthday.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/people.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../tama/tama_view.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';

// --- Textos -------------------------------------------------------------------

String presenceLabel(L l, PresenceState state) => switch (state) {
      PresenceState.online => l.presenceOnline,
      PresenceState.away => l.presenceAway,
      PresenceState.busy => l.presenceBusy,
      PresenceState.offline => l.presenceOffline,
    };

String presenceModeLabel(L l, PresenceMode mode) => switch (mode) {
      PresenceMode.online => l.presenceOnline,
      PresenceMode.away => l.presenceAway,
      PresenceMode.busy => l.presenceBusy,
      PresenceMode.invisible => l.presenceInvisible,
    };

String presenceModeHint(L l, PresenceMode mode) => switch (mode) {
      PresenceMode.online => l.presenceOnlineHint,
      PresenceMode.away => l.presenceAwayHint,
      PresenceMode.busy => l.presenceBusyHint,
      PresenceMode.invisible => l.presenceInvisibleHint,
    };

/// "desconectado · hace 3 h". Solo tiene sentido para desconectado: el resto
/// de estados no ensenan cuando fue la ultima vez.
String presenceLine(L l, Presence presence, DateTime now) {
  final label = presenceLabel(l, presence.state);
  final seen = presence.lastSeen;
  if (presence.state != PresenceState.offline || seen == null) return label;
  final since = now.difference(seen);
  final ago = since.inMinutes < 1
      ? l.seenJustNow
      : since.inMinutes < 60
          ? l.seenMinutesAgo(since.inMinutes)
          : since.inHours < 24
              ? l.seenHoursAgo(since.inHours)
              : l.seenDaysAgo(since.inDays);
  return '$label · $ago';
}

Color presenceColor(PresenceState state) => switch (state) {
      PresenceState.online => T.presenceOnline,
      PresenceState.away => T.presenceAway,
      PresenceState.busy => T.presenceBusy,
      PresenceState.offline => T.presenceOffline,
    };

Color presenceModeColor(PresenceMode mode) => switch (mode) {
      PresenceMode.online => T.presenceOnline,
      PresenceMode.away => T.presenceAway,
      PresenceMode.busy => T.presenceBusy,
      PresenceMode.invisible => T.presenceOffline,
    };

/// "7 h por delante de ti", "misma hora que tu", "2 h 30 min por detras".
String zoneDifferenceLabel(L l, Duration difference) {
  final minutes = difference.inMinutes;
  if (minutes == 0) return l.timeSame;
  final hours = minutes.abs() ~/ 60;
  final rest = minutes.abs() % 60;
  final amount = rest == 0 ? l.timeHours(hours) : l.timeHoursMinutes(hours, rest);
  return minutes > 0 ? l.timeAhead(amount) : l.timeBehind(amount);
}

// --- Piloto de presencia ---------------------------------------------------------

/// El piloto de estado: un LED de plastico con su brillo, como el de una
/// consola. Desconectado se ve apagado.
class PresenceLight extends StatelessWidget {
  const PresenceLight({super.key, required this.color, this.size = 14, this.lit = true});

  PresenceLight.of(PresenceState state, {Key? key, double size = 14})
      : this(key: key, color: presenceColor(state), size: size, lit: state != PresenceState.offline);

  final Color color;
  final double size;
  final bool lit;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-.35, -.4),
              radius: .9,
              colors: [
                Color.lerp(color, T.shellTop, lit ? .55 : .35)!,
                color,
                Color.lerp(color, T.dusk, lit ? .18 : .1)!,
              ],
              stops: const [0, .55, 1],
            ),
            border: Border.all(color: T.shellTop, width: size * .14),
            boxShadow: [
              if (lit)
                BoxShadow(color: color.withValues(alpha: .45), blurRadius: size * .6),
              const BoxShadow(color: T.shadow, blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
        ),
      );
}

// --- Avatar ----------------------------------------------------------------------

/// El Tama de perfil de alguien, sacado de su ficha: lo unico que se puede
/// pintar de una persona que aun no es amiga. Sin Tama, la silueta en su
/// color.
class CardTama extends ConsumerWidget {
  const CardTama({
    super.key,
    required this.accountId,
    required this.size,
    this.card,
    this.interactive = false,
    this.shadow = false,
    this.wear = TamaWear.none,
    this.joy = .5,
  });

  final String accountId;
  final double size;

  /// Si ya se tiene a mano (la busqueda por codigo), no se vuelve a pedir.
  final UserCard? card;

  final bool interactive;
  final bool shadow;
  final TamaWear wear;
  final double joy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = card ?? ref.watch(cardOfProvider(accountId)).valueOrNull;
    final tamaId = resolved?.tamaId;
    final tama = tamaId == null
        ? null
        : ref.watch(publicTamaProvider((accountId, tamaId))).valueOrNull;
    if (tama == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: GlyphIcon(
            Glyph.tama,
            size: size * .5,
            color: (resolved?.accent ?? T.inkSoft).withValues(alpha: .55),
            strokeWidth: 2.2,
          ),
        ),
      );
    }
    return TamaView(
      look: tama.look,
      personality: tama.personality,
      name: tama.name,
      voice: tama.voice,
      seed: tama.id.hashCode ^ size.round(),
      joy: joy,
      size: size,
      interactive: interactive,
      shadow: shadow,
      wear: wear,
    );
  }
}

// --- Insignias -------------------------------------------------------------------

/// Insignias de un perfil. Salen de lo que un amigo puede leer; no se guardan.
enum ProfileBadge {
  /// Hoy es su cumpleaños.
  birthday(Glyph.cake),

  /// Entro en Ibasho el primer año.
  pioneer(Glyph.star),

  /// Sois amigos desde hace mas de un año.
  oldFriend(Glyph.heart),

  /// Tiene cinco amigos o mas.
  social(Glyph.friends),

  /// Ha descubierto todas las canciones.
  musicLover(Glyph.note);

  const ProfileBadge(this.glyph);

  final Glyph glyph;
}

List<ProfileBadge> badgesFor({
  required UserProfile profile,
  required DateTime now,
  DateTime? friendsSince,
  int friendCount = 0,
  Set<String> unlockedTracks = const <String>{},
}) =>
    [
      if (isBirthdayToday(profile, now)) ProfileBadge.birthday,
      if (profile.createdAt.millisecondsSinceEpoch > 0 && profile.createdAt.year <= 2026)
        ProfileBadge.pioneer,
      if (friendsSince != null && now.difference(friendsSince).inDays >= 365)
        ProfileBadge.oldFriend,
      if (friendCount >= 5) ProfileBadge.social,
      if (MusicTrack.values
          .where((t) => !t.unlockedByDefault)
          .every((t) => unlockedTracks.contains(t.id)))
        ProfileBadge.musicLover,
    ];

String badgeLabel(L l, ProfileBadge badge) => switch (badge) {
      ProfileBadge.birthday => l.badgeBirthday,
      ProfileBadge.pioneer => l.badgePioneer,
      ProfileBadge.oldFriend => l.badgeOldFriend,
      ProfileBadge.social => l.badgeSocial,
      ProfileBadge.musicLover => l.badgeMusicLover,
    };

/// Una insignia: pastilla hundida con su icono.
class BadgeChip extends StatelessWidget {
  const BadgeChip({super.key, required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final party = badge == ProfileBadge.birthday;
    final ink = party ? T.warn : skin.accentDeep;
    return SizedBox(
      height: 30,
      child: GlossSurface(
        radius: 15,
        recessed: true,
        tint: party ? T.warn : skin.accent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(badge.glyph, size: 15, color: ink),
            const SizedBox(width: 6),
            // En un lienzo estrecho la insignia no empuja: se recorta su
            // texto antes de desbordar la fila.
            Flexible(
              child: Text(
                badgeLabel(l, badge),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ty.caption.copyWith(color: ink, height: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Numero de solicitudes pendientes sobre un icono: una gota roja de plastico.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.size = 26});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 99 ? '99+' : '$count';
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: size, minHeight: size, maxHeight: size),
      child: GlossSurface(
        radius: size / 2,
        tint: T.badge,
        elevation: 1.4,
        borderColor: T.shellTop,
        borderWidth: 2,
        padding: EdgeInsets.symmetric(horizontal: size * .26),
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            style: Ty.numeral(size * .54, color: T.onAccent, weight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
