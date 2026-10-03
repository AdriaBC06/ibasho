// Ibasho — el canal de Tsumiki: el menú (solo, versus, historial), los
// retos entre amigos y la sala del versus.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../audio/audio_service.dart';
import '../../backend/tsumiki_versus.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/tsumiki_versus.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/social/social_widgets.dart' show CardTama, CountBadge;
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/hint_bubble.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/panel.dart' show IbashoScroll;
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/slot_tile.dart';
import '../game_stage.dart';
import '../koen/koen_album.dart' show koenFriendName;
import 'tsumiki_channel.dart';
import 'tsumiki_vs_play.dart';

enum _View { menu, solo, lobby, history }

/// El canal de Tsumiki.
///
/// Entra a un menú: solo (la partida de siempre), versus (retar a un amigo o
/// responder a sus retos) e historial (las partidas con cada amigo). Los
/// retos que llegan se ven al momento en cualquier parte del canal.
class TsumikiChannel extends ConsumerStatefulWidget {
  const TsumikiChannel({super.key});

  @override
  ConsumerState<TsumikiChannel> createState() => _TsumikiChannelState();
}

class _TsumikiChannelState extends ConsumerState<TsumikiChannel> {
  _View _view = _View.menu;
  String? _historyFriend;
  late final TsumikiVersusController _vs = ref.read(tsumikiVersusProvider.notifier);
  final GlobalKey<TsumikiVersusPlayState> _play = GlobalKey<TsumikiVersusPlayState>();
  Timer? _waitTick;

  @override
  void initState() {
    super.initState();
    // Se guarda ya: al cerrar el canal hace falta y `ref` ya no vale.
    _vs;
  }

  @override
  void dispose() {
    _waitTick?.cancel();
    // Salir del canal retira la invitación o rinde la partida.
    final p = _play.currentState;
    unawaited(_vs.close(lines: p?.lines ?? 0, sent: p?.sent ?? 0));
    super.dispose();
  }

  void _go(_View v) => setState(() {
        _view = v;
        if (v != _View.history) _historyFriend = null;
      });

  Future<void> _invite(String friend) async {
    await _vs.invite(friend);
  }

  Future<void> _accept(TsumikiInvite invite) async {
    _go(_View.lobby);
    final ok = await _vs.accept(invite);
    if (!ok && mounted) showIbashoToast(context, L.of(context)!.tsumikiVsCancelled);
  }

  Future<void> _leaveRoom() async {
    final p = _play.currentState;
    await _vs.close(lines: p?.lines ?? 0, sent: p?.sent ?? 0);
    if (mounted) _go(_View.lobby);
  }

  Future<void> _askLeave() async {
    final l = L.of(context)!;
    final friend = ref.read(tsumikiVersusProvider).friend;
    final yes = await askConfirmation(
      context,
      title: l.tsumikiVsLeaveTitle,
      body: l.tsumikiVsLeaveBody(friend == null ? '' : koenFriendName(ref, friend)),
      confirmLabel: l.tsumikiVsLeaveConfirm,
      cancelLabel: l.tsumikiVsStay,
      width: 420,
    );
    if (yes && mounted) await _leaveRoom();
  }

