// Ibasho — canal de mensajes.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/messaging.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/identity.dart';
import '../../../state/messages.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../social/social_widgets.dart';
import '../../../state/people.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/pressable.dart';
import '../channel_route.dart';
import '../messages/backup_key.dart';
import '../messages/conversation_screen.dart';

/// El canal de mensajes.
///
/// Antes de cualquier conversacion esta el cifrado: sin claves en este aparato
/// no hay nada que leer, asi que lo primero que decide esta pantalla es si hay
/// que crear la clave de respaldo, pedirla o seguir adelante. Es la unica
/// parte de Ibasho que puede pedir algo antes de dejarte pasar, y por eso lo
/// hace aqui dentro y no en el arranque: quien no use los mensajes no tiene
/// por que enterarse.
class MessagesChannel extends ConsumerWidget {
  const MessagesChannel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final identity = ref.watch(identityProvider);

    return ChannelScaffold(
      title: l.messagesTitle,
      glyph: Glyph.chat,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          layout.pick(28, 18),
          layout.gutter,
          44,
        ),
        child: Center(
          child: SizedBox(
            width: layout.pick(880, layout.column),
            child: switch (identity.phase) {
              IdentityPhase.loading => _Notice(text: l.keysPreparing),
              IdentityPhase.fresh => BackupKeyPanel(
                  words: identity.phrase,
                  onDone: () => AudioService.instance.play(Sfx.tick),
                ),
              IdentityPhase.needsPhrase => const RestoreKeyPanel(),
              IdentityPhase.unavailable => _Unavailable(),
              IdentityPhase.ready => const _Conversations(),
            },
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    return SectionCard(
      title: l.keysLockedTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(l.keysUnavailable, style: Ty.body.copyWith(color: T.inkSoft)),
          const SizedBox(height: 16),
          IbashoButton(
            label: l.keysRetry,
            glyph: Glyph.refresh,
            onPressed: () =>
                unawaited(ref.read(identityProvider.notifier).retry()),
          ),
        ],
      ),
    );
  }
}

/// La lista: primero el grupo, luego los amigos.
class _Conversations extends ConsumerWidget {
  const _Conversations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final channel = ref.watch(messagesProvider);
    final friends = ref.watch(friendsProvider);
    // De la conversacion mas reciente a la mas antigua, no por antiguedad de
    // la amistad: lo que se busca aqui es con quien hablabas hace un rato.
    final conversaciones =
        channel.byRecency(friends.friends, (f) => f.accountId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GlobalGroup(),
        const SizedBox(height: 22),
        if (friends.friends.isEmpty)
          SectionCard(
            title: l.messagesTitle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                friends.loaded ? l.messagesNoFriends : l.keysPreparing,
                textAlign: TextAlign.center,
                style: Ty.body.copyWith(color: T.inkSoft),
              ),
            ),
          )
        else
          SectionCard(
            title: l.messagesTitle,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < conversaciones.length; i++) ...[
                  if (i > 0) const Hairline(),
                  _FriendRow(
                    accountId: conversaciones[i].accountId,
                    unread: channel.unreadFrom(conversaciones[i].accountId),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GlyphIcon(Glyph.lock, size: 14, color: T.inkSoft),
            const SizedBox(width: 7),
            Text(l.messagesPrivacy, style: Ty.caption.copyWith(color: T.inkSoft)),
          ],
        ),
      ],
    );
  }
}

/// El grupo Global: se ve siempre, se lee solo desde dentro.
class _GlobalGroup extends ConsumerStatefulWidget {
  const _GlobalGroup();

  @override
  ConsumerState<_GlobalGroup> createState() => _GlobalGroupState();
}

class _GlobalGroupState extends ConsumerState<_GlobalGroup> {
  bool _working = false;
  String? _error;

