// Ibasho — canal de mensajes.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/identity.dart';
import '../../../state/messages.dart';
import '../../../state/providers.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../social/social_widgets.dart';
import '../../../state/people.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
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
          Text(l.keysUnavailable, style: Ty.body.copyWith(color: Ty.inkSoft)),
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

/// La lista de amigos, de la conversacion mas reciente a la mas antigua.
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
        if (friends.friends.isEmpty)
          SectionCard(
            title: l.messagesTitle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                friends.loaded ? l.messagesNoFriends : l.keysPreparing,
                textAlign: TextAlign.center,
                style: Ty.body.copyWith(color: Ty.inkSoft),
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
            GlyphIcon(Glyph.lock, size: 14, color: Ty.inkSoft),
            const SizedBox(width: 7),
            Text(l.messagesPrivacy, style: Ty.caption.copyWith(color: Ty.inkSoft)),
          ],
        ),
      ],
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
              GlyphIcon(Glyph.arrowRight, size: 16, color: Ty.inkSoft),
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
          style: Ty.body.copyWith(color: Ty.inkSoft),
        ),
      );
}