  /// La cruz y el atrás del sistema: un paso atrás dentro del canal.
  void _back() {
    final vs = ref.read(tsumikiVersusProvider);
    if (vs.phase == TsumikiVsPhase.playing) {
      unawaited(_askLeave());
      return;
    }
    AudioService.instance.play(Sfx.back);
    if (vs.phase != TsumikiVsPhase.idle) {
      unawaited(_leaveRoom());
    } else if (_view == _View.history && _historyFriend != null) {
      setState(() => _historyFriend = null);
    } else if (_view != _View.menu) {
      _go(_View.menu);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _showInvite(TsumikiInvite invite) async {
    final l = L.of(context)!;
    final yes = await askConfirmation(
      context,
      title: l.tsumikiVsInviteFrom(koenFriendName(ref, invite.from)),
      body: l.tsumikiVsHowTo,
      confirmLabel: l.tsumikiVsAccept,
      cancelLabel: l.tsumikiVsDecline,
      width: 440,
    );
    if (!mounted) return;
    if (yes) {
      await _accept(invite);
    } else {
      await _vs.decline(invite);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final vs = ref.watch(tsumikiVersusProvider);
    final invites = ref.watch(tsumikiInvitesProvider).valueOrNull ?? const <TsumikiInvite>[];
    _syncWaitTick(vs);

    // El aviso de reto: en el menú, a solas o en el historial (en la sala de
    // rivales ya salen en la lista; en partida no se molesta).
    final notice = vs.phase == TsumikiVsPhase.idle && _view != _View.lobby && invites.isNotEmpty
        ? _InviteNotice(
            invite: invites.last,
            onOpen: () => unawaited(_showInvite(invites.last)),
          )
        : null;

    if (_view == _View.solo && vs.phase == TsumikiVsPhase.idle) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _go(_View.menu);
        },
        child: Stack(
          children: [
            TsumikiSolo(onBack: () => _go(_View.menu)),
            if (notice != null) Positioned(top: Layout.of(context).header + 4, left: 0, right: 0, child: Center(child: notice)),
          ],
        ),
      );
    }

    final Widget body = switch (vs.phase) {
      TsumikiVsPhase.idle => switch (_view) {
          _View.lobby => _Lobby(invites: invites, onInvite: _invite, onAccept: _accept, onDecline: _vs.decline),
          _View.history => _History(
              friend: _historyFriend,
              onPick: (f) => setState(() => _historyFriend = f),
              onChallenge: (f) {
                _go(_View.lobby);
                unawaited(_invite(f));
              },
            ),
          _ => _Menu(pending: invites.length, onPick: _go),
        },
      TsumikiVsPhase.playing || TsumikiVsPhase.done when vs.room != null && _playRoom(vs) != null =>
        TsumikiVersusPlay(
          key: _play,
          room: _playRoom(vs)!,
          onLeave: () => unawaited(_askLeave()),
          onExit: () => unawaited(_leaveRoom()),
        ),
      _ => _RoomCard(state: vs, onWithdraw: () => unawaited(_leaveRoom()), onBack: () => unawaited(_leaveRoom())),
    };

    return PopScope(
      canPop: vs.phase == TsumikiVsPhase.idle && _view == _View.menu,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: ChannelScaffold(
        title: l.tsumikiTitle,
        glyph: Glyph.blocks,
        art: ArtIcon.tsumiki,
        onClose: _back,
        child: Stack(
          children: [
            Positioned.fill(
              child: KeyedSubtree(key: ValueKey<String>('tsumiki.view.${vs.matchId ?? _view.name}'), child: body),
            ),
            if (notice != null) Positioned(top: 4, left: 0, right: 0, child: Center(child: notice)),
          ],
        ),
      ),
    );
  }

  /// La sala de la partida que se juega (o se acaba de jugar): la primera
  /// que se vio en juego con el id de esta partida.
  TsumikiRoom? _playRoom(TsumikiVsState vs) {
    final room = vs.room;
    if (room != null && room.id == vs.matchId && room.state != TsumikiRoomState.wait && _started?.id != room.id) {
      _started = room;
    }
    // Con la revancha del otro, la sala ya es otra: se sigue enseñando la
    // acabada hasta que se acepte.
    return _started?.id == vs.matchId ? _started : null;
  }

  TsumikiRoom? _started;

  /// Mientras se espera respuesta, cada segundo: la cuenta atrás y la
  /// caducidad.
  void _syncWaitTick(TsumikiVsState vs) {
    final waiting = vs.phase == TsumikiVsPhase.waiting;
    if (waiting && _waitTick == null) {
      _waitTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        unawaited(_vs.checkExpiry());
        setState(() {});
      });
    } else if (!waiting && _waitTick != null) {
      _waitTick!.cancel();
      _waitTick = null;
    }
  }
}

// --- Menú ----------------------------------------------------------------------

class _Menu extends StatelessWidget {
  const _Menu({required this.pending, required this.onPick});