  Future<void> _join() async {
    final l = L.of(context)!;
    setState(() {
      _working = true;
      _error = null;
    });
    final failure = await ref.read(messagesProvider.notifier).joinGlobal();
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = switch (failure) {
        JoinFailure.full => l.groupFull,
        JoinFailure.closed => l.groupClosed,
        JoinFailure.noKeys => l.groupNoKeys,
        JoinFailure.network => l.messagesFailed,
        null => null,
      };
    });
    AudioService.instance.play(failure == null ? Sfx.open : Sfx.error);
  }

  Future<void> _leave() async {
    final l = L.of(context)!;
    final confirmed = await askConfirmation(
      context,
      title: l.groupLeaveConfirmTitle,
      body: l.groupLeaveConfirmBody,
      confirmLabel: l.groupLeave,
      cancelLabel: l.actionCancel,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(messagesProvider.notifier).leaveGlobal();
    if (mounted) AudioService.instance.play(ok ? Sfx.back : Sfx.error);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final channel = ref.watch(messagesProvider);
    final group = channel.global;

    if (group == null) {
      return SectionCard(
        title: l.groupGlobalName,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            channel.loaded ? l.groupMissing : l.keysPreparing,
            textAlign: TextAlign.center,
            style: Ty.body.copyWith(color: T.inkSoft),
          ),
        ),
      );
    }

    return SectionCard(
      title: group.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            channel.inGlobal
                ? l.groupMembers(channel.globalMembers.length)
                : l.groupLockedBody,
            style: Ty.body.copyWith(color: T.inkSoft),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: Ty.caption.copyWith(color: T.warn)),
          ],
          const SizedBox(height: 16),
          if (channel.inGlobal)
            Row(
              children: [
                Expanded(
                  child: IbashoButton(
                    label: group.name,
                    glyph: Glyph.chat,
                    tone: ButtonTone.accent,
                    expand: true,
                    onPressed: () => _open(context),
                  ),
                ),
                const SizedBox(width: 12),
                IconPill(
                  glyph: Glyph.power,
                  semanticLabel: l.groupLeave,
                  onPressed: () => unawaited(_leave()),
                ),
                if (channel.unreadInGlobal) ...[
                  const SizedBox(width: 10),
                  const CountBadge(count: 1, size: 14),
                ],
              ],
            )
          else ...[
            IbashoButton(
              label: _working ? l.groupJoining : l.groupJoin,
              glyph: Glyph.personPlus,
              tone: ButtonTone.accent,
              onPressed: _working ? null : () => unawaited(_join()),
            ),
            const SizedBox(height: 10),
            Text(
              l.groupJoinedNote,
              style: Ty.caption.copyWith(color: skin.accentDeep),
            ),
          ],
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    final l = L.of(context)!;
    final channel = ref.read(messagesProvider);
    pushChannelPage<void>(
      context,
      (_) => ConversationScreen(
        target: const GroupTarget(globalGroupId),
        title: channel.global?.name ?? l.groupGlobalName,
        subtitle: l.groupMembers(channel.globalMembers.length),
      ),
    );
  }
}

/// Una fila de la lista: el Tama de perfil, el nombre y el punto de sin leer.
class _FriendRow extends ConsumerWidget {
  const _FriendRow({required this.accountId, required this.unread});

  final String accountId;
  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(cardOfProvider(accountId)).valueOrNull;
    final name = card?.displayName ?? '';

    return Pressable(
      onPressed: () => pushChannelPage<void>(
        context,
        (_) => ConversationScreen(
          target: DirectTarget(accountId),
          title: name,
        ),
      ),
      semanticLabel: name,
      builder: (context, state) => FocusRing(
        visible: state.focus,
        radius: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              CardTama(accountId: accountId, size: 40, card: card),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body,
                ),
              ),
              if (unread) const CountBadge(count: 1, size: 14),
              const SizedBox(width: 10),
              const GlyphIcon(Glyph.arrowRight, size: 16, color: T.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Ty.body.copyWith(color: T.inkSoft),
        ),
      );
}
