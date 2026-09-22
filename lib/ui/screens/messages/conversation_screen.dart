// Ibasho — una conversacion abierta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/messaging.dart';
import '../../../core/clock_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/conversation.dart';
import '../../../state/messages.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../tama/tama_sticker.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/pressable.dart';
import '../../widgets/text_field.dart';
import '../channel_route.dart';
import 'sticker_picker.dart';

/// La conversacion: la lista de mensajes y lo que hace falta para escribir.
///
/// Lo que llega de la base son sobres cerrados; el controlador los abre en un
/// isolate y por tandas, empezando por los ultimos. Por eso al entrar se ve
/// enseguida lo de abajo —que es lo que se estaba mirando— y lo viejo va
/// apareciendo mientras se sube.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.target,
    required this.title,
  });

  final ConversationTarget target;
  final String title;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final TextEditingController _typed = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composer = FocusNode();
  DateTime? _markedUpTo;

  @override
  void dispose() {
    _typed.dispose();
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  /// Apunta la lectura hasta el ultimo mensaje que hay a la vista.
  void _markRead(DateTime? last) {
    if (last == null) return;
    if (_markedUpTo != null && !last.isAfter(_markedUpTo!)) return;
    _markedUpTo = last;
    unawaited(
      ref.read(messagesProvider.notifier).markRead(widget.target, last),
    );
  }

  Future<void> _send(MessageBody body) async {
    final ok = await ref
        .read(conversationProvider(widget.target).notifier)
        .send(body);
    if (!mounted) return;
    AudioService.instance.play(ok ? Sfx.open : Sfx.error);
    if (ok) {
      _typed.clear();
      setState(() {});
      // Al mandar siempre se baja del todo: lo que acabas de escribir tiene
      // que verse, estuvieras donde estuvieras en el historial.
      _jumpToEnd();
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.minScrollExtent);
    });
  }

  Future<void> _sendText() async {
    final text = _typed.text.trim();
    if (text.isEmpty || text.length > messageTextMax) return;
    await _send(TextBody(text));
  }

  Future<void> _sendSticker() async {
    final sticker = await pickSticker(context);
    if (sticker == null || !mounted) return;
    await _send(sticker);
  }

  Future<void> _remove(Message message) async {
    final l = L.of(context)!;
    final confirmed = await askConfirmation(
      context,
      title: l.messagesDeleteTitle,
      body: l.messagesDeleteBody,
      confirmLabel: l.messagesDelete,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref
        .read(conversationProvider(widget.target).notifier)
        .remove(message.id);
    if (mounted) AudioService.instance.play(ok ? Sfx.back : Sfx.error);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final state = ref.watch(conversationProvider(widget.target));
    final me = ref.watch(sessionProvider.select((s) => s.accountId));

    // Marcar leido en cuanto cambia el ultimo mensaje, no al abrir: si llega
    // algo con la conversacion delante, tambien cuenta como leido.
    ref.listen(
      conversationProvider(widget.target).select((s) => s.lastAt),
      (_, after) => _markRead(after),
    );
    _markRead(state.lastAt);

    return ChannelScaffold(
      title: widget.title,
      glyph: Glyph.chat,
      child: Column(
        children: [
          Expanded(
            child: switch (state) {
              ConversationState(loading: true) => _Notice(
                text: l.keysPreparing,
                glyph: Glyph.lock,
              ),
              ConversationState(messages: final m) when m.isEmpty => _Notice(
                text: l.messagesEmptyConversation,
                glyph: Glyph.chat,
              ),
              _ => _Thread(
                state: state,
                me: me,
                scroll: _scroll,
                onDelete: _remove,
              ),
            },
          ),
          _Composer(
            controller: _typed,
            focus: _composer,
            state: state,
            gutter: layout.gutter,
            onChanged: () => setState(() {}),
            onSend: _sendText,
            onSticker: _sendSticker,
          ),
        ],
      ),
    );
  }
}

/// La lista. Va del reves —el ultimo abajo— porque es donde esta la
/// conversacion viva; subir es ir hacia atras en el tiempo.
class _Thread extends StatelessWidget {
  const _Thread({
    required this.state,
    required this.me,
    required this.scroll,
    required this.onDelete,
  });