  final int pending;
  final ValueChanged<_View> onPick;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tiles = [
      _MenuTile(
        key: const ValueKey<String>('tsumiki.menu.solo'),
        glyph: Glyph.blocks,
        title: l.tsumikiMenuSolo,
        hint: l.tsumikiMenuSoloHint,
        onPressed: () => onPick(_View.solo),
      ),
      _MenuTile(
        key: const ValueKey<String>('tsumiki.menu.versus'),
        glyph: Glyph.friends,
        title: l.tsumikiMenuVersus,
        hint: l.tsumikiMenuVersusHint,
        badge: pending,
        accent: true,
        onPressed: () => onPick(_View.lobby),
      ),
      _MenuTile(
        key: const ValueKey<String>('tsumiki.menu.history'),
        glyph: Glyph.trophy,
        title: l.tsumikiMenuHistory,
        hint: l.tsumikiMenuHistoryHint,
        onPressed: () => onPick(_View.history),
      ),
    ];
    if (layout.tall) {
      return IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, 24),
        child: Column(
          children: [
            // Hueco para el aviso de reto, que va arriba.
            const SizedBox(height: 52),
            for (final t in tiles) ...[SizedBox(height: 112, child: t), const SizedBox(height: 12)],
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ArtIconView(ArtIcon.tsumiki, size: 110),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SizedBox(
              height: 220,
              child: Row(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 18),
                    Expanded(child: tiles[i]),
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

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.glyph,
    required this.title,
    required this.hint,
    required this.onPressed,
    this.badge = 0,
    this.accent = false,
  });

  final Glyph glyph;
  final String title;
  final String hint;
  final VoidCallback onPressed;
  final int badge;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    final icon = GlyphIcon(glyph, size: tall ? 34 : 46, color: skin.accentDeep, strokeWidth: 2.4);
    final text = Column(
      crossAxisAlignment: tall ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Ty.title.copyWith(color: skin.accentDeep)),
        const SizedBox(height: 4),
        Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: tall ? TextAlign.start : TextAlign.center, style: Ty.caption),
      ],
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Pressable(
            semanticLabel: title,
            onPressed: onPressed,
            builder: (context, st) => GlossSurface(
              radius: 28,
              tint: accent ? skin.accentWash : null,
              elevation: 1.6 + st.hover - st.press,
              sink: st.press,
              padding: const EdgeInsets.all(18),
              child: tall
                  ? Row(children: [icon, const SizedBox(width: 16), Expanded(child: text)])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [icon, const SizedBox(height: 12), text]),
            ),
          ),
        ),
        if (badge > 0) Positioned(top: -6, right: -6, child: CountBadge(count: badge)),
      ],
    );
  }
}

// --- El aviso de reto ------------------------------------------------------------

class _InviteNotice extends ConsumerWidget {
  const _InviteNotice({required this.invite, required this.onOpen});

  final TsumikiInvite invite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: Pressable(
        key: const ValueKey<String>('tsumiki.notice'),
        semanticLabel: l.tsumikiVsInviteFrom(koenFriendName(ref, invite.from)),
        onPressed: onOpen,
        builder: (context, st) => GlossSurface(
          radius: 24,
          tint: skin.accent,
          elevation: 2.4 - st.press,
          sink: st.press,
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 36, height: 36, child: IgnorePointer(child: CardTama(accountId: invite.from, size: 36))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l.tsumikiVsInviteFrom(koenFriendName(ref, invite.from)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body.copyWith(color: T.onAccent, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(l.tsumikiVsSee, style: Ty.caption.copyWith(color: T.onAccent)),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Sala de rivales -------------------------------------------------------------

class _Lobby extends ConsumerWidget {
  const _Lobby({required this.invites, required this.onInvite, required this.onAccept, required this.onDecline});

  final List<TsumikiInvite> invites;
  final Future<void> Function(String friend) onInvite;
  final Future<void> Function(TsumikiInvite) onAccept;
  final Future<void> Function(TsumikiInvite) onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final layout = Layout.of(context);
    final friends = ref.watch(friendsProvider.select((f) => f.friends));
    return IbashoScroll(
      padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final inv in invites.reversed) ...[
                GlossSurface(
                  key: ValueKey<String>('tsumiki.invite.${inv.from}'),
                  radius: 24,
                  tint: skin.accentWash,
                  elevation: 1.6,
                  padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  child: _InviteRow(
                    invite: inv,
                    tall: layout.tall,
                    onAccept: () => unawaited(onAccept(inv)),
                    onDecline: () => unawaited(onDecline(inv)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              Text(l.tsumikiVsPickFriend, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 10),
              if (friends.isEmpty)
                Text(l.tsumikiVsNoFriends, style: Ty.body)
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final f in friends)
                      SlotTile(
                        key: ValueKey<String>('tsumiki.friend.${f.accountId}'),
                        width: 104,
                        height: 120,
                        semanticLabel: koenFriendName(ref, f.accountId),
                        onPressed: () => unawaited(onInvite(f.accountId)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                          child: Column(
                            children: [
                              Expanded(child: IgnorePointer(child: CardTama(accountId: f.accountId, size: 72))),
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
              const SizedBox(height: 18),
              GlossSurface(
                radius: 20,
                recessed: true,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.tsumikiVsHowTo, style: Ty.caption.copyWith(color: Ty.ink)),
                    const SizedBox(height: 6),
                    Text(l.tsumikiVsNoCoins, style: Ty.micro),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un reto recibido: su Tama, quién reta y sí o no. En vertical los
/// botones van debajo, para que quepa el nombre.
class _InviteRow extends ConsumerWidget {
  const _InviteRow({required this.invite, required this.tall, required this.onAccept, required this.onDecline});

  final TsumikiInvite invite;
  final bool tall;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final who = Row(
      children: [
        SizedBox(width: 52, height: 52, child: IgnorePointer(child: CardTama(accountId: invite.from, size: 52))),
        const SizedBox(width: 10),
        Expanded(
          child: Text(l.tsumikiVsInviteFrom(koenFriendName(ref, invite.from)), style: Ty.body.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
    final buttons = [
      IbashoButton(
        key: ValueKey<String>('tsumiki.invite.${invite.from}.no'),
        label: l.tsumikiVsDecline,
        tone: ButtonTone.quiet,
        height: 40,
        cue: Sfx.back,
        onPressed: onDecline,
      ),
      const SizedBox(width: 6),
      IbashoButton(
        key: ValueKey<String>('tsumiki.invite.${invite.from}.yes'),
        label: l.tsumikiVsAccept,
        tone: ButtonTone.accent,
        height: 40,
        onPressed: onAccept,
      ),
    ];
    if (tall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [who, const SizedBox(height: 6), Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons)],
      );
    }
    return Row(children: [Expanded(child: who), ...buttons]);
  }
}

// --- Espera y avisos de la sala ----------------------------------------------------

/// Todo lo de la sala que no es jugar: mandando, esperando respuesta, y los
/// finales sin partida (no puede, caducada, cancelada, sin conexión).
class _RoomCard extends ConsumerWidget {
  const _RoomCard({required this.state, required this.onWithdraw, required this.onBack});

  final TsumikiVsState state;
  final VoidCallback onWithdraw;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final friend = state.friend;
    final name = friend == null ? '' : koenFriendName(ref, friend);
    final room = state.room;
    String? left;
    if (state.phase == TsumikiVsPhase.waiting && room != null) {
      final ms = tsumikiInviteTtl.inMilliseconds - (DateTime.now().millisecondsSinceEpoch - room.at);
      final s = (ms / 1000).ceil().clamp(0, tsumikiInviteTtl.inSeconds);
      left = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    final (title, hint, waiting) = switch (state.phase) {
      TsumikiVsPhase.waiting => (l.tsumikiVsWaiting(name), l.tsumikiVsWaitingHint, true),
      TsumikiVsPhase.declined => (l.tsumikiVsDeclined(name), null, false),
      TsumikiVsPhase.expired => (l.tsumikiVsExpired(name), null, false),
      TsumikiVsPhase.cancelled => (l.tsumikiVsCancelled, null, false),
      TsumikiVsPhase.failed => (l.tsumikiVsFailed, null, false),
      _ => (l.tsumikiVsJoining, null, true),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PopIn(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: GlossSurface(
              key: ValueKey<String>('tsumiki.room.${state.phase.name}'),
              radius: 30,
              elevation: 3,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (friend != null)
                    SizedBox(width: 110, height: 110, child: CardTama(accountId: friend, size: 110, joy: waiting ? .6 : -.2)),
                  const SizedBox(height: 8),
                  Text(title, textAlign: TextAlign.center, style: Ty.title.copyWith(color: skin.accentDeep)),
                  if (hint != null) ...[
                    const SizedBox(height: 4),
                    Text(hint, textAlign: TextAlign.center, style: Ty.caption),
                  ],
                  if (left != null) ...[
                    const SizedBox(height: 8),
                    Text(l.tsumikiVsExpiresIn(left), style: Ty.numeral(18, color: Ty.ink, weight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 16),
                  if (state.phase == TsumikiVsPhase.waiting)
                    IbashoButton(
                      key: const ValueKey<String>('tsumiki.room.withdraw'),
                      label: l.tsumikiVsWithdraw,
                      glyph: Glyph.cross,
                      expand: true,
                      cue: Sfx.back,
                      onPressed: onWithdraw,
                    )
                  else if (!waiting)
                    IbashoButton(
                      key: const ValueKey<String>('tsumiki.room.back'),
                      label: l.actionBack,
                      tone: ButtonTone.accent,
                      expand: true,
                      cue: Sfx.back,
                      onPressed: onBack,
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

// --- Historial -------------------------------------------------------------------

class _History extends ConsumerWidget {
  const _History({required this.friend, required this.onPick, required this.onChallenge});

  final String? friend;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onChallenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    return IbashoScroll(
      padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: friend == null
              ? _HistoryFriends(onPick: onPick)
              : TsumikiHistoryWith(friend: friend!, onChallenge: () => onChallenge(friend!)),
        ),
      ),
    );
  }
}

class _HistoryFriends extends ConsumerWidget {
  const _HistoryFriends({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final friends = ref.watch(friendsProvider.select((f) => f.friends));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.tsumikiHistPick, style: Ty.title.copyWith(color: skin.accentDeep)),
        const SizedBox(height: 10),
        if (friends.isEmpty)
          Text(l.tsumikiVsNoFriends, style: Ty.body)
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final f in friends)
                SlotTile(
                  key: ValueKey<String>('tsumiki.hist.${f.accountId}'),
                  width: 104,
                  height: 136,
                  semanticLabel: koenFriendName(ref, f.accountId),
                  onPressed: () => onPick(f.accountId),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                    child: Column(
                      children: [
                        Expanded(child: IgnorePointer(child: CardTama(accountId: f.accountId, size: 68))),
                        Text(
                          koenFriendName(ref, f.accountId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.micro.copyWith(color: Ty.ink),
                        ),
                        _ScoreLine(friend: f.accountId, size: 16),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// «3 – 1» con un amigo; nada mientras se lee o si no habéis jugado.
class _ScoreLine extends ConsumerWidget {
  const _ScoreLine({required this.friend, this.size = 16});

  final String friend;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(tsumikiScoreProvider(friend)).valueOrNull;
    if (s == null || s.isEmpty) return SizedBox(height: size * 1.3);
    return Text('${s.mine} – ${s.theirs}', style: Ty.numeral(size, color: IbashoSkin.of(context).accentDeep, weight: FontWeight.w700));
  }
}

/// Las partidas con [friend]: el marcador arriba y una fila por partida.
class TsumikiHistoryWith extends ConsumerWidget {
  const TsumikiHistoryWith({super.key, required this.friend, this.onChallenge});

  final String friend;
  final VoidCallback? onChallenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final me = ref.watch(sessionProvider.select((s) => s.accountId));
    final name = koenFriendName(ref, friend);
    final score = ref.watch(tsumikiScoreProvider(friend)).valueOrNull ?? const TsumikiScore();
    final history = ref.watch(tsumikiHistoryProvider(friend));
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag());
    String why(TsumikiMatchRecord r) {
      final won = r.winner == me;
      return switch ((r.end, won)) {
        (TsumikiEnd.top, true) => l.tsumikiVsWhyTopThem(name),
        (TsumikiEnd.top, false) => l.tsumikiVsWhyTopMe,
        (TsumikiEnd.leave, true) => l.tsumikiVsWhyLeaveThem(name),
        (TsumikiEnd.leave, false) => l.tsumikiVsWhyLeaveMe,
        (TsumikiEnd.quit, true) => l.tsumikiVsWhyQuitThem(name),
        (TsumikiEnd.quit, false) => l.tsumikiVsWhyQuitMe,
      };
    }

    return Column(
      key: ValueKey<String>('tsumiki.history.$friend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlossSurface(
          radius: 26,
          elevation: 1.6,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              SizedBox(width: 64, height: 64, child: IgnorePointer(child: CardTama(accountId: friend, size: 64))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.body.copyWith(fontWeight: FontWeight.w600)),
                    Text(l.tsumikiVsScore, style: Ty.micro),
                    Text('${score.mine} – ${score.theirs}', style: Ty.numeral(28, color: skin.accentDeep, weight: FontWeight.w700)),
                  ],
                ),
              ),
              if (onChallenge != null)
                IbashoButton(
                  key: const ValueKey<String>('tsumiki.history.challenge'),
                  label: l.tsumikiHistChallenge,
                  glyph: Glyph.play,
                  tone: ButtonTone.accent,
                  height: 44,
                  onPressed: onChallenge,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...switch (history) {
          AsyncData(:final value) when value.isEmpty => [Text(l.tsumikiHistEmpty, style: Ty.body)],
          AsyncData(:final value) => [
              for (final r in value) ...[
                _HistoryRow(
                  won: r.winner == me,
                  title: r.winner == me ? l.tsumikiHistWon : l.tsumikiHistLost(name),
                  why: why(r),
                  when: date.format(r.at),
                  length: '${r.seconds ~/ 60}:${(r.seconds % 60).toString().padLeft(2, '0')}',
                  detail: l.tsumikiHistDetail(r.lines[me] ?? 0, r.sent[me] ?? 0),
                ),
                const SizedBox(height: 8),
              ],
            ],
          AsyncError() => [Text(l.tsumikiVsFailed, style: Ty.body)],
          _ => [const SizedBox(height: 40)],
        },
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.won,
    required this.title,
    required this.why,
    required this.when,
    required this.length,
    required this.detail,
  });

  final bool won;
  final String title;
  final String why;
  final String when;
  final String length;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 20,
      recessed: true,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          GlyphIcon(won ? Glyph.trophy : Glyph.flag, size: 24, color: won ? skin.accentDeep : Ty.inkSoft, strokeWidth: 2.2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Ty.body.copyWith(fontWeight: FontWeight.w600, color: won ? skin.accentDeep : Ty.ink)),
                Text('$why · $detail', maxLines: 2, overflow: TextOverflow.ellipsis, style: Ty.micro),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(when, style: Ty.micro),
              Text(length, style: Ty.numeral(14, color: Ty.ink, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// La píldora del marcador en la ficha de un amigo; al tocarla salen las
/// partidas. No aparece si aún no habéis jugado.
class TsumikiScoreChip extends ConsumerWidget {
  const TsumikiScoreChip({super.key, required this.friend});

  final String friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(tsumikiScoreProvider(friend)).valueOrNull;
    if (s == null || s.isEmpty) return const SizedBox.shrink();
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return HintBubble(
      key: ValueKey<String>('friend.tsumiki.$friend'),
      message: l.tsumikiFriendScoreHint,
      onPressed: () {
        AudioService.instance.play(Sfx.tick);
        unawaited(showIbashoModal<void>(context, (_) => _TsumikiHistoryDialog(friend: friend)));
      },
      child: SizedBox(
        height: 30,
        child: GlossSurface(
          radius: 15,
          recessed: true,
          tint: skin.accentWash,
          padding: const EdgeInsets.only(left: 5, right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ArtIconView(ArtIcon.tsumiki, size: 20),
              const SizedBox(width: 6),
              Text(
                l.tsumikiFriendScore(s.mine, s.theirs),
                maxLines: 1,
                style: Ty.caption.copyWith(color: Ty.ink, height: 1.1, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TsumikiHistoryDialog extends ConsumerWidget {
  const _TsumikiHistoryDialog({required this.friend});

  final String friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.tsumikiHistTitle(koenFriendName(ref, friend)),
      width: 560,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: SingleChildScrollView(child: TsumikiHistoryWith(friend: friend)),
      ),
      actions: [
        IbashoButton(
          key: const ValueKey<String>('tsumiki.history.close'),
          label: l.actionClose,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