  final ConversationState state;
  final String me;
  final ScrollController scroll;
  final ValueChanged<Message> onDelete;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final messages = state.messages;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            reverse: true,
            padding: EdgeInsets.fromLTRB(layout.gutter, 16, layout.gutter, 16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[messages.length - 1 - index];
              final previous = index + 1 <= messages.length - 1
                  ? messages[messages.length - 2 - index]
                  : null;
              return _Bubble(
                message: message,
                mine: message.from == me,
                // La cabecera del dia solo cuando cambia: en una conversacion
                // de un rato seguido, una fecha por mensaje seria ruido.
                daySeparator:
                    previous == null || !_sameDay(previous.at, message.at),
                onDelete: message.from == me ? () => onDelete(message) : null,
              );
            },
          ),
        ),
        if (state.decrypting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.messagesDecrypting,
              style: Ty.caption.copyWith(color: T.inkSoft),
            ),
          ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.daySeparator,
    this.onDelete,
  });

  final Message message;
  final bool mine;
  final bool daySeparator;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final code = Localizations.localeOf(context).languageCode;
    final hourFormat24 =
        ref.watch(preferencesProvider.select((p) => p.hourFormat24));
    final body = message.body;

    final content = switch (body) {
      TextBody(:final text) => Text(
        text,
        style: Ty.body.copyWith(color: mine ? T.shellTop : T.ink),
      ),
      StickerBody(:final face, :final name, :final look) => TamaSticker(
        look: look,
        face: face,
        size: 108,
        name: name,
      ),
      null => Text(
        l.messagesUnreadable,
        style: Ty.caption.copyWith(color: T.inkSoft),
      ),
    };

    // Un sticker no lleva bocadillo: es un dibujo suelto, como en las consolas.
    final sticker = body is StickerBody;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (daySeparator)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              DateFormat.yMMMMd(code).format(message.at),
              textAlign: TextAlign.center,
              style: Ty.caption.copyWith(color: T.inkSoft),
            ),
          ),
        Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          // Un mensaje no es un boton: no se abre al pulsarlo. Borrar lo
          // propio se pide con pulsacion larga en el movil y con el boton
          // derecho en el escritorio, que es donde cada uno lo busca.
          child: GestureDetector(
            onLongPress: onDelete,
            child: Pressable(
              onSecondaryPressed: onDelete,
              cue: null,
              semanticLabel: mine ? l.messagesYou : '',
              builder: (context, pressState) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: mine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: sticker
                          ? content
                          : GlossSurface(
                              radius: 14,
                              tint: mine ? skin.accentDeep : T.wellBottom,
                              elevation: mine ? 1 : .4,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 11,
                                ),
                                child: content,
                              ),
                            ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatClock(message.at, hourFormat24: hourFormat24),
                      style: Ty.numeral(11, color: T.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lo de abajo: el campo, el sticker y el boton de mandar.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.state,
    required this.gutter,
    required this.onChanged,
    required this.onSend,
    required this.onSticker,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ConversationState state;
  final double gutter;
  final VoidCallback onChanged;
  final Future<void> Function() onSend;
  final Future<void> Function() onSticker;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final text = controller.text.trim();
    final left = messageTextMax - controller.text.characters.length;

    if (state.block != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 20),
        child: Text(
          switch (state.block!) {
            SendBlock.noKeys => l.keysPreparing,
            SendBlock.otherHasNoKeys => l.messagesOtherNoKeys,
          },
          textAlign: TextAlign.center,
          style: Ty.caption.copyWith(color: T.inkSoft),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconPill(
                key: const ValueKey<String>('conversation.sticker'),
                glyph: Glyph.tama,
                semanticLabel: l.stickerOpen,
                onPressed: state.sending ? null : () => unawaited(onSticker()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: IbashoTextField(
                  controller: controller,
                  focusNode: focus,
                  label: l.messagesComposeHint,
                  maxLength: messageTextMax,
                  multiline: true,
                  enabled: !state.sending,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => unawaited(onSend()),
                ),
              ),
              const SizedBox(width: 10),
              IbashoButton(
                key: const ValueKey<String>('conversation.send'),
                label: state.sending ? l.messagesSending : l.messagesSend,
                glyph: Glyph.send,
                tone: ButtonTone.accent,
                onPressed: text.isEmpty || state.sending
                    ? null
                    : () => unawaited(onSend()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const GlyphIcon(Glyph.lock, size: 13, color: T.inkSoft),
                  const SizedBox(width: 6),
                  Text(
                    l.messagesPrivacy,
                    style: Ty.caption.copyWith(color: T.inkSoft),
                  ),
                ],
              ),
              if (state.failed)
                Text(
                  l.messagesFailed,
                  style: Ty.caption.copyWith(color: T.warn),
                )
              // El contador solo cuando queda poco: enseñarlo siempre es meter
              // prisa a quien escribe dos frases.
              else if (left <= 80)
                Text(
                  l.messagesLeft(left),
                  style: Ty.numeral(12, color: left < 0 ? T.warn : T.inkSoft),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.glyph});

  final String text;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(glyph, size: 34, color: T.inkSoft),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Ty.body.copyWith(color: T.inkSoft),
          ),
        ],
      ),
    ),
  );
}
